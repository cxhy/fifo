# FIFO 项目状态

本文件是 FIFO 子项目的本地项目记忆入口。FIFO 相关阶段状态、长期设计决策、
阻塞记录和复盘应保存在本目录下，不写入上一级 workspace 的 `../memory/`。

## 当前焦点

- FIFO 公共组件定位为通用 `push/pop` FIFO/bridge，不绑定 AXI 或其他上层协议。
- 第一阶段规划 4 类核心：`fifo_sync_reg`、`fifo_sync_mem`、`fifo_async_reg`、`fifo_async_mem`。
- `T002`-`T005` 已完成：`fifo_sync_reg`、`fifo_sync_mem`、`fifo_async_reg`、`fifo_async_mem`
  均已实现 RTL、Verilator DV 和运行脚本。
- `T006` 已完成：补充 `docs/fifo-design-guide.md` 和 `docs/fifo-verification-plan.md`，
  并保留 `docs/documentation-plan.md` 作为文档化过程记录。
- `T007` 已完成：把 spec freeze/change-control、feature/verification ID、traceability
  matrix、失败 triage 和 completion gate 固化到 `AGENTS.md`、`agents/fifo-architect.md`
  和 `TASKS.json`。
- `T008` 已完成：扩展 `DATA_WIDTH=1/8/17`、`DEPTH=1/2/4/8` 参数矩阵，拆分
  almost-full / almost-empty / 非 2 次幂深度负向 case，并使用脚本级 coverage summary
  量化命中。
- `T009` 已完成：`fifo_sync_mem/fifo_async_mem` 内部例化可替换 memory wrapper，
  `fifo_async_reg/fifo_async_mem` 内部例化可配置级数 Gray pointer CDC sync module；
  `Q002/Q003` 已确认并关闭。
- `T010` 已完成：FIFO 子项目已删除 local author 覆盖配置，重写 `main` 提交
  Author/Committer 和 annotated tag tagger 为全局 Git 配置；本轮不修改 RTL/DV 行为。
- `T011` 已进入 `plan_ready`：用户确认异步 FIFO 采用 flush-on-any-side-reset 语义；
  任一侧 reset 后不保留已有数据，flush/alignment 期间写侧 `wr_full=1` 阻塞 `push`、
  读侧 `rd_empty=1` 阻塞 `pop`。本节点只记录确认和计划，尚未开始 RTL/DV 重构。
- `fifo-architect` 负责 `TASKS.json`、`docs/`、`memory/` 的任务状态、约束一致性和集成检查，不写 RTL/DV。
- `fifo-rtl-designer` 负责 RTL 实现，写入范围限定为：
  - `T002`: `rtl/fifo_sync_reg.sv`
  - `T003`: `rtl/fifo_sync_mem.sv`
  - `T004`: `rtl/fifo_async_reg.sv`
  - `T005`: `rtl/fifo_async_mem.sv`
- `fifo-dv-verifier` 负责 Verilator 验证环境、参考模型、scoreboard、测试和运行脚本，写入范围限定为：
  - `T002`: `dv/fifo_sync_reg/`、`scripts/run_fifo_sync_reg.sh`
  - `T003`: `dv/fifo_sync_mem/`、`scripts/run_fifo_sync_mem.sh`
  - `T004`: `dv/fifo_async_reg/`、`scripts/run_fifo_async_reg.sh`
  - `T005`: `dv/fifo_async_mem/`、`scripts/run_fifo_async_mem.sh`
- 第一版只支持 2 次幂深度；非 2 次幂 FIFO 后续单独设计。
- 任务、模块功能点、设计约束和验证项使用 `TASKS.json` 管控。
- `TASKS.json` schema v2 增加 `spec_items`、`features`、`verification_points`、
  `traceability`、`iterations` 和 `validation` 字段，用于追踪
  spec -> feature -> design item -> verification item -> test/case -> result。
- 已创建三个默认协作角色：`fifo-architect`、`fifo-rtl-designer`、`fifo-dv-verifier`。
- 每推进一个有意义的节点后，立即在 FIFO 子项目仓库中创建聚焦 commit。

## 当前验证结果

- `make lint` 通过：四个 RTL 均按独立 top 通过 Verilator lint。
- `make verilator` 通过：四个模块的主测试和非法水线 assertion 测试均通过。
- `bash scripts/run_t009_boundaries.sh` 通过：T009 结构检查、wrapper contract、
  `fifo_cdc_sync` `STAGES=2/3` contract 和 `STAGES=1` 负向配置均通过。
