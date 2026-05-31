# FIFO 项目状态

本文件是 FIFO 子项目的本地项目记忆入口。FIFO 相关阶段状态、长期设计决策、
阻塞记录和复盘应保存在本目录下，不写入上一级 workspace 的 `../memory/`。

## 当前焦点

- FIFO 公共组件定位为通用 `push/pop` FIFO/bridge，不绑定 AXI 或其他上层协议。
- 第一阶段规划 4 类核心：`fifo_sync_reg`、`fifo_sync_mem`、`fifo_async_reg`、`fifo_async_mem`。
- 当前工作项为 `T002`：实现 `fifo_sync_reg`，RTL 写入范围为 `rtl/fifo_sync_reg.sv`，DV 写入范围为 `dv/fifo_sync_reg/` 和 `scripts/run_fifo_sync_reg.sh`。
- 第一版只支持 2 次幂深度；非 2 次幂 FIFO 后续单独设计。
- 任务、模块功能点、设计约束和验证项使用 `TASKS.json` 管控。
- 已创建三个默认协作角色：`fifo-architect`、`fifo-rtl-designer`、`fifo-dv-verifier`。
- 每推进一个有意义的节点后，立即在 FIFO 子项目仓库中创建聚焦 commit。

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

## 当前阻塞

- 当前无开放接口问题；`fifo-architect` 已分发 `fifo_sync_reg` 的 RTL 和 DV 任务。

## 关键入口

- [FIFO 公共组件设计规格](../docs/fifo-common-design.md)
- [JSON 任务事实源](../TASKS.json)
- [Agent 角色定义](../agents/)
- [设计决策索引](decisions.md)
