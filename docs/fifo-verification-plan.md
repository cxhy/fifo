# FIFO 验证计划

**状态**: implemented
**日期**: 2026-06-02
**角色**: fifo-dv-verifier
**覆盖任务**: T002, T003, T004, T005, T008, T009(spec draft)

## 验证目标

本验证面向第一阶段 4 个通用 `push/pop` FIFO 模块：

- `fifo_sync_reg`
- `fifo_sync_mem`
- `fifo_async_reg`
- `fifo_async_mem`

验证依据为 `TASKS.json` 与 `docs/fifo-common-design.md`，不以当前 RTL 实现细节作为期望来源。目标是确认：

- reset 后 FIFO 为空，状态信号和 `pop_data` 初值符合规格。
- 合法 `push/pop` 保持 FIFO 顺序，数据不丢失、不重复、不乱序。
- `full/empty/level` 或 `wr_full/rd_empty/wr_level/rd_level` 状态符合同步和异步语义。
- `almost_full/almost_empty` 或对应异步域水线状态由运行时配置端口驱动。
- `overflow/underrun` 是单周期错误 pulse，且非法请求不破坏已存数据。
- 同步 FIFO 覆盖 `FALL_THROUGH=0/1`，包括空时同周期 `push && pop` 的差异。
- 同步 FIFO 满时 `push && pop` 合法替换，不触发 `overflow`。
- 异步 FIFO 覆盖独立 reset、跨域可见性延迟、保守 level 语义和读写域错误 pulse。
- 非法水线配置通过 assertion 暴露。

## 测试环境

当前 DV 使用 Verilator C++ testbench：

- 每个模块一个主 testbench，位于 `dv/<module>/tb_<module>.cpp`。
- 每个模块一个非法水线配置负向 testbench，位于 `dv/<module>/tb_illegal_config.cpp`。
- 主 testbench 内置 reference model 和 scoreboard，直接检查 DUT 端口输出。
- T008 后主 testbench 由脚本传入 `DATA_WIDTH_VALUE`、`DEPTH_VALUE` 和同步 FIFO 的
  `FALL_THROUGH_VALUE`，与 Verilator `-GDATA_WIDTH/-GDEPTH/-GFALL_THROUGH` 保持一致。
- 默认参数矩阵覆盖 `DATA_WIDTH=1/8/17` 和 `DEPTH=1/2/4/8`；同步 FIFO 额外分别编译
  `FALL_THROUGH=0/1`。
- 脚本使用 `verilator --cc --exe --assert -Wall -Wno-fatal --build` 构建并运行。
- 构建产物写入 `build/<module>/`。

## 脚本入口

- 全量 RTL lint: `make lint`
- 全量 Verilator DV: `make verilator`
- 单模块入口:
  - `bash scripts/run_fifo_sync_reg.sh`
  - `bash scripts/run_fifo_sync_mem.sh`
  - `bash scripts/run_fifo_async_reg.sh`
  - `bash scripts/run_fifo_async_mem.sh`

`make verilator` 会顺序调用 4 个单模块脚本。每个脚本默认运行参数矩阵和独立负向 case，并打印
`COVERAGE <module> positive_matrix=... negative_cases=...` 作为轻量覆盖摘要。

矩阵可以用环境变量临时收窄：

```text
FIFO_DATA_WIDTHS="8" FIFO_DEPTHS="1" FIFO_FALL_THROUGHS="0" bash scripts/run_fifo_sync_reg.sh
FIFO_DATA_WIDTHS="8" FIFO_DEPTHS="1" bash scripts/run_fifo_async_reg.sh
```

## Reference Model 与 Scoreboard 策略

同步 FIFO 使用 `std::deque<uint32_t>` 建模已接受数据队列：

- `push` 在未 overflow 时进入参考队列。
- `pop` 在非空时从队首取数并更新 `last_pop_data`。
- `FALL_THROUGH=1` 且空时 `push && pop` 直接更新 `last_pop_data`，不入队。
- `FALL_THROUGH=0` 且空时 `pop` 产生 `underrun`。
- `pop_data` 在无合法读取时必须保持 `last_pop_data`。
- `level/full/empty/almost_full/almost_empty/overflow/underrun` 每周期与参考结果比对。

