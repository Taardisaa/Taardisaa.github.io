---
layout: post
title:  "Summary on Learning PyTorch"
date:   2025-01-11 23:37:00 -0700
categories: Deep Learning
---

## Suggested Tutorial

[Intro to PyTorch(Simplified Chinese)](https://datawhalechina.github.io/thorough-pytorch/index.html)

## About Model Evaluation Metrics

Common metrics to evaluate machine learning models include:

- Accuracy: Percentage of correct predictions
- Precision: True positives / (True positives + False positives)
- Recall: True positives / (True positives + False negatives)
- F1 Score: Harmonic mean of precision and recall
- ROC Curve: True Positive Rate vs False Positive Rate
- AUC: Area under the ROC curve

PyTorch provides tools to calculate these metrics through `torchmetrics` library.

The tutorial also discussed about the above metrics, with custom algorithms.

## About Tensor

Suggestions on understanding tensor:
1. treat Tensor as an extended Array/Vector/Matrix, with multiple dimensions.
2. try not to think of its "visual" representation, like a common matrix or 1-D array. Rather, think of the "meaning" for each dimension. For example, for a single picture, it can be represented by a 3-D tensor: `(width, height, channel)`. For a more specific one, let's say, a random RGB image of size 256*256, should be initialized by `torch.rand(256, 256, 3)`. Furthermore, for a batch of pictures, we could use a 4-D tensor, by addinig another dimension to represent the "total number" of pictures, `(number_of_pics, width, height, channel)`.
3. See PyTorch doc for further details on how to operate on those tensors exactly.
4. I don't like "broadcasting", 'cause I think it's a very dangerous feature, that will introduce hidden errors.

## About Autograd

1. Cool stuff! I finally understand how exactly those gradients are calculated. Keep in mind of `require_grads=True` and `grad_fn` something.
2. Here's some math thing happening, keep in mind of the Jaccob Matrix: suppose a vector function $y = f(x)$, the gradients between $y$ and $x$ is a jaccob matrix. For function $f$: $R^n -> R^m$, the size of its Jaccob matrix is $(m, n)$:


$$
J=\left(\begin{array}{ccc}\frac{\partial y_{1}}{\partial x_{1}} & \cdots & \frac{\partial y_{1}}{\partial x_{n}} \\ \vdots & \ddots & \vdots \\ \frac{\partial y_{m}}{\partial x_{1}} & \cdots & \frac{\partial y_{m}}{\partial x_{n}}\end{array}\right)
$$

3. Also about chain rule: suppose $v$ is the gradient of $l = g(y)$, 

$$ 
v=\left(\begin{array}{lll}\frac{\partial l}{\partial y_{1}} & \cdots & \frac{\partial l}{\partial y_{m}}\end{array}\right)
$$

then we can get

$$
v J=\left(\begin{array}{lll}\frac{\partial l}{\partial y_{1}} & \cdots & \frac{\partial l}{\partial y_{m}}\end{array}\right)\left(\begin{array}{ccc}\frac{\partial y_{1}}{\partial x_{1}} & \cdots & \frac{\partial y_{1}}{\partial x_{n}} \\ \vdots & \ddots & \vdots \\ \frac{\partial y_{m}}{\partial x_{1}} & \cdots & \frac{\partial y_{m}}{\partial x_{n}}\end{array}\right)=\left(\begin{array}{lll}\frac{\partial l}{\partial x_{1}} & \cdots & \frac{\partial l}{\partial x_{n}}\end{array}\right)
$$

(J here is the matrix to calc the gradient between $y$ and $x$ just discussed above)

4. Remember that gradient is accumulated.
5. Though for most of the time, we(actually I mean myself, as a 'not-very-interested-in-maths-guy' involved in traditional software security) just need to use the API call instead of studying its mathematical or implementation details, its still kinda fun though.

## About Training in Multiple Graphic Cards

This section is skipped because:
1. I don't have multiple graphic cards right now.
2. I don't care about how to make the training process more efficient.
3. They are all wrapped in a convenient API: `nn.DataParallel(model)`. (Data parallelism only)
4. Distributed Data Parallel is kinda difficult for me.


