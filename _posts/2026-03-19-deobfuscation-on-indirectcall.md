---
layout: post
title: Deobfuscation on Polaris-Obfuscator/IndirectCall
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

考虑到该obfuscation pass通常还会与更复杂的数据流混淆pass结合使用，比如MBA obfuscation，本人并不打算直接针对该pass的构造流程来进行deobfuscation。我的想法是，先提出一个更通用的去混淆方法（一个框架/workflow），进而实现通用性的deobfuscation方法.

我将这个问题建模为一个约束求解问题：在一个间接调用点`I`处，我们已知的信息是：`call var`。这里的`var`可以是一个寄存器（如`call rax`），也可以是一个内存地址（如`call [0x114514]`）；但无论哪种情况，它都不是一个直接调用（即不是一个常量）。我们的目标是找出`var`的所有可能取值。如果这个间接调用是由类似上述obfuscation pass构造的，那么`var`的可能取值应该只有一个。我们可以将其形式化为一个更通用的约束收集与求解问题：

$$
var = F(v_1, v_2, \dots, v_n, c_1, c_2, \dots, c_m), \quad \text{where } v_i \in V,\; c_j \in C
$$

其中 $$V$$ 是所有参与构造 `var` 的变量集合，$$C$$ 是所有参与构造的常量集合。函数 $$F$$ 是对构造 `var` 的数据流的一般性表示。以上面的例子为例，$$F$$ 可以表示为：

$$
F = GV - MaskValue
$$

所以说我们的目标其实很简单，就三个步骤：

1. collect：做backward slice，收集所有与`var`相关的变量和常量，并从其数据流关系中构造出一系列的symbolic constraints.
2. solve: 使用constraint solver来求解这些constraints，得到`var`的值.可以使Z3，也可以使用其他求解工具，比如MBA-Blast（https://www.usenix.org/conference/usenixsecurity21/presentation/liu-binbin），这是专门用于求解MBA的。**或者更暴力的方法：用angr做符号执行，这样collect+solve就可以合成在一起了。**不过具体而言还是要有些trick的，主要核心点就是剪枝：只对backward slice影响到的basic blocks做符号执行，其他全部丢掉。
3. patch(optional): 将求解得到的`var`的值直接patch回二进制中。**直接改成直接调用是很困难的**，因为indirect call的size一般比direct call要小不少，所以根本没那么多空间塞多余的字节。但是有一个简单的这种方法：因为obfuscation本身会添加很多的多余的计算指令；那么我们只需要在其中找到任意一个足够大的instruction，把它patch成`mov rax, func_addr`，然后将剩余的计算指令nop掉就行了。这样，反编译器会把它正常恢复成一个直接调用了。

## Deobfuscation Prototype

这是我针对上述概念简单编写的一个working prototype，目前在IndirectCall+MBA Obfuscation的一个样本上通过了测试。

