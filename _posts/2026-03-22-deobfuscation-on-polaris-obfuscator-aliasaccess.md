---
layout: post
title: Deobfuscation on Polaris-Obfuscator/AliasAccess
description: Analyzing and deobfuscating Polaris Obfuscator's AliasAccess pass, which routes local variable accesses through randomized struct packing and multi-hop pointer chains.
date: 2026-03-22 18:11 -0600
math: true
---

## AliasAccess 简要介绍

AliasAccess pass 的核心思路是：把函数里的局部变量（alloca）藏进随机生成的 struct 里，再通过一条多跳的间接指针链来访问它们，而不是直接引用。

原本的代码：

```c
int x = 42;
use(x);
```

经过混淆后，变量 `x` 被塞进某个 struct 的某个随机字段里，访问时变成：

```c
// 穿过若干层 getter 调用，最终 GEP 到那个字段
v9 = getter_1(v50);         // transit hop 1
v10 = getter_2(*v9);        // transit hop 2
*(int*)(*v10 + offset) = 42; // 最终写入 raw struct 的字段
```

反编译出来的伪代码大概是这样：

```c
v9 = (_QWORD *)sub_1BE0(v50);
*(_DWORD *)(*(_QWORD *)sub_1BF0(*v9) + 28LL) = 42;
```

其中每一个 `sub_1Bxx` 都是一个 getter 函数，`+28` 是该变量在 raw struct 里的字段偏移。

## 混淆 Pass 的实现

实现代码见 `src/llvm/lib/Transforms/Obfuscation/AliasAccess.cpp`，`process()` 函数分 7 个阶段完成混淆。

### 数据结构

每个节点用 `ReferenceNode` 表示：

```cpp
struct ReferenceNode {
    AllocaInst *AI;                                      // 对应的 alloca 指令
    bool IsRaw;                                          // 是否是叶节点（raw node）
    unsigned Id;
    std::map<AllocaInst *, ElementPos> RawInsts;         // raw node 专用：alloca -> 字段位置
    std::map<unsigned, ReferenceNode *> Edges;           // 出边：slot index -> 子节点
    std::map<AllocaInst *, std::vector<unsigned>> Path;  // 可达性：alloca -> 到达它所需的 slot 序列
};
```

- **Raw node**（`IsRaw = true`）：叶节点，真正存储变量数据的地方。其 `AI` 是一个自定义 struct 的 alloca，该 struct 里混杂了真实字段和 `i8*` dummy 字段。
- **Transit node**（`IsRaw = false`）：中间节点，不存储任何变量数据，只持有指向其他节点的指针。其 `AI` 是 `TransST` 的 alloca，`TransST` 本质上就是 `{ i8* slot[BRANCH_NUM] }`。

### Phase 1：收集 alloca

遍历函数所有指令，收集对齐 <= 8 的 `AllocaInst`，这些是待混淆的候选变量。

```cpp
for (BasicBlock &BB : F) {
  for (Instruction &I : BB) {
    if (isa<AllocaInst>(I)) {
      AllocaInst *AI = (AllocaInst *)&I;
      if (AI->getAlign().value() <= 8) {
        AIs.push_back((AllocaInst *)&I);
      }
    }
  }
}
```

### Phase 2：构造 TransST

构造一个固定的 transit struct 类型，本质上就是 `{ i8* slot[BRANCH_NUM] }`。每个 slot 要么指向下一个节点，要么为 null。BRANCH_NUM 控制每个 transit 节点最多有几条出边。

```cpp
for (unsigned i = 0; i < BRANCH_NUM; i++) {
  Slots.push_back(PtrType);
}
TransST->setBody(Slots);
```

### Phase 3：随机分桶

把所有 alloca 随机分配到 `AIs.size()` 个 bucket 里，分布不均匀，其中同一个 bucket 里的 alloca 会被打包进同一个 raw struct。

```cpp
std::vector<std::vector<AllocaInst *>> Bucket;
for (unsigned i = 0; i < AIs.size(); i++) {
  Bucket.push_back(std::vector<AllocaInst *>());
}
for (AllocaInst *AI : AIs) {
  unsigned Index = getRandomNumber() % AIs.size();
  Bucket[Index].push_back(AI);
}
```

