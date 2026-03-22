---
layout: post
title: Anti Deobfuscation on BogusControlFlow
date: 2026-03-20 22:26 -0600
math: true
---


## Introduction

这个混淆也算是从OLLVM继承下来的老玩意了；简单来说就是对于一个basic block，在它之前创建一个相同的basic block，这个新的basic block包含一个opaque predicate（一个永远为真/永远为假的条件，即new block永远也不会被真正执行到）；然后在这个新的block里面还可以相应的加入一些junk instructions，使得反编译器无法正确解析这个block。

具体可以看此篇：https://github.com/obfuscator-llvm/obfuscator/wiki/Bogus-control-flow

## Implementation Details

https://github.com/za233/Polaris-Obfuscator/blob/main/src/llvm/lib/Transforms/Obfuscation/BogusControlFlow.cpp

我们逐个函数的来分析：

### 1. 克隆basic block（`cloneAlterBasicBlock`）

```cpp
BasicBlock *BogusControlFlow::cloneAlterBasicBlock(BasicBlock *BB) {
  ValueToValueMapTy VMap;
  BasicBlock *CBB = CloneBasicBlock(BB, VMap, "cloneBB", BB->getParent());
  BasicBlock::iterator Iter = BB->begin();
  for (Instruction &I : *CBB) {
    for (unsigned i = 0; i < I.getNumOperands(); i++) {
      Value *V = MapValue(I.getOperand(i), VMap);
      if (V) {
        I.setOperand(i, V);
      }
    }
    SmallVector<std::pair<unsigned, MDNode *>, 4> MDs;
    I.getAllMetadata(MDs);
    for (std::pair<unsigned, MDNode *> pair : MDs) {
      MDNode *MD = MapMetadata(pair.second, VMap);
      if (MD) {
        I.setMetadata(pair.first, MD);
      }
    }
    I.setDebugLoc(Iter->getDebugLoc());
    Iter++;
  }
  return CBB;
}
```

这个函数的功能就是克隆一个basic block。当然也进行了相应的变量重命名，以及metadata的克隆。但是并没有对其进行任何的修改，没有添加junk code。

### 2. 拆分basic block

```cpp
/* 将函数中的每个基本块按每 Size 条指令拆分成多个较小的块 */
void BogusControlFlow::splitBasicBlock(Function &F, unsigned Size) {
  std::vector<Instruction *> SplitPoints;
  for (BasicBlock &BB : F) {
    unsigned Idx = 0;
    for (auto Iter = BB.getFirstInsertionPt(); Iter != BB.end(); Iter++) {
      Instruction &I = *Iter;
      if (I.isTerminator()) {
        continue;
      }
      if (Idx % Size == Size - 1) {
        SplitPoints.push_back(&I);
      }
      Idx = (Idx + 1) % Size;
    }
  }
  for (Instruction *I : SplitPoints) {
    BasicBlock *BB = I->getParent();
    BB->splitBasicBlock(I);
  }
}
```

这个函数的功能就是将函数中的每个基本块按每Size条指令拆分成多个较小的块。这样做的目的是为了增加基本块的数量，后面便可以插入更多的opaque predicates。

### 3. `process`函数

首先在函数头创建两个变量，`Var`和`Var0`。

```cpp
IRBuilder<> IRB(&*F.getEntryBlock().getFirstInsertionPt());
Value *Var = IRB.CreateAlloca(IRB.getInt64Ty());
Value *Var0 = IRB.CreateAlloca(IRB.getInt64Ty());
```

紧接着，得到两个变量`Mod`和`X`：

$$
Mod = 0x100000000 - rand32()
$$

$$
X = randPrime() \mod Mod
$$

```cpp
uint64_t Mod = 0x100000000 - getRand32();
// X is just a random prime % Mod
uint64_t X =
    primes[getRandomNumber() % (sizeof(primes) / sizeof(primes[0]))] % Mod;
```

然后`Var`和`Var0`都初始化成了`X`：

```cpp
// Both Var and Var0 are set to X at the beginning of the function.
IRB.CreateStore(IRB.getInt64(X), Var);
IRB.CreateStore(IRB.getInt64(X), Var0);
```

