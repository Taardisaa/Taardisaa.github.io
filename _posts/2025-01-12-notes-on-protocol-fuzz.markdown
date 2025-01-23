---
layout: post
title: "Notes on Protocol Fuzz"
date: "2025-01-12 19:28:11 -0700"
categories: "Fuzz"
---

## Paper Read

1. Large Language Model guided  Protocol Fuzzing(NDSS 24)

## Notes 

### How to evaluate the effectiveness of LLM

1. Answers --> Grammar: Given a set of concrete protocol messages/responses as a study set, firstly ask the LLM to generate grammars of this protocol, to see whether LLM can produce machine-readable structures that can match the protocol's definition(aka, the ground truth)
2. Grammar --> Answers: Given a set of rules/grammars, ask LLM to generate concrete messages. This is the inversed version of 1.
3. State Transition: Whether the generated messages can trigger a state transition.

## EMPF

This is the classic protocol fuzzing routine. 