异步 FIFO 使用独立于 RTL 的接受队列建模全局已接受数据，并按读写时钟域检查端口：

- 写域在 `push && !wr_full` 时接受数据入队；`push && wr_full` 期望 `overflow`。
- 读域在 `pop && !rd_empty` 时出队并检查 `pop_data`；`pop && rd_empty` 期望 `underrun`。
- `wr_level` 必须在 `0..DEPTH` 内，且不低估参考队列占用，用于保守写域状态检查。
- `rd_level` 必须在 `0..DEPTH` 内，且不高估参考队列占用，用于保守读域状态检查。
- `wr_almost_full` 与 `wr_level >= cfg_almost_full_level` 对齐。
- `rd_almost_empty` 与 `rd_level <= cfg_almost_empty_level` 对齐。
- `pop_data` 在读域 reset 后回到 `0`，无合法读取时保持最近有效输出。

## 每模块用例覆盖

| 模块 | 主 testbench | 已覆盖场景 |
| --- | --- | --- |
| `fifo_sync_reg` | `dv/fifo_sync_reg/tb_fifo_sync_reg.cpp` | reset 空状态和 `pop_data==0`；顺序写读；写满读空；overflow；underrun；无合法读取输出保持；满时 `push && pop` 替换；`FALL_THROUGH=0/1` 空时同周期 `push && pop`；almost 水线边界 |
| `fifo_sync_mem` | `dv/fifo_sync_mem/tb_fifo_sync_mem.cpp` | 同步 FIFO 外部语义复用；memory 同地址读写/替换压力；写满读空；overflow；underrun；fall-through；reset 输出为 0；输出保持 |
| `fifo_async_reg` | `dv/fifo_async_reg/tb_fifo_async_reg.cpp` | 独立 `wr_rst_n/rd_rst_n`；写到读跨域可见性；写满和 `overflow`；读空和 `underrun`；跨域顺序保持；wraparound/CDC 序列；保守 `wr_level/rd_level`；水线状态 |
| `fifo_async_mem` | `dv/fifo_async_mem/tb_fifo_async_mem.cpp` | 异步 FIFO 外部语义复用；独立 reset 和输出保持；读延迟；写满读空；overflow/underrun；memory 冲突和 wraparound；跨域顺序保持；保守状态和水线状态 |

## T008 参数矩阵与覆盖摘要

T008 扩展了四个模块的默认脚本矩阵：

| 模块 | DATA_WIDTH | DEPTH | FALL_THROUGH | 正向矩阵 |
| --- | --- | --- | --- | --- |
| `fifo_sync_reg` | `1, 8, 17` | `1, 2, 4, 8` | `0, 1` | 24 cases |
| `fifo_sync_mem` | `1, 8, 17` | `1, 2, 4, 8` | `0, 1` | 24 cases |
| `fifo_async_reg` | `1, 8, 17` | `1, 2, 4, 8` | 不适用 | 12 cases |
| `fifo_async_mem` | `1, 8, 17` | `1, 2, 4, 8` | 不适用 | 12 cases |

本轮不启用 Verilator coverage 数据库；选择脚本级自定义 coverage summary 量化参数矩阵和负向
case 命中。后续如需要 line/toggle/branch 级覆盖率，可另建任务引入 Verilator coverage。

## 非法配置 Assertion 测试

每个模块都有 `tb_illegal_config.cpp` 负向测试。T008 后负向测试拆成三个独立 case：

- `illegal_almost_full`: 将 `cfg_almost_full_level` 设为 `0`，期望触发 assertion。
- `illegal_almost_empty`: 将 `cfg_almost_empty_level` 设为 `DEPTH`，期望触发 assertion。
- `non_power_of_two_depth`: 使用 `DEPTH=3`，期望参数 assertion 在 elaboration 或 runtime 暴露。

脚本在观察到预期失败后将其计为 coverage 命中；如果负向 case 正常退出，则脚本失败。

## 当前运行结果

2026-06-01 第一阶段实现后运行：

```text
make lint      PASS
make verilator PASS
```

`make verilator` 子项结果：

- `fifo_sync_reg`: `FALL_THROUGH=0` PASS，`FALL_THROUGH=1` PASS，非法水线 assertion PASS。
- `fifo_sync_mem`: `FALL_THROUGH=0` PASS，`FALL_THROUGH=1` PASS，非法水线 assertion PASS。
- `fifo_async_reg`: 主测试 PASS，非法水线 assertion PASS。
- `fifo_async_mem`: 主测试 PASS，非法水线 assertion PASS。

