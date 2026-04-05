---
layout: post
title: Backtracking for LLM
date: 2026-03-27 16:03 -0600
---

This is a course project (currently a proposal) for [CS 5955/6955 Advanced Artificial Intelligence - Spring 2026](https://dsbrown1331.github.io/advanced-ai-26/).

## Overview

### Original Goal

Our original proposal was **adaptive compute allocation**. The core idea was to train a policy that acts as a controller for an LLM: it would allocate shorter reasoning chains to easier problems and longer reasoning chains to harder ones. However, this direction has already been studied extensively, so the topic itself does not feel especially novel.

We also initially proposed four explicit actions to make the setup more reinforcement-learning-like:
- `<branch>`: emit this token when the model wants to explore a new idea or switch to a different line of reasoning
- `<continue>`: continue the current reasoning path
- `<terminate>`: stop reasoning and produce the final answer
- `<verify>`: check the correctness of the intermediate reasoning steps

After thinking it through, I now believe these explicit action tokens are mostly unnecessary or redundant:

- `<branch>`: This behavior can already be expressed naturally in language, for example, "Wait, let's try another approach" or "This will not work; we should instead...". More importantly, branching-based reasoning has already been explored heavily, so it is difficult to claim much novelty here.
- `<continue>`: This is almost a no-op because it simply means staying on the current reasoning path. In practice, forcing the model to emit such a token could even hurt reasoning quality.
- `<terminate>`: This is not meaningfully different from an existing end-of-thinking marker such as `</think>`.
- `<verify>`: Intermediate verification is difficult because it creates a classic credit assignment problem in reinforcement learning. Process Reward Models (PRMs) have shown that rewarding intermediate steps can outperform only rewarding the final outcome with an Outcome Reward Model (ORM), but they are much harder to implement in practice. Existing approaches often rely on heavily hand-crafted rewards, which makes them difficult to scale.

### My Goal

Personally my idea is to simplify into only one task: let the LLM learn to do "backtrace". 

**Goal:** Train a small open LLM (via LoRA + GRPO) that learns to **undo bad reasoning mid-generation** — and show this improves accuracy over standard forward-only reasoning at the same token cost.

**Problem:** Current LLMs can only append tokens. Once a model goes down a wrong reasoning path, those tokens stay in context, waste the context window, and can mislead subsequent reasoning. The model has no way to say "that was wrong, let me start this part over."

**Our approach:** Add a $\langle\texttt{backoff}\rangle$ action that hard-truncates unhelpful tokens from the KV cache, reclaims context space, and optionally injects a short directive before resuming. The model learns when to use it through RL.

**Key claim:** A model with access to $\langle\texttt{backoff}\rangle$ achieves higher accuracy than one that can only continue or stop.

"think" -> "feels something off" -> "<backoff_N>" -> "a new directive/fix"

Then, 我们根据N来将前面的部分进行删除;目前删除的边界是semantic boundaries,比如

Train a small LLM that learns to do 


## Appendix

### Original Goal

Large language models (LLMs) often improve reasoning performance by increasing test-time computation, such as generating longer chains of reasoning or sampling multiple candidate solutions. However, most existing approaches allocate a fixed amount of computation for every input, which can be inefficient: simple problems may receive unnecessary reasoning, while difficult problems may require additional exploration. In this project, we investigate whether reinforcement learning can train LLMs to adaptively allocate reasoning computation during inference. We formulate reasoning as a sequential decision-making problem in which the model acts as an agent that chooses among actions such as continuing reasoning, verifying an intermediate result, sampling an alternative solution, or terminating inference. The objective is to learn a policy that dynamically determines how much reasoning effort a problem should receive.

To train this policy, we will use reinforcement learning with a reward function that balances answer correctness with computational cost. Experiments will be conducted on reasoning benchmarks such as GSM8K and HumanEval using a base instruction-tuned LLM with lightweight fine-tuning (e.g., LoRA). We will compare the learned adaptive policy against fixed compute strategies such as standard chain-of-thought reasoning and self-consistency sampling. Evaluation will focus on both task accuracy and compute efficiency, including metrics such as reasoning token usage and compute-per-correct-answer. The expected contribution of this project is an empirical analysis of whether reinforcement learning can enable language models to dynamically control their own inference computation and improve the accuracy–efficiency trade-off in LLM reasoning.
