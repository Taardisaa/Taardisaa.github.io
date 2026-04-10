---
layout: post
title: Deobfuscation on Polaris-Obfuscator/IndirectCall
description: Analyzing and deobfuscating Polaris Obfuscator's IndirectCall pass, which converts direct calls into indirect calls through computed addresses.
date: 2026-03-19 19:49 -0600
math: true
---

## IndirectCall 简要介绍

这个obfuscation pass简单来说就是把直接调用改成间接调用。比如：

```asm
call func_1
```

改成：

```asm
; perform some operations to compute the address of func_1
; and load the address into a register, say rax
call rax
```

在我所测试用的例子里面，代码如下：

```asm
MOV        RAX ,qword ptr [DAT_00104040 ]                    = 00000000328B36C6h
SUB        RAX ,0x327b23c6
CALL       RAX => platform_main_begin                        void platform_main_begin(void)
```

反编译出来就是：

```c
(*(code *)(DAT_00104040 + -0x327b23c6))();
```

而我们的目标就是将其恢复成一个正常的函数调用：

```c
platform_main_begin();
```

## 具体实现

在该Obfuscator的具体实现中（见`src/llvm/lib/Transforms/Obfuscation/IndirectCall.cpp`）：

```c++
void IndirectCall::process(Function &F) {
  // F.getParent() 返回 llvm::Module*,
  // DataLayout 包含 该 Module 的各种数据布局信息。详见https://llvm.org/doxygen/classllvm_1_1DataLayout.html
  DataLayout Data = F.getParent()->getDataLayout();
  // F.getContext() 返回 llvm::LLVMContext&
  // ->getPointerTo() 返回一个指向该函数的指针类型
  // Data.getTypeAllocSize(ptr) 返回该指针类型的大小（以字节为单位）。
  int PtrSize =
      Data.getTypeAllocSize(Type::getInt8Ty(F.getContext())->getPointerTo());
  // getIntNTy 返回一个具有指定位数的整数类型。假设前面函数指针的大小（PtrSize）是 8 字节（64 位系统），则 PtrValueType 将是一个 64 位的整数类型。
  Type *PtrValueType = Type::getIntNTy(F.getContext(), PtrSize * 8);

  // 遍历函数 F 中的所有基本块和指令，寻找调用指令（CallInst）。对于每个调用指令，检查它是否调用了一个具有确切定义的函数（即不是间接调用）。如果是，则将该调用指令添加到 CIs 中，以便稍后处理。
  std::vector<CallInst *> CIs;
  for (BasicBlock &BB : F) {
    for (Instruction &I : BB) {
      if (isa<CallInst>(I)) {
        CallInst *CI = (CallInst *)&I;
        Function *Func = CI->getCalledFunction();
        if (Func && Func->hasExactDefinition()) {
          CIs.push_back(CI);
        }
      }
    }
  }

  for (CallInst *CI : CIs) {
    // 函数指针类型
    Type *Ty = CI->getFunctionType()->getPointerTo();

    Constant *Func = (Constant *)CI->getCalledFunction();
    // First of all, 将函数cast成一个整数值（即函数的地址）
    Constant *CValue = ConstantExpr::getPtrToInt(
        ConstantExpr::getBitCast(Func, Ty, false), PtrValueType, false);
    // 然后随机生成一个掩码（Mask），32bit
    unsigned Mask = getRandomNumber();
    // 将掩码添加到函数地址上，得到一个新的整数值
    CValue = ConstantExpr::getAdd(CValue, ConstantInt::get(PtrValueType, Mask));
    // 最后将这个整数值转换回一个指针类型。
    CValue = ConstantExpr::getIntToPtr(
        CValue, Type::getInt8Ty(F.getContext())->getPointerTo());
    // 总结以上操作便是：CValue = Func + getRandomNumber()

    // 创建一个全局变量GV（好糟糕的名字）
    // 后面这个全局变量被设置成了CValue，即Func + Mask
    GlobalVariable *GV = new GlobalVariable(
        *(F.getParent()), Type::getInt8Ty(F.getContext())->getPointerTo(),
        false, GlobalValue::PrivateLinkage, NULL);

    // 使用 IRBuilder 来构建新的指令。
    /* 这里创建的IRs就是：（伪代码）
    
      MaskValue = (uint64_t) Mask          // zero-extend Mask to pointer width
      loaded    = *GV                      // load the masked pointer (Func + Mask)
      int_val   = (uint64_t) loaded        // reinterpret as integer
      real_addr = int_val - MaskValue      // subtract Mask → recovers Func
      CallPtr   = (FuncType*) real_addr    // cast back to function pointer type
    */
    IRBuilder<> IRB((Instruction *)CI);
    Value *MaskValue = IRB.getInt32(Mask);
    MaskValue = IRB.CreateZExt(MaskValue, PtrValueType);
    Value *CallPtr = IRB.CreateIntToPtr(
        IRB.CreateSub(IRB.CreatePtrToInt(IRB.CreateLoad(IRB.getInt8PtrTy(), GV),
                                         PtrValueType),
                      MaskValue),
        Ty);
    CI->setCalledFunction(CI->getFunctionType(), CallPtr);
    GV->setInitializer(CValue);
  }
}
```

