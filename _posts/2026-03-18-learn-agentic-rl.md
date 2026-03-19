---
title: "Learn Agentic RL"
description: A brief introduction to Agentic Reinforcement Learning. And some of my thoughts.
author: Taardisaa
date: 2026-03-18 16:52 -0600
categories: [Artificial Intelligence, Reinforcement Learning]
tags: [Agentic RL, LLM, Reinforcement Learning, Artificial Intelligence]
pin: true
math: true
mermaid: true
---

# What is Agentic RL?

Agentic Reinforcement Learning (Agentic RL) refers to a paradigm in which LLMs, rather than
being treated as static conditional generators optimized for single-turn output alignment or benchmark
performance, are conceptualized as learnable policies embedded within sequential decision-making
loops, where RL endows them with autonomous agentic capabilities, such as planning, reasoning, tool
use, memory maintenance, and self-reflection, enabling the emergence of long-horizon cognitive and
interactive behaviors in partially observable, dynamic environments. (https://arxiv.org/pdf/2509.02547)

To summarize, it performs RL methods on LLMs to enhance its abilities in the following fields:
- multi-turn tasks (sequential decision-making loops)
- planning, reasoning
- tool use
- memory maintenance
- self-reflection

## Agent

**In the field of LLMs**, An LLM agent is a software system centered on a language model that can perceive context, reason over objectives, select actions, interact with external tools or environments, and continue this loop until a task is completed or stopped by constraints.

**In reinforcement learning**, an agent is the decision-making entity that interacts with an environment. At each step, it observes the current state or observation, chooses an action, receives a reward, and updates its behavior to maximize long-term cumulative reward.

These are two different concepts, but share the same high-level intuition: **an agent is an entity that perceives an environment, makes decisions, and acts toward some objective.**

### Typical Agent Practices

There are several frameworks for building LLM agents:

- **LangGraph / LangChain** — offers fine-grained control over the agentic loop, making it well-suited for custom multi-step workflows.
- **smolagents** — a lightweight option for writing simple coding agents, though it exposes fewer customization options.
- **veRL** — provides an interface for designing agents within an RL training context. See their [agent loop tutorial](https://github.com/verl-project/verl/blob/main/examples/tutorial/agent_loop_get_started/agent_loop_tutorial.ipynb) for an example.

I've used LangGraph and smolagents for coursework, and veRL is particularly relevant here since it bridges the gap between agent design and RL training.


# References

- [The Landscape of Agentic Reinforcement Learning for LLMs: A Survey](https://arxiv.org/pdf/2509.02547)