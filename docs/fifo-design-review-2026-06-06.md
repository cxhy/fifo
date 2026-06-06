# FIFO Design Review Report

**日期**: 2026-06-06
**Review 模式**: `readiness_gate` + RTL/DV/spec/CDC-RDC review
**Review 方法**: 使用上级目录 `skills/chip-design-review`，按 `fifo-architect`、`fifo-rtl-designer`、`fifo-dv-verifier` 三角色视角只读审查。
**结论**: BLOCK for readiness/release

## 核心判断

当前 FIFO 项目的基本 RTL/DV 回归是绿的，但这不是 closure。最危险的问题集中在异步 FIFO reset/alignment：

- reset 释放后的 alignment 窗口中，写侧可见 `wr_full=0`，但 RTL 实际不接收 `push`，会静默丢数据。
- 单侧 reset 可能让远端指针回到 0，导致本地域 `level` 越界，并破坏 `full/empty` 判定。
- 异步 DV scoreboard 使用 DUT 的 `wr_full/rd_empty` 决定 reference model 是否接受交易，独立性不足，可能吞掉上述 bug。

技术判断：这个设计适合继续迭代，不适合宣称 readiness closure。`make verilator` 通过只能说明当前定向回归没打到高风险 reset/CDC 路径。

## Review 目标

- Artifact:
  - `rtl/*.sv`
  - `dv/**`
  - `scripts/**`
  - `TASKS.json`
  - `docs/fifo-common-design.md`
  - `docs/fifo-design-guide.md`
  - `docs/fifo-verification-plan.md`
  - `memory/project-status.md`
- Spec/Feature/Verification IDs:
  - `S_RESET_001`, `S_STATE_001`, `S_TIMING_001`, `S_PARAM_001`
  - `F_ASYNC_001`, `F_ASYNC_002`, `F_ASYNC_005`, `F_CDC_SYNC_001`, `F_MEM_IF_*`
  - `V_ASYNC_001`, `V_ASYNC_002`, `V_ASYNC_003`, `V_CDC_SYNC_001`, `V_COMMON_005`
- Freeze 状态: `TASKS.json` 中相关 spec 标为 `frozen`；`Q002/Q003` 已确认。
- 未纳入范围:
  - 真实 CDC/RDC 工具报告
  - STA/SDC 约束
  - vendor SRAM macro adapter
  - 形式验证

## 主要发现

### [S0 blocker] 异步 FIFO alignment 期间 `wr_full=0` 但 `push` 被丢弃

Evidence:

- `fifo_async_reg` alignment 期间 `wr_level` 被强制为 0，`wr_full = !wr_align_pending && (wr_level == DEPTH_LEVEL)`，所以 `wr_full=0`；但真正写入条件是 `!wr_align_pending && push && !wr_full`。
  - `rtl/fifo_async_reg.sv:127`
  - `rtl/fifo_async_reg.sv:130`
  - `rtl/fifo_async_reg.sv:149`
  - `rtl/fifo_async_reg.sv:163`
- `fifo_async_mem` 同构。
  - `rtl/fifo_async_mem.sv:145`
  - `rtl/fifo_async_mem.sv:148`
  - `rtl/fifo_async_mem.sv:167`
  - `rtl/fifo_async_mem.sv:181`
- 验证计划写明写域 `push && !wr_full` 时 reference model 接受数据。
  - `docs/fifo-verification-plan.md:81`

Impact:

reset 释放后的 alignment 窗口中，上游看到 FIFO 非满并发起 `push`，RTL 不写入、不报 `overflow`。这是静默数据丢失，属于 release blocker。

Fix:

- 让可见状态和接收条件一致。最保守做法是 alignment 期间 `wr_full=1`，直到写域真正可接收。
- 或者实现 alignment 期间真实接收 `push`，但这会扩大 reset/alignment 语义，需要 change-control。

Verification:

- 增加 reset release 后立即 `push` 的定向 case。
- 覆盖 `fifo_async_reg`、`fifo_async_mem`，`DEPTH=1/4`，`CDC_SYNC_STAGES=2/3`。
- 检查数据最终可读，或者状态明确阻塞且没有假接受。

Confidence: High

### [S0 blocker] 单侧远端 reset 可使异步 `level` 越界并破坏 `full/empty`

Evidence:

- spec 要求异步 FIFO 支持独立 reset 和保守 level。
  - `TASKS.json:S_RESET_001`
  - `TASKS.json:S_STATE_001`