接下来的就是比较tricky的部分了。我先把代码贴上来，然后再进行分析：

```cpp
  std::vector<BasicBlock *> BBs;
  for (BasicBlock &BB : F) {
    // At the end of each basic block
    IRB.SetInsertPoint(BB.getTerminator());
    // a*x - b = x (mod m)
    // (a - 1) * x = b (mod m)
    uint64_t B = getRand32() % Mod;
    uint64_t Inv = getInverse(X, Mod);
    uint64_t A = ((B * Inv) % Mod + 1) % Mod;

    Value *V = IRB.CreateLoad(IRB.getInt64Ty(), Var0);
    IRB.CreateStore(
        IRB.CreateURem(
            IRB.CreateSub(IRB.CreateURem(IRB.CreateMul(IRB.getInt64(A), V),
                                         IRB.getInt64(Mod)),
                          IRB.getInt64(B)),
            IRB.getInt64(Mod)),
        Var0);
    BBs.push_back(&BB);
  }
```

首先来说说下面的这个IR到底是啥玩意：

```llvm
%v = load i64, ptr %Var0
%mul  = mul i64 A, %v
%rem1 = urem i64 %mul, Mod
%sub  = sub i64 %rem1, B
%rem2 = urem i64 %sub, Mod
store i64 %rem2, ptr %Var
```

转化成high level code的话就是：

```cpp
Var0 = ((A * Var0) % Mod - B) % Mod
```

那么这个公式到底算了啥玩意？从上面的计算公式可知：

$$
B = rand32() \bmod Mod
$$

$$
A = ((B * Inv(X, Mod)) \bmod Mod + 1) \bmod Mod
$$

这两个刻意构造的变量`A`和`B`满足如下的关系：

$$
(A - 1) * X = B \bmod Mod
$$

其中，`X`可以是任何一个小于`Mod`的数。这个公式只需要将上面的`A`和`B`代入进去就可以轻松验证。

下面，只需要稍微变形一下上面的公式就可以得到：

$$
A * X = (X + B) \bmod Mod
$$

将这个玩意带入到上面用于变换`Var0`的公式中就可以得到：

$$
\begin{align}
Var0 &= ((A * Var0) \bmod Mod - B) \bmod Mod \\
&= ((Var0 + B) \bmod Mod - B) \bmod Mod \\
&= Var0 \bmod Mod \\
&= Var0
\end{align}
$$

所以实际上`Var0`的值是永远不会改变的，一直和`Var`的值相等的。上面花里胡哨的计算其实只是为了让编译器和反编译器无法进行优化。

> **注意：这里的实现实际上有一个bug。** 上面的推导在数学模运算下是正确的，但IR中使用的是`sub i64`（无符号64位减法）+ `urem i64`。当`(A * X) % Mod < B`时，`sub`会发生unsigned underflow，wrap到$2^{64}$附近的大数，后续的`urem`就不再等价于数学模运算了。例如取`Mod=11, X=3, B=8`，数学上$(-8) \bmod 11 = 3$，但uint64下`0 - 8 = 2^{64} - 8`，$(2^{64} - 8) \bmod 11 = 8 \neq 3$。这会导致opaque predicate不再恒真，进而使程序陷入死循环。

接下来就是注入blocks和opaque predicates了：

