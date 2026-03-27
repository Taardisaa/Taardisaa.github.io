---
layout: post
title: "[Paper] FoxDec: Formally verified lifting of C-compiled x86-64 binaries [Work in Progress]"
description: Paper read of FoxDec, which claims to be able to lift C-compiled x86-64 binaries with provably sound overapproximation using Hoare Graphs verified in Isabelle/HOL.
date: 2026-03-23 15:13 -0600
math: true
---

## The Two Base Questions

Binary lifting must answer two fundamental questions:

1. **Disassembly**: What are the assembly instructions in the binary?
2. **Control Flow Recovery**: In what order are these instructions executed?

Both questions are **inherently undecidable** in the general case — by Rice's Theorem (any non-trivial semantic property of programs is undecidable) and Horspool & Marovac 1980 (faithfully detranslating machine code back to a high-level language is undecidable for arbitrary binaries).

## The Chicken-and-Egg Problem

These two questions cannot be answered in isolation — they are circularly dependent:

- **To disassemble**, you need to know which addresses are reachable from the entry point.
- **To determine reachability**, you need control flow information — where do jumps go? Where does `ret` return to? What are the bounds of a jump table?
- **To analyze control flow**, you need to have already disassembled the instructions.

Even seemingly simple sub-problems are deep. Trusting that `ret` returns to the caller requires proving the return address on the stack was not overwritten, which requires alias analysis and proving absence of stack overflows. Resolving a jump table `jmp [rax*8 + table]` requires an upper bound on `rax`, which requires value analysis. Tracking the stack pointer across function calls requires trusting that callees restore it, which requires analyzing the callee first.

## FoxDec's Approach: Provably Sound Overapproximation

FoxDec does **not** claim to solve these undecidable problems. Instead, it produces a **sound overapproximation**: the result may include extra behaviors that don't actually occur, but it will never miss a real one.

The approach has two steps:

1. **Step 1**: Lift the binary while verifying properties with algorithms proven correct via *pencil-and-paper proofs* — that is, traditional mathematical proofs written by humans, as opposed to machine-checked proofs. This is faster to develop but relies on trusting the human didn't make a mistake.
2. **Step 2**: Validate that each inference from Step 1 can be proven formally correct in **Isabelle/HOL**, a proof assistant that mechanically checks every logical step. This acts as a machine-verified safety net.

## The Hoare Graph

The central data structure is the **Hoare Graph (HG)** — a directed graph extracted from the binary where:

- **Vertices** contain predicates (information on registers, memory locations, flags) and memory models (pointer aliasing information).
- **Edges** are labeled with disassembled instructions.
- Each edge forms a **Hoare triple** $$\{P\}\ \texttt{instr}\ \{Q\}$$: if precondition $$P$$ holds before the instruction, then postcondition $$Q$$ holds after.

The key property is that each vertex's invariant is **sufficiently strong** to prove what instructions can be executed next — making the graph *one-step-inductive*.

### Concrete Example

Consider this function:

```c
int abs(int x) {
    if (x < 0) return -x;
    return x;
}
```

Compiled to x86-64:

```asm
0x1000: mov  eax, edi
0x1002: test eax, eax
0x1004: jns  0x1008
0x1006: neg  eax
0x1008: ret
```

The Hoare Graph:

```text
 V0: { RSP = RSP₀, [RSP₀] = ret_addr, RDI = x }
     Memory model: { [RSP₀] not aliased by any write }
            │
            │  mov eax, edi
            ▼
 V1: { RSP = RSP₀, [RSP₀] = ret_addr, EAX = x }
            │
            │  test eax, eax
            ▼
 V2: { RSP = RSP₀, [RSP₀] = ret_addr, EAX = x, SF = (x < 0) }
           / \
   SF=1  /    \  SF=0
  (x<0) /      \ (x≥0)
        ▼       \
 V3: { ...,      V4: { ...,
   EAX = x,        EAX = x,
   x < 0 }         x ≥ 0 }
        │               │
        │ neg eax       │
        ▼               │
 V5: { RSP = RSP₀,      │
   [RSP₀] = ret_addr,   │
   EAX = -x }           │
        \               /
         \             /
          ▼           ▼
 V6: { RSP = RSP₀, [RSP₀] = ret_addr, EAX = |x| }
            │
            │  ret
            ▼
        (returns to ret_addr)
```

Each edge is a Hoare triple. For example, the `neg eax` edge:

$$\{RSP = RSP_0,\ [RSP_0] = \text{ret\_addr},\ EAX = x,\ x < 0\}$$