- `fifo_async_reg` 直接用 `wr_bin - rd_bin_wr_sync` 生成写域 level，并只用 `wr_level == DEPTH` 判 full。
  - `rtl/fifo_async_reg.sv:124`
  - `rtl/fifo_async_reg.sv:127`
  - `rtl/fifo_async_reg.sv:130`
- `fifo_async_mem` 同构。
  - `rtl/fifo_async_mem.sv:142`
  - `rtl/fifo_async_mem.sv:145`
  - `rtl/fifo_async_mem.sv:148`
- 例子：`DEPTH=4` 时，如果 `wr_bin=5`、`rd_bin=4` 后读域单独 reset，写域同步到 `rd_bin_wr_sync=0` 后会得到 `wr_level=5`，超过 `DEPTH`，且 `wr_full` 不会被 `==4` 拉高。

Impact:

单侧 reset 后可能输出非法 level，并错误开放 push/pop。后果包括覆盖旧数据、读取无效数据，或者让上游/下游基于错误状态继续交易。

Fix:

- 定义远端 reset 的跨域重新 alignment/flush 协议。
- 或收窄 spec：要求异步 FIFO reset 在 quiesce 条件下成对执行。该变更必须进入 change-control，因为它改变了已冻结的独立 reset 语义。

Verification:

- pointer wrap 后执行单侧 `rd_rst_n` / `wr_rst_n` reset。
- 断言 `wr_level/rd_level` 始终在 `0..DEPTH`。
- 检查 reset 后不允许非法交易，且后续重新填充/读取顺序正确。

Confidence: High

### [S1 high] 异步 DV scoreboard 依赖 DUT status，独立性不足

Evidence:

- `dv/fifo_async_reg/tb_fifo_async_reg.cpp` 中 `wr_tick` 使用 `dut.wr_full` 决定期望 `overflow` 和 reference queue 是否入队；`rd_tick` 使用 `dut.rd_empty` 决定是否出队。
  - `dv/fifo_async_reg/tb_fifo_async_reg.cpp:92`
  - `dv/fifo_async_reg/tb_fifo_async_reg.cpp:115`
- `dv/fifo_async_mem/tb_fifo_async_mem.cpp` 同样使用 DUT status 决定 reference model 交易接受。
  - `dv/fifo_async_mem/tb_fifo_async_mem.cpp:92`
  - `dv/fifo_async_mem/tb_fifo_async_mem.cpp:115`

Impact:

如果 RTL 过早拉高 `wr_full` 或过久保持 `rd_empty`，scoreboard 会跟着 DUT 改变 reference queue 行为。false full/false empty 和错误跨域可见性可能被吸收，DV 无法独立证明 FIFO 接受/拒绝语义。

Fix:

- DV 侧拆分两个概念：
  - protocol-level accepted queue
  - DUT status 合法性检查
- 不要让 DUT `full/empty` 成为唯一 reference truth。

Verification:

- 做 mutation test：临时让 RTL 提前 assert `wr_full` 或 `rd_empty`，测试必须失败。
- 增加独立可见性模型或基于 bounded latency 的检查。

Confidence: High

### [S1 high] CDC/RDC 和 coverage closure 被高估

Evidence:

- 设计文档明确写当前没有形式验证、CDC 静态检查或 coverage closure。
  - `docs/fifo-design-guide.md:263`
- 验证计划明确写：
  - 异步时钟比例仍是手写 tick 交错序列。
  - 没有 Verilator line/toggle/branch coverage。
  - CDC 结构本身未做静态 CDC 检查。
  - `docs/fifo-verification-plan.md:182`
  - `docs/fifo-verification-plan.md:183`
  - `docs/fifo-verification-plan.md:185`
- `memory/decisions.md` 也说明后续 ASIC/CDC signoff 仍需 Gray bus skew、false path、synchronizer placement 处理。
  - `memory/decisions.md:80`

Impact:

`V_ASYNC_001`、`V_ASYNC_002`、`V_CDC_SYNC_001` 当前只能算行为 smoke/regression 覆盖，不能作为 CDC/RDC closure 或 release readiness 证据。

Fix:

- 增加多组 clock ratio/phase sweep，包括写快读慢、读快写慢、相近频率和 drifting phase。
- 增加 CDC/RDC report 或结构性 waiver，记录 source/destination domain、exact path、proof、owner 和 review trigger。
- 增加功能 coverage bins 或 Verilator coverage。

Verification:

- 回归输出 ratio/phase matrix 和命中结果。
- CDC/RDC 工具或结构检查产物纳入 `TASKS.json.traceability`。

Confidence: High

