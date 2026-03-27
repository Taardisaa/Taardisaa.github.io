---
layout: post
title: "[SPA] Live Variable Analysis"
description: Live variable analysis in static program analysis — a backward may-analysis determining which variables may be used before redefinition.
date: 2026-03-22 00:37 -0600
math: true
---

Live-variable analysis is a classic **backward may-analysis**.

**Definition**: a variable is **live** at program point P if its value will be read on some forward execution path from P (including P itself) before being redefined.

- Why backward: the definition looks forward along execution paths, but to *compute* liveness we need information from later program points — specifically, where uses and redefinitions occur. So the analysis propagates that information backward, from exit toward entry.
- Why may: if there exists *any* forward path where the variable is read before redefinition, it is considered live.

## What Does "Live" Mean?

A variable is **live** at a program point if there exists a path from that point to a **use** of the variable, with no intervening redefinition. In other words, "live" means "still needed in the future" — not "just created."

A variable that is defined but never used afterward is **dead** at that point. This directly enables **dead code elimination**: if an assignment's target variable is not live after the assignment, the assignment is a dead store and can be safely removed.

```text
x = 1        ← x is defined, but no future path reads it → x is dead
y = 2        ← y is live because "return y" reads it
return y
```

Here, `x = 1` is a dead store and can be eliminated. Liveness is defined by future uses, not by definitions.

## How Backward Propagation Works (Intuition)

Consider a straight-line program:

```text
x = 1
a = 2 * x
b = 3 * a
```

The analysis starts from the bottom and propagates upward:

1. `b = 3 * a` — reads `a` → `a` is live here.
2. `a = 2 * x` — `a` is redefined (killed), so `a`'s liveness stops. But this reads `x` → `x` is live here.
3. `x = 1` — `x` is redefined (killed), `x`'s liveness stops.

Live sets at each point (before the statement):

- before `b = 3 * a`: `{a}`
- before `a = 2 * x`: `{x}`
- before `x = 1`: `∅`

Note that `b` is dead everywhere because nothing reads it after its definition — another dead store candidate.

## Standard Equations (Basic-Block Form)

$$
OUT[B] = \bigcup_{S \in Succ(B)} IN[S]
$$

$$
IN[B] = USE[B] \cup (OUT[B] - DEF[B])
$$

## Meaning of USE/DEF

- $$USE[B]$$: variables read in $$B$$ before any local definition in $$B$$.
- $$DEF[B]$$: variables assigned in $$B$$.

Interpretation:

- If a variable is used in $$B$$, it must be live at entry.
- Otherwise, it is live at entry only if it is live at exit and not overwritten by $$B$$.

## Concrete Example

```text
B1: x = 1; y = 2; goto B2
B2: z = x + 3; goto B3
B3: return z
```

Per-block sets:

- $$USE[B1]=\emptyset$$, $$DEF[B1]=\{x,y\}$$
- $$USE[B2]=\{x\}$$, $$DEF[B2]=\{z\}$$
- $$USE[B3]=\{z\}$$, $$DEF[B3]=\emptyset$$

Backward solution:

- $$OUT[B3]=\emptyset$$, $$IN[B3]=\{z\}$$
- $$OUT[B2]=IN[B3]=\{z\}$$
- $$IN[B2]=USE[B2] \cup (OUT[B2]-DEF[B2]) = \{x\} \cup (\{z\}-\{z\}) = \{x\}$$
- $$OUT[B1]=IN[B2]=\{x\}$$
- $$IN[B1]=USE[B1] \cup (OUT[B1]-DEF[B1]) = \emptyset \cup (\{x\}-\{x,y\}) = \emptyset$$

So:

- $$x$$ is live out of $$B1$$ because $$B2$$ uses it.
- $$y$$ is dead after $$B1$$ because it is never used.

## Why This Matters for Decompilation

- If a register/value is **not live-out**, its computation can often be removed or simplified.
- Together with def-use/use-def information, liveness supports safe temporary-register elimination and expression substitution.
