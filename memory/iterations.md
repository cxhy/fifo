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
