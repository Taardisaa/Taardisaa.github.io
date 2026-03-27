---
layout: post
title: "[SPA] Reaching Definition Analysis"
description: Reaching definition analysis in static program analysis — a forward may-analysis determining which definitions may reach each program point without being overwritten.
date: 2026-03-22 01:05 -0600
math: true
---

Reaching definitions is a **forward may-analysis**.

**Definition**: a definition $$d$$ (an assignment like $$x = \dots$$) **reaches** program point P if there exists a forward execution path from $$d$$ to P along which $$x$$ is not redefined.

- Why forward: a definition is created at some earlier point and propagates along execution paths toward later points. To know what reaches P, you only need information from predecessors — so the analysis flows forward, from entry toward exit.
- Why may: if there exists *any* path along which the definition arrives without being overwritten, it is considered reaching.

## What Does "Reaching" Mean?

A definition "reaches" a point if its assigned value *could still be in effect* there. If every path from the definition to that point overwrites the variable, the definition is **killed** and does not reach.

This is the forward counterpart of live variable analysis: liveness asks "will this value be read in the future?", while reaching definitions asks "which past assignments could have produced the current value?"

## Reaching Definitions vs Liveness: Two Sides of the Same Coin

- **Reaching definitions**: starts from where a value is **created** (assignment), propagates **forward** along execution to see how far it survives before being overwritten. It tracks the *supply* of values.
- **Liveness**: starts from where a value is **consumed** (use), propagates **backward** against execution to see how far back the value is needed. It tracks the *demand* for values.

## Data-Flow Equations (Block Form)

$$
IN[B] = \bigcup_{P \in Pred(B)} OUT[P]
$$

$$
OUT[B] = GEN[B] \cup (IN[B] - KILL[B])
$$

## Explicit Meaning of GEN/KILL

Let a definition be an assignment statement (e.g., $$x = \dots$$).

- $$GEN[B]$$: definitions created in block $$B$$ that reach the end of $$B$$.
  - In block-level bit-vector form, this is typically the **last** definition per variable in $$B$$.
- $$KILL[B]$$: definitions of the same variables (from elsewhere, or earlier in $$B$$) that are overwritten by definitions in $$B$$.

If $$B$$ defines $$x$$, then all other definitions of $$x$$ are killed in $$OUT[B]$$.

## Concrete Example

```text
B1:
 d1: x = 1
 d2: y = 0
 if c goto B2 else B3

B2:
 d3: x = 2
 goto B4

B3:
 d4: y = 3
 goto B4

B4:
 d5: z = x + y
```

Definition universe: $$D = \{d1, d2, d3, d4\}$$.

- $$GEN[B1]=\{d1,d2\}$$, $$KILL[B1]=\{d3,d4\}$$
- $$GEN[B2]=\{d3\}$$, $$KILL[B2]=\{d1\}$$
- $$GEN[B3]=\{d4\}$$, $$KILL[B3]=\{d2\}$$
- $$GEN[B4]=\emptyset$$, $$KILL[B4]=\emptyset$$

At fixed point:

- $$OUT[B1]=\{d1,d2\}$$
- $$OUT[B2]=\{d3,d2\}$$
- $$OUT[B3]=\{d1,d4\}$$
- $$IN[B4]=OUT[B2] \cup OUT[B3]=\{d1,d2,d3,d4\}$$

Thus at $$d5$$:

- reaching defs of $$x$$ are $$\{d1,d3\}$$
- reaching defs of $$y$$ are $$\{d2,d4\}$$

## Def-Use vs Use-Def Chains

- **DU chain (def-use):** from a definition to uses it may reach.
- **UD chain (use-def):** from a use to definitions that may reach it.

Both are different query directions over the same reaching-definitions relation.

Important: reaching definitions remains a **forward** analysis; UD chains do not make it a backward analysis.