非法配置测试中 Verilator 打印 `%Fatal` 和进程 `Aborted` 是预期行为；脚本将其解释为 assertion 成功触发。

2026-06-01 推进 T008 时运行：

```text
make lint                    PASS
bash scripts/run_fifo_sync_reg.sh   PASS, positive_matrix=24/24, negative_cases=3/3
bash scripts/run_fifo_sync_mem.sh   PASS, positive_matrix=24/24, negative_cases=3/3
bash scripts/run_fifo_async_reg.sh  PASS, positive_matrix=12/12, negative_cases=3/3
bash scripts/run_fifo_async_mem.sh  PASS, positive_matrix=12/12, negative_cases=3/3
```

T008 初次运行发现 `DEPTH=1` 同步 FIFO 满时 `push && pop` 替换路径的 RTL bug；architect
triage 分类为 RTL bug，已由 RTL agent 修复 `fifo_sync_reg` 和 `fifo_sync_mem` 的
`DEPTH=1` 指针回绕行为，并通过上述矩阵回归。

## 当前覆盖缺口与后续建议

- T009 已进入 spec 草案阶段，新增 memory wrapper 和 CDC sync module 的验证计划尚未实现；
  需等待 `Q002/Q003` 确认后再修改 DV。
- 参数矩阵已扩展到 `DATA_WIDTH=1/8/17`、`DEPTH=1/2/4/8`。后续可继续增加更大深度、
  更宽数据宽度和更多 level 编码组合。
- 非 2 次幂深度已有 `DEPTH=3` 负向路径覆盖。后续可扩展更多非法参数组合，例如
  `DATA_WIDTH=0` 或 `DEPTH=0` 的工具兼容性检查。
- 异步时钟比例仍是手写 tick 交错序列，不是系统化 sweep。建议增加多组写快读慢、读快写慢、相近频率和相位漂移场景。
- 当前已有脚本级 coverage summary，但尚无 Verilator line/toggle/branch 覆盖率收集。建议后续打开 Verilator coverage 或补充更细粒度自定义 coverage counter，量化 full/empty/wrap/error/reset/waterline 命中。
- 当前随机压力较少。建议在现有定向测试通过后加入 seed 可复现随机序列，并保留 scoreboard 独立期望。
- CDC 结构本身未做静态 CDC 检查；当前只从端口行为和跨域保守状态验证，建议后续配合 lint/CDC 工具或结构性检查。
- 尚未验证 reset 与有效交易同周期释放/拉低的更多边界组合。建议补充 reset 交错、局部 reset 后残留数据处理和 reset 后重新填充的定向用例。

## T009 计划验证项

T009 目标是在不改变 FIFO 顶层端口和外部行为的前提下，抽取 ASIC 可替换边界。确认前
DV 不修改 scoreboard 或测试期望。

计划覆盖：

- `V_MEM_IF_001`: `fifo_sync_mem` 使用 `fifo_sync_1r1w_mem` 后，复用现有参数矩阵，
  覆盖 fall-through、满时替换、同地址读写、reset 输出为 `0` 和输出保持。
- `V_MEM_IF_002`: `fifo_async_mem` 使用 `fifo_async_1r1w_mem` 后，复用现有参数矩阵，
  覆盖跨域顺序、独立 reset、读写冲突、overflow/underrun 和输出保持。
- `V_CDC_SYNC_001`: `fifo_async_reg` 和 `fifo_async_mem` 使用 `fifo_cdc_sync` 后，
  复用异步参数矩阵，覆盖 reset 后 alignment、wraparound CDC、保守 `wr_level/rd_level`
  和水线状态。
- `V_ASIC_BOUNDARY_001`: `make lint` 和相关 `scripts/run_fifo_*.sh` 必须包含新增 RTL
  文件，避免 Verilator 只编译顶层单文件导致实例缺失。

确认后建议最窄验证顺序：

```text
jq empty TASKS.json
make lint
bash scripts/run_fifo_sync_mem.sh
bash scripts/run_fifo_async_reg.sh
bash scripts/run_fifo_async_mem.sh
make verilator
```