$$\texttt{neg eax}$$

$$\{RSP = RSP_0,\ [RSP_0] = \text{ret\_addr},\ EAX = -x\}$$

Why each vertex must be "sufficiently strong":

- At **V6** (before `ret`): the predicate $$[RSP_0] = \text{ret\_addr}$$ proves the return address was not corrupted. The memory model at every vertex tracks that no write aliases $$[RSP_0]$$, making this provable.
- At **V2** (before `jns`): the predicate contains the sign flag $$SF$$, so the analysis can prove exactly two successors exist — fall-through to V3 and jump to V4. Without this, the jump target would be unbounded.

## Three Verified Properties

FoxDec verifies three properties over functions, each necessary for soundness:

1. **Return Address Integrity**: Functions do not overwrite their own return address.
2. **Bounded Control Flow**: All indirect jumps transfer control flow to fixed, statically known, bounded sets of addresses.
3. **Calling Convention Adherence**: All functions properly restore the set of registers indicated by the calling convention as non-volatile.

### Is This Enough?

For FoxDec's stated scope — C-compiled, single-threaded, non-obfuscated binaries — these three form a reasonable minimal set. But they are **not universally sufficient**:

- **Self-modifying code**: FoxDec assumes code pages are immutable (W^X). If code rewrites itself at runtime, the static disassembly is invalid — this is assumed, not verified.
- **Concurrency**: Another thread can modify the stack between instructions, bypassing all three properties. The paper acknowledges this as future work.
- **Non-local control flow**: `longjmp`, signal handlers, and C++ exception unwinding all violate normal return semantics without technically "overwriting" the return address.
- **Compiler assumptions**: The whole framework rests on the binary being produced by a well-behaved C compiler. Hand-written assembly, inline asm, or compiler bugs can silently break any of the three properties.

The paper is honest about this — Section 7 explicitly states that assumptions may not hold (e.g., `memset` could violate return address integrity), and the negation leads to "weird" behavior. The soundness claim is **conditional**: *if* these properties hold, *then* the lifting is correct.

## Assumptions

The paper makes a number of explicit assumptions. The soundness guarantee is conditional on all of them holding.

### Scope Restrictions

1. **C-compiled binaries only**: The approach is limited to binaries compiled from C. C++ features like throw-catch and object initialization are unsupported.
2. **Single-threaded**: No support for concurrency. Another thread could invalidate any invariant between instructions.
3. **No destructors after exit**: Destructors executed after an `exit` call are not modeled.
4. **Stripped COTS ELF binaries**: Targets stripped commercial off-the-shelf x86-64 binaries in ELF format, compiled with various optimization levels. No debugging information or address labeling is required.

### Semantic Assumptions

5. **Sound per-instruction semantics**: Assumes the existence of a function $$\tau$$ that correctly models the state transformation of each x86-64 instruction. The paper uses semantics that have been machine-learned from actual hardware.
6. **Sound fetch function**: Assumes a `fetch` function that, given an address, soundly retrieves exactly one instruction from the binary. This implicitly assumes **no self-modifying code** — the code section is static.

### External Function Assumptions

7. **System V calling convention**: All external functions are assumed to adhere to the 64-bit System V calling convention — the local stack frame and callee-saved registers are preserved; the heap and global space are destroyed (set to $$\bot$$).
8. **No stack frame tampering**: External functions are assumed not to touch the local stack frame of the caller. Proof obligations are generated to assert this, and if proven, the lifted representation is sound.

### Analysis-Level Assumptions

9. **Context-free function calls**: To gain scalability, internal function calls are treated as context-free — each function is analyzed only once, regardless of call site. If a function pointer is passed as a parameter, its concrete value is unknown.
10. **Memory region partial overlap**: When the aliasing relationship between two memory regions cannot be determined (i.e., they may partially overlap), all potentially overlapping regions are destroyed — reads from them produce $$\bot$$. This is sound but lossy: it overapproximates by treating any ambiguous memory as unknowable.

### What This Means in Practice

The assumptions are designed so that their **negation** produces "weird" behavior — control flow paths that were not intended by the programmer but are technically possible. Since FoxDec produces an overapproximation, these weird paths are *included* in the Hoare Graph. The overapproximation contains both the normal/intended control flow and the weird edges.

This is by design: if all assumptions hold, the weird edges are unreachable. If an assumption is violated (e.g., a buffer overflow corrupts the return address), the weird edge represents a real, exploitable execution path. The paper argues this makes FoxDec useful for security analysis — the weird edges are exactly the ones an attacker would exploit.