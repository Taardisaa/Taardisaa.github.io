---
layout: post
title: "[SPA] Weakest Precondition"
description: Weakest precondition as a backward predicate transformer — core rules, binary IR implementation with Miasm/PyVEX, and application to patch verification.
date: 2026-03-22 01:12 -0600
math: true
---

Weakest precondition is a **backward predicate transformer**.

**Definition**: given a statement/program fragment $$S$$ and a postcondition $$Q$$ that must hold after $$S$$, $$WP(S, Q)$$ is the **least restrictive** (weakest) condition that must hold before $$S$$ so that executing $$S$$ guarantees $$Q$$.

- Why backward: like live variable analysis, WP starts from a goal at a later program point (the postcondition) and propagates requirements backward toward the entry. To know what must be true *before* $$S$$, you need to know what is required *after* $$S$$.
- Why "weakest": any other sufficient precondition is strictly stronger — it implies $$WP(S, Q)$$. The weakest precondition captures exactly the necessary condition, nothing more.

## What Does "Weakest" Mean?

Consider:

```c
if (x > 10) {
    func();
}
```

The weakest precondition for `func()` to execute is simply $$x > 10$$ — that is the minimum requirement.

Now, $$x > 10 \land y < 100$$ is also a valid precondition — it implies $$x > 10$$, so `func()` would still be reached. But it is **stronger**: it unnecessarily excludes inputs where $$y \geq 100$$ that would work just fine. The extra constraint adds nothing.

"Weakest" means it captures **all** inputs that satisfy the postcondition, nothing less, nothing more. Any stronger precondition is a strict subset — correct but unnecessarily restrictive.

## How WP Relates to Data-Flow Analysis

WP is not a bit-vector data-flow analysis like liveness or reaching definitions. It is a **predicate transformer**: instead of tracking sets of variables or definitions, it transforms logical formulas backward through statements. However, the backward propagation pattern is the same — start from the end, apply a transfer rule per statement, work toward the entry.

| | Reaching Definitions | Liveness | WP |
|--|-----|------|------|
| **Direction** | Forward | Backward | Backward |
| **Domain** | Sets of definitions | Sets of variables | Logical formulas |
| **Propagates from** | Assignments (supply) | Uses (demand) | Postconditions (requirements) |

## Core Rules (Assignment, Sequence, Branch)

For deterministic, side-effect-free expressions:

**1. Assignment**

$$
WP(x := e, Q) = Q[x \leftarrow e]
$$

Meaning: **substitute** every occurrence of $$x$$ in $$Q$$ by $$e$$.

> **Substitution** is the key operation in WP.

Example: let $$Q$$ be $$x > 5$$ and the statement be `x := x + 3`. Then:

$$
WP(x := x + 3, \; x > 5) = (x + 3) > 5 = x > 2
$$

So the input must satisfy $$x > 2$$ to guarantee $$x > 5$$ after the assignment.

**2. Sequence**

$$
WP(S_1; S_2, Q) = WP(S_1, WP(S_2, Q))
$$

Example: consider `x := x + 1; y := x * 2` with postcondition $$y > 6$$. Work **inside-out**:

$$
WP(y := x * 2, \; y > 6) = x * 2 > 6 = x > 3
$$

$$
WP(x := x + 1, \; x > 3) = (x + 1) > 3 = x > 2
$$

So $$WP = x > 2$$.

**3. Conditional**

$$
WP(\text{if } c \text{ then } S_t \text{ else } S_f, Q)
= (c \Rightarrow WP(S_t, Q)) \land (\neg c \Rightarrow WP(S_f, Q))
$$

Equivalent form:

$$
(c \land WP(S_t, Q)) \lor (\neg c \land WP(S_f, Q))
$$

Example: consider `if (x >= 0) then y := x else y := -x` with postcondition $$y \geq 0$$:

- True branch: $$WP(y := x, \; y \geq 0) = x \geq 0$$
- False branch: $$WP(y := -x, \; y \geq 0) = -x \geq 0 = x \leq 0$$

Combine:

$$
(x \geq 0 \Rightarrow x \geq 0) \land (x < 0 \Rightarrow x \leq 0)
$$

Both conjuncts are tautologies, so $$WP = true$$ — the postcondition holds for all inputs (which makes sense: this is computing absolute value).

## Easy Example

Program:

```text
1) x = x + 1
2) y = 2*x
```

Postcondition:

$$
Q: y > 10
$$

Compute backward:

- Step 2:

$$
WP(y := 2x, \; y > 10) = 2x > 10
$$

- Step 1:

$$
WP(x := x+1, \; 2x > 10) = 2(x+1) > 10
$$

Simplify:

$$
x > 4
$$