```cpp  
for (BasicBlock *BB : BBs) {
    if (isa<InvokeInst>(BB->getTerminator()) || BB->isEHPad() ||
        BB->isEntryBlock()) {
      continue;
    }
    BasicBlock *BodyBB =
        BB->splitBasicBlock(BB->getFirstNonPHIOrDbgOrLifetime(), "bodyBB");
    BasicBlock *TailBB =
        BodyBB->splitBasicBlock(BodyBB->getTerminator(), "endBB");
    BasicBlock *CloneBB = cloneAlterBasicBlock(BodyBB);
    BB->getTerminator()->eraseFromParent();
    BodyBB->getTerminator()->eraseFromParent();
    CloneBB->getTerminator()->eraseFromParent();
    IRB.SetInsertPoint(BB);
    if (getRandomNumber() % 2) {
      Value *Cond = IRB.CreateICmpEQ(IRB.CreateLoad(IRB.getInt64Ty(), Var),
                                     IRB.CreateLoad(IRB.getInt64Ty(), Var0));
      IRB.CreateCondBr(Cond, BodyBB, CloneBB);
    } else {
      Value *Cond = IRB.CreateICmpNE(IRB.CreateLoad(IRB.getInt64Ty(), Var),
                                     IRB.CreateLoad(IRB.getInt64Ty(), Var0));
      IRB.CreateCondBr(Cond, CloneBB, BodyBB);
    }

    IRB.SetInsertPoint(BodyBB);
    if (getRandomNumber() % 2) {
      Value *Cond = IRB.CreateICmpEQ(IRB.CreateLoad(IRB.getInt64Ty(), Var),
                                     IRB.CreateLoad(IRB.getInt64Ty(), Var0));
      IRB.CreateCondBr(Cond, TailBB, CloneBB);
    } else {
      Value *Cond = IRB.CreateICmpNE(IRB.CreateLoad(IRB.getInt64Ty(), Var),
                                     IRB.CreateLoad(IRB.getInt64Ty(), Var0));
      IRB.CreateCondBr(Cond, CloneBB, TailBB);
    }

    IRB.SetInsertPoint(CloneBB);
    IRB.CreateBr(BodyBB);
  }
```

具体的插入稍微有点复杂，涉及在graph上的变换。不过整体变化后的图像可以直接参考：

![BogusControlFlow](/assets/img/posts/BogusControlFlow.png)

来源：https://www.apriorit.com/dev-blog/obfuscating-code-to-secure-android-apps

不过核心点其实还是在于opaque predicate的构造上。只要能够把opaque predicate给优化掉，那么具体的插入方式实际上并不重要；反编译器会自动把dead block给剪枝掉。

## BogusControlFlow2分析

刚刚快速看了一下源码，发现里面有两个都是BogusControlFlow的pass，分别是`BogusControlFlow`和`BogusControlFlow2`。前者就是我们上面分析的那个，而后者则是一个更为简单的版本？我没记错的话，以前OLLVM用的就是这个：

```cpp
Value *createBogusCmp(BasicBlock *insertAfter) {
  // if((y < 10 || x * (x + 1) % 2 == 0))
  Module *M = insertAfter->getModule();
  LLVMContext &context = M->getContext();
  GlobalVariable *xptr = new GlobalVariable(
      *M, Type::getInt32Ty(context), false, GlobalValue::CommonLinkage,
      ConstantInt::get(Type::getInt32Ty(context), 0), "x");
  GlobalVariable *yptr = new GlobalVariable(
      *M, Type::getInt32Ty(context), false, GlobalValue::CommonLinkage,
      ConstantInt::get(Type::getInt32Ty(context), 0), "y");

  IRBuilder<> builder(context);
  builder.SetInsertPoint(insertAfter);
  LoadInst *x = builder.CreateLoad(Type::getInt32Ty(context), xptr);
  LoadInst *y = builder.CreateLoad(Type::getInt32Ty(context), yptr);
  Value *cond1 =
      builder.CreateICmpSLT(y, ConstantInt::get(Type::getInt32Ty(context), 10));
  Value *op1 =
      builder.CreateAdd(x, ConstantInt::get(Type::getInt32Ty(context), 1));
  Value *op2 = builder.CreateMul(op1, x);
  Value *op3 =
      builder.CreateURem(op2, ConstantInt::get(Type::getInt32Ty(context), 2));
  Value *cond2 =
      builder.CreateICmpEQ(op3, ConstantInt::get(Type::getInt32Ty(context), 0));
  return BinaryOperator::CreateOr(cond1, cond2, "", insertAfter);
}
```

这里面生成的opaque predicate明显要简单很多，并没有涉及mod+invserse的计算。

在Pipeline.cpp里面，`BogusControlFlow2`才是那个被注册成pass的，而那个看上去更复杂的`BogusControlFlow`反而完全没有被使用上。