- 单独脚本均通过：
  - `bash scripts/run_fifo_sync_reg.sh`
  - `bash scripts/run_fifo_sync_mem.sh`
  - `bash scripts/run_fifo_async_reg.sh`
  - `bash scripts/run_fifo_async_mem.sh`
- T008 参数矩阵结果：
  - `fifo_sync_reg`: `positive_matrix=24/24`，`negative_cases=3/3`
  - `fifo_sync_mem`: `positive_matrix=24/24`，`negative_cases=3/3`
  - `fifo_async_reg`: `positive_matrix=12/12`，`negative_cases=3/3`
  - `fifo_async_mem`: `positive_matrix=12/12`，`negative_cases=3/3`
- 集成时修正了 `fifo_async_mem` DV reset reference：read-domain reset 后 `pop_data` 期望回到 `0`。
- T008 初次矩阵暴露同步 FIFO `DEPTH=1` 满时 `push && pop` 替换路径 RTL bug；已由
  `7de73ac fix: handle depth-one sync fifo replacement` 修复 `fifo_sync_reg` 和 `fifo_sync_mem`。
- T008 集成时还修正了异步 reg/mem testbench 中隐含 `DEPTH=4` 的填满流程，使其按参数化
  `kDepth` 触发 full/overflow 检查。
- T009 验证结果：
  - `bash scripts/run_fifo_sync_mem.sh`: `positive_matrix=24/24`，`negative_cases=3/3`
  - `bash scripts/run_fifo_async_reg.sh`: `positive_matrix=12/12`，`cdc_sync_stages=2`，`negative_cases=3/3`
  - `bash scripts/run_fifo_async_mem.sh`: `positive_matrix=12/12`，`cdc_sync_stages=2`，`negative_cases=3/3`
  - `FIFO_CDC_SYNC_STAGES=3 FIFO_DATA_WIDTHS=8 FIFO_DEPTHS=4` 的 async reg/mem smoke 均 PASS
  - `make lint`、`make verilator` 均 PASS

## 已确认决策

- 同步 FIFO `overflow = push && full && !pop`；异步 FIFO 写域 `overflow = push && wr_full`。
- 同步 FIFO `underrun = pop && empty && !(FALL_THROUGH && push)`；异步 FIFO 读域 `underrun = pop && rd_empty`。
- `overflow/underrun` 是 critical error。
- 使用低有效复位；异步 FIFO 使用独立 `wr_rst_n` 和 `rd_rst_n`。
- 异步 FIFO 的 `wr_level/rd_level` 是各自时钟域的保守观测值，不承诺全局瞬时精确。
- `fall-through` 只用于同步 FIFO；异步 FIFO 第一阶段不支持透传。
- `pop_data` 在无合法读取时保持上一次有效输出。
- 复位后 `pop_data` 统一为 `0`。
- 非法水线配置通过 assertion 报出。
- 同步 FIFO 满状态下 `push && pop && full` 是合法同周期替换，不触发 `overflow`。
- memory 类型 FIFO 顶层端口不暴露 memory macro 接口；后续 vendor macro 必须通过 wrapper/adapter
  满足 `rd_data` reset、合法读更新和无合法读保持 contract。
- 异步 FIFO 的 Gray pointer 同步器由内部 `fifo_cdc_sync` 承担，`CDC_SYNC_STAGES` 默认 2 且可配置。
- 异步 FIFO T011 reset 语义已确认：任一侧 reset 触发 flush/alignment，reset 前已有数据不保留；
  flush/alignment 期间 `wr_full/rd_empty` 对外阻塞交易，恢复后从共同 empty 状态重新开始。

## 当前阻塞

- 当前无待用户确认的 T009/T011 spec 问题；`Q002/Q003/Q004` 已确认。
- 第一阶段四个核心 FIFO 和 T009 ASIC 替换边界均已完成。
- T011 尚未实现 RTL/DV；下一步应按三角色流程分派 `fifo-rtl-designer` 和
  `fifo-dv-verifier`，实现并验证 flush-on-any-side-reset。
- Git 身份清理已完成，后续提交默认使用全局 Git 配置。
- 剩余覆盖建议：更大参数矩阵、系统化异步时钟比例 sweep、seed 可复现随机压力、Verilator
  line/toggle/branch coverage 或更细粒度自定义 coverage counter。

## 关键入口

- [FIFO 公共组件设计规格](../docs/fifo-common-design.md)
- [FIFO 设计文档](../docs/fifo-design-guide.md)
- [FIFO 验证计划](../docs/fifo-verification-plan.md)
- [文档补充过程记录](../docs/documentation-plan.md)
- [JSON 任务事实源](../TASKS.json)
- [Agent 角色定义](../agents/)
- [设计决策索引](decisions.md)
