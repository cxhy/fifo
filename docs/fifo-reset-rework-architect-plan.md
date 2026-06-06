# FIFO Reset Rework Architect Plan

**状态**: draft, pending user confirmation
**日期**: 2026-06-06
**角色**: fifo-architect
**输入**: `docs/fifo-design-review-2026-06-06.md`
**重构前基线**: tag `pre-reset-rework-20260606` -> commit `180e44c`

## 目标

本计划用于确认 review 报告中的问题是否值得进入下一轮重构，并给出重构前的范围边界。用户确认本计划后，才能按 FIFO 三角色流程进入 RTL/DV 实现。

核心目标是把异步 FIFO reset 语义从当前不完备的“独立 reset + 本地域 alignment”改为可验证的 reset/flush 协议：

- 任一侧 reset 都会使异步 FIFO 进入 flush/alignment。
- flush/alignment 期间不接受用户交易。
- 写侧对外阻塞 push，读侧对外阻塞 pop。
- reset/flush 后 FIFO 为空，`pop_data` 为 0，错误 pulse 不误报。
- 后续交易从空 FIFO 状态重新开始。

## Review 点取舍

### 必须纳入 T011

1. `S0` alignment 期间 `wr_full=0` 但 push 被丢弃

结论：必须修。该问题会导致静默数据丢失，属于功能正确性 blocker。

期望方向：

- alignment/flush 期间 `wr_full=1`。
- alignment/flush 期间 `rd_empty=1`。
- alignment/flush 期间 suppress `overflow/underrun`。
- alignment/flush 期间不接受 `push/pop`。

2. `S0` 单侧远端 reset 导致 level 越界和 full/empty 不可信

结论：必须修。当前“独立 reset”没有远端 reset 协议，不能保留为 frozen 语义。

期望方向：

- 采用 flush-on-any-side-reset 语义。
- 任一 reset 被本域或远端同步观察到后，本域重新进入 flush/alignment。
- flush 结果是 FIFO 内容被丢弃，两个域恢复共同 empty 状态。
- 不承诺单侧 reset 后保留未读数据。

3. 异步 reset/alignment DV 不足

结论：必须和 RTL 同轮修。否则无法证明 T011 没有回归。

最小 DV 覆盖：

- reset release 后立即 push，必须被阻塞而不是假接受。
- 写入若干数据后读域单侧 reset，最终 FIFO flush 为空，后续重新写读顺序正确。
- 写入若干数据后写域单侧 reset，最终 FIFO flush 为空，后续重新写读顺序正确。
- reset 与 push/pop 同周期，错误 pulse 不误报，指针和 level 不越界。
- 覆盖 `fifo_async_reg` 和 `fifo_async_mem`。
- 至少覆盖 `DEPTH=1/4`、`CDC_SYNC_STAGES=2/3` 的关键组合。

4. 异步 scoreboard 对 DUT status 依赖过强

结论：T011 至少需要局部修到能抓 reset/flush 语义。完整随机独立模型可作为后续 hardening，但本轮不能继续让 DUT `wr_full/rd_empty` 单独决定 reference queue。

T011 最小要求：

- 在 alignment/flush 期间，如果 `push && !wr_full` 出现，test 必须 fail。
- reset/flush 后 reference queue 明确清空。
- 后续合法 push/pop 由 test scenario 和 spec 期望驱动，不把错误 full/empty 吸收到 reference model 中。

### T011 可顺手处理但不作为主目标

1. async top-level `CDC_SYNC_STAGES=1` 负向配置

价值高、改动小。可以纳入 T011 的脚本负向 case，避免 CDC stage 约束只在 standalone sync module 中覆盖。

2. `DATA_WIDTH=0` / `DEPTH=0` 负向配置

价值中等。可以作为 T011 后续小补丁或 T012，避免参数负向测试把本轮 reset 重构拖大。

3. `fifo_async_1r1w_mem` 写口空 reset 分支

价值中等，属于 ASIC wrapper hygiene。若 T011 修改 `fifo_async_mem` 时碰到 wrapper，可顺手清理；否则建议单独 T012。

### 不纳入 T011