总结一下就是：
1. 创建一个全局变量GV，设置成func_addr + random_value。个人认为创建全局变量的主要目的是为了防止被编译器优化掉.
2. 然后创建IR来构造以下公式：GV - random_value. 这个值也就是func_addr。不过由于这个地址是动态创建的，因此编译器会使用间接调用(e.g., call rax)来调用函数.

> 个人认为单独使用这个obfuscation pass并不能提供太强的保护。从上面Ghidra提供的例子都可以发现，在间接调用上都已经直接表明了会跳转到的真实函数。**但是一但结合其他的obfuscation pass，尤其是MBA obfuscation，分析地址的过程就会变得复杂很多.**

## Deobfuscation

### Definitions of Obfuscation

为了形式化 deobfuscation，我们先把 obfuscation 视为一个程序变换：

$$
\mathcal{O}: P \mapsto P'
$$

其中 $$P$$ 是原始程序，$$P'$$ 是混淆后的程序。我们通常要求该变换在某个给定的语义模型下保持语义等价，即：

$$
\llbracket P \rrbracket = \llbracket P' \rrbracket
$$

这里 $$\llbracket \cdot \rrbracket$$ 表示程序的可观察语义（observable semantics），例如在相同输入下的输出、内存副作用、系统调用行为，或者控制流是否终止等。

### Definitions of Deobfuscation

理想化地说，deobfuscation 可以被写成一个逆变换：

$$
\mathcal{D}: P' \mapsto P
$$

也就是说，我们希望从混淆后的程序 $$P'$$ 恢复出原始程序 $$P$$。但这一定义在实践中往往过于理想化：程序经过 compilation、optimization 和 obfuscation 之后，原始结构信息通常已经部分丢失，因此完全恢复出唯一的 $$P$$ 往往并不现实。

因此，更现实的定义是：给定一个混淆程序 $$P'$$，构造出一个更易分析的程序 $$\hat{P}$$，使得

$$
\llbracket \hat{P} \rrbracket = \llbracket P' \rrbracket
$$

并且 $$\hat{P}$$ 在结构上比 $$P'$$ 更接近人类可理解的表示，例如更直接的控制流、更简单的数据依赖，或者更显式的调用目标。在一些较弱的混淆下，配合反编译技术，$$\hat{P}$$ 甚至可以非常接近原始程序 $$P$$，只保留少量语法层面的差别。

因此，从这个角度看，deobfuscation 更接近于一种 semantics-preserving simplification，而不一定是严格意义上的 inverse transformation：

$$
P' \mapsto \hat{P}, \quad \text{where } \llbracket \hat{P} \rrbracket = \llbracket P' \rrbracket
$$

### Formalization of Indirect Call

先看本文关心的这类 IndirectCall obfuscation 本身是如何形式化的。设原始程序在某个调用点直接调用函数 $$f$$，即其调用目标为常量地址 $$\operatorname{addr}(f)$$。该 obfuscation pass 引入一个随机 mask $$k$$，并构造一个全局变量 $$GV$$，使得：

$$
GV = \operatorname{addr}(f) + k
$$

在真正调用之前，程序再通过一次 load 和减法恢复目标地址：

$$
t_I = \operatorname{load}(GV) - k
$$

随后将原本的直接调用

$$
\operatorname{call}\; f
$$

替换为

$$
\operatorname{call}\; t_I
$$

其中 $$t_I$$ 不再是一个字面量常量，而是一个运行时计算得到的 target expression。对上面这个简单例子来说，$$t_I$$ 最终仍然等于 $$\operatorname{addr}(f)$$；但从静态分析的角度看，调用目标已经从“显式常量”变成了“由数据流恢复出来的表达式”。

这也是本文进行 deobfuscation 的基本出发点：虽然直接调用被改写成了 `call t_I`，但为了保持语义等价，$$t_I$$ 在执行到调用点时仍必须恢复出真实的 target address。**于是问题的关键就变成了：恢复 $$t_I$$ 的构造过程，并求解它在调用点处的实际取值。**

