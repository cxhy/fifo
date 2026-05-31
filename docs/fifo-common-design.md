# FIFO 公共组件设计规格

**状态**: draft
**日期**: 2026-06-01

## 目标

本仓库交付通用 FIFO/bridge 公共组件，不绑定 AXI、NoC 或其他上层协议。
核心接口采用 `push/pop` 语义，用于构建数据流缓冲、跨模块解耦和跨时钟域桥接。

第一阶段规划覆盖 4 类 FIFO：

| 时钟类型 | register 版本 | memory 版本 |
| --- | --- | --- |
| 同步单时钟 | `fifo_sync_reg` | `fifo_sync_mem` |
| 异步跨时钟 | `fifo_async_reg` | `fifo_async_mem` |

## 非目标

- AXI、AXI-Stream、NoC 或特定上层协议封装。
- 非 2 次幂深度 FIFO。第一阶段 `DEPTH` 必须是 2 的幂。
- 多读写端口 FIFO。
- ECC、奇偶校验、QoS 或优先级调度。
- 依赖具体 SRAM macro 的实现。

## 通用参数

- `DATA_WIDTH`: 数据位宽，必须大于 0。
- `DEPTH`: FIFO 可存储元素数，第一阶段必须大于 0 且为 2 的幂。
- `FALL_THROUGH`: 仅同步 FIFO 支持。异步 FIFO 第一阶段不支持透传。

参数非法时，RTL 或仿真阶段应通过 elaboration-time assertion 暴露错误。

## 同步 FIFO 接口草案

```systemverilog
module fifo_sync_reg #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter bit FALL_THROUGH = 1'b0
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         push,
    input  logic [DATA_WIDTH-1:0]        push_data,
    input  logic                         pop,
    output logic [DATA_WIDTH-1:0]        pop_data,

    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_full_level,
    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_empty_level,

    output logic                         full,
    output logic                         empty,
    output logic                         almost_full,
    output logic                         almost_empty,
    output logic [$clog2(DEPTH+1)-1:0]   level,

    output logic                         overflow,
    output logic                         underrun
);
```

`fifo_sync_mem` 使用同一接口。

## 异步 FIFO 接口草案

```systemverilog
module fifo_async_reg #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16
) (
    input  logic                         wr_clk,
    input  logic                         wr_rst_n,
    input  logic                         push,
    input  logic [DATA_WIDTH-1:0]        push_data,
    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_full_level,
    output logic                         wr_full,
    output logic                         wr_almost_full,
    output logic [$clog2(DEPTH+1)-1:0]   wr_level,
    output logic                         overflow,

    input  logic                         rd_clk,
    input  logic                         rd_rst_n,
    input  logic                         pop,
    output logic [DATA_WIDTH-1:0]        pop_data,
    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_empty_level,
    output logic                         rd_empty,
    output logic                         rd_almost_empty,
    output logic [$clog2(DEPTH+1)-1:0]   rd_level,
    output logic                         underrun
);
```

`fifo_async_mem` 使用同一接口。

## Push/Pop 语义

- 写入请求条件为 `push`。
- 读取请求条件为 `pop`。
- 同步 FIFO 满状态下 `push && pop && full` 是合法同周期替换：读出旧队首，写入新队尾，`level` 保持 `DEPTH`，不触发 `overflow`。
- 同步 FIFO 的 `overflow` 为单周期 pulse，条件是 `push && full && !pop`。
- 异步 FIFO 的 `overflow` 为写时钟域单周期 pulse，条件是 `push && wr_full`。
- 同步 FIFO 的 `underrun` 为单周期 pulse，条件是 `pop && empty && !(FALL_THROUGH && push)`。
- 异步 FIFO 的 `underrun` 为读时钟域单周期 pulse，条件是 `pop && rd_empty`。
- `overflow/underrun` 是 critical error，表示上游或下游违反 FIFO 可用性边界，数据流已经存在丢失或非法读取风险。
- 复位后 FIFO 为空，`level == 0`，`empty == 1`，`full == 0`。
- 复位后 `pop_data` 统一为 `0`。
- 满状态下，如果同周期有合法读取，同步 FIFO 可以允许同周期写入，避免吞吐下降。
- 空状态下，同步 FIFO 是否允许同周期写入读取由 `FALL_THROUGH` 决定；异步 FIFO 不支持该行为。
- `pop_data` 在没有合法读取时保持上一次有效输出数据，不因为 `empty` 或非法 `pop` 被覆盖。

## 水线配置

- `cfg_almost_full_level` 和 `cfg_almost_empty_level` 是端口输入，不是 parameter。
- `almost_full` 在本地域观测 `level >= cfg_almost_full_level` 时拉高。
- `almost_empty` 在本地域观测 `level <= cfg_almost_empty_level` 时拉高。
- 配置端口由调用方保证在目标时钟域内稳定；异步 FIFO 的写侧水线输入属于写时钟域，读侧水线输入属于读时钟域。
- 水线配置非法时通过 assertion 报出：
  - `cfg_almost_full_level` 合法范围为 `1..DEPTH`。
  - `cfg_almost_empty_level` 合法范围为 `0..DEPTH-1`。

