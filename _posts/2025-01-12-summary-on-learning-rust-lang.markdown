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

## About Concurrency

1. `thread::spawn`: remember to call `join()`. Also, pass `FnOnce` closures(with `move` keyword) if you want to pass a vector or else.
2. `Mutex<T>`I consider it to be an augmented `RefCell` with "internal mutability", and also "thread safety".
3. `Arc<T>` is an augmemnted `Rc<T>` with thread safety.
4. `Send` and `Sync` cannot be implemented safely(`unsafe` block must be used for such internal implementations), so it is not discussed here, but rather in the "Unsafe Rust" chapter.

## About Pattern and Matching

1. `..` will expand as many values as it needs to be. 
```rust
fn main() {
    let numbers = (2, 4, 8, 16, 32);

    match numbers {
        (first, .., last) => {
            println!("Some numbers: {first}, {last}");
        }
    }
}
```
2. in `match` arms, `if` statement can be added to add constraints.
```rust
    let num = Some(4);

    match num {
        Some(x) if x % 2 == 0 => println!("The number {x} is even"),
        Some(x) => println!("The number {x} is odd"),
        None => (),
    }
```
3. `|` means or: this code means 4 or 5 or 6 AND y is true;
```rust
    let x = 4;
    let y = false;

    match x {
        4 | 5 | 6 if y => println!("yes"),
        _ => println!("no"),
    }
```
4. `@` binding:
```rust
    enum Message {
        Hello { id: i32 },
    }

    let msg = Message::Hello { id: 5 };

    match msg {
        Message::Hello {
            id: id_variable @ 3..=7,
        } => println!("Found an id in range: {id_variable}"),
        Message::Hello { id: 10..=12 } => {
            println!("Found an id in another range")
        }
        Message::Hello { id } => println!("Found some other id: {id}"),
    }
```
