---
layout: post
title: "[SPA] Forward-flow Analysis"
date: 2026-03-22 00:35 -0600
description: A description of forward-flow analysis in static program analysis (SPA).
math: true
---

Consider a control-flow graph (CFG), where basic blocks are connected by directed edges.

In **forward data-flow analysis**, information propagates in the same direction as execution (from entry toward exit).

## Generic Forward Framework

For each block $$B$$:

$$
IN[B] = MERGE_{P \in Pred(B)} OUT[P]
$$

$$
OUT[B] = f_B(IN[B])
$$

Here, $$MERGE$$ is the predecessor-combination operator (depends on the analysis), and $$f_B$$ is the transfer function of block $$B$$.

Important: $$MERGE$$ is **not fixed**. Depending on the data-flow problem, it can be either a meet/intersection-style merge or a union-style merge.

## Common GEN/KILL Form (Forward, Bit-Vector Style)

For many forward **may** analyses (e.g., reaching definitions), the meet is union, and the transfer is:

$$
IN[B] = \bigcup_{P \in Pred(B)} OUT[P]
$$

$$
OUT[B] = GEN[B] \cup (IN[B] - KILL[B])
$$

This form is standard for **reaching definitions** (often described via def-use/use-def chains).

## Reaching Definitions: Explicit GEN/KILL

*To be covered in a separate post.*