```python
import angr
from angr import sim_options as o
from angr.analyses.cdg import CDG, TemporaryNode
from collections import deque

TARGET_BINARY = "examples/sample_001_indcall_mba"
OUTPUT_BINARY = "examples/sample_001_mba_patched"
TARGET_FUNC_NAME = "main"

# Patch CDG: _entry defaults to project.entry which may not be in a starts=[main]-only CFG
@staticmethod
def _patched_pd_graph_successors(graph, node):
    if node is None or type(node) is TemporaryNode:
        return iter([])
    return (s for s in graph.model.get_successors(node) if s is not None)
CDG._pd_graph_successors = _patched_pd_graph_successors

proj = angr.Project(TARGET_BINARY, auto_load_libs=False)
main_addr = proj.loader.find_symbol(TARGET_FUNC_NAME).rebased_addr  # type: ignore

cfg = proj.analyses.CFGEmulated(
    keep_state=True,
    normalize=True,
    starts=[main_addr],
    state_add_options={o.TRACK_REGISTER_ACTIONS, o.TRACK_MEMORY_ACTIONS, o.TRACK_TMP_ACTIONS},
)
ddg = proj.analyses.DDG(cfg, start=main_addr)

def find_indirect_calls(proj, func):
    """Return addresses of all indirect call instructions in a function."""
    import pyvex
    result = []
    for block_addr in func.block_addrs:
        block = proj.factory.block(block_addr)
        irsb = block.vex
        # Indirect call: exit jumpkind is Call and target is not a constant
        if irsb.jumpkind == 'Ijk_Call' and not isinstance(irsb.next, pyvex.expr.Const):
            # The call instruction is the last one in the block
            call_insn = block.capstone.insns[-1]
            result.append(call_insn.address)
    return result

def slice_to_symbolic(proj, slice_cls, target_reg='rax'):
    """
    Symbolically execute the blocks in a backward slice and return
    the symbolic expression for target_reg at the end of the slice.
    """
    block_addrs = sorted(set(
        cl.block_addr for cl in slice_cls if cl.block_addr is not None
    ))
    if not block_addrs:
        return None

    state = proj.factory.blank_state(addr=block_addrs[0])
    simgr = proj.factory.simgr(state)

    # Step through each block, keeping only states headed to the next slice block
    for next_addr in block_addrs[1:]:
        simgr.step()
        simgr.move('active', 'deadended', lambda s, na=next_addr: s.addr != na)
        if not simgr.active:
            break

    # Step the final block
    if simgr.active:
        simgr.step()

    all_states = simgr.active + simgr.deadended + simgr.unsat
    if not all_states:
        return None

    return all_states[0].regs.get(target_reg)

def build_slice_patch(proj, slice_cls, target_addr):
    """
    Compute the patch bytes for one slice: returns a dict {file_offset: bytes}.
    Finds the first contiguous slice region >= 5 bytes, places 'call target' there,
    and NOPs out everything else.
    """
    import keystone
    ks = keystone.Ks(keystone.KS_ARCH_X86, keystone.KS_MODE_64)
    CALL_SIZE = 5

    seen = {}
    for cl in slice_cls:
        addr = cl.ins_addr
        if addr is None or addr in seen:
            continue
        for insn in proj.factory.block(addr).capstone.insns:
            if insn.address == addr:
                seen[addr] = insn.size
                break
    insns = sorted(seen.items())

    patch_start = patch_total = None
    for i, (addr, size) in enumerate(insns):
        run_size = size
        for j in range(i + 1, len(insns)):
            if insns[j-1][0] + insns[j-1][1] != insns[j][0]:
                break
            run_size += insns[j][1]
            if run_size >= CALL_SIZE:
                break
        if run_size >= CALL_SIZE:
            patch_start, patch_total = addr, run_size
            break

    if patch_start is None:
        raise RuntimeError(f"No contiguous slice region >= {CALL_SIZE} bytes for call 0x{target_addr:x}")

    call_bytes, _ = ks.asm(f"call 0x{target_addr:x}", addr=patch_start)
    assert call_bytes is not None
    file_base = proj.loader.main_object.min_addr
    patches = {}
    patches[patch_start - file_base] = bytes(call_bytes) + b'\x90' * (patch_total - len(call_bytes))
    for addr, size in insns:
        if patch_start <= addr < patch_start + patch_total:
            continue
        patches[addr - file_base] = b'\x90' * size

    print(f"  -> call 0x{target_addr:x} at 0x{patch_start:x} (+{patch_total - CALL_SIZE} nops)")
    return patches

def apply_patches(patches_list, input_file, output_file):
    """Write all accumulated patches to output_file in one pass."""
    import shutil
    shutil.copy(input_file, output_file)
    with open(output_file, "r+b") as f:
        for patches in patches_list:
            for offset, data in patches.items():
                f.seek(offset)
                f.write(data)

def backward_slice_from(proj, cfg, ddg, target_insn_addr):
    """Return all DDG nodes in the backward slice of the instruction at target_insn_addr."""
    # Find the containing block
    block_node = cfg.model.get_any_node(target_insn_addr, anyaddr=True)
    if block_node is None:
        raise RuntimeError(f"No CFG node found containing 0x{target_insn_addr:x}")

    # Use only the block exit node (stmt_idx == -2), which represents
    # the indirect jump/call target — avoids pulling in call mechanics (RSP chain)
    seed_nodes = [
        n for n in ddg.graph.nodes()
        if getattr(n, 'block_addr', None) == block_node.addr
        and getattr(n, 'stmt_idx', None) == -2
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

main_func = cfg.kb.functions[main_addr]
indirect_calls = find_indirect_calls(proj, main_func)
print(f"Indirect calls in main: {[hex(a) for a in indirect_calls]}\n")

all_patches = []
for call_addr in indirect_calls:
    # call_rax_addr = 0x004011c7
    slice_cls = backward_slice_from(proj, cfg, ddg, call_addr)

    print(f"\nBackward slice of 0x{call_addr:x} ({len(slice_cls)} nodes):")
    for cl in sorted(slice_cls, key=lambda x: (x.block_addr or 0, x.stmt_idx or 0)):
        if cl.ins_addr is not None:
            block = proj.factory.block(cl.ins_addr)
            for insn in block.capstone.insns:
                if insn.address == cl.ins_addr:
                    print(f"  [{cl.stmt_idx:>3}] 0x{insn.address:x}:  {insn.mnemonic} {insn.op_str}")
                    break

    # TODO: the register here is hardcoded as `rax`. We should change to a more generic approach that detects which register is used in the indirect jump/call and tracks that instead.
    sym = slice_to_symbolic(proj, slice_cls, target_reg='rax')
    print(f"  symbolic rax: {sym}")

    if sym is not None and sym.concrete:
        all_patches.append(build_slice_patch(proj, slice_cls, sym.concrete_value))

if all_patches:
    apply_patches(all_patches, TARGET_BINARY, OUTPUT_BINARY)
    print(f"\nWrote {len(all_patches)} patches -> {OUTPUT_BINARY}")
```