```cpp
else if (pass == "bcf") {
      FunctionPassManager FPM;
      FPM.addPass(BogusControlFlow2());
      MPM.addPass(createModuleToFunctionPassAdaptor(std::move(FPM)));
    }
```

## Example

对一个csmith生成的测试样本进行bcf混淆后，得到的混淆片段如下：

```c
    if (iVar4 == 0) {
      if (y.12 < 10 || ((x.11 + 1) * x.11 & 1U) == 0) goto LAB_001012af;
      do {
        local_28->f0 = 1;
LAB_001012af:
        local_28->f0 = 1;
      } while (9 < y.14 && ((x.13 + 1) * x.13 & 1U) != 0);
    }
  }
  if (y.16 < 10 || ((x.15 + 1) * x.15 & 1U) == 0) goto LAB_0010132a;
```

注意，这里由于还是使用的旧的`BogusControlFlow2`, 所以生成的opaque predicate比较简单。

## Deobfuscation Prototype

核心点在于对opaque predicate的判断。我认为可以分成如下流程：

1. collect. 使用基于DDG的backward slicing收集影响branch guard的所有指令。
2. merge(optional). 有的时候，一个opaque predicate可能会在编译后被拆分成独立的多个条件进行判断；因此需要对这些条件进行合并，得到一个完整的predicate。**在测试的样本里面并没有遇到过这种情况，暂时跳过这层的考虑。**
3. solve. 使用符号执行对收集到的predicate进行求解，得到一个优化后的判断条件。在这个BogusControlFlow的例子中，得到的条件应该就是要么True，要么False。
4. patch. 对binary进行patch，消除opaque predicates对反编译器的影响。

不过在涉及到细节的时候，对这三个步骤的实现会复杂不少。具体而言：

1. collect. 我们需要确定到底是哪种code construct需要进行collect。对于IndirectCall，我们只需要遍历，对所有的indirect call site进行collect即可；但是对于BogusControlFlow这种就比较tricky；理论上我们需要对所有的branch predicates进行收集。这显然增加了不少工作量。
2. solve. 使用符号执行沿slice路径执行到branch处，然后检查guard是否只能取一个值。由于opaque predicate永远为真或者永远为假，因此我们可以从这个入手。
3. patch. 只需要patch成直接跳转即可，难度不大.

下面简单post一下实现的代码：

### Step 1: 找到所有branch

首先，我们需要找到目标函数中所有的conditional branch指令。在VEX IR中，一个conditional branch对应的block会有`Ijk_Boring`类型的jumpkind，同时block内部会有一个`Exit`语句（也是`Ijk_Boring`类型）。

```python
def find_branches(proj, func):
    result = []
    for block_addr in func.block_addrs:
        block = proj.factory.block(block_addr)
        irsb = block.vex
        if irsb.jumpkind == 'Ijk_Boring' and any(
            isinstance(s, pyvex.stmt.Exit) and s.jumpkind == 'Ijk_Boring'
            for s in irsb.statements
        ):
            branch_insn = block.capstone.insns[-1]
            result.append(branch_insn.address)
    return result
```

这里的逻辑很简单：遍历函数中的所有basic block，找到那些包含conditional branch的block（block的default exit是`Ijk_Boring`，且内部有一个`Exit`语句也是`Ijk_Boring`），然后把branch指令的地址记录下来。

### Step 2: Backward Slicing

对于每个branch，我们需要进行backward slicing来收集所有影响这个branch guard的指令。这里使用了angr的DDG（Data Dependency Graph）来进行backward slicing。