### Phase 4：构造 Raw Node

对每个非空 bucket，创建一个 raw node。struct 的 slot 数为 `Items.size() * 2 + 1`：

- 真实字段：`Items.size()` 个，类型是对应 alloca 的原始类型，放在随机选的位置
- Dummy 字段：剩余位置填 `i8*`，纯粹是迷惑性 padding

下面是一个例子：

```
struct RawST {
    i8     *dummy_0;   // padding
    int32_t real_x;    // <- 真正的变量 x，放在随机位置
    i8     *dummy_2;   // padding
    float   real_y;    // <- 真正的变量 y
    i8     *dummy_4;   // padding
};
```

其中，5个字段里面，有两个是真的有用的；剩下的dummy只用于增加逆向时的难度。

```cpp
ReferenceNode *RN = new ReferenceNode();
RN->IsRaw = true;
StructType *ST = StructType::create(F.getContext());
unsigned Num = Items.size() * 2 + 1;

// 随机选 Items.size() 个不重复的位置放真实字段
getRandomNoRepeat(Num, Items.size(), Random);
for (unsigned i = 0; i < Items.size(); i++) {
  AllocaInst *AI = Items[i];
  unsigned Idx = Random[i];
  Slots[Idx] = AI->getAllocatedType();  // 真实类型
  ElementPos EP;
  EP.Type = ST;
  EP.Index = Idx;
  RN->RawInsts[AI] = EP;  // 记录 alloca -> 字段位置的映射
}
// 剩余位置填 i8* dummy
for (unsigned i = 0; i < Num; i++) {
  if (!Slots[i]) Slots[i] = PtrType;
}
ST->setBody(Slots);
RN->AI = IRB.CreateAlloca(ST);
```

### Phase 5：构造 Transit Node

创建 `Graph.size() * 3` 个 transit 节点，形成一个有向无环图（DAG）。每个 transit 节点随机选几条出边，指向已有的节点（raw 或 transit），并在函数入口处 emit store 指令把子节点指针写入对应的 slot。同时，**Path 自底向上传播可达性**：一个 transit 节点知道"从我的 slot[N] 出发，能到达哪些 alloca"，这是 Phase 6 use-site 改写的依据。

```cpp
unsigned Num = Graph.size() * 3;
for (unsigned i = 0; i < Num; i++) {
  ReferenceNode *Parent = new ReferenceNode();
  AllocaInst *Cur = IRB.CreateAlloca(TransST);
  Parent->AI = Cur;
  Parent->IsRaw = false;
  unsigned BN = getRandomNumber() % BRANCH_NUM;  // 随机决定出边数量
  getRandomNoRepeat(BRANCH_NUM, BN, Random);       // 随机选 BN 个不重复的 slot index
  for (unsigned j = 0; j < BN; j++) {
    unsigned Idx = Random[j];
    ReferenceNode *RN = Graph[getRandomNumber() % Graph.size()];  // 随机选子节点
    Parent->Edges[Idx] = RN;
    // 运行时：Cur->slot[Idx] = RN->AI
    IRB.CreateStore(RN->AI,
        IRB.CreateGEP(TransST, Cur, {IRB.getInt32(0), IRB.getInt32(Idx)}));
    // 传播可达性到 Parent->Path
    if (RN->IsRaw) {
      for (auto Iter = RN->RawInsts.begin(); Iter != RN->RawInsts.end(); Iter++)
        Parent->Path[Iter->first].push_back(Idx);
    } else {
      for (auto Iter = RN->Path.begin(); Iter != RN->Path.end(); Iter++)
        Parent->Path[Iter->first].push_back(Idx);
    }
  }
  Graph.push_back(Parent);  // push_back 在末尾，保证不会有环
}
```

> 原本本人以为这样的链式结构有可能会意外引入环，导致无限死循环；然而后面仔细观察发现，Transit 节点只能指向比自己**更早**加入 Graph 的节点，`push_back` 在 for 循环末尾执行，天然保证了 DAG 结构，链条一定终止于 raw leaf.

### Phase 6：改写 Use-Site

对每个用到原始 alloca 的操作数，in-place 替换成 chain 计算的结果：

