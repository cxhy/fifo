# FIFO 设计文档

**状态**: implemented
**日期**: 2026-06-02
**覆盖任务**: T002, T003, T004, T005, T009

## 事实源关系

本文件是第一阶段 FIFO RTL 的设计说明，面向使用者和后续维护者。接口、功能点、
约束和验证项的事实源仍是：

1. `TASKS.json`
2. `docs/fifo-common-design.md`
3. `memory/decisions.md`
4. `memory/project-status.md`

本文件不引入新的接口语义；若与上述事实源冲突，以上述文件为准。

## 范围

第一阶段实现 4 个通用 `push/pop` FIFO 组件：

| 模块 | 时钟 | 后端 | 适用场景 |
| --- | --- | --- | --- |
| `fifo_sync_reg` | 单时钟 | register array | 小深度同步缓冲，作为同步 FIFO 行为参考 |
| `fifo_sync_mem` | 单时钟 | memory array | 与 `fifo_sync_reg` 同外部语义的 memory 后端 |
| `fifo_async_reg` | 写/读双时钟 | register array | 跨时钟域 FIFO，使用 Gray pointer CDC |
| `fifo_async_mem` | 写/读双时钟 | memory array | 与 `fifo_async_reg` 同外部语义的 memory 后端 |

非目标：

- 不封装 AXI、AXI-Stream、NoC 或其他上层协议。
- 不支持非 2 次幂深度。
- 不支持多读写端口。
- 不绑定具体 SRAM macro。
- 不提供 sticky error、错误计数或 CSR 清除机制。

## 公共参数

- `DATA_WIDTH`: 数据位宽，必须大于 0。
- `DEPTH`: FIFO 深度，必须大于 0 且为 2 的幂。
- `FALL_THROUGH`: 仅同步 FIFO 支持。异步 FIFO 第一阶段不支持 fall-through。
- `CDC_SYNC_STAGES`: 仅异步 FIFO 支持，默认 2，必须大于等于 2，用于配置内部
  `fifo_cdc_sync` 同步级数。

非法参数在 elaboration/simulation 阶段通过 `$fatal` 暴露。当前 RTL 兼容 `DEPTH == 1`，
地址宽度会退化为 1，地址固定或自然环绕。

## 同步 FIFO 接口

`fifo_sync_reg` 和 `fifo_sync_mem` 使用相同端口：

- `clk/rst_n`: 单时钟和低有效复位。
- `push/push_data`: 写入请求和写入数据。
- `pop/pop_data`: 读取请求和读取数据。
- `cfg_almost_full_level/cfg_almost_empty_level`: 运行时水线配置端口。
- `full/empty/level`: 当前占用状态。
- `almost_full/almost_empty`: 基于 `level` 和水线配置的组合状态。
- `overflow/underrun`: 单周期 critical error pulse。

同步 FIFO 的核心状态为 `wr_ptr`、`rd_ptr` 和 `level`。`full` 由 `level == DEPTH`
生成，`empty` 由 `level == 0` 生成。

## 同步行为

合法存储读取条件为 `pop && !empty`。读取时，`pop_data` 在时钟沿更新为旧队首数据；
没有合法读取时，`pop_data` 保持最近一次有效输出。

合法存储写入条件为：

```text
push && (!full || (pop && !empty)) && !fall_through_read
```

这带来两个关键行为：

- 满状态下 `push && pop` 是合法替换：读出旧队首、写入新队尾、`level` 保持 `DEPTH`、
  不触发 `overflow`。
- 满状态下 `push && !pop` 触发 `overflow`，不写 array，不推进写指针。

`FALL_THROUGH == 1` 且 FIFO 为空时，`push && pop` 形成直接透传：

- `pop_data` 更新为 `push_data`。
- 数据不进入存储 array。
- FIFO 仍为空，`level` 保持 0。
- 不触发 `underrun`。

