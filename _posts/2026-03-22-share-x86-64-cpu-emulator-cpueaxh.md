---
layout: post
title: '[Share] X86-64 CPU Emulator "Cpueaxh"'
description: 在网上发现了开源的x86-64 CPU模拟器
date: 2026-03-22 20:20 -0600
---

原帖在看雪论坛上：https://bbs.kanxue.com/thread-290354.htm

这是另一个相关的post：https://key08.com/index.php/2026/01/24/3039.html

这是Github repo：https://github.com/saileaxh/cpueaxh

开发者开发这玩意的目的是为了绕过`PspCallProcessNotifyRoutines`？不过除此之外，这玩意据称不需要再人工去map memory了，比Unicorn Emulator方便许多。

不知道支不支持Linux。目前从blog来看，开发者主要是针对Windows设计的。

## 能不能用于分析VMP？

