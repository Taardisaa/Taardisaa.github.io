---
layout: post
title: About Langmem
date: 2026-04-02 15:08 -0600
---

https://langchain-ai.github.io/langmem/

This is a library I used for my course project, which is about a gaming agent. The tricky point is to let the agent "store, read its past behaviors, refer to its past experience and reflect on its past behavior". A simple `MemorySaver` couldn't help because it only persists within one subagent, but our current design makes each subagent handles only one typical scenario. For example, battle subagent only cares about combating with enemies, while shop subagent only handles what cards/potions to buy, upgrade or discard. 