`FALL_THROUGH == 0` 时，空状态 `pop` 始终触发 `underrun`，即使同周期 `push` 为 1。

## 异步 FIFO 接口

`fifo_async_reg` 和 `fifo_async_mem` 使用相同端口，分为写域和读域。

写域：

- `wr_clk/wr_rst_n`
- `push/push_data`
- `cfg_almost_full_level`
- `wr_full/wr_almost_full/wr_level`
- `overflow`

读域：

- `rd_clk/rd_rst_n`
- `pop/pop_data`
- `cfg_almost_empty_level`
- `rd_empty/rd_almost_empty/rd_level`
- `underrun`

异步 FIFO 没有 `FALL_THROUGH` 参数。读域只根据 `rd_empty` 判断读取合法性，
`pop && rd_empty` 始终触发 `underrun`。

## 异步 CDC 结构

异步 FIFO 使用扩展二进制指针和 Gray 指针：

- 写域维护 `wr_bin/wr_gray`。
- 读域维护 `rd_bin/rd_gray`。
- 写指针 Gray 值通过内部 `fifo_cdc_sync` 同步进入读域。
- 读指针 Gray 值通过内部 `fifo_cdc_sync` 同步进入写域。
- 各域将同步后的远端 Gray 指针转回 binary 后计算本地域 level。

`DEPTH > 1` 时指针宽度为 `clog2(DEPTH)+1`，额外一位用于区分环绕；
`DEPTH == 1` 时地址固定为 0。

写域状态：

```text
wr_level = wr_bin - rd_bin_wr_sync
wr_full  = wr_level == DEPTH
```

读域状态：

```text
rd_level = wr_bin_rd_sync - rd_bin
rd_empty = rd_level == 0
```

由于远端指针经过同步链，`wr_level` 和 `rd_level` 是保守观测值，不承诺全局瞬时精确：

- `wr_level` 可能比真实占用偏大，适合写域判断 full/almost_full。
- `rd_level` 可能比真实可读量偏小，适合读域判断 empty/almost_empty。

每个时钟域复位释放后会进入一次 alignment 状态，将本地域指针对齐到已采样的远端
Gray 指针。alignment 期间 suppress 对应错误 pulse，并输出保守空状态。
`fifo_cdc_sync` reset 时同步链各级清 0；alignment 等待同步输出有效后完成，等待时间随
`CDC_SYNC_STAGES` 配置增长。

## Reset 语义

- 同步 FIFO 使用低有效 `rst_n`。
- 异步 FIFO 使用独立低有效 `wr_rst_n` 和 `rd_rst_n`。
- 复位后指针和 level 状态归零。
- 复位后 `pop_data == 0`。
- 复位后 `overflow == 0`，`underrun == 0`。
- 异步读域 reset 会将 `pop_data` 重新置 0；reset 释放后，在第一次合法读取前保持 0。

## 错误语义

`overflow` 和 `underrun` 都是单周期 critical error pulse。

同步 FIFO：

```text
overflow = push && full && !pop
underrun = pop && empty && !(FALL_THROUGH && push)
```

异步 FIFO：

```text
overflow = push && wr_full
underrun = pop && rd_empty
```

错误请求不能破坏 FIFO 状态：

- overflow 不推进写指针，不覆盖已存数据。
- underrun 不推进读指针，不覆盖 `pop_data`。

## 水线配置

水线配置通过端口提供，不是 parameter。

- `cfg_almost_full_level` 合法范围为 `1..DEPTH`。
- `cfg_almost_empty_level` 合法范围为 `0..DEPTH-1`。

同步 FIFO 中：

```text
almost_full  = level >= cfg_almost_full_level
almost_empty = level <= cfg_almost_empty_level
```

异步 FIFO 中：

```text
wr_almost_full  = wr_level >= cfg_almost_full_level
rd_almost_empty = rd_level <= cfg_almost_empty_level
```

