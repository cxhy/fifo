# FIFO 设计决策

## 2026-05-31: FIFO 组件族与接口语义

- 状态: accepted
- 决策: FIFO 子项目面向通用 FIFO/bridge 公共组件，不绑定 AXI；核心接口采用 `push/pop`，第一阶段覆盖同步/异步 FIFO 以及 register/memory 两种后端。
- 背景和约束: 组件需要可复用，既能服务协议桥，也能服务普通数据流缓冲和跨时钟域桥接。
- 被拒绝的替代方案: 仅实现同步 ready/valid FIFO；仅面向 AXI 桥封装。
- 影响: `docs/fifo-common-design.md` 已改为 4 类核心 FIFO 的规划，后续 RTL 和验证应围绕 `push/pop` critical error 语义展开。

## 2026-05-31: Overflow/Underrun 错误语义

- 状态: accepted
- 决策: 同步 FIFO 中 `overflow` 为 `push && full && !pop` 的单周期 pulse，异步 FIFO 写域中 `overflow` 为 `push && wr_full` 的单周期 pulse。同步 FIFO 中 `underrun` 为 `pop && empty && !(FALL_THROUGH && push)` 的单周期 pulse，异步 FIFO 读域中 `underrun` 为 `pop && rd_empty` 的单周期 pulse。两者均为 critical error。
- 背景和约束: `push/pop` 接口表达强制读写请求，调用方必须根据 `full/empty` 或水线信号管理流控。
- 被拒绝的替代方案: 将 `valid && !ready` 或 `ready && !valid` 这类 ready/valid 背压状态直接视为错误。
- 影响: 验证必须覆盖满后强写和空后强读，检查错误 pulse 且不破坏 FIFO 内部状态。

## 2026-05-31: 异步 FIFO 状态与 Fall-Through 范围

- 状态: accepted
- 决策: 异步 FIFO 的 `wr_level/rd_level` 是各自时钟域的保守观测值，不承诺全局瞬时精确。`fall-through` 只在同步 FIFO 中支持，异步 FIFO 第一阶段不支持。
- 背景和约束: 异步 FIFO 指针跨域需要同步延迟，全局瞬时精确 level 不符合 CDC 实际；异步透传会扩大跨域语义复杂度。
- 被拒绝的替代方案: 提供单一精确 `level`；在异步 FIFO 中支持 empty 时 push/pop 直通。
- 影响: 异步 RTL 使用 Gray pointer 和双触发同步器；写域水线基于 `wr_level`，读域水线基于 `rd_level`。

## 2026-05-31: 任务事实源与逐功能点设计流程

- 状态: accepted
- 决策: FIFO 子项目使用 `TASKS.json` 管控任务、模块功能点、设计约束和验证项；进入每个模块 RTL 前必须先列完整功能点和约束。影响接口、架构、状态语义、错误语义或验证准则的不确定点必须先与用户讨论确认。
- 背景和约束: 架构、设计和验证需要使用同一套任务与约束描述，避免实现阶段隐式补决策。
- 被拒绝的替代方案: 使用 Markdown 任务文件作为事实源；在实现中自行补齐未确认接口细节。
- 影响: 后续实现前读取并同步 `TASKS.json`；当前 RTL 实现等待 `pop_data` reset 初始值确认。

## 2026-05-31: 输出保持、水线断言与满时替换

- 状态: accepted
- 决策: 复位后 `pop_data` 统一为 `0`；`pop_data` 在无合法读取时保持上一次有效输出；非法水线配置通过 assertion 报出；同步 FIFO 满状态下 `push && pop && full` 是合法同周期替换，不触发 `overflow`。
- 背景和约束: 输出保持减少下游对空状态输出的无谓翻转依赖；水线端口是运行时配置，需要显式约束；满时替换可保持同步 FIFO 吞吐。
- 被拒绝的替代方案: `pop_data` 在空时为 don't-care；非法水线配置自然生效；满时任何 `push` 都报 `overflow`。
- 影响: 同步 FIFO `overflow` 条件为 `push && full && !pop`；异步 FIFO 写域仍使用 `push && wr_full`，不定义跨域同周期替换。