1. 从 Graph 中随机选一个能到达该 alloca 的入口节点
2. 沿 Path 逐跳 emit getter 调用（每跳一次 `CreateCall` + `CreateLoad`），直到到达 raw node
3. 在 raw node 上 emit GEP，取得该 alloca 对应的字段地址
4. `U.set(VP)` 原地替换操作数

```cpp
for (Use &U : I.operands()) {
  AllocaInst *AI = (AllocaInst *)Opnd;
  IRB.SetInsertPoint(&I);
  std::shuffle(Graph.begin(), Graph.end(), std::default_random_engine());
  // 找一个能到达 AI 的入口节点
  ReferenceNode *Ptr = nullptr;
  for (ReferenceNode *RN : Graph) {
    if (RN->Path.find(AI) != RN->Path.end() ||
        (RN->IsRaw && RN->RawInsts.find(AI) != RN->RawInsts.end())) {
      Ptr = RN; break;
    }
  }
  Value *VP = Ptr->AI;
  // 沿链逐跳 emit getter 调用
  while (!Ptr->IsRaw) {
    std::vector<unsigned> &Idxs = Ptr->Path[AI];
    unsigned Idx = Idxs[getRandomNumber() % Idxs.size()];
    if (Getter.find(Idx) == Getter.end())
      Getter[Idx] = buildGetterFunction(*F.getParent(), TransST, Idx);
    VP = IRB.CreateLoad(PtrType, IRB.CreateCall(FunctionCallee(Getter[Idx]), {VP}));
    Ptr = Ptr->Edges[Idx];
  }
  // 到达 raw node，GEP 取字段地址
  ElementPos &EP = Ptr->RawInsts[AI];
  VP = IRB.CreateGEP(EP.Type, VP, {IRB.getInt32(0), IRB.getInt32(EP.Index)});
  U.set(VP);  // 原地替换操作数
}
```

控制流、基本块结构不变，只是操作数从直接引用 alloca 变成了一串 call chain 的结果。

### Phase 7：清理

删除原始的 alloca 指令（已被 struct 字段替代），释放 graph 节点内存。

```cpp
for (AllocaInst *AI : AIs)
  AI->eraseFromParent();
for (auto Iter = Graph.begin(); Iter != Graph.end(); Iter++)
  delete *Iter;
```

### Getter 函数

Getter 函数由 `buildGetterFunction` 生成，签名为 `i8*(i8*)`：

```cpp
i8* getter(i8* ptr) {
    return &((TransST*)ptr)->slot[Index];
}
```

**关键弱点**：`Index` 是编译期静态确定的常量，直接 baked 进 GEP 的 immediate 里。每个唯一的 index 对应一个独立的 getter 函数，lazy 创建并缓存在 `Getter` map 里。这是一个潜在的反混淆突破口。

## 混淆效果分析

两层叠加：

- **Struct 内部**：真假字段混杂，字段位置随机。
- **Struct 之间**：多跳指针链，每个 use-site 的入口节点随机选取，call chain 深度不固定

源码片段：

```c
print_hash_value = 1;
```

从混淆后binary反编译的伪代码来看（IDA Pro 示例，O0优化）：

```c
// 访问 print_hash_value = 1，实际经过两跳
v9  = (_QWORD *)sub_1BE0(v50);                          // transit hop 1
*(_DWORD *)(*(_QWORD *)sub_1BF0(*v9) + 28LL) = 1;      // transit hop 2 + GEP(offset=0x1c)
```

其中：
- `v50` 是某个 transit node 的 alloca（栈上的 `local_xxx`）
- `sub_1BE0` / `sub_1BF0` 是 getter 函数（或其 inline 展开）
- `+28`（0x1c）是 `print_hash_value` 在 raw struct 里的字段偏移

### 在high level optimization下的表现

我又在O2优化下进行了一次测试：

