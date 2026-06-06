# FIFO 迭代复盘

本文件记录 FIFO 子项目本地迭代复盘。跨项目可复用的经验先在这里保留证据，
再按需提升到父 workspace 的 `memory/project-knowledge.md`。

## 2026-06-01: T008 参数矩阵和覆盖量化

**Trigger**: completed_task
**Scope**: `T008`, `I004`, `TASKS.json`, `memory/project-status.md`, commits `7de73ac`, `819604d`, `af719c5`
**Outcome**: FIFO 四个核心模块的扩展参数矩阵和负向 case 均通过，且矩阵暴露并修复了一个同步 FIFO 边界 RTL bug 和一个异步 testbench 参数化假设。

### What Worked

- 参数矩阵覆盖 `DATA_WIDTH=1/8/17` 和 `DEPTH=1/2/4/8`，比默认参数更早触达退化合法边界。
- 失败先由 `fifo-architect` triage，再分派给 `fifo-rtl-designer` 或 `fifo-dv-verifier`，避免 RTL 和 DV 互相迁就。
- `TASKS.json` 中的 feature、verification point、traceability、validation 和 triage 字段让完成状态可以回溯到具体 case 和结果。

### Friction

- 迭代复盘文件此前没有落地，导致跨项目经验只能从 `TASKS.json` 和 `memory/project-status.md` 反推。
- 异步 testbench 中存在隐含 `DEPTH=4` 的默认参数假设，直到扩展到 `DEPTH=8` 才暴露。
- 当前 coverage 仍是脚本级 summary，尚未接入 Verilator line/toggle/branch coverage 或 seed 可复现随机压力。

### Lessons

- **Lesson**: 参数化组件应早期覆盖最小合法值、非典型宽度、边界深度和非法参数负向 case。
  - Evidence: `T008` 矩阵暴露 `DEPTH=1` 满时 `push && pop` 替换路径 RTL bug，并由 commit `7de73ac` 修复。
  - Action: knowledge
  - Follow-up: 提升到父级 `memory/project-knowledge.md`。
- **Lesson**: 失败 case 先分类再分派 owner，可以保护 RTL/DV 职责边界。
  - Evidence: `T008` 同时记录 `rtl_bug` 和 `dv_testbench_bug`，分别交给 `fifo-rtl-designer` 和 `fifo-dv-verifier` 处理。
  - Action: knowledge
  - Follow-up: 提升到父级 `memory/project-knowledge.md`。
- **Lesson**: 完成门禁不能只有仿真通过，还需要 traceability、覆盖结论、任务状态、记忆更新和聚焦 commit。
  - Evidence: `T007` 固化 traceability 和 completion gate；`T008` 记录 positive matrix、negative cases、known coverage gaps 和 completion commit。
  - Action: knowledge
  - Follow-up: 提升到父级 `memory/project-knowledge.md`。

### Next Check

- 下一次进入 wrapper、随机压力、异步时钟比例 sweep 或非 2 次幂 FIFO 设计前，检查是否需要把 coverage gaps 转成新的 `TASKS.json` 任务。

## 2026-06-04: Git 身份历史清理

**Trigger**: user_request
**Scope**: `T010`, Git commit metadata, annotated tag `0.1`, `TASKS.json`, `memory/`
**Outcome**: FIFO 子项目删除 local author 覆盖配置，重写 `main` 可达提交 Author/Committer
和 annotated tag tagger 为全局 Git 配置，并准备强推子项目远端和更新父 workspace gitlink。

### What Worked

- 先用 `git config --show-origin` 区分全局配置和子模块 local 覆盖，避免误判提交身份来源。
- 重写 branch 后单独检查 annotated tag，发现 tagger 不会随 commit env-filter 自动修正。
- 强推前保留本地 `origin/main` 旧值，用于 `--force-with-lease` 防止覆盖远端新提交。

### Lesson

- **Lesson**: 隐私类 Git 历史清理不能只看 branch commit；annotated tag、`refs/original`、
  reflog、本地不可达对象和父 workspace submodule gitlink 都需要纳入检查。
  - Evidence: `0.1` tag 在 branch rewrite 后仍保留旧 tagger，必须重建 tag。
  - Action: local_process
  - Follow-up: 后续子项目执行相同清理时，把 tag 审计列入 preflight。

