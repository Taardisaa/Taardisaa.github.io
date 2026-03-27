---
layout: post
title: "[SPA] Backward-flow Analysis"
date: 2026-03-22 00:26 -0600
description: A description of backward-flow analysis in static program analysis (SPA).
math: true
---

Consider a control-flow graph (CFG), where basic blocks are connected by directed edges.

In **backward data-flow analysis**, information propagates in the opposite direction of execution (from exit toward entry).

## Generic Backward Framework

For each block $$B$$:

$$
OUT[B] = MERGE_{S \in Succ(B)} IN[S]
$$

$$
IN[B] = f_B(OUT[B])
$$

Here, $$MERGE$$ is the successor-combination operator (depends on the analysis), and $$f_B$$ is the transfer function of block $$B$$.

Important: $$MERGE$$ is **not fixed**. Depending on the data-flow problem, it can be either a meet/intersection-style merge or a union-style merge.

## Common GEN/KILL Form (Backward, Bit-Vector Style)

For many backward **may** analyses (e.g., live-variable analysis), the merge is union, and the transfer is:

$$
OUT[B] = \bigcup_{S \in Succ(B)} IN[S]
$$

$$
IN[B] = USE[B] \cup (OUT[B] - DEF[B])
$$

This form is standard for **live-variable analysis**.

## Live Variable Analysis

*To be covered in a separate post.*