```c
int __fastcall main(int argc, const char **argv, const char **envp)
{
    // 省略variable declarations

  if ( argc == 2 )
  {
    v3 = strcmp(argv[1], "1");
    v4 = v3 != 0;
    v5 = v3 == 0;
  }
  else
  {
    v5 = 0;
    v4 = 1;
  }
  si128 = _mm_load_si128((const __m128i *)&xmmword_2010);
  v7 = 0LL;
  v8 = _mm_load_si128((const __m128i *)&xmmword_2020);
  v9 = _mm_load_si128((const __m128i *)&xmmword_2030);
  do
  {
    v10 = _mm_srai_epi32(_mm_slli_epi32(si128, 0x1Fu), 0x1Fu);
    v11 = _mm_srli_epi32(si128, 1u);
    v12 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v11, v8), v10), _mm_andnot_si128(v10, v11));
    v13 = _mm_slli_epi32(v12, 0x1Fu);
    v14 = _mm_srli_epi32(v12, 1u);
    v15 = _mm_srai_epi32(v13, 0x1Fu);
    v16 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v14, v8), v15), _mm_andnot_si128(v15, v14));
    v17 = _mm_srli_epi32(v16, 1u);
    v18 = _mm_srai_epi32(_mm_slli_epi32(v16, 0x1Fu), 0x1Fu);
    v19 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v17, v8), v18), _mm_andnot_si128(v18, v17));
    v20 = _mm_srli_epi32(v19, 1u);
    v21 = _mm_srai_epi32(_mm_slli_epi32(v19, 0x1Fu), 0x1Fu);
    v22 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v20, v8), v21), _mm_andnot_si128(v21, v20));
    v23 = _mm_srai_epi32(_mm_slli_epi32(v22, 0x1Fu), 0x1Fu);
    v24 = _mm_srli_epi32(v22, 1u);
    v25 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v24, v8), v23), _mm_andnot_si128(v23, v24));
    v26 = _mm_slli_epi32(v25, 0x1Fu);
    v27 = _mm_srli_epi32(v25, 1u);
    v28 = _mm_srai_epi32(v26, 0x1Fu);
    v29 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v27, v8), v28), _mm_andnot_si128(v28, v27));
    v30 = _mm_srli_epi32(v29, 1u);
    v31 = _mm_srai_epi32(_mm_slli_epi32(v29, 0x1Fu), 0x1Fu);
    v32 = _mm_or_si128(_mm_and_si128(_mm_xor_si128(v30, v8), v31), _mm_andnot_si128(v31, v30));
    v33 = _mm_srli_epi32(v32, 1u);
    v34 = _mm_srai_epi32(_mm_slli_epi32(v32, 0x1Fu), 0x1Fu);
    *(__m128i *)((char *)&crc32_tab + v7) = _mm_or_si128(
                                              _mm_and_si128(_mm_xor_si128(v33, v8), v34),
                                              _mm_andnot_si128(v34, v33));
    si128 = _mm_add_epi32(si128, v9);
    v7 += 16LL;
  }
  while ( v7 != 1024 );
  transparent_crc(0LL, "g_4", v5);
  transparent_crc(g_7, "g_7[i]", v5);
  if ( v4 )
  {
    transparent_crc(dword_4024, "g_7[i]", v5);
    transparent_crc(dword_4028, "g_7[i]", v5);
    transparent_crc(g_11, "g_11[i].f0", v5);
  }
  else
  {
    printf("index = [%d]\n", 0LL);
    transparent_crc(dword_4024, "g_7[i]", v5);
    printf("index = [%d]\n", 1LL);
    transparent_crc(dword_4028, "g_7[i]", v5);
    printf("index = [%d]\n", 2LL);
    transparent_crc(g_11, "g_11[i].f0", v5);
    printf("index = [%d]\n", 0LL);
  }
  printf("checksum = %X\n", (unsigned int)~crc32_context);
  return 0;
}
```

仔细一看，感觉AliasAccess添加的混淆被优化掉了不少。比如`v4 = 1;`对应的就是源码`print_hash_value = 1;`。然后上面一坨乱七八糟的SIMD指令，似乎是Csmith源码里面本来就有的crc32计算逻辑，和AliasAccess没啥关系。

**因此得出初步结论**：AliasAccess需要配合Linear MBA等其他反优化手段，才能在O2/O3优化下获得更好的混淆效果。

## 反混淆方案

下面介绍如何在二进制层面还原 AliasAccess 的混淆。整体流程分为三个阶段：**定位** → **求解** → **Patch**，逐步展开。

### 总览

AliasAccess 混淆后，每一次对局部变量的读写都变成了一条 getter 调用链：

