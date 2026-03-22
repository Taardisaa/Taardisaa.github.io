---
layout: post
title: "Empirical Analysis of Binary Obfuscations [Working]"
description: Ad-hoc analysis of binary obfuscation techniques using Polaris Obfuscator, examining effectiveness against reverse engineering and interaction with compiler optimizations.
date: 2026-03-18 22:01 -0600
---

This is just my personal thought on binary obfuscation techniques. Typically, I want to understand these aspects:
- Effectiveness of each obfuscation technique: How well does it prevent reverse engineering? Can they be trivially de-obfuscated?
- Will compiler optimizations break the obfuscation, or enhance its obfuscation effect?

This is a quite ad-hoc analysis, not quite a paper-ready work (I won't post this here if it is).

What I do NOT care:
- Performance overhead

## Obfuscation Frameworks

- [Polaris Obfuscator](https://github.com/za233/Polaris-Obfuscator)
- [Obfuscator-LLVM](https://github.com/wwh1004/ollvm-16)

Here, I use Polaris Obfuscator for the analysis.

## De-obfuscation Tools

- https://github.com/cdong1012/ollvm-unflattener
- https://github.com/cq674350529/deflat

## Metrics

- **CFG Similarity**: Typically, we use **graph edit distance**  to measure the similarity between the CFG of an original binary function and the CFG of the obfuscated one.

## Workflow

It is intended to be a combination of qualitative and quantitative analysis. For the quantitative part:

1. Prepare dataset. Two types: real-world projects (e.g., coreutils, ffmpeg, libxml2, etc.) and synthetic code snippets (e.g., Csmith generated code).
2. Apply obfuscation techniques to the dataset, and compile with different optimization levels (e.g., -O0, -O1, -O2, -O3).
3. Use de-obfuscation tools to try to recover the original CFG.
4. Use metrics proposed above for evaluation.


## References

- https://plzin.github.io/posts/mba
- https://github.com/mazeworks-security/MSiMBA
- https://arxiv.org/pdf/2406.10016