配置端口由调用方保证在目标时钟域稳定。RTL 不对配置端口做跨域同步或去抖。
非法配置通过 assertion/fatal 暴露。

## 后端差异

`reg` 版本当前使用可综合 SystemVerilog array 保存数据；`mem` 版本通过内部 memory
wrapper 提供可替换 1R1W 后端边界。

- 同步 `reg` 与 `mem` 的外部端口和状态语义一致。
- 异步 `reg` 与 `mem` 的外部端口和状态语义一致。
- `mem` 版本内部例化 `fifo_sync_1r1w_mem` 或 `fifo_async_1r1w_mem` 行为级模型，
  不在 FIFO 顶层新增 memory 端口。

若后续接入具体 SRAM macro，需要重新审查：

- 同地址读写冲突语义。
- 读延迟对 `pop_data` 的影响。
- 异步读写端口和 CDC 约束。

## T009 ASIC 替换边界

T009 将当前 memory 后端和异步 Gray pointer 同步链抽取为可替换边界。`Q002/Q003`
已确认并已实现。

新增 RTL 边界：

- `rtl/fifo_sync_1r1w_mem.sv`: `fifo_sync_mem` 内部使用的单时钟 1R1W memory wrapper。
- `rtl/fifo_async_1r1w_mem.sv`: `fifo_async_mem` 内部使用的双时钟 1R1W memory wrapper。
- `rtl/fifo_cdc_sync.sv`: `fifo_async_reg` 和 `fifo_async_mem` 内部使用的 Gray pointer sync module。

保持不变的外部语义：

- 四个 FIFO 顶层端口不变。
- `overflow/underrun` 仍是单周期 pulse。
- `pop_data` reset 后为 `0`，无合法读取时保持。
- 同步 `FALL_THROUGH` 和满时 `push && pop` 替换语义不变。
- 异步 FIFO 仍不支持 fall-through，`wr_level/rd_level` 仍是本地域保守观测值。

memory wrapper contract：

- wrapper 负责对 FIFO 侧提供稳定 `rd_data`，reset 后输出为 `0`。
- 合法读后 `rd_data` 更新，无合法读时保持最近有效输出。
- vendor memory macro 的读延迟、同地址读写模式和 reset 能力若不同，必须通过 adapter
  满足 FIFO 侧 contract。
- 若 vendor memory macro 无法通过 adapter 维持当前 `pop_data` 时序，必须另走
  change-control，T009 不静默改变 FIFO 外部语义。

CDC sync contract：

- `fifo_cdc_sync` 参数化 `WIDTH` 和 `STAGES`，`STAGES >= 2`。
- `fifo_async_reg/fifo_async_mem` 通过 `CDC_SYNC_STAGES` parameter 配置内部同步级数。
- sync module 使用目标域 `clk/rst_n`，reset 后同步链各级和输出均为 `0`。
- 抽取 sync module 不改变现有 alignment、保守 level、full/empty 或错误 pulse 行为。

## 设计限制

- 第一阶段只支持 2 次幂深度。
- 异步 FIFO 不支持 fall-through。
- 异步 FIFO 不提供全局精确 occupancy。
- 当前没有 ready/valid wrapper。
- 当前没有形式验证、CDC 静态检查或 coverage closure。

## 文件索引

- RTL:
  - `rtl/fifo_sync_reg.sv`
  - `rtl/fifo_sync_mem.sv`
  - `rtl/fifo_sync_1r1w_mem.sv`
  - `rtl/fifo_async_reg.sv`
  - `rtl/fifo_async_mem.sv`
  - `rtl/fifo_async_1r1w_mem.sv`
  - `rtl/fifo_cdc_sync.sv`
- 设计规格: `docs/fifo-common-design.md`
- 验证计划: `docs/fifo-verification-plan.md`
- 任务事实源: `TASKS.json`
- 决策记录: `memory/decisions.md`