```python
def backward_slice_from(proj, cfg, ddg, target_insn_addr):
    block_node = cfg.model.get_any_node(target_insn_addr, anyaddr=True)
    if block_node is None:
        raise RuntimeError(f"No CFG node found containing 0x{target_insn_addr:x}")

    irsb = proj.factory.block(block_node.addr).vex
    exit_indices = {
        i for i, s in enumerate(irsb.statements)
        if isinstance(s, pyvex.stmt.Exit)
    } or {-2}

    seed_nodes = [
        n for n in ddg.graph.nodes()
        if getattr(n, 'block_addr', None) == block_node.addr
        and getattr(n, 'stmt_idx', None) in exit_indices
    ]
    if not seed_nodes:
        raise RuntimeError(f"No DDG nodes found for ins_addr=0x{target_insn_addr:x}")

    # BFS backward through the DDG
    visited = set()
    queue = deque(seed_nodes)
    slice_cls = set()
    while queue:
        cl = queue.popleft()
        if cl in visited:
            continue
        visited.add(cl)
        slice_cls.add(cl)
        for pred in ddg.graph.predecessors(cl):
            queue.append(pred)
    return slice_cls
```

具体流程如下：

1. 首先通过CFG找到包含目标指令的block node。
2. 然后在VEX IR中找到所有的`Exit`语句——这些就是conditional branch的guard所在的位置。
3. 在DDG中找到对应的节点作为seed。
4. 从seed节点开始，沿DDG的反向边进行BFS，收集所有能够到达seed的节点——这就是backward slice。

最终得到的`slice_cls`就是所有影响这个branch guard值的指令集合。

### Step 3: 符号执行求解

拿到backward slice之后，接下来就是通过符号执行来判断这个branch guard是不是一个opaque predicate。

```python
def analyze_branch_guard(proj, slice_cls, branch_block_addr):
    block_addrs = sorted(set(
        cl.block_addr for cl in slice_cls if cl.block_addr is not None
    ))
    if branch_block_addr not in block_addrs:
        block_addrs.append(branch_block_addr)

    state = proj.factory.blank_state(addr=block_addrs[0])
    simgr = proj.factory.simgr(state)

    for next_addr in block_addrs[1:]:
        simgr.step()
        simgr.move('active', 'deadended', lambda s, na=next_addr: s.addr != na)
        if not simgr.active:
            break
```

首先，我们收集backward slice中涉及到的所有block地址并排序。然后从第一个block开始进行符号执行，逐步step到下一个block。在每次step之后，我们把那些跑到了"错误"地址的state移到`deadended` stash里——这样就保证我们只沿着slice中的路径执行。

```python
    # 从VEX IR中获取conditional exit语句
    irsb = proj.factory.block(branch_block_addr).vex
    cond_exit = next(
        (s for s in irsb.statements if isinstance(s, pyvex.stmt.Exit)),
        None,
    )
    if cond_exit is None:
        return 'unconditional', None

    # 在branch block再step一次，观察产生的successor数量
    succs = simgr.active[0].step()

    if len(succs.successors) == 1:
        taken_addr = cond_exit.dst.value
        resolved_addr = succs.successors[0].addr
        if resolved_addr == taken_addr:
            return 'always_true', None
        else:
            return 'always_false', None

    # 有两个successor，用solver检查guard的可满足性
    guard = succs.successors[0].history.jump_guard
    solver = simgr.active[0].solver

    can_be_true  = solver.satisfiable(extra_constraints=[guard])
    can_be_false = solver.satisfiable(extra_constraints=[claripy.Not(guard)])

    if can_be_true and not can_be_false:
        return 'always_true', guard
    elif can_be_false and not can_be_true:
        return 'always_false', guard
    else:
        return 'symbolic', guard
```

到达branch block之后，我们再step一次，检查产生了多少个successor：

- **只有1个successor**：说明angr已经具体化了guard的值，直接判定为opaque predicate。通过比较resolved地址和`Exit`语句的目标地址来判断是`always_true`还是`always_false`。
- **有2个successor**：说明guard是符号化的。这时候我们用solver分别检查guard能否为true和能否为false：
  - 只能为true → `always_true`（opaque predicate）
  - 只能为false → `always_false`（opaque predicate）
  - 两者皆可 → `symbolic`（真正的branch，不是opaque predicate）

### Step 4: Patch

一旦确定了一个branch是opaque predicate，接下来就需要对binary进行patch。