```
prologue init stores → getter call → getter call → ... → deref → 数据访问
```

我们的目标是把每个数据访问点的间接链恢复成直接的 `rbp` 相对寻址。核心思路是**分层求解**：

1. **结构化定位**：基于 CFG 结构找到所有经过 getter 链的数据访问点（不区分读/写）
2. **Chain-walk 求解**：从 use site 沿 CFG 后向遍历 getter 链，利用 prologue 初始化的 transit node 内存逐跳读取，得到最终的 `rbp` 相对偏移。不需要跑全函数符号执行，不涉及路径爆炸。
3. **二进制 Patch**：把最后一跳 getter call 替换成 `lea rax, [rbp+K]`，NOP 掉 deref 指令，最后清理残留的 dead getter call。

### 步骤一：识别 Getter 函数

Getter 函数是 AliasAccess 生成的小函数，签名统一为 `i8*(i8*)`，做的事情就是 `return rdi + offset`。在二进制层面：

```asm
mov  rax, rdi
add  rax, 0x10     ; offset 是编译期常量
ret
```

我们通过 VEX IR 来匹配这个 pattern：检查函数是否为单基本块、以 `Ijk_Ret` 结尾、且包含 `Add64(GET(rdi), Const) → PUT(rax)` 模式：

```python
def _extract_getter_offset(proj, getter_addr):
    irsb = proj.factory.block(getter_addr).vex
    if irsb.jumpkind != 'Ijk_Ret':
        return None
    rax_off = proj.arch.registers['rax'][0]
    for s in irsb.statements:
        if isinstance(s, pyvex.stmt.Put) and s.offset == rax_off:
            if isinstance(s.data, pyvex.expr.RdTmp):
                tmp = s.data.tmp
                for s2 in irsb.statements:
                    if isinstance(s2, pyvex.stmt.WrTmp) and s2.tmp == tmp:
                        if isinstance(s2.data, pyvex.expr.Binop) and 'Add' in s2.data.op:
                            for arg in s2.data.args:
                                if isinstance(arg, pyvex.expr.Const):
                                    return arg.con.value
    return None
```

返回值就是该 getter 的常量偏移（如 `0x10`、`0x18` 等），如果不匹配则返回 `None`。

如果 getter 被 MBA（Mixed Boolean-Arithmetic）混淆，VEX pattern match 会失败。此时自动回退到 **per-getter symex**，即对这单个小函数做符号执行，输入 symbolic `rdi`，求解 `rax - rdi` 得到 offset：

```python
def _symex_getter_offset(proj, getter_addr):
    irsb = proj.factory.block(getter_addr).vex
    if irsb.jumpkind != 'Ijk_Ret':
        return None  # 只对 ret 函数尝试
    rdi = claripy.BVS("rdi", 64)
    state = proj.factory.call_state(getter_addr, rdi)
    simgr = proj.factory.simgr(state)
    simgr.run()
    if not simgr.deadended:
        return None
    rax = simgr.deadended[0].regs.rax
    return simgr.deadended[0].solver.eval(rax - rdi)
```

通过约束符号执行的粒度和范围，我们能尽量避免符号执行出现符号爆炸的情况。

### 步骤二：定位所有被混淆的数据访问

**核心观察**：每一个被混淆的数据访问（不管是读还是写）都有相同的结构：

```
[前驱块] call getter  →  [使用块] mov REG, [REG]  →  数据访问 [REG+offset]
                              ↑ deref（自引用加载）
```

也就是说，使用块的前驱块一定以 getter 调用结尾（`Ijk_Call`），而使用块内一定包含一条 self-deref 指令，即从某个寄存器加载到同一个寄存器（`mov rax, [rax]`）。

检测分两步：

**1. 前驱检测**：遍历函数所有基本块，找到以 getter call 结尾的块（`Ijk_Call` 且 callee 是已识别的 getter 函数）。

**2. Self-deref 检测**：在后继块中找到 `mov REG, [REG]` 指令。使用 capstone 的结构化操作数 API，完全不依赖硬编码的字节序列或特定寄存器名：