1. 静态 CDC/RDC signoff

理由：需要工具报告、约束和 waiver 模板，不应和 RTL reset 修复混在同一轮。T011 只应把 RTL 结构和行为测试修到可审查。

2. Verilator line/toggle/branch coverage closure

理由：这是 verification closure hardening，不是 reset 语义修复的前置条件。

3. vendor memory macro adapter

理由：当前仓库没有具体 macro。T011 不改变 memory macro adapter contract。

4. 完整随机压力和机器可复核 traceability 基建

理由：有价值，但范围大。T011 可保留 deterministic directed tests，后续 T012/T013 做 regression infrastructure。

## 拟冻结的新 reset 语义

用户确认后，将通过 change-control 更新 `TASKS.json` 和文档。拟冻结语义如下：

1. Reset polarity

- 同步 FIFO 保持单一低有效 `rst_n`。
- 异步 FIFO 保持低有效 `wr_rst_n` 和 `rd_rst_n`。

2. Reset assertion

- 任一异步 FIFO reset 拉低时，本地域立即清本地域指针、状态、错误 pulse。
- 读域 reset 立即将 `pop_data` 置 0。

3. Reset release and flush

- 异步 FIFO 任一侧 reset 被任一域观察到后，FIFO 进入 flush/alignment。
- flush/alignment 结果是 FIFO 逻辑内容为空。
- reset/flush 不保留 reset 前已经写入但未读出的数据。

4. User-visible state during flush/alignment

- 写域：`wr_full=1`，`wr_level=DEPTH` 或一个明确的阻塞状态，`wr_almost_full=1`。
- 读域：`rd_empty=1`，`rd_level=0`，`rd_almost_empty=1`。
- `overflow=0`，`underrun=0`。
- `push/pop` 请求不被接受，不改变 FIFO 内容。

5. Normal operation resume

- 本域 reset 已同步释放。
- 远端 reset release 已同步可见。
- Gray pointer sync chain 已稳定。
- 本地域从共同 empty 状态开始重新接受交易。

## RTL 修改计划

Owner: `fifo-rtl-designer`

Write scope:

- `rtl/fifo_async_reg.sv`
- `rtl/fifo_async_mem.sv`
- 如需要，`rtl/fifo_async_1r1w_mem.sv`

计划步骤：

1. 抽象每个异步域的 reset/flush 状态

- 写域维护 `wr_flush_pending` 或复用/扩展 `wr_align_pending`。
- 读域维护 `rd_flush_pending` 或复用/扩展 `rd_align_pending`。
- 任一远端 reset 事件同步到本域后，本域进入 flush/alignment。

2. 增加远端 reset 同步

- 写域同步 `rd_rst_n` 或 reset epoch/toggle。
- 读域同步 `wr_rst_n` 或 reset epoch/toggle。
- 优先采用 reset epoch/toggle，避免只同步 level reset 信号带来的脉冲遗漏。

3. 定义共同 empty 对齐点

- flush 后两域本地 pointer 回到 0。
- Gray pointer 输出为 0。
- 两域等待远端 reset release/epoch 可见后退出 flush。

4. 阻塞 alignment 期间用户交易

- `wr_full` 在 flush/alignment 期间为 1。
- `rd_empty` 在 flush/alignment 期间为 1。
- 写入条件必须包含 `!wr_flush_pending`。
- 读取条件必须包含 `!rd_flush_pending`。

5. 保持现有非 reset 行为

- 正常状态下 Gray pointer、full/empty、level、overflow/underrun 语义不退化。
- `CDC_SYNC_STAGES` 参数继续控制 pointer sync module。

## DV 修改计划

Owner: `fifo-dv-verifier`

Write scope:

- `dv/fifo_async_reg/tb_fifo_async_reg.cpp`
- `dv/fifo_async_mem/tb_fifo_async_mem.cpp`
- `scripts/run_fifo_async_reg.sh`
- `scripts/run_fifo_async_mem.sh`
- 如需要，`docs/fifo-verification-plan.md`

计划步骤：

1. 新增 reset/flush 定向 case