```python
def build_slice_patch(proj, slice_cls, target_addr, insn="jmp"):
    # 收集slice中所有指令的地址和大小
    seen = {}
    for cl in slice_cls:
        addr = cl.ins_addr
        if addr is None or addr in seen:
            continue
        for i in proj.factory.block(addr).capstone.insns:
            if i.address == addr:
                seen[addr] = i.size
                break
    insns = sorted(seen.items())

    # 找到第一个连续区域 >= 5 bytes（jmp指令需要5字节）
    patch_start = patch_total = None
    for i, (addr, size) in enumerate(insns):
        run_size = size
        for j in range(i + 1, len(insns)):
            if insns[j-1][0] + insns[j-1][1] != insns[j][0]:
                break
            run_size += insns[j][1]
            if run_size >= INSN_SIZE:
                break
        if run_size >= INSN_SIZE:
            patch_start, patch_total = addr, run_size
            break

    # 在找到的区域放置jmp指令，其余全部NOP
    asm_bytes, _ = ks.asm(f"{insn} 0x{target_addr:x}", addr=patch_start)
    patches = {}
    patches[patch_start - file_base] = bytes(asm_bytes) + b'\x90' * (patch_total - len(asm_bytes))
    for addr, size in insns:
        if patch_start <= addr < patch_start + patch_total:
            continue
        patches[addr - file_base] = b'\x90' * size
    return patches
```

Patch的策略：

1. 收集backward slice中所有指令的地址和大小。
2. 找到一段连续的、至少5字节的区域——因为x86-64的`jmp rel32`指令正好需要5字节。
3. 在这个区域放置一条无条件跳转指令`jmp target`，跳转目标是opaque predicate恒真/恒假所对应的那个分支。
4. 把slice中其余所有指令全部NOP掉——因为这些指令都只是用来计算opaque predicate的，去掉它们不会影响程序的正确性。

### 主流程

最后，把上面的步骤串起来：

```python
proj, main_func, cfg, ddg = load_everything(
    TARGET_BINARY, target_func_name=TARGET_FUNC_NAME,
    cfg_type="Emulated", auto_load_libs=False
)

branches = find_branches(proj, main_func)
print(f"Found {len(branches)} branches in {TARGET_FUNC_NAME}.")

all_patches = []
for branch_addr in branches:
    block_node = cfg.model.get_any_node(branch_addr, anyaddr=True)
    block_addr = block_node.addr

    slice_cls = backward_slice_from(proj, cfg, ddg, branch_addr)

    kind, guard = analyze_branch_guard(proj, slice_cls, block_addr)
    print(f"  Guard: {kind}")

    if kind in ('always_true', 'always_false'):
        irsb = proj.factory.block(block_addr).vex
        cond_exit = next(s for s in irsb.statements if isinstance(s, pyvex.stmt.Exit))
        taken_addr = cond_exit.dst.value
        fall_addr = irsb.next.con.value
        patch_target = taken_addr if kind == 'always_true' else fall_addr
        all_patches.append(build_slice_patch(proj, slice_cls, patch_target, insn='jmp'))

if all_patches:
    apply_patches(all_patches, TARGET_BINARY, OUTPUT_BINARY)
    print(f"\nWrote {len(all_patches)} patches -> {OUTPUT_BINARY}")
```

对于每个branch：
1. 做backward slicing
2. 符号执行判断是否为opaque predicate
3. 如果是，确定正确的跳转目标（`always_true`取taken分支，`always_false`取fallthrough分支），生成patch
4. 最后一次性把所有patch写入到输出文件

## 评测效果

这是原来混淆的：

![bcf](/assets/img/posts/bcf.png)

去混淆后：

![bcf_patched](/assets/img/posts/bcf_patched.png)

## Limitations

当前的实现存在一些限制：

1. 目前的实现对于`x*(x+1) % 2 == 0`这类简单的opaque predicate效果很好；但对于更复杂的构造（如前面分析的基于modular inverse的方案），可能需要更强的约束求解能力。
2. **Backward slice的连续性假设**。Patch阶段假设slice中存在一段至少5字节的连续指令区域来放置`jmp`指令。虽然在实际中这个假设基本成立，但理论上可能存在slice中指令极度碎片化的极端情况。

## 代码地址

https://github.com/Taardisaa/DePolaris
