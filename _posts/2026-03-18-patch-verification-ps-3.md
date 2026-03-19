---
layout: post
title: "Paper Reading: PS^3 — Patch Semantic Symbolic Signatures"
date: 2026-03-18 17:14 -0600
categories: [Patch Verification]
tags: [Patch Verification, Binary Analysis, Software Security]
---

> PS^3: Precise Patch Presence Test based on Semantic Symbolic Signature (ICSE '24)
>
> [Paper](https://arxiv.org/pdf/2312.03393)

## Key Attributes

- **Binary-binary matching** (requires source to compile references, but the analysis pipeline is entirely binary-level)
- **Lightweight symbolic emulation** (not full symbolic execution)

## Key Contribution

Existing patch presence test methods rely heavily on syntactic information and **only work when reference and target binaries are compiled with the same compiler options**. PS^3 addresses this by extracting *semantic-level* symbolic signatures that remain stable across different compilers and optimization levels. It is the first to use a theorem prover to check semantic equivalence of binary signatures.

The authors argue that:
1. Their method works with reference binaries compiled with different compiler options — no need to match the exact target binary's compilation configuration.
2. High efficiency: average 7.4s per test, applicable to large-scale software systems.

## Motivating Example

FFmpeg/CVE-2020-22019: added two branch conditionals to guard input params `w` and `h` (check `w < 3 || h < 3`).

The authors argue that:
1. Raw assembly matching will not help. Addresses can change, registers can change. Root cause: lack of register allocation info and contextual info.
2. The generated signature is a constraint on the function's input parameters: `Not(R(w) <= 2)` and `Not(R(h) <= 2)`.
3. These signatures remain constant across different binaries because parameter passing order is consistent with calling conventions.
4. SMT solver proves `Not(R(h) < 3) == Not(R(h) <= 2)` when `h` is an integer — syntactically different but semantically equivalent.

## Approach

### Symbolic Emulator

- Compile source code into two reference binaries (vulnerable + patched) with debug info (gcc O0 + `-g`).
- Parse the patch diff file, then use debug info to identify which binary instructions correspond to added/deleted source lines.
- Perform lightweight symbolic emulation on the function's CFG via DFS from function entry.
    - Key difference from full symbolic execution: skips callee internals (assigns symbolic return values), only tracks forward control flow, does not solve constraints.
    - Uses VEX IR (via Angr) for architecture independence.

### Signature Extractor

Collect side effects from symbolic emulation. 4 types of signatures:
1. **Register Write**: index (which register) + symbolic value expression
2. **Memory Store**: symbolic address + symbolic value
3. **Condition**: boolean expression from branch conditions
4. **Call / Return**: function name + parameters; or return name + index

Sanitization rules:
- Remove register/memory write signatures whose values are consumed by later instructions (keeps signatures small and precise).
- Use Z3 to simplify stack pointer calculations for more precise memory mapping.
- Prefer modified hunks (add+delete) over pure additions/deletions — more unique signatures.

### Addition/Deletion Checking Module

Before matching, classify the patch type:
- **Pure addition**: require all `condition` and `call` signatures from patched reference to exist in target.
- **Pure deletion**: require the deleted signatures to be absent in target.
- **Modification**: compare both vulnerable and patched reference signatures against target; use weighted score to decide.

### Matching Engine

Compare signatures extracted from reference binaries against target binary.

Per-type matching rules:
1. **Call**: function name and all parameters must be equal
2. **Register Write**: index and value expression
3. **Memory Store**: address and value expression
4. **Condition**: symbolic expressions (via Z3 equivalence checking)
5. **Return**: name and index

Returns a weighted score — sum of all matched signatures. **Call** and **condition** signatures get higher weights (more likely to be unique to the patch). If score(vulnerable_ref → target) >= score(patched_ref → target), classify as vulnerable.

String parameters in function calls are wildcarded (ignored in matching) since string representations vary across binaries.

## Evaluation

### Dataset

- 62 CVEs from 4 C/C++ projects: OpenSSL (23), FFmpeg (26), Tcpdump (11), Libxml2 (2)
- 75 release versions across projects
- Compiled with **8 compiler configurations**: gcc × {O0, O1, O2, O3} + clang × {O0, O1, O2, O3}
- Reference binaries: always gcc O0 with debug info
- **3,631 (CVE, binary) pairs total** (1,582 vulnerable + 1,893 patched)

### Effectiveness vs. Baselines

| Approach | Precision | Recall | F1 |
|----------|-----------|--------|----|
| Asm2Vec  | 0.60      | 0.50   | 0.65 |
| BinXray* | 0.51      | 0.96   | 0.67 |
| **PS^3** | **0.82**  | **0.97** | **0.89** |

*BinXray returns "unknown" for most targets when compiler options differ; counted as vulnerable.

PS^3 outperforms baselines by 33% (BinXray) and 37% (Asm2Vec) in F1.

### Cross-Compiler Robustness

| Compiler Config | BinXray F1 | PS^3 F1 |
|-----------------|------------|---------|
| Gcc O0          | 0.85       | 0.93    |
| Gcc O1          | 0.83       | 0.91    |
| Gcc O2          | 0.66       | 0.90    |
| Gcc O3          | 0.66       | 0.90    |
| Clang O0        | 0.63       | 0.89    |
| Clang O1        | 0.64       | 0.87    |
| Clang O2        | 0.64       | 0.86    |
| Clang O3        | 0.63       | 0.86    |

Key findings:
- BinXray drops to 50% precision when compiler options differ (only reliable at O0 & gcc).
- PS^3 stays stable (F1 range 0.86–0.93) across all configurations.
- Greatest improvement: gcc O1, where PS^3 yields 44% higher F1 than BinXray.

### Per-CVE Results

- 35/62 CVEs achieve perfect F1 score (1.0).
- 58/62 CVEs achieve 100% recall.
- 4 CVEs fail (F1 < 0.6) — all involve patches where the vulnerability root lies in backward data flow or arithmetic-only changes.

### Efficiency

| Approach | Preprocess | Max   | Min  | Average  |
|----------|------------|-------|------|----------|
| PS^3     | —          | 45.1s | 2.1s | **7.4s** |
| BinXray  | 110s       | 0.1s  | —    | 0.06s    |

PS^3 is slower per-test but requires no preprocessing. BinXray needs 110s IDA Pro preprocessing per file (+ 257s avg to extract functions in FFmpeg). PS^3's signatures are reusable across multiple targets.

## Limitations

- **Forward-only control flow**: PS^3 only analyzes forward instructions. When the vulnerability root lies in backward data flow (e.g., CVE-2022-1343 — a return value assignment is the fix), PS^3 cannot distinguish patched from vulnerable.
- **Angr/VEX IR limitations**: cannot handle vector instructions well (OpenSSL uses them heavily), causing imprecise symbolic register values.
- **CFGFast imprecision**: uses Angr's fast CFG recovery, which can be imprecise.
- **Amd64 only** currently (though extensible via VEX IR).
- **Assumes function entry address is known** — stripped binaries need additional binary function matching as preprocessing.
- **Only tested on C/C++ projects** — external validity limited.