- `CASE_ASYNC_RESET_RELEASE_PUSH_BLOCKED`
- `CASE_ASYNC_RD_RESET_FLUSH_NONEMPTY`
- `CASE_ASYNC_WR_RESET_FLUSH_NONEMPTY`
- `CASE_ASYNC_RESET_WITH_ACTIVE_REQ`
- `CASE_ASYNC_POST_FLUSH_REUSE`

2. 修正 scoreboard

- flush 发生时 reference queue 明确清空。
- alignment/flush 期间如果 DUT 暴露可接受状态但实际不接受，test fail。
- reset/flush 后重新建模合法交易。

3. 扩展参数 smoke

- 默认矩阵继续覆盖 `DATA_WIDTH=1/8/17`、`DEPTH=1/2/4/8`。
- T011 最小额外 smoke：`FIFO_CDC_SYNC_STAGES=3 FIFO_DATA_WIDTHS=8 FIFO_DEPTHS=1 4`。

4. 增加 async top-level illegal stage negative

- `CDC_SYNC_STAGES=1` 在 `fifo_async_reg` 和 `fifo_async_mem` 顶层必须 fatal。

## Architect 集成计划

Owner: `fifo-architect`

Write scope:

- `TASKS.json`
- `docs/fifo-common-design.md`
- `docs/fifo-design-guide.md`
- `docs/fifo-verification-plan.md`
- `memory/project-status.md`
- `memory/decisions.md`
- `memory/iterations.md`

计划步骤：

1. 用户确认本计划后，创建 `T011`。
2. 记录 change-control `CCR_T011_001`，影响：
   - `S_RESET_001`
   - `S_STATE_001`
   - `S_TIMING_001`
   - `F_ASYNC_001`
   - `F_ASYNC_002`
   - `F_ASYNC_005`
   - `V_ASYNC_001`
   - `V_ASYNC_002`
   - `V_ASYNC_003`
3. 新增或更新 feature/verification IDs：
   - `F_ASYNC_RESET_001`: 任一侧 reset 触发 flush-on-reset。
   - `F_ASYNC_RESET_002`: flush/alignment 期间阻塞用户交易。
   - `V_ASYNC_RESET_001`: reset release 后立即 push/pop 阻塞。
   - `V_ASYNC_RESET_002`: 单侧 reset while non-empty flush。
   - `V_ASYNC_RESET_003`: post-flush reuse。
4. 更新 traceability matrix。
5. 完成 RTL/DV 后执行集成验证并记录结果。

## 验收命令

最窄 RTL/DV 验证：

```text
jq empty TASKS.json
make lint
bash scripts/run_fifo_async_reg.sh
bash scripts/run_fifo_async_mem.sh
FIFO_CDC_SYNC_STAGES=3 FIFO_DATA_WIDTHS="8" FIFO_DEPTHS="1 4" bash scripts/run_fifo_async_reg.sh
FIFO_CDC_SYNC_STAGES=3 FIFO_DATA_WIDTHS="8" FIFO_DEPTHS="1 4" bash scripts/run_fifo_async_mem.sh
```

完整回归：

```text
make verilator
```

## 提交计划

已完成：

- 当前重构前基线已打 tag：`pre-reset-rework-20260606`。
- tag 指向 review 报告提交：`180e44c docs: add fifo design review report`。

待用户确认后：

1. commit: `chore: plan async reset rework`
2. commit: `docs: confirm async reset flush semantics`
3. commit: `fix: block async fifo transactions during reset flush`
4. commit: `test: cover async fifo reset flush`
5. commit: `chore: record async reset rework completion`

最终 commit 数量可按实际调试过程调整，但每个 commit 必须保持单一职责。

## 需要用户确认的问题

1. 是否确认异步 FIFO 采用 flush-on-any-side-reset 语义，即任一侧 reset 后不保留 FIFO 中已有数据？
2. 是否确认 flush/alignment 期间写侧以 `wr_full=1` 对外阻塞 push，读侧以 `rd_empty=1` 对外阻塞 pop？
3. 是否确认 T011 只处理 reset/flush 语义和最小 DV 证明，CDC/RDC signoff、coverage DB、vendor macro adapter 留作后续任务？
