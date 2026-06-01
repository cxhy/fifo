# FIFO 文档补充计划

**状态**: completed
**日期**: 2026-06-01
**负责人**: fifo-architect

## 目标

补齐第一阶段 FIFO 公共组件的设计文档和验证文档入口，使设计约束、接口语义、
验证矩阵和运行入口都能从文档中追溯到同一事实源。

本记录覆盖文档组织和事实源一致性，不改变已确认接口、错误语义、状态语义、
RTL 实现或 DV 期望。

## 事实源和引用顺序

文档编写和审阅时应按以下顺序对齐：

1. `TASKS.json`: 任务、模块功能点、设计约束、验证项、agent ownership 的事实源。
2. `docs/fifo-common-design.md`: 第一阶段公共设计规格和已确认接口语义。
3. `memory/project-status.md`: 当前阶段状态、验证结果和关键入口。
4. `memory/decisions.md`: 长期设计决策和被拒绝方案。
5. RTL/DV 文件只作为实现现状引用，不作为接口或验证准则的事实源。

## 已新增文档

### `docs/fifo-design-guide.md`

用途: 面向 RTL 使用者和后续维护者，整理第一阶段四个 FIFO 的设计说明。

覆盖章节：

- 范围和非目标: 说明第一阶段只覆盖通用 `push/pop` FIFO、2 次幂深度、同步/异步和 register/memory 后端。
- 模块矩阵: 列出 `fifo_sync_reg`、`fifo_sync_mem`、`fifo_async_reg`、`fifo_async_mem` 的适用场景和后端差异。
- 公共参数和端口: 引用 `docs/fifo-common-design.md` 的接口定义，不复制为新的事实源。
- 同步 FIFO 语义: 覆盖 `push/pop`、满时替换、`fall-through`、`overflow/underrun`、`pop_data` 复位和保持。
- 异步 FIFO 语义: 覆盖独立 reset、Gray pointer CDC、`wr_level/rd_level` 保守观测、不支持异步 `fall-through`。
- 水线配置: 说明 `cfg_almost_full_level`、`cfg_almost_empty_level` 的端口属性、合法范围和 assertion 行为。
- 错误语义: 明确 `overflow/underrun` 是单周期 critical error pulse。
- 模块级约束追踪: 对每个模块引用 `TASKS.json.modules[*].constraints`，避免新增未确认约束。
- 已确认决策索引: 链接 `memory/decisions.md` 中 D001-D008 对应决策。

### `docs/fifo-verification-plan.md`

用途: 面向 DV 维护者和集成检查，整理验证目标、测试矩阵、运行入口和覆盖缺口。

覆盖章节：

- 验证目标: 说明验证必须覆盖满、空、同时 `push/pop`、overflow、underrun、复位、水线配置和异步跨域状态。
- 验证范围: 列出四个模块和对应 DV 目录、运行脚本。
- 运行入口: 记录 `make lint`、`make verilator` 和四个 `scripts/run_fifo_*.sh`。
- 模块验证矩阵: 按模块映射 `TASKS.json.modules[*].verification` 到具体 testbench 文件。
- 公共检查项: 顺序保持、错误 pulse 单周期、错误请求不破坏状态、`pop_data` 复位为 0 和无合法读取保持。
- 同步特有检查: 满时 `push && pop` 替换、`FALL_THROUGH` 开关行为、同步水线边界。
- 异步特有检查: 不同比例时钟、独立 reset、写/读域错误 pulse、`wr_level/rd_level` 保守状态、跨域顺序保持。
- Assertion 检查: 非法参数和非法水线配置的预期失败入口。
- 当前验证结果: 引用 `memory/project-status.md`，不把结果复制成新的状态事实源。
- 已知缺口和后续扩展: 随机压力测试、wrapper、参数边界扩展、非 2 次幂 FIFO 单独设计。

## 已更新文档

### `docs/fifo-common-design.md`

保留为第一阶段公共设计规格入口，并补充 RTL 实现复核说明。更新只记录事实源引用和
实现对齐说明，不改变接口或错误语义。

已补充：

- “事实源关系”小节，说明模块功能点、约束和验证项以 `TASKS.json` 为准。
- “实现与验证入口”小节，链接 RTL/DV 目录、Makefile 目标和脚本。
- “文档索引”小节，链接 `fifo-design-guide.md` 和 `fifo-verification-plan.md`。

### `README.md`

已增加文档入口：

- 设计指南: `docs/fifo-design-guide.md`
- 验证计划: `docs/fifo-verification-plan.md`
- 文档补充计划: `docs/documentation-plan.md`

### `memory/project-status.md`

已记录当前文档化任务和入口，保持项目恢复时能看到文档状态。

## TASKS.json 记录

已新增并完成文档任务：

- `T006`: 补充设计文档和验证文档。
- owner: `fifo-architect`
- status: `done`
- scope: `docs/fifo-design-guide.md`、`docs/fifo-verification-plan.md`、`README.md`、`memory/project-status.md`
- acceptance:
  - 设计文档覆盖四个 FIFO 的模块矩阵、接口语义、参数约束、水线配置、错误语义和 CDC 状态语义。
  - 验证文档覆盖模块验证矩阵、运行入口、公共/同步/异步检查项、assertion 检查和当前验证结果引用。
  - 文档引用 `TASKS.json`、`docs/fifo-common-design.md`、`memory/project-status.md`、`memory/decisions.md`，不创建新的接口事实源。
  - 不修改 RTL、DV、scripts，也不改变已确认接口、状态语义或错误语义。

## 当前无需用户确认的问题

本计划未提出新的接口、架构、状态语义、错误语义或验证准则变更。
如果后续文档编写发现现有 RTL/DV 与 `TASKS.json` 或 `docs/fifo-common-design.md`
不一致，应先记录为架构问题并请求用户确认，不应在文档中自行改写语义。