```python
import capstone.x86 as cx

def _find_self_deref_insn(block):
    for insn in block.capstone.insns:
        if insn.mnemonic != 'mov' or len(insn.operands) != 2:
            continue
        dst, src = insn.operands
        if (dst.type == cx.X86_OP_REG and src.type == cx.X86_OP_MEM
                and src.mem.base == dst.reg
                and src.mem.index == 0 and src.mem.disp == 0):
            return insn
    return None
```

两个条件同时满足的块就是被混淆的数据访问点。中间跳转块（`mov [rax], rdi` 传参给下一个 getter）不包含 self-deref，所以不会被误报。

> 早期方案使用 DDG（数据依赖图）的后向切片来判断 use site 是否与 getter 函数有关，但 DDG 存在精度问题（寄存器别名导致误报），且只能检测 VEX `Store` 语句，漏掉了所有的读操作。最终方案完全基于 CFG 结构，不需要 DDG，也不需要 CFGEmulated; 最简单的`CFGFast` 就够了。

### 步骤三：Chain-walk 求解

对于每个被混淆的使用块，我们需要知道 getter 链最终解析出的 `rbp` 相对地址。

#### Chain-walk：分层求解

该方案不跑全函数的符号执行。符号执行只用在两个最小粒度的地方：

- **Prologue**（一次性）：执行函数prologue block来初始化 transit node 内存
- **Per-getter**（按需）：当 VEX pattern match 失败时，对单个 getter 函数做 symex 求解 offset

中间的use chain通过**纯内存读取**完成。

```
prologue symex (一次)  →  chain-walk (纯内存读取)
                            ↑ getter offset: VEX match ‖ per-getter symex
```

具体步骤：

**1. 后向遍历 getter 链**。从使用块出发，沿 CFG 向后走，每一步找到以 getter call 结尾的前驱块，记录 getter offset。当遇到**链起点**时停止，其判定条件有两个：

- **Self-deref 边界**（主要）：如果当前块自身包含 self-deref，说明它是上一条链的 use site，同时也是本条链的起点（AliasAccess 的块结构是交错的）。
- **非 getter 前驱**（fallback）：如果当前块的前驱不是 getter call（比如 prologue），则它就是链的第一跳。

```python
for depth in range(MAX_DEPTH):
    pred = _find_getter_pred(proj, current, func_blocks, _resolve_getter_offset)
    if pred is None:
        break
    chain.append(pred['offset'])
    current = pred['block_addr']

    # 链边界检测：当前块有 self-deref → 是上条链的 endpoint，也是本链的起点
    if _has_self_deref(proj.factory.block(current)):
        chain_entry = current
        break

    # 兜底：前驱不是 getter call → 本块就是第一跳
    if _find_getter_pred(proj, current, func_blocks, _resolve_getter_offset) is None:
        chain_entry = current
        break
```

**2. 获取起始指针**。链入口块包含一条 `lea rdi, [rbp-K]`（加载 transit node 地址）和紧接着的 `call getter`。我们不解析 `lea` 指令的编码，而是对这个**单块做一次 symex**，即用 prologue 状态的寄存器和内存执行这一个块，然后读取 `rdi` 的具体值：

```python
if chain_entry == func.addr:
    # 链从 prologue 开始：prologue 状态已经持有正确的 rdi
    initial_ptr = base_state.regs.rdi.concrete_value
else:
    # 非 prologue 入口：单块 symex
    entry_state = base_state.copy()
    entry_state.regs.rip = claripy.BVV(chain_entry, 64)
    succ = entry_state.step()
    initial_ptr = succ.flat_successors[0].regs.rdi.concrete_value
```

这样即使 O2/O3 把 `lea rdi, [rbp-K]` 优化成其他形式（比如 `mov rdi, rbp; add rdi, -K`）也能正确处理。

**3. 前向读取 transit node 内存**。拿到起始指针后，沿链的每一跳：`ptr = prologue_mem[ptr + getter_offset]`。最后一次读取得到的就是 raw struct 的地址。

```python
ptr = initial_ptr + chain[0]
for getter_offset in chain[1:]:
    mem = base_state.memory.load(ptr, 8, endness=proj.arch.memory_endness)
    ptr = mem.concrete_value + getter_offset

# 最终 deref：读取 slot 指针得到 raw struct 地址
mem = base_state.memory.load(ptr, 8, endness=proj.arch.memory_endness)
return mem.concrete_value - RBP_CONCRETE
```