#### Special case: Instruction substitution or MBA obfuscations

在实际混淆中，IndirectCall 往往不会被单独使用，而是会与 MBA 等数据流混淆结合。此时，target-recovery 链条中的某个简单计算 $$g$$ 会被改写为一个更复杂但语义等价的表达式 $$g'$$。可以将这种变换抽象为：

$$
\mathcal{MBA}: g \mapsto g'
$$

其中 $$g$$ 是原本较简单的运算，而 $$g'$$ 是其 MBA-obfuscated 形式。对本文来说，关键点在于：MBA 改变的主要不是最终 target 的值，而是它的表示形式。原本简单的恢复公式，例如

$$
t_I = \operatorname{load}(GV) - k
$$

在经过 instruction substitution 或 MBA rewriting 之后，可以统一写成一个更一般的 target expression：

$$
t_I = f(\operatorname{load}(GV), k, c_1, \dots, c_m)
$$

其中 $$f$$ 表示一个由算术运算、位运算及其组合构成的 bit-vector expression，并且在语义上与原本的 target-recovery computation 等价。因此，在本文的抽象层面，我不单独对 MBA 的具体语法做建模，而是将其统一到这个更一般的表达式 $$f$$ 中。

### Formalization of Deobfuscating Indirect Call

在本文中，我们并不尝试恢复整个程序 $$\hat{P}$$，而是只关注其中一个局部性质：对于给定的间接调用点 $$I$$，恢复其真实的调用目标集合。

形式上，给定混淆后的程序 $$P'$$ 和其中一个间接调用点 $$I$$，记该调用目标表达式为 $$t_I$$。我们的目标是恢复集合：

$$
\mathcal{T}(I) = \{ a \mid a \text{ is a feasible runtime target of } I \}
$$

> 这里的问题表面上与 pointer analysis 有些相似，因为二者都关心一个间接引用最终可能指向什么；但本文的目标并不是恢复一般的 points-to / alias 关系，而是针对特定调用点做 indirect-call target recovery。

如果该间接调用是由类似 IndirectCall pass 构造出来的，那么通常有：

$$
|\mathcal{T}(I)| = 1
$$

此时 deobfuscation 的任务就退化为恢复这个唯一的目标地址。

考虑到该 obfuscation pass 通常还会与更复杂的数据流混淆 pass 结合使用，比如 MBA obfuscation，我并不打算直接针对该 pass 的构造流程做 pattern-specific 的 deobfuscation。也和前面章节所述一致（见Formalization of Indirect Call），更自然的做法是提出一个相对通用的 workflow：**只要能够恢复 $$t_I$$ 的构造过程，就有机会恢复其真实 target。**

在上述形式化下，deobfuscation 的任务可以进一步建模为一个约束收集与求解问题。给定间接调用点 $$I$$ 及其调用目标表达式 $$t_I$$，我们的目标是恢复所有可能的运行时取值，也就是求解集合 $$\mathcal{T}(I)$$。

更一般地，可以将 $$t_I$$ 视为由一组变量与常量共同构造出来的表达式：

$$
t_I = F(v_1, v_2, \dots, v_n, c_1, c_2, \dots, c_m), \quad \text{where } v_i \in V,\; c_j \in C
$$

其中 $$V$$ 表示参与构造 $$t_I$$ 的变量集合，$$C$$ 表示参与构造的常量集合，而 $$F$$ 则表示从这些变量和常量到最终调用目标的计算过程。于是，deobfuscation 的核心问题就变成了：恢复 $$F$$ 的定义，并求解其在调用点处的可行取值。

<!-- 对于本文最开始给出的简单例子，$$F$$ 可以写成：

$$
F = \operatorname{load}(GV) - k
$$

而在与 MBA 等数据流混淆结合时，$$F$$ 则会退化为更复杂但语义等价的 bit-vector expression。 -->

#### Assumptions

为了将问题收敛到一个可处理的 prototype setting，本文默认以下假设成立：

1. 对于给定的间接调用点 $$I$$，其真实调用目标集合 $$\mathcal{T}(I)$$ 较小；在本文关注的主要情形下，通常有 $$|\mathcal{T}(I)| = 1$$。
2. 调用目标表达式 $$t_I$$ 的主要依赖可以通过局部的 backward slicing 恢复出来，而不需要完整重建整个程序的全局语义。
3. 与目标恢复无关的控制流和数据流可以被安全忽略，或者至少不会改变 $$t_I$$ 在调用点处的最终取值。
4. MBA 等数据流混淆主要改变的是 target expression 的表示复杂度，而不是引入新的可行调用目标。