## 2026-06-06: T011 异步 reset flush 计划确认

**Trigger**: review_followup
**Scope**: `docs/fifo-design-review-2026-06-06.md`, `docs/fifo-reset-rework-architect-plan.md`,
`TASKS.json`, `memory/decisions.md`, `memory/project-status.md`
**Outcome**: 用户确认 T011 采用 flush-on-any-side-reset 语义，并确认本轮只处理 reset/flush
语义和最小 DV 证明；CDC/RDC signoff、coverage DB、vendor macro adapter 留作后续任务。

### What Worked

- 先打 `pre-reset-rework-20260606` tag 固定重构前基线，再记录架构计划，避免后续 RTL/DV 修改与 review 证据混在一起。
- 将用户确认写入 `Q004`、`CCR_T011_001`、`S_ASYNC_RESET_001`、`F_ASYNC_RESET_*`
  和 `V_ASYNC_RESET_*`，使后续三角色实现不依赖聊天上下文。

### Lesson

- **Lesson**: reset 语义修复前必须先冻结 user-visible reset contract，尤其是是否保留 in-flight/stored data。
  - Evidence: 本轮明确拒绝“单侧 reset 后保留未读数据”，确认任一侧 reset 都 flush FIFO。
  - Action: local_process
  - Follow-up: 已在下一节 T011 RTL/DV 重构复盘中关闭。

## 2026-06-06: T011 异步 reset flush RTL/DV 重构

**Trigger**: user_request
**Scope**: `T011`, `rtl/fifo_async_reg.sv`, `rtl/fifo_async_mem.sv`,
`dv/fifo_async_reg/`, `dv/fifo_async_mem/`, `scripts/run_fifo_async_*.sh`,
`docs/`, `TASKS.json`, `memory/`
**Outcome**: 异步 FIFO 已实现 flush-on-any-side-reset。单侧 reset 会经 reset-done 同步触发远端
flush；flush/alignment 期间写侧 full 阻塞、读侧 empty 阻塞，错误 pulse 不误报；flush 后从共同
empty 状态重新使用。默认 async 矩阵和 CDC_SYNC_STAGES=3 smoke 均通过。

### What Worked

- 三角色写入范围拆分有效：RTL 只改异步 RTL，DV 只改 testbench/脚本，architect 负责 TASKS、docs、memory 和集成验证。
- reset-done level 跨域同步比单周期 reset pulse 更适合本轮合同，避免远端漏观测 reset 事件。
- 定向 case 同时检查 reset release、单侧 reset while non-empty、active request during reset 和 post-flush reuse，比只跑普通 independent reset 更接近 review S0 风险。

### Friction

- DV 脚本首次新增 `CDC_SYNC_STAGES=1` 负例时复用了 non-power-of-two 宏名，后续集成阶段改为显式 `ILLEGAL_CDC_SYNC_STAGES`。
- `DEPTH=1` 参数实例中 level clamp 的保守比较会触发 Verilator `CMPCONST` warning，需要局部 pragma 保持脚本输出干净。
- 当前仍没有静态 CDC/RDC signoff 或 coverage DB，T011 只完成行为级 reset/flush 证明。

### Lessons

- **Lesson**: 异步 reset 协议应把远端 reset 观测建成可同步的 level/epoch，而不是只依赖本地 reset 后对齐远端 pointer。
  - Evidence: T011 使用 reset-done level 跨域同步后，单侧 reset 可使两侧进入共同 flush 并从 empty 恢复。
  - Action: local_process
  - Follow-up: 后续 CDC/RDC signoff 时检查 reset-done 同步链约束和 reset deassertion 假设。
- **Lesson**: reset/flush DV 需要显式建模 flush 窗口，不能直接复用正常 `push && wr_full`/`pop && rd_empty` 错误期望。
  - Evidence: T011 flush 期间要求 `overflow/underrun == 0`，testbench 增加 `wr_flush_tick/rd_flush_tick` 专门检查。
  - Action: knowledge
  - Follow-up: 后续随机 reset 相位测试也应继承该 flush-window 建模。