### 步骤四：Patch

得到每个使用块的 `rbp` 相对偏移后，在二进制上做两处修改：

**1. 替换最后一跳 getter call**。把前驱块的 `call getter` 指令替换为 `lea rax, [rbp + K]`。LEA 指令通常比 CALL 短（disp8 编码只需 4 字节 vs CALL 的 5 字节），多余的字节填 NOP：

```python
lea_bytes, _ = ks.asm(f"lea rax, [rbp + ({rbp_rel})]", addr=call_insn.address)
patch = bytes(lea_bytes) + b'\x90' * (call_insn.size - len(lea_bytes))
```

**2. NOP 掉 deref 指令**。使用块的 `mov rax, [rax]` 必须去掉，否则会把我们 LEA 设置的直接地址再解引用一次，导致访问错误的内存。

两处 patch 是**分开**做的，因为它们之间可能夹着用于计算存储值的指令（比如 `mov edi, [rbp-0x22c]` 加载要写入的值），这些指令必须保持不变。

```
修改前:                              修改后:
call getter     (5B)                lea rax, [rbp+K]  (4B) + nop (1B)
mov edi, [rbp-0x22c]  ← 保持不变    mov edi, [rbp-0x22c]  ← 保持不变
mov rax, [rax]  (3B)  ← deref       nop nop nop           ← NOP'd
mov [rax], edi        ← store       mov [rax], edi        ← 现在 rax 直接指向目标
```

### 步骤五：清理中间跳转的 Dead Code

经过步骤四之后，所有数据访问端点都已经被 LEA 替代。但中间的 getter 跳转指令（`lea rdi,...; call getter; mov rdi,[rax]`）还残留着。它们现在是 dead code，因为计算出来的 `rax` 值总会被后续的 LEA 覆盖。

对每个残留的 getter call 块，NOP 掉 `call` 指令和后继块开头的结果加载。

注意：**不能 NOP 整个块**。因为 AliasAccess 的块结构是交错的，同一个块可能既包含上一条链的数据存储，又包含下一条链的 getter call。只 NOP `call` 指令本身和后继块的结果加载指令就够了。

### 效果

IDA 反编译效果对比：

```c
// 混淆后
v9 = (_QWORD *)sub_1BC0(v27, argv, v5);
sub_1BD0(*v9);
// ... 大量 getter 调用和间接指针操作 ...

// Patch 后
func_1();
transparent_crc(g_4, "g_4", v6);
for ( i = 0; i < 3; ++i ) {
    transparent_crc(g_7[i], "g_7[i]", v6);
    if ( v6 ) printf("index = [%d]\n", (unsigned int)i);
}
```

与原始源码在结构上完全一致。


## 已知 Bug

在分析和测试 AliasAccess pass 的过程中，我们还发现它在 O1+ 优化级别下存在一个会导致崩溃的 bug。

### 在 O1+ 下，被混淆的 alloca 作为 PHI 操作数时会导致崩溃

#### Phase 6 做错了什么

Phase 6 会原地改写每一个被混淆的 alloca 的 use：

```cpp
IRB.SetInsertPoint(&I);   // 在指令 I 前插入
// … emit getter calls and GEP …
U.set(VP);                // 把操作数替换成 GEP 结果
```

当 `I` 是普通指令（load、store、call……）时，这样做没有问题。但当 `I` 是 **PHI node** 时就会出错。

LLVM 要求一个基本块内所有 PHI node 必须出现在任何 non-PHI 指令之前。调用 `IRB.SetInsertPoint(&phi)` 然后插入 `call` + `load` + `getelementptr` 序列，会把这些 non-PHI 指令放到 PHI **之前**，从而产生非法 IR。

此外，GEP 结果 `%VP` 现在定义在与 PHI node **同一个**基本块中。当 `U.set(VP)` 把旧的 alloca 操作数替换为 `%VP` 时，PHI 就会引用来自自己所在块的值，而不是来自前驱块的值，这违反了 PHI 的语义。

#### 为什么 O1+ 会触发而 O0 不会

