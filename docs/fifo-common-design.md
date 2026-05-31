# FIFO 公共组件设计规格

**状态**: draft
**日期**: 2026-05-31

## 目标

第一阶段交付一个同步单时钟、可复用、可综合的 FIFO 核心组件，作为后续协议转换、缓冲和跨模块解耦的基础模块。

该组件优先解决通用 `ready/valid` 数据流缓冲问题。AXI、交换机接口或其他协议的包装层不进入第一阶段核心 RTL，但可以在后续基于同一握手语义扩展。

## 非目标

- 异步跨时钟 FIFO。
- AXI、AXI-Stream 或 NoC 专用封装。
- 多读写端口 FIFO。
- ECC、奇偶校验、QoS 或优先级调度。
- 依赖具体 SRAM macro 的实现。

## 初始模块

第一阶段模块名暂定为 `sync_fifo`。

```systemverilog
module sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter bit FALL_THROUGH = 1'b0,
    parameter int ALMOST_FULL_LEVEL = DEPTH - 1,
    parameter int ALMOST_EMPTY_LEVEL = 1
) (
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  in_valid,
    output logic                  in_ready,
    input  logic [DATA_WIDTH-1:0] in_data,

    output logic                  out_valid,
    input  logic                  out_ready,
    output logic [DATA_WIDTH-1:0] out_data,

    output logic                  full,
    output logic                  empty,
    output logic                  almost_full,
    output logic                  almost_empty,
    output logic [$clog2(DEPTH+1)-1:0] level
);
```

## 参数语义

- `DATA_WIDTH`: 数据位宽，必须大于 0。
- `DEPTH`: FIFO 可存储元素数，必须大于 0；需要支持非 2 次幂深度。
- `FALL_THROUGH`: 当 FIFO 为空且同周期有新输入时，是否允许输出侧同周期看到该输入。
- `ALMOST_FULL_LEVEL`: `level >= ALMOST_FULL_LEVEL` 时拉高 `almost_full`。
- `ALMOST_EMPTY_LEVEL`: `level <= ALMOST_EMPTY_LEVEL` 时拉高 `almost_empty`。

参数非法时，RTL 或仿真阶段应通过 elaboration-time assertion 暴露错误。

## 握手语义

- 入队成功条件为 `in_valid && in_ready`。
- 出队成功条件为 `out_valid && out_ready`。
- 复位后 FIFO 为空，`level == 0`，`empty == 1`，`full == 0`。
- FIFO 满时，如果同周期发生出队，允许同周期入队，避免吞吐下降。
- FIFO 空时，默认不允许出队；当 `FALL_THROUGH == 1` 且同周期入队时，可以形成直接旁路。
- 任意合法握手序列下不能丢数、重数或改变数据顺序。

## 状态信号

- `level` 表示当前已存储元素数，范围为 `0..DEPTH`。
- `full` 等价于 `level == DEPTH`。
- `empty` 等价于 `level == 0`。
- `almost_full` 和 `almost_empty` 只用于状态观测和上层背压策略，不改变核心入队/出队语义。

## 实现策略

- 使用读指针、写指针和计数器维护状态。
- 存储阵列优先用普通寄存器数组，确保第一版可在 Verilator 中直接仿真。
- 指针回绕必须支持非 2 次幂 `DEPTH`。
- `DEPTH == 1` 作为一等场景验证，不通过特殊禁用规避。
- 第一版保持单时钟同步复位；如需要异步复位或低有效复位，后续用 wrapper 或参数扩展。

## Verilator 验证计划

第一阶段测试应至少覆盖：

- 基础入队后出队，检查顺序保持。
- 连续写满后检查 `full`、`in_ready` 和 `level`。
- 连续读空后检查 `empty`、`out_valid` 和 `level`。
- 满状态下同周期出队加入队。
- 空状态下 fall-through 开启和关闭两种行为。
- 随机 `in_valid`、`out_ready` 背压，使用 scoreboard 校验数据序列。
- 复位后状态清空，且复位后可重新正常传输。
- `DEPTH` 为 `1`、`2`、`3`、`16` 的参数组合。

## 下一步

1. 创建 `rtl/sync_fifo.sv`。
2. 创建最小 Verilator smoke test。
3. 建立 `uv` 管理的测试入口，固定常用验证命令。
4. 根据首轮实现结果决定是否需要拆分 fall-through 旁路逻辑。