So the weakest precondition of the whole program w.r.t. $$y > 10$$ is:

$$
WP = x > 4
$$

## Why WP is Useful for Binary Analysis

- Backward reasoning from a security/property goal at a sink (e.g., branch target, memory safety condition).
- Path-condition generation for symbolic execution and exploitability checks.
- Equivalence checking / translation validation for lifted IR blocks.
- Program slicing focused on conditions required to reach a behavior.

## Implementing WP for Binary Analysis (Proposal)

We implement WP on binary-level IR, which powers many static analyses and verification tasks on a binary executable.

At binary level, we usually compute WP over a CFG and per-block IR statements.

Currently we consider Miasm IR and PyVEX IR, but the principles apply to any SSA-based IR with explicit memory modeling.

### 1) Choose State Model and Logic

Model state as symbolic variables:

- registers ($$RAX$$, $$RBX$$, ... or VEX temporaries)
- flags ($$ZF$$, $$CF$$, $$OF$$, ...)
- memory ($$Mem(addr, size)$$ via array/select-store or memory SSA)
- instruction pointer / PC when needed for control-flow constraints

Use bit-vector logic (SMT-LIB BV) to preserve machine-width semantics.

### 2) Normalize IR Statements into Transformer-Friendly Forms

Typical forms you need:

- `dst <- expr` (register/temp assignment)
- `mem[addr] <- expr` (memory store)
- guard/branch (`if cond goto T else F`)
- call/return/jump (direct/indirect)

For Miasm IR and VEX IR, first lower each statement to a common internal expression AST:

- constants, variables, unary/binary ops, extracts, concatenation
- memory load/store nodes
- comparisons and boolean combinations

### 3) Statement-Level WP Rules for Binary IR

Let $$Q$$ be a formula on post-state symbols.

- **Register/temp assignment:** `r := e`
  - $$WP = substitute(Q, r, e)$$

- **Memory store:** `Mem[a] := v`
  - Use functional update: $$Mem' = store(Mem, a, v)$$
  - $$WP = substitute(Q, Mem, store(Mem, a, v))$$

- **Load into register:** `r := load(Mem, a)`
  - Same as assignment substitution.

- **Assume/guard:** `assume(c)`
  - $$WP = c \Rightarrow Q$$ (or $$c \land Q$$ for must-follow paths)

- **Assert(c):**
  - To prove safety: $$WP = c \land Q$$

- **Havoc(x)** (unknown write, e.g., clobbered register by opaque call):
  - $$WP = \forall x'. \; Q[x \leftarrow x']$$ (rare in practice)
  - Pragmatic over-approximation: replace with fresh symbol and track loss of precision.

### 4) Block-Level Backward Pass

For a basic block with statements $$s_1; s_2; \dots; s_n$$ and outgoing postcondition $$Q_{out}$$:

```text
Q := Q_out
for i = n downto 1:
    Q := WP(si, Q)
return Q   // this is block entry condition
```

### 5) CFG-Level Equations (Joins and Loops)

For each block $$B$$ with successors $$Succ(B)$$:

$$
WP_{out}(B) = \bigwedge_{S \in Succ(B)} EdgeCond(B, S) \Rightarrow WP_{in}(S)
$$

$$
WP_{in}(B) = WP_{block}(B, WP_{out}(B))
$$

Notes:

- Use implication with edge conditions for precise branch semantics.
- Loops require fixed-point iteration (or user-supplied invariants if proving stronger properties).
- In practice, simplify formulas after each step to avoid blow-up.

### 6) Miasm / PyVEX Specific Guidance

- **Miasm IR:**
  - Convert `ExprId`, `ExprInt`, `ExprOp`, `ExprMem`, etc. into your WP AST.
  - Be explicit about bit-widths in all substitutions.

- **PyVEX IR:**
  - Handle `IRStmt.WrTmp`, `Put`, `Store`, `Exit`, and `IMark`.
  - Translate `IRExpr.Get`, `RdTmp`, `Load`, `Binop`, `Unop`, `ITE`.
  - Respect endianness and size in `Load/Store` semantics.

- **Calls:**
  - If summary is available: apply summary transformer.
  - Otherwise, havoc call-clobbered registers/memory regions conservatively.

- **Indirect jumps:**
  - Add target constraints from jump expression; when unresolved, over-approximate successor set.

### 7) Minimal Implementation Skeleton

