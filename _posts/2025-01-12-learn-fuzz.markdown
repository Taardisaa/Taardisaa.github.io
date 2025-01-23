---
layout: post
title: "learn-fuzz"
date: "2025-01-12 20:50:04 -0700"
categories: "Fuzz"
---

## Learning Pipeline

1. build a basic project based on AFL++ on lab's CPU server.
2. 

## Paper Read

### Protocol Fuzz

1. [NDSS 24]Large Language Model guided  Protocol Fuzzing
2. 

### Kernel Fuzz

1. [FSE 24]BRF: eBPF Runtime Fuzzer

## Tutorial

1. https://www.bilibili.com/video/BV1ZM4m1R7gZ
2. https://github.com/u1f383/fuzzing-learning-in-30-days
3. 

## Problem Unsolved

1. Details on `__afl_maybe_log`: how does it calculate the `edge`, and update the results on shared memory?
2. 

## Notes

1. in AFL's `read_testcases();` it will read all seeds to a corresponding "query entry", and form a linked list. Suppose seed files "a", "b", "c", then they
will generate a query list: "a->b->c->NULL"; if the whole query list finished execution, it will be treated as one cycle;