## 2026-06-01: 三 Agent 协作分工

- 状态: accepted
- 决策: 创建 `fifo-architect`、`fifo-rtl-designer`、`fifo-dv-verifier` 三个 agent，分别负责架构规划与任务分发、RTL 设计实现、DV 验证环境与测试。
- 背景和约束: 避免自己设计自己验证；RTL 与 DV 的写入范围和职责必须分离，架构师负责进度和接口一致性。
- 被拒绝的替代方案: 单一 agent 同时设计 RTL 并编写验证期望。
- 影响: 三个 agent prompt 保存在 `agents/`；`TASKS.json` 增加 agent ownership 和写入范围。

## 2026-06-01: 推进即提交

- 状态: accepted
- 决策: 每推进一个有意义的设计、RTL、DV 或流程节点后，立即在 FIFO 子项目仓库中创建一个聚焦 commit。
- 背景和约束: FIFO 子项目会由多个 agent 协作推进，需要可回退、可追溯的细粒度进度记录。
- 被拒绝的替代方案: 多个设计/实现/验证节点堆积到一次大提交。
- 影响: 后续每个阶段完成后先验证并提交，再继续推进下一阶段。

## 2026-06-01: Spec Freeze、Traceability 与完成门禁

- 状态: accepted
- 决策: `TASKS.json` schema v2 必须显式记录 spec items、稳定 feature IDs、verification point IDs、traceability matrix、iteration 记录和 validation 结果。spec 一经确认即视为 freeze；后续接口或语义变更必须进入 change-control。case 失败先由 `fifo-architect` triage，再分派给 RTL 或 DV agent。done 标准必须包含仿真或适用验证、覆盖确认、任务状态更新、必要文档/记忆更新和聚焦 commit。
- 背景和约束: 仅靠 case pass 容易遗漏功能点覆盖；调试阶段也可能隐式改变接口或语义。流程需要把 spec -> feature -> design item -> verification item -> test/case -> result 串起来。
- 被拒绝的替代方案: 只保留自然语言 feature/verification 列表；失败后直接让某个 agent 盲改；用仿真通过作为唯一完成标准。
- 影响: `AGENTS.md`、`agents/fifo-architect.md` 和 `TASKS.json` 均需遵守新流程；后续任务必须记录 feature scope、verification scope、owner、写入范围、状态、验收标准、验证命令、结果和提交。

## 2026-06-02: ASIC 替换边界

- 状态: accepted
- 决策: T009 在不改变现有 FIFO 顶层 `push/pop` 接口和外部行为的前提下，抽取
  `fifo_sync_mem/fifo_async_mem` 的可替换 memory wrapper，以及 `fifo_async_reg/fifo_async_mem`
  的 Gray pointer CDC sync module。
- 背景和约束: 后续 ASIC 流程需要能将通用 RTL wrapper 替换为 vendor-provided memory macro
  adapter 和专用 synchronizer cell wrapper；当前不能引入 vendor-specific 实例或改变已冻结行为。
- 已确认: `TASKS.json.open_questions.Q002` 确认 memory wrapper contract；`Q003` 确认 sync module
  reset、级数和 alignment 语义。
- 实现结果: `fifo_sync_mem` 内部例化 `fifo_sync_1r1w_mem`，`fifo_async_mem` 内部例化
  `fifo_async_1r1w_mem`；`fifo_async_reg/fifo_async_mem` 内部例化 `fifo_cdc_sync`。
  异步 FIFO 通过 `CDC_SYNC_STAGES` parameter 配置内部同步级数，默认 2。
- 影响: 后续 vendor macro 若无法满足当前 FIFO 外部语义，必须另走 change-control。
  后续 ASIC/CDC signoff 仍需结合工艺约束处理 Gray bus skew、false path 和 synchronizer
  placement，本仓库当前只提供 RTL 结构边界和 Verilator 行为验证。