## 附录

用于研究的样本C文件（由Csmith生成）：

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

/************************ statistics *************************
XXX max struct depth: 0
breakdown:
   depth: 0, occurrence: 3
XXX total union variables: 1

XXX non-zero bitfields defined in structs: 0
XXX zero bitfields defined in structs: 0
XXX const bitfields defined in structs: 0
XXX volatile bitfields defined in structs: 0
XXX structs with bitfields in the program: 0
breakdown:
XXX full-bitfields structs in the program: 0
breakdown:
XXX times a bitfields struct's address is taken: 0
XXX times a bitfields struct on LHS: 0
XXX times a bitfields struct on RHS: 0
XXX times a single bitfield on LHS: 0
XXX times a single bitfield on RHS: 0

XXX max expression depth: 1
breakdown:
   depth: 1, occurrence: 3

XXX total number of pointers: 4

XXX times a variable address is taken: 3
XXX times a pointer is dereferenced on RHS: 0
breakdown:
XXX times a pointer is dereferenced on LHS: 0
breakdown:
XXX times a pointer is compared with null: 0
XXX times a pointer is compared with address of another variable: 0
XXX times a pointer is compared with another pointer: 0
XXX times a pointer is qualified to be dereferenced: 109
XXX number of pointers point to pointers: 0
XXX number of pointers point to scalars: 4
XXX number of pointers point to structs: 0
XXX percent of pointers has null in alias set: 50
XXX average alias set size: 1.25

XXX times a non-volatile is read: 1
XXX times a non-volatile is write: 1
XXX times a volatile is read: 0
XXX    times read thru a pointer: 0
XXX times a volatile is write: 0
XXX    times written thru a pointer: 0
XXX times a volatile is available for access: 13
XXX percentage of non-volatile access: 100

XXX forward jumps: 0
XXX backward jumps: 0

XXX stmts: 2
XXX max block depth: 0
breakdown:
   depth: 0, occurrence: 2

XXX percentage a fresh-made variable is used: 12
XXX percentage an existing variable is used: 88
XXX total OOB instances added: 0
********************* end of statistics **********************/

```