### [S1 high] 参数和 traceability closure 不完整

Evidence:

- `V_COMMON_005` 标为 covered，但脚本负向只覆盖：
  - illegal almost-full
  - illegal almost-empty
  - `DEPTH=3`
- 未覆盖 `DATA_WIDTH=0`、`DEPTH=0`，也未覆盖 async top-level `CDC_SYNC_STAGES=1`。
- 验证计划把 `DATA_WIDTH=0` / `DEPTH=0` 明确列为后续建议。
  - `docs/fifo-verification-plan.md:180`
- `TASKS.json.coverage_review.status` 为 `pass_with_known_gaps`，但 `follow_up_tasks` 为空。
  - `TASKS.json:1627`

Impact:

`covered` 这个状态过强。当前 traceability 可以证明一批定向 case 通过，但不能证明 `S_PARAM_001` 和 CDC stage 参数约束已完整关闭。

Fix:

- 补齐参数负向 case：
  - `DATA_WIDTH=0`
  - `DEPTH=0`
  - async reg/mem `CDC_SYNC_STAGES=1`
  - wrapper `ADDR_WIDTH` mismatch
- 或将相关 verification point 改成 `partial` / `waived`，并创建 follow-up task。

Verification:

- 脚本 summary 拆分各负向 case 名称。
- 增加 `jq` gate：每个 `verification_points[].feature_ids[]` 必须能追到含同一 V/F 的 trace row 和可执行 case ID。

Confidence: High

### [S2 medium] T009 memory wrapper 替换边界还不够硬

Evidence:

- `fifo_async_1r1w_mem` 写口 always_ff 含 `negedge wr_rst_n`，但 reset 分支为空。
  - `rtl/fifo_async_1r1w_mem.sv:33`
- 同步/异步 wrapper 都暴露 `ADDR_WIDTH` 参数，但 initial assertion 只检查 `DATA_WIDTH` 和 `DEPTH`。
  - `rtl/fifo_sync_1r1w_mem.sv:1`
  - `rtl/fifo_sync_1r1w_mem.sv:20`
  - `rtl/fifo_async_1r1w_mem.sv:1`
  - `rtl/fifo_async_1r1w_mem.sv:21`
- T009 wrapper standalone test 主要覆盖先写后读、reset 和 hold，没有显式覆盖同地址 `wr_en && rd_en` 冲突。

Impact:

后续替换 vendor macro 时，同地址读写模式、地址宽度错误或 reset 行为差异可能绕过当前 wrapper contract 测试。

Fix:

- 写口 reset 如果只用于禁止写入，应改成同步写口并用 `wr_rst_n && wr_en` 门控。
- 将 `ADDR_WIDTH` 改为 localparam，或加 elaboration-time assertion。
- 补同地址并发读写、不同地址并发读写、读延迟和 hold 的明确期望。

Verification:

- `run_t009_boundaries.sh` 将 `wrapper_contracts=2/2` 拆为 reset/read/hold/same_addr_conflict/addr_width_negative。

Confidence: Medium-High

## Scorecard

| Dimension | Score | Evidence |
| --- | ---: | --- |
| Spec coverage | 3/5 | frozen spec 存在，但单侧 reset、reset-in-flight、alignment 接收语义不完整 |
| RTL correctness | 2/5 | 异步 reset/alignment 有 S0 blocker |
| DV independence | 2/5 | 异步 scoreboard 依赖 DUT status |
| Verification closure | 2/5 | 当前是 pass_with_known_gaps，不是 closure |
| Protocol assertions | 1/5 | 主要是参数 assertion，缺交易不变量 |
| CDC/RDC hygiene | 1/5 | 无 CDC/RDC report 或 waiver |
| Lint cleanliness | 4/5 | `make lint` 通过，但 wrapper reset 写法弱 |
| Regression evidence | 4/5 | 当前 `make verilator` 通过 |
| Waiver quality | 1/5 | 没有可审计 waiver 或 follow-up task |
| Simplicity | 4/5 | RTL 总体简单，风险集中在 reset/CDC contract |

## 已运行验证

本次 review 期间在当前工作区运行：

```text
jq empty TASKS.json
make lint
make verilator
```

结果：

- `jq empty TASKS.json`: PASS
- `make lint`: PASS
- `make verilator`: PASS
- Verilator: 5.032
- 当前 Git 工作区在 review 前后未发现源码改动。

注意：`make verilator` 通过是必要证据，但不能覆盖 S0 reset/alignment 风险，也不能替代 CDC/RDC 和 coverage closure。

## 应该砍掉什么