#### Current Limitations

当前 prototype 仍有一些明确限制：

1. 目前实现主要面向单目标 indirect call，尚未系统处理多目标调用点。
1. 当前 workflow 强依赖 CFG/DDG 和 backward slice 的质量，尚未显式建模更复杂的跨块路径条件、aliasing 或跨函数传播。
1. patch 部分目前只是 proof-of-concept，目标是恢复可读性，而不是构造一个通用、鲁棒的 binary rewriting pipeline。

### Insight

在上述建模下，整个 deobfuscation workflow 可以被概括为三个步骤：

1. collect：围绕调用点 $$I$$ 对目标表达式 $$t_I$$ 做 backward slicing，收集参与构造它的变量、常量以及相关数据流关系，并将这些信息组织成可进一步求解的 symbolic constraints。
1. solve：对收集到的 constraints 求解，从而恢复 $$t_I$$ 在调用点处的可行取值，也就是集合 $$\mathcal{T}(I)$$。这一步可以借助通用 constraint solver，例如 Z3；如果表达式中包含较强的 MBA 成分，也可以考虑专门面向 MBA simplification 的工具，例如 MBA-Blast（https://www.usenix.org/conference/usenixsecurity21/presentation/liu-binbin）。另一种更直接的思路是使用 symbolic execution，将 collect 与 solve 合并到同一个分析过程中。
1. patch (optional)：如果目标不仅是恢复真实调用目标，还包括改善反编译结果或提升可读性，那么可以将求解得到的 target information 进一步用于 binary patching。不过这一步并不是本文方法成立所必需的部分；它更接近于一个后处理步骤，而其可靠性也依赖于具体 patch 策略是否能够保持原始语义。

## Deobfuscation Prototype

这是我针对上述概念简单编写的一个working prototype，目前在IndirectCall+MBA Obfuscation的一个样本上通过了测试。

https://github.com/Taardisaa/DePolaris/blob/main/indcall.py

## 附录

用于研究的样本C文件（由Csmith生成）：

{% raw %}
```c
/*
 * This is a RANDOMLY GENERATED PROGRAM.
 *
 * Generator: csmith 2.4.0
 * Git version: 0cdc710
 * Options:   (none)
 * Seed:      11336776431190565663
 */

#include "csmith.h"


static long __undefined;

/* --- Struct/Union Declarations --- */
union U4 {
   volatile int32_t  f0;
   uint16_t  f1;
};

/* --- GLOBAL VARIABLES --- */
static int32_t g_4 = 0L;
static volatile int32_t g_7[3] = {9L,9L,9L};
static union U4 g_11[1] = {{0x32406135L}};


/* --- FORWARD DECLARATIONS --- */
static union U4  func_1(void);


/* --- FUNCTIONS --- */
/* ------------------------------------------ */
/* 
 * reads : g_11
 * writes:
 */
__attribute((__annotate__(("indirectcall"))))
static union U4  func_1(void)
{ /* block id: 0 */
    int32_t *l_2 = (void*)0;
    int32_t *l_3 = &g_4;
    int32_t *l_5 = &g_4;
    int32_t *l_6[10][1][1] = {{{(void*)0}},{{&g_4}},{{(void*)0}},{{&g_4}},{{(void*)0}},{{&g_4}},{{(void*)0}},{{&g_4}},{{(void*)0}},{{&g_4}}};
    uint64_t l_8 = 0x03B8AF769BF4A3CALL;
    int i, j, k;
    l_8--;
    return g_11[0];
}

/* ---------------------------------------- */
__attribute((__annotate__(("indirectcall"))))
int main (int argc, char* argv[])
{
    int i;
    int print_hash_value = 0;
    if (argc == 2 && strcmp(argv[1], "1") == 0) print_hash_value = 1;
    platform_main_begin();
    crc32_gentab();
    func_1();
    transparent_crc(g_4, "g_4", print_hash_value);
    for (i = 0; i < 3; i++)
    {
        transparent_crc(g_7[i], "g_7[i]", print_hash_value);
        if (print_hash_value) printf("index = [%d]\n", i);

    }
    for (i = 0; i < 1; i++)
    {
        transparent_crc(g_11[i].f0, "g_11[i].f0", print_hash_value);
        if (print_hash_value) printf("index = [%d]\n", i);

    }
    platform_main_end(crc32_context ^ 0xFFFFFFFFUL, print_hash_value);
    return 0;
}

```
{% endraw %}
