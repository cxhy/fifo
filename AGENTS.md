# FIFO 子项目规则

本子项目完整继承 workspace 根目录 `AGENTS.md`。如无用户更新指令，
交流、文档和任务记录优先使用中文。

## 范围

- 本仓库只维护 FIFO 公共组件的设计、RTL、验证 collateral、构建脚本和局部文档。
- 变更应聚焦可复用 FIFO 逻辑，不把上层协议转换、SoC 集成或无关实验混入本仓库。
- 不削弱根 workspace 对 Git 安全、验证、项目记忆和工具链的要求。

## 项目记忆

- 本子项目的项目记忆必须写入 `memory/` 子目录，不写入上一级 workspace 的 `../memory/`。
- 恢复 FIFO 研发上下文时，优先读取 `memory/project-status.md`；涉及设计历史时再读取
  `memory/decisions.md`、`memory/iterations.md` 和相关 ADR。
- 长期设计决策、阶段状态、复盘和阻塞记录应保留在本子项目内，避免污染上一级项目记忆。

## 任务与设计流程

- 本子项目使用 `TASKS.json` 管控任务、设计功能点、约束、验证项和确认状态，不使用
  Markdown 任务文件作为事实源。
- 设计每个模块前，必须先列出该模块的完整功能点、设计约束和验证项，确保架构、RTL
  设计和验证使用同一套任务与约束描述。
- 遇到会影响接口、架构、状态语义、错误语义、验证准则或用户可见结果的不确定点时，
  先主动和用户讨论并等待确认，不自行决策后继续实现。
- 每推进一个有意义的设计、RTL、DV 或流程节点后，应立即在本子项目 Git 仓库中创建一个聚焦 commit，
  记录当前状态，便于回退和追溯进度。

## 多 Agent 协作

- 本子项目默认使用三个角色：`fifo-architect`、`fifo-rtl-designer`、`fifo-dv-verifier`。
- `fifo-architect` 负责架构规划、任务拆分、进度把控、接口决策收敛和集成检查；不直接编写 RTL 或 DV 代码。
- `fifo-rtl-designer` 负责 RTL 设计与实现；不得修改 DV 参考模型、scoreboard 或测试期望来适配自己的实现。
- `fifo-dv-verifier` 负责验证计划、验证环境、测试用例、scoreboard 和覆盖项；不得修改 RTL 实现来让测试通过。
- RTL 与 DV 的写入范围必须分离；交叉修改必须先由 `fifo-architect` 明确分发并记录到 `TASKS.json`。
- 三个角色的可复用 prompt 和协作流程保存在 `agents/` 目录。
- 涉及架构、接口语义、RTL、DV、`TASKS.json`、验证计划、覆盖准则或跨角色交付的任务时，
  Codex 应主动启用 FIFO 三 Agent 协作流程；若判断无需启用，应简短说明原因。
- 用户可用“请启用 FIFO 多 Agent 协作流程”或“按 FIFO 三 Agent 流程推进”提醒 Codex：
  先由 `fifo-architect` 拆任务并更新 `TASKS.json`，再分派 `fifo-rtl-designer` 和
  `fifo-dv-verifier` 分别处理 RTL/DV，最后由 `fifo-architect` 集成检查并创建聚焦 commit。
- 简单问答、只读检查、局部文档润色或不影响架构/RTL/DV/验证语义的微小改动，可以不启用多 Agent；
  但不得因此绕过任务、验证和提交规则。

## 工具链

- Python 环境、依赖和脚本执行使用 `uv`。
- Verilog/SystemVerilog 仿真使用 Verilator。
- 修改 RTL 或验证代码后，优先运行最窄相关仿真，再扩展到更大测试集合。
- 用户可提前授权仓库内常用构建和验证命令，例如 `make verilator` 以及带有必要变量的同类命令
  （如 `make verilator MODEL=... CONFIG=...`），仅限本仓库构建和验证使用。
- 聊天中的提前授权用于指导 Codex 行为；若工具沙箱仍要求审批，Codex 应发起实际 approval request，
  并在适合时请求持久授权前缀，例如 `["make", "verilator"]`。
- 提前授权不覆盖破坏性操作、仓库外写入、全局依赖安装、强推、`git reset --hard` 或删除文件；
  这些操作必须单独确认。

## 硬件设计约定

- 第一阶段目标是通用 `push/pop` FIFO 组件族，覆盖同步 FIFO、异步 FIFO，以及
  register/memory 两种实现后端。
- 初始 RTL 优先使用可综合 SystemVerilog；如后续改用 Chisel 或其他 HDL，需要保持同等接口语义并记录决策。
- 第一版只支持 2 次幂深度；非 2 次幂 FIFO 后续单独设计。
- 参数化设计需要覆盖数据宽度、深度、同步 FIFO 可选 fall-through 行为和状态观测信号。
- 水线配置必须以端口形式提供，不作为固定参数。
- 验证必须覆盖满、空、同时 push/pop、overflow、underrun、复位、水线配置和异步跨域状态。
