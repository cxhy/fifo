# FIFO 公共组件设计规格

**状态**: implemented
**日期**: 2026-06-02

## 文档索引

- `docs/fifo-design-guide.md`: 已实现 RTL 的设计说明。
- `docs/fifo-verification-plan.md`: Verilator 验证计划、覆盖矩阵和当前结果。
- `TASKS.json`: 模块功能点、设计约束、验证项和任务状态事实源。
- `memory/decisions.md`: 长期设计决策记录。

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
- `CDC_SYNC_STAGES`: 仅异步 FIFO 支持，默认 2，必须大于等于 2，用于配置内部
  `fifo_cdc_sync` 同步级数。

参数非法时，RTL 或仿真阶段应通过 elaboration-time assertion 暴露错误。

## 同步 FIFO 接口

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

## 异步 FIFO 接口

```systemverilog
module fifo_async_reg #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int CDC_SYNC_STAGES = 2
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

## T009 ASIC 替换边界

**状态**: implemented

本节是 T009 已实现规格，目标是在不改变现有 FIFO 顶层 `push/pop` 端口和外部行为的前提下，
抽取 ASIC 阶段可替换边界。当前 RTL 已提供行为级 wrapper，后续 ASIC 流程可用 vendor
macro adapter 或 synchronizer cell wrapper 替换对应内部模块。

### Memory Wrapper 边界

`fifo_sync_mem` 和 `fifo_async_mem` 已改为内部实例化可替换 memory wrapper。FIFO
顶层端口保持不变，memory wrapper 作为 RTL 内部后端边界，用于后续 vendor memory macro
adapter 替换。

同步 memory wrapper：

```systemverilog
module fifo_sync_1r1w_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         wr_en,
    input  logic [ADDR_WIDTH-1:0]        wr_addr,
    input  logic [DATA_WIDTH-1:0]        wr_data,
    input  logic                         rd_en,
    input  logic [ADDR_WIDTH-1:0]        rd_addr,
    output logic [DATA_WIDTH-1:0]        rd_data
);
```

异步 memory wrapper：

```systemverilog
module fifo_async_1r1w_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                         wr_clk,
    input  logic                         wr_rst_n,
    input  logic                         wr_en,
    input  logic [ADDR_WIDTH-1:0]        wr_addr,
    input  logic [DATA_WIDTH-1:0]        wr_data,
    input  logic                         rd_clk,
    input  logic                         rd_rst_n,
    input  logic                         rd_en,
    input  logic [ADDR_WIDTH-1:0]        rd_addr,
    output logic [DATA_WIDTH-1:0]        rd_data
);
```

contract：

- wrapper 对 FIFO 侧暴露 1R1W 行为；同步版本为单时钟，异步版本为写读双时钟。
- `rd_data` 在 reset 后为 `0`，合法 `rd_en` 后更新为读取数据，无合法 `rd_en` 时保持最近有效输出。
- 同步 FIFO 的 `fall-through` 仍由 FIFO 控制逻辑处理，不通过 memory wrapper 读出空队列数据。
- 同步满状态 `push && pop` 仍读出旧队首并写入新队尾，不触发 `overflow`。
- vendor memory macro 如果读延迟、reset 能力或同地址读写模式不同，必须通过 wrapper adapter
  满足上述 FIFO 侧 contract；本仓库第一版不实例化具体 vendor macro。
- vendor memory macro 如果无法通过 adapter 维持当前 `pop_data` 时序，必须另走
  change-control；T009 不允许静默改变 FIFO 外部语义。

确认记录见 `TASKS.json.open_questions.Q002`。

### CDC Sync Module 边界

`fifo_async_reg` 和 `fifo_async_mem` 已将 Gray pointer 同步链抽取为独立
sync module，便于 ASIC 阶段替换为专用 synchronizer cell wrapper。

sync module：

```systemverilog
module fifo_cdc_sync #(
    parameter int WIDTH = 1,
    parameter int STAGES = 2
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] async_i,
    output logic [WIDTH-1:0] sync_o
);
```

contract：

- `STAGES` 必须大于等于 2，默认 2；`fifo_async_reg/fifo_async_mem` 通过
  `CDC_SYNC_STAGES` parameter 配置内部 `fifo_cdc_sync` 实例。
- `clk/rst_n` 属于目标时钟域；reset 后同步链各级和 `sync_o` 均为 0。
- sync module 只同步 Gray pointer 向量，不承担 Gray/binary 转换、full/empty 判定或 level 计算。
- 抽取后必须保持现有 alignment 行为：reset 释放后本地域指针对齐到同步后的远端 Gray pointer，
  alignment 期间 suppress 对应 `overflow/underrun`，并保持保守状态输出。
- `wr_level/rd_level` 继续是各自时钟域保守观测值，不提供全局瞬时精确占用。

确认记录见 `TASKS.json.open_questions.Q003`。

## RTL 实现复核说明

本节记录当前 `rtl/` 中 4 个核心模块的实现侧结构和边界行为，作为设计文档与 RTL 对齐依据。

### 模块接口概览

- `fifo_sync_reg` 和 `fifo_sync_mem` 共享同步 FIFO 接口：单一 `clk/rst_n`；`push/push_data` 写入；`pop/pop_data` 读取；`cfg_almost_full_level/cfg_almost_empty_level` 运行时水线配置；输出 `full/empty/almost_full/almost_empty/level/overflow/underrun`。
- `fifo_async_reg` 和 `fifo_async_mem` 共享异步 FIFO 接口：写域使用 `wr_clk/wr_rst_n`、`push/push_data`、`cfg_almost_full_level`、`wr_full/wr_almost_full/wr_level/overflow`；读域使用 `rd_clk/rd_rst_n`、`pop/pop_data`、`cfg_almost_empty_level`、`rd_empty/rd_almost_empty/rd_level/underrun`。
- 同步 FIFO 有 `FALL_THROUGH` parameter；异步 FIFO 没有 `FALL_THROUGH` parameter，第一阶段固定不支持跨域透传。
- `reg` 与 `mem` 后端在当前 RTL 中都使用可综合 SystemVerilog array 保存数据。`mem` 版本对外端口和状态语义必须与同类 `reg` 版本一致，不绑定具体 SRAM macro。

### 同步实现结构

- 同步 FIFO 使用 `wr_ptr`、`rd_ptr` 和 `level` 作为核心状态；`wr_ptr/rd_ptr` 地址宽度为 `max(1, clog2(DEPTH))`，`level` 宽度为 `clog2(DEPTH+1)`。
- `full` 由 `level == DEPTH` 得到，`empty` 由 `level == 0` 得到；`almost_full/almost_empty` 直接基于当前 `level` 和水线输入组合生成。
- 合法存储读取条件为 `pop && !empty`。没有合法读取时，`pop_data` 不被覆盖，保持最近一次有效输出。
- 合法存储写入条件为 `push && (!full || storage_pop) && !fall_through_read`。因此满状态下同周期 `push && pop` 可以读出旧队首并写入新队尾，`level` 保持不变，不触发 `overflow`。
- `fall_through_read` 仅在 `FALL_THROUGH && empty && push && pop` 时成立。该场景下 `pop_data` 在时钟沿更新为 `push_data`，数据不写入 array，`level` 保持 `0`。
- `fifo_sync_reg` 与 `fifo_sync_mem` 的同步读写控制相同：读取输出在合法 `pop` 的时钟沿更新，写入在合法 `push` 的时钟沿更新。当前规格不承诺组合读或零周期 SRAM macro 行为。

### 异步 Gray Pointer/CDC/Level 语义

- 异步 FIFO 使用扩展二进制指针 `wr_bin/rd_bin` 和对应 Gray 指针 `wr_gray/rd_gray`。`DEPTH > 1` 时指针宽度为 `clog2(DEPTH)+1`，额外一位用于区分环绕；`DEPTH == 1` 时地址固定为 `0`。
- 写指针 Gray 值通过 `wr_gray_rd_sync1/wr_gray_rd_sync2` 两级同步进入读域；读指针 Gray 值通过 `rd_gray_wr_sync1/rd_gray_wr_sync2` 两级同步进入写域。各域将同步后的 Gray pointer 转回 binary 后计算本地域 level。
- 写域 `wr_level = wr_bin - rd_bin_wr_sync`，读域 `rd_level = wr_bin_rd_sync - rd_bin`。两个 level 都只表示本地域根据同步后远端指针得到的观测值，不代表跨域瞬时精确占用。
- 写域 `wr_full` 由 `wr_level == DEPTH` 生成；读域 `rd_empty` 由 `rd_level == 0` 生成。由于远端指针经过同步链，`wr_full` 可能保守保持一段时间，`rd_empty` 也可能保守保持一段时间。
- 每个时钟域复位释放后先进入一次 alignment 状态：本地域指针对齐到已采样的远端 Gray pointer，期间写域 suppress `overflow`，读域 suppress `underrun`，`wr_level/rd_level` 输出为 `0`，读域 `rd_empty` 保持为 `1`。
- 异步 `push` 仅在写域 `!wr_full` 且不处于 alignment 时写 array 并推进写指针；异步 `pop` 仅在读域 `!rd_empty` 且不处于 alignment 时读取 array、更新 `pop_data` 并推进读指针。

### Reset/错误/水线/Fall-Through 行为

- 同步 FIFO 使用低有效 `rst_n`；异步 FIFO 使用低有效且互相独立的 `wr_rst_n` 和 `rd_rst_n`。
- 复位后本地域指针和 level 归零；`pop_data` 在同步 FIFO 和异步读域复位后均为 `0`；`overflow/underrun` 复位为 `0`。
- `overflow` 和 `underrun` 是寄存的单周期 pulse。同步 FIFO 中 `overflow = push && full && !pop`，`underrun = pop && empty && !(FALL_THROUGH && push)`；异步 FIFO 中 `overflow = push && wr_full`，`underrun = pop && rd_empty`。
- 错误请求不会推进对应指针，也不会写坏已存数据。满时同步 `push && !pop` 不写 array；空时非法 `pop` 不更新 `pop_data`。
- 水线输入是端口级配置，RTL 在对应时钟沿检查合法范围。`cfg_almost_full_level` 合法范围为 `1..DEPTH`，`cfg_almost_empty_level` 合法范围为 `0..DEPTH-1`；非法配置通过 assertion/fatal 暴露。
- `almost_full` 和 `almost_empty` 是基于本地域当前观测 level 的组合输出，不额外寄存。异步版本中它们继承 `wr_level/rd_level` 的保守观测属性。
- `fall-through` 仅适用于同步 FIFO。异步 FIFO 中读域只根据 `rd_empty` 判断读取合法性，`pop && rd_empty` 始终是 `underrun`，即使写域同一真实时间发生 `push`。

### 已知限制

- 第一阶段只支持 `DEPTH > 0` 且为 2 的幂；非 2 次幂深度需要单独设计指针和 full/empty 判定。
- 当前模块不提供 ready/valid 协议封装，不提供 AXI/AXI-Stream/NoC 等上层协议转换。
- 异步 FIFO 不提供全局精确占用计数，也不承诺跨域同一时刻的 `wr_level` 与 `rd_level` 一致。
- 异步 array 存储未抽象为特定双口 SRAM macro 接口；后续若绑定 macro，需要重新审查读写冲突、读延迟和 CDC 约束。
- 当前错误输出为 pulse，不提供 sticky error latch、错误计数或清除寄存器。
- 当前水线配置由调用方保证在目标时钟域稳定；RTL 不对配置端口做跨域同步或去抖。

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
