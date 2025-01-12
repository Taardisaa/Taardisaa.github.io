---
layout: post
title:  "Summary on Learning Rust Lang"
date:   2025-01-11 23:37:00 -0700
categories: Programming Language
---

## Where to learn

[The Rust Programming Language](https://doc.rust-lang.org/book/ch16-01-threads.html)

## About Pointers

1. `Box<T>` 
2. `Rc<T>` is enhanced with multiple ownership by a "strong counter" to count the number of pointers to the same data(only "strong" pointers)
3. `RefCell<T>` is to allow "internal mutability" through borrow rules check in runtime instead of compile time.
4. `Weak<T>` is to avoid memory leak caused by "reference cycle"

### Things that I wanna learn more about pointers in Rust

1. The implementation details of borrow rules check in runtime.
2. How to convert C pointers to Rust pointers? As part of the C2Rust project.

<!-- ##  -->