在 **O0** 下，每个局部变量都有自己的 `alloca`。所有读写都通过显式的 `load`/`store` 指令完成。alloca 地址永远不会直接出现在 PHI 操作数中，因为存在的 PHI node 合并的是 *loaded* 的标量值，而不是 alloca 指针。

在 **O1+** 下，`mem2reg` 会把指针变量提升为 SSA 形式。一个类似这样的 C 模式：

```c
int32_t *p = cond ? &local_var : &global_var;
*p = 42;
```

提升之后会变成：

```llvm
merge_block:
  %p = phi ptr [ %alloca_local_var, %then ], [ @global_var, %else ]
  store i32 42, ptr %p
```

现在 alloca 地址本身（`%alloca_local_var`）成了 PHI 的操作数。Phase 6 找到这个 use，调用 `IRB.SetInsertPoint(&phi)`，在 PHI 之前插入 getter chain，从而产生了如下所示的非法块布局。

#### 产生的具体非法 IR（sample_021，func_38，block `102`）

Pass 执行前（概念上）：

```llvm
102:                         ; preds = %100, %32
  %orig = phi ptr [ %alloca_l_1219, %32 ], [ @g_1219, %100 ]
  ; … uses of %orig …
```

Pass 改写 `%alloca_l_1219` 之后：

```llvm
102:                         ; preds = %100, %32
  ; ← non-PHI 指令被 SetInsertPoint(&phi) 插入到此处
  %103 = call ptr @__obfu_aliasaccess_getter.146(ptr %12)
  %104 = load ptr, ptr %103, align 8
  %105 = call ptr @__obfu_aliasaccess_getter(ptr %104)
  %106 = load ptr, ptr %105, align 8
  %107 = getelementptr %1, ptr %106, i32 0, i32 2
  ; ← PHI node 现在出现在 non-PHI 指令之后 → 非法 IR
  %108 = phi ptr [ %107, %32 ], [ @g_1219, %100 ]
  ;                 ^^^^ 定义在当前块 102 内，而非前驱块 %32 → 同样非法
```

两个同时发生的违规：
1. Non-PHI 指令出现在了 block `102` 中 PHI node 的前面。
2. PHI 操作数 `%107` 定义在 `102` 本身，而不是在其声称的前驱块 `%32` 中。

#### 为什么崩溃发生在 SelectionDAG 而不是更早被捕获

在 O1 下，该 pipeline 配置中 LLVM verifier 并不会在每个 pass 之间运行，因此损坏的 IR 不会被检测到。后续的优化 pass（GVN、LICM……）恰好没有修改这个畸形的基本块。SelectionDAG 随后假设 IR 是良构的，对不存在的 PHI 状态进行解引用，导致在 `X86DAGToDAGISel::runOnMachineFunction` 内部产生空指针崩溃。

#### 修复方案

在 **Phase 1** 中过滤掉作为 PHI 操作数使用的 alloca，使其永远不会被打包进 raw struct：

```cpp
for (BasicBlock &BB : F) {
  for (Instruction &I : BB) {
    if (isa<AllocaInst>(I)) {
      AllocaInst *AI = (AllocaInst *)&I;
      if (AI->getAlign().value() <= 8) {
        bool hasPHIUse = false;
        for (User *U : AI->users())
          if (isa<PHINode>(U)) { hasPHIUse = true; break; }
        if (!hasPHIUse)
          AIs.push_back(AI);
      }
    }
  }
}
```

仅在 Phase 6 中跳过替换是不够的。如果 alloca 仍然被打包进了 raw struct（Phase 4），但其 PHI use 没有被替换，Phase 7 的 `AI->eraseFromParent()` 就会删除一个仍有活跃 use 的 alloca，从而导致另一个崩溃。即使对 Phase 7 的删除加了保护，结果在语义上也是错误的：non-PHI use 已经被重定向到 raw struct 字段，而 PHI 仍然持有原始 alloca 的地址。通过 PHI 结果进行的任何 load/store 都会命中未初始化的 alloca，而不是 raw struct 字段。

通过在 Phase 1 中将该 alloca 排除出 `AIs`，它永远不会获得 raw struct slot，其 use 永远不会被修改，也永远不会被删除。这些 alloca 不会被混淆，但正确性得以保证，pass 的其余部分继续正常工作。