```python
def wp_stmt(stmt, Q):
    match stmt.kind:
        case "assign":      # dst := expr
            return substitute(Q, stmt.dst, stmt.expr)
        case "store":       # Mem[addr] := val
            mem_new = Store(MEM, stmt.addr, stmt.val, stmt.size)
            return substitute(Q, MEM, mem_new)
        case "assume":
            return Implies(stmt.cond, Q)
        case "assert":
            return And(stmt.cond, Q)
        case "havoc":
            fresh = Fresh(stmt.var.sort)
            return substitute(Q, stmt.var, fresh)
        case _:
            raise NotImplementedError


def wp_block(stmts, Q_out):
    Q = Q_out
    for s in reversed(stmts):
        Q = simplify(wp_stmt(s, Q))
    return Q
```

## Precision Pitfalls on Binary IR

- Aliasing: two addresses may refer to same memory bytes.
- Partial-register writes (`al`, `ax`, `eax`, `rax`) must be modeled exactly.
- Flags are implicit outputs of arithmetic; missing flag semantics breaks branch WP.
- Undefined/architecture-specific behavior (shift counts, division overflow, FP flags).
- Formula explosion on long traces/loops; use slicing + simplification + SSA.

> Computing WP across a large portion of a CFG is non-trivial — formulas grow quickly with path count and statement complexity. As with other symbolic analyses, it is practical to scope WP to a small neighborhood of the sink (e.g., a few blocks) rather than the entire function, keeping formulas manageable and solver queries fast.

## Practical Workflow

1. Lift machine code to IR (Miasm/PyVEX).
2. Build CFG and edge predicates.
3. Define target postcondition at sink point.
4. Compute backward WP per block with fixed-point on loops.
5. Query SMT solver:
   - $$pre \Rightarrow WP$$ validity (proof)
   - or $$pre \land \neg WP$$ satisfiable (counterexample).

If solver says unsat for $$pre \land \neg WP$$, then $$pre$$ is sufficient for the property.

## Alternative: Backward Slice + Forward Symbolic Execution

Building a standalone WP engine is non-trivial, especially when a mature forward symbolic execution framework like angr already exists. A practical alternative is to combine both directions:

1. **Backward slice** from the sink to identify only the statements and branches that influence the target postcondition.
2. **Forward symbolic execution** on the sliced CFG, pruning irrelevant branches so the engine explores only paths relevant to the property.

Note that WP and forward SE face the same fundamental combinatorial problem — the number of feasible paths — just manifested differently: SE explodes in **path count**, WP explodes in **formula size**. The backward slice helps both equally by reducing the number of branches in scope. This does not eliminate path explosion entirely, but significantly narrows the search space in practice.

## Using WP to Detect a Patched Snippet in a Binary Function

Suppose inside a large function $$P$$ you expect a snippet like:

```c
if (x > 10) {
    malloc(256);
}
```

and you want to check whether this behavior exists in the current binary.

### 1) Encode a Snippet Postcondition at the Call Site

Let:

- $$E$$ be function entry.
- $$C$$ be the program point just before the allocator call.
- $$g$$ be the guard edge predicate corresponding to $$x > 10$$.

Define:

$$
Q_{snip} := (pc = C) \land (callee = malloc) \land (arg_0 = 256) \land took\_guard\_edge(g)
$$

Then compute backward:

$$
\Phi := WP(P, Q_{snip})
$$

Interpretation:

- $$SAT(\Phi)$$: there exists an input/state at entry that reaches this guarded `malloc(256)` behavior (snippet exists semantically).
- $$UNSAT(\Phi)$$: no such behavior is reachable (snippet absent, rewritten away, or infeasible).

### 2) Check That the Guard is Truly Required

To avoid matching an unrelated `malloc(256)` path, also check a bypass formula:

$$
Q_{bypass} := (pc = C) \land (callee = malloc) \land (arg_0 = 256) \land \neg g
$$

$$
\Phi_{bypass} := WP(P, Q_{bypass})
$$

- $$UNSAT(\Phi_{bypass})$$: the call cannot be reached without the guard (good patch shape).
- $$SAT(\Phi_{bypass})$$: there is a path to the same call without $$x > 10$$ (guard not enforced as expected).

### 3) Practical Construction on Miasm/PyVEX

- Lift to IR and recover CFG edges with branch predicates.
- Build call-site facts (`callee`, calling-convention argument extraction for `arg_0`).
- Use SSA to bind the exact version of $$x$$ used at the guard.
- Compute WP from call site back to entry with edge predicates.
- Query SMT for $$SAT(\Phi)$$ and $$SAT(\Phi_{bypass})$$.

### 4) Caveats

- Optimized code may inline/replace `malloc` (match allocator summary, not symbol name only).
- Constant propagation may turn $$x > 10$$ into an equivalent but different predicate form.
- Multiple call sites require disambiguation by $$pc$$ (or by a set of allowed PCs).
- Unknown calls may clobber state; use conservative summaries/havoc where needed.
