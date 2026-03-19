---
layout: post
title: Decompiler RL
---

This is a very wild idea: Use reinforcement learning to enhance the current LLM-based decompilation.

## Is there any existing work?

Yes — there is now some directly relevant work, but it is **quite recent and still sparse**, rather than a large established line of research.

### Baselines and Precursors

- **[LLM4Decompile (EMNLP 2024)](https://aclanthology.org/2024.emnlp-main.203.pdf)** is a major baseline for LLM-based decompilation. Its training recipe centers on large-scale supervised fine-tuning, data augmentation, data cleaning, and two-stage training — not reinforcement learning. Highly relevant as the baseline that RL methods build upon.

### RL-Based Approaches

- **[D-LiFT (2025)](https://arxiv.org/html/2506.10125v2)** explicitly improves an LLM-based decompiler backend using **code-quality-aware reinforcement learning**. It aims to improve decompiled-code quality while preserving accuracy via an integrated scoring system. This is RL for post-processing / backend improvement rather than pure end-to-end decompilation from binary.

- **[SK2Decompile (2025)](https://arxiv.org/abs/2509.22114)** describes a **two-phase binary decompilation** pipeline that uses reinforcement learning in both phases — one reward for structure recovery following compiler-like syntactic/semantic rules, and another reward for identifier naming based on semantic similarity. This is very close to "using RL to improve LLM-based decompilers" end-to-end.

- **[RlDecompiler (ICPC 2026)](https://conf.researchr.org/details/icpc-2026/icpc-2026-research/14/RlDecompiler-Enhancing-LLM-based-Decompilation-via-Reinforcement-Learning-with-a-Mul)** — *"Enhancing LLM-based Decompilation via Reinforcement Learning with a Multi-Faceted Reward Function."* An explicitly decompilation-focused RL paper at a top program comprehension venue. Very recent; I have not yet found an openly accessible full PDF.

### Two Emerging Directions

These papers split into two directions:

1. **RL for improving decompiler outputs** after or around an existing decompiler pipeline (e.g., D-LiFT).
2. **RL inside the decompilation model itself**, training the LLM's generation with RL objectives (e.g., SK2Decompile, RlDecompiler).

### Takeaway

Before 2025, the best-known LLM decompilation work (LLM4Decompile) was mostly supervised. By 2025–2026, papers are explicitly introducing **RL-based training objectives** for decompilation quality, structure recovery, readability, and backend refinement. The idea is valid and already emerging, but still early-stage rather than saturated.