## Fall-Through 语义

`fall-through` 指同步 FIFO 为空时，同周期 `push && pop` 可以形成输入到输出的直接透传。

- `FALL_THROUGH == 0`: `pop && empty` 触发 `underrun`，即使同周期 `push == 1`。
- `FALL_THROUGH == 1`: 同步 FIFO 中 `empty && push && pop` 是合法透传，不触发 `underrun`，数据不进入存储阵列，FIFO 保持 empty。
- 异步 FIFO 第一阶段不支持 `fall-through`；读域 `pop && rd_empty` 始终触发 `underrun`。

## 异步 FIFO 状态语义

异步 FIFO 不提供全局瞬时精确 `level`。它提供两个时钟域下的本地域保守状态：

- `wr_level`: 写时钟域基于本地写指针和同步后的读指针计算。它可能比真实占用偏大，适合生成 `wr_full/wr_almost_full`。
- `rd_level`: 读时钟域基于同步后的写指针和本地读指针计算。它可能比真实可读量偏小，适合生成 `rd_empty/rd_almost_empty`。

跨域指针同步使用 Gray pointer 和至少两级同步器。第一阶段要求 `DEPTH` 为 2 的幂，以保持指针环和 full/empty 判断简单可靠。

## 实现计划

1. 建立共享参数检查、指针宽度和状态计算约定。
2. 实现 `fifo_sync_reg`，作为同步 FIFO 行为参考。
3. 实现 `fifo_sync_mem`，保持与 register 版本一致的端口和错误语义。
4. 实现 `fifo_async_reg`，使用 Gray pointer 和双触发同步器。
5. 实现 `fifo_async_mem`，保持与 async register 版本一致的端口和跨域状态语义。
6. 增加可选通用 wrapper，例如 `fifo_sync_bridge` 和 `fifo_async_bridge`，只做通用接口封装，不引入协议专用信号。
7. 建立 Verilator 验证矩阵，覆盖同步/异步、reg/mem、满、空、同时 push/pop、overflow、underrun、复位、背压模型和水线配置端口。

## 模块功能点与约束

### `fifo_sync_reg`

- 功能点: 单时钟 `push/pop` FIFO；register array 存储；低有效复位；`full/empty/level`；端口配置水线；单周期 `overflow/underrun`；同步 `fall-through`；满时同周期替换；`pop_data` 复位为 `0` 并保持最近一次有效输出。
- 设计约束: `DEPTH` 必须是 2 的幂；非法参数和非法水线配置必须 assertion；合法传输保持 FIFO 顺序；错误请求不能破坏内部指针、计数和已存数据。
- 验证项: reset 空状态和 `pop_data == 0`；顺序写读；写满和读空；满时 `push && !pop` 报 `overflow`；满时 `push && pop` 不报 `overflow`；空时 `pop` 报 `underrun`；`FALL_THROUGH` 开关两种行为；水线配置边界和非法配置。

### `fifo_sync_mem`

- 功能点: 与 `fifo_sync_reg` 同端口同语义；memory array 存储；同步读写控制；端口配置水线；单周期错误输出。
- 设计约束: 外部行为必须对齐 `fifo_sync_reg`；memory 读延迟与 `fall-through` 组合必须明确，不允许产生未定义输出；错误请求不能写坏 memory 内容。
- 验证项: 复用 `fifo_sync_reg` 行为测试；增加 memory 读写同地址、满时替换、空时透传、复位输出为 `0` 和保持 `pop_data` 的定向测试。

### `fifo_async_reg`

- 功能点: 写时钟域 `push`、读时钟域 `pop`；register array 存储；独立 `wr_rst_n/rd_rst_n`；Gray pointer 跨域同步；`wr_full/wr_level/wr_almost_full`；`rd_empty/rd_level/rd_almost_empty`；写域 `overflow`；读域 `underrun`；`pop_data` 复位为 `0`。
- 设计约束: `DEPTH` 必须是 2 的幂；不支持 `fall-through`；不提供全局瞬时精确 `level`；跨域指针至少两级同步；写侧水线配置只在写域使用，读侧水线配置只在读域使用。
- 验证项: 异步不同比例时钟；独立 reset 和 `pop_data == 0`；写满和读空；跨域顺序保持；写域 `overflow` pulse；读域 `underrun` pulse；`wr_level/rd_level` 保守状态；水线配置断言。

### `fifo_async_mem`

- 功能点: 与 `fifo_async_reg` 同端口同语义；memory array 存储；异步跨域读写；Gray pointer 跨域同步；写域和读域独立状态观测；`pop_data` 复位为 `0`。
- 设计约束: 外部行为必须对齐 `fifo_async_reg`；memory 读写端口模型必须可综合并可由 Verilator 验证；不支持异步 `fall-through`；错误请求不能破坏已存数据。
- 验证项: 复用 `fifo_async_reg` 行为测试；增加 memory 后端读写冲突、跨域读延迟、reset 后 `pop_data == 0` 和输出保持行为测试。

## 待确认问题

- 当前无开放接口问题；新增影响接口、架构、状态语义、错误语义或验证准则的问题必须先与用户确认。