- 砍掉把脚本级 `COVERAGE positive_matrix=...` 当作 closure 的说法。
- 砍掉没有 case ID、没有机器可复核映射的 traceability PASS claim。
- 砍掉没有 CDC/RDC report 或 waiver 的 readiness 结论。
- 砍掉“独立 reset 已覆盖”的宽泛表述，除非补齐 outstanding data/reset-in-flight 用例或收窄 spec。

## 必须补的验证

Directed:

- alignment 期间立即 `push`
- pointer wrap 后单侧 reset
- reset while non-empty / partially full
- reset 与 `push/pop` 同周期
- reset 后重新填充和读取
- async top-level `CDC_SYNC_STAGES=1`
- `DATA_WIDTH=0`、`DEPTH=0`
- wrapper same-address read/write conflict
- wrapper `ADDR_WIDTH` mismatch

Assertion/Formal:

- alignment 期间 `!wr_full` 必须意味着 push 可被接受，或 alignment 期间必须阻塞 push。
- `wr_level/rd_level` 始终在 `0..DEPTH`。
- illegal `push/pop` 不改变 pointer 和 stored data。
- reset release 后无 ghost valid / stale pointer。

Coverage:

- async clock ratio/phase matrix
- reset x transaction cross coverage
- full/empty/wrap/error/waterline bins
- wrapper contract bins

Regression:

- 生成 machine-readable summary，包含 git hash、Verilator 版本、命令、case ID、result。
- `TASKS.json.traceability.test_cases` 中每个 case ID 都能被脚本输出匹配。

## Knowledge Candidates

### KC-001: Alignment 状态必须和可见 backpressure 一致

**Domain:** RTL / CDC-RDC / reset

**Context:** 异步 FIFO reset release、CDC synchronizer alignment、跨域状态恢复。

**Bad pattern:** alignment 期间对外显示 `not full`，但内部实际不接收 push。

**Good pattern:** alignment 期间要么明确 backpressure，要么真正接收交易；状态输出不能诱导上游发送会被静默丢弃的数据。

**Why it matters:** 这是静默数据丢失，不是 coverage 小洞。

**Review questions:**

- reset release 后第一个 legal cycle 是什么？
- `!full` 是否严格意味着 push 可被接受？
- alignment suppress error 时，是否也同步 suppress transaction acceptance?

**Verification signals:**

- Directed test: reset release 后立即 push。
- Assertion/formal: `push && !full` implies accepted or explicitly blocked by spec-visible state。
- Coverage: reset/alignment x push/pop。

**Source evidence:** Finding S0-1.

**Promotion recommendation:** subproject memory / chip-design-review CDC-RDC reference.

### KC-002: 异步 FIFO scoreboard 不能用 DUT full/empty 当唯一事实源

**Domain:** DV / CDC-RDC

**Context:** 异步 FIFO、保守状态、跨域可见性延迟。

**Bad pattern:** reference model 根据 DUT `wr_full/rd_empty` 决定交易是否发生。

**Good pattern:** reference model 与 DUT status 检查分离；DUT status 是被检查对象，不是 reference truth。

**Why it matters:** false full/empty 会被 scoreboard 吸收，导致高风险 CDC bug 逃逸。

**Verification signals:**

- Directed test: forced false full/empty mutation must fail。
- Coverage: accepted/rejected transaction bins independent from DUT internal state。

**Source evidence:** Finding S1-1.

**Promotion recommendation:** subproject memory / DV closure reference.

### KC-003: `covered` 必须绑定可执行 case ID 和机器可复核结果

**Domain:** coverage / traceability

**Context:** `TASKS.json` 管理 spec -> feature -> verification -> case -> result。

**Bad pattern:** verification point 标 `covered`，但 test case 名称是人工字符串，脚本输出无法匹配。

**Good pattern:** 每个 case 输出稳定 ID；traceability 由脚本或 CI 机器检查。

**Why it matters:** 手写 PASS 记录会把 coverage hole 包装成 closure。

**Verification signals:**

- Regression/log: machine-readable result summary。
- Coverage: every V/F pair maps to executable case ID。

**Source evidence:** Finding S1-4.

**Promotion recommendation:** task source / subproject memory / workflow docs.

## 残余风险

- 未审查综合工具对 SystemVerilog array、empty async reset branch、`async_reg` attribute 的实际处理。
- 未审查 CDC/RDC 工具报告和 timing constraints。
- 未审查 vendor memory macro adapter，因为当前仓库尚未引入具体 macro。
- 未运行 formal 或 Verilator coverage database。
