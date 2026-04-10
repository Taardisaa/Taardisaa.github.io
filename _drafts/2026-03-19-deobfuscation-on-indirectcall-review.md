# Review Notes: `2026-03-19-deobfuscation-on-indirectcall.md`

## Main Findings

1. The core pruning idea, "only symbolically execute basic blocks covered by the backward slice and drop the rest", is not reliable as a general workflow.

   Evidence:
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:141-142`
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:206-220`

   Why this is risky:
   - The call target may depend not only on explicit data dependencies, but also on path predicates, memory aliasing, phi/merge behavior, and calling-convention-related implicit state.
   - In the prototype, `slice_to_symbolic()` deduplicates `block_addr`, sorts them by address, and executes them in that order. That assumes:
   - address order approximates execution order;
   - non-slice blocks do not contribute required semantics;
   - the first surviving state is representative.
   - Those assumptions can hold for a demo sample, but they are not generally sound.

2. The article formulates the problem as recovering all possible values of `var`, but the prototype only handles a narrow subcase.

   Evidence:
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:126-142`
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:191-220`
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:331-336`

   Mismatch:
   - The writeup presents a general model: `call var`, where `var` may be a register or memory target, and the goal is to recover all possible values.
   - The prototype hardcodes `rax`, takes only `all_states[0]`, and only patches when the result is already concrete.
   - It does not enumerate multiple targets and does not support `call [mem]`.
   - So the writeup currently overstates the generality relative to the implementation.

3. The patching discussion overclaims about instruction size and does not match the actual prototype.

   Evidence:
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:142`
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:223-270`

   Issues:
   - The article says direct patching is difficult because indirect calls are generally much smaller than direct calls. That is too broad on x86-64.
   - The real difficulty is usually in-place rewriting constraints: available bytes, encoding form, and relocation/control-flow safety.
   - The prose suggests one strategy: rewrite some earlier instruction into `mov rax, func_addr` and NOP the rest.
   - The prototype does something else: it searches for a contiguous slice region and writes `call 0x...` directly there via `build_slice_patch()`.
   - Right now the text and the code describe different patching strategies.

4. The explanation of why the pass introduces a global variable is too speculative.

   Evidence:
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:117-118`

   Concern:
   - The article says the main purpose of introducing `GV` is to prevent compiler optimization.
   - From the code shown in the post, the directly supported claim is weaker and more concrete: the masked function pointer is materialized in memory, and recovering the real target now requires a load plus arithmetic.
   - "Prevent optimization" may be an intuition, but it is not clearly established by the posted evidence.

5. The overall direction is good, but the article understates how hard the `collect` phase is.

   Evidence:
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:138-142`
   - `_posts/2026-03-19-deobfuscation-on-indirectcall.md:282-311`

   Why this matters:
   - The article presents `collect -> solve -> patch` as a fairly clean decomposition.
   - In practice, the hardest part is often not the solver but dependency recovery:
   - whether slicing should be done at machine-code level or lifted IR level;
   - whether the seed is a register value, memory dereference, or exit edge;
   - how memory aliasing is handled;
   - how path conditions and merged states are preserved.
   - The prototype leans heavily on angr's CFG/DDG. That is fine for a proof of concept, but the writeup should make the precision limitations more explicit.

## Overall Judgment

The high-level direction is reasonable.

What seems correct:
- Modeling indirect-call target recovery as "recover the target expression, then solve or simplify it" is a sensible framing.
- For Polaris-style address-recovery chains, this is more extensible than writing a one-off matcher for a single pass pattern.
- The prototype demonstrates feasibility on at least one sample.

What needs to be toned down:
- The article currently reads closer to a general deobfuscation workflow than the implementation really supports.
- A more accurate framing is: this is a slice-driven prototype workflow for recovering single-target indirect calls under relatively favorable conditions.

## Suggested Revisions

1. Narrow the claim.

   Suggested change:
   - Replace "a more general deobfuscation workflow/framework" with something like "a relatively general prototype workflow for recovering single-target indirect-call targets".

2. Add an explicit limitations section.

   Suggested points:
   - non-slice blocks may still contribute path constraints;
   - sorting slice blocks by address is not the same as following the real execution order;
   - `call [mem]`, multi-target calls, and cross-function propagation are not yet handled;
   - the result depends heavily on CFG/DDG precision.

3. Make the patching text consistent with the prototype.

   Options:
   - update the prose to describe the current `call rel32 + NOP` strategy;
   - or change the prototype later so it actually matches the `mov reg, imm; call reg` discussion.

4. Rewrite the `GV` explanation in a more evidence-backed way.

   Suggested wording:
   - "The direct effect of introducing the global variable here is to materialize the masked pointer in memory, so recovering the real target requires a load followed by arithmetic."

5. Call out that the main research risk is in `collect`, not just `solve`.

   Suggested wording:
   - "In practice, the hardest part is usually not solving the recovered constraints, but preserving enough dependency and path semantics during collection without exploding the state space."

6. If the post is expanded later, add one or two failure cases.

   Suggested additions:
   - a case where the method succeeds because the target expression stays local and single-valued;
   - a case where it degrades because of path merges, aliasing, or a non-`rax` carrier.

## Short Verdict

The idea is directionally correct, but the current writeup gives the impression that the method is more generally robust than the prototype actually demonstrates.

## Candidate Sentence Rewrites

1. Original:

   > 我的想法是，先提出一个更通用的去混淆方法（一个框架/workflow）

   Suggested:

   > 我的想法是，先提出一个相对通用的 workflow 原型，用来恢复单目标 indirect call 的真实 target。

2. Original:

   > 只对backward slice影响到的basic blocks做符号执行，其他全部丢掉。

   Suggested:

   > 一个激进但常常有效的剪枝办法，是优先对 backward slice 覆盖到的 basic blocks 做符号执行；不过这种做法并不总是 sound，因为非 slice blocks 中的路径条件或内存状态仍可能影响最终 target。

3. Original:

   > 创建全局变量的主要目的是为了防止被编译器优化掉.

   Suggested:

   > 这里引入全局变量的直接效果，是把 masked pointer 物化到内存中，使后续必须通过一次 load 和算术运算来恢复真实 target。

4. Original:

   > 直接改成直接调用是很困难的，因为indirect call的size一般比direct call要小不少

   Suggested:

   > 如果要求原地 patch 到原调用点，直接改写成 direct call 往往不方便，因为可用字节数、编码形式和重定位约束都可能不匹配。
