# FIFO Agents

本目录定义 FIFO 子项目默认使用的三个协作 agent。三者共享同一份
`TASKS.json`、`docs/fifo-common-design.md` 和本地 `memory/`，但职责和写入范围分离。

| Agent | 主要职责 | Prompt |
| --- | --- | --- |
| `fifo-architect` | 架构规划、任务分发、进度把控、接口一致性和集成检查 | [fifo-architect.md](fifo-architect.md) |
| `fifo-rtl-designer` | SystemVerilog RTL 设计与实现 | [fifo-rtl-designer.md](fifo-rtl-designer.md) |
| `fifo-dv-verifier` | Verilator 验证环境、参考模型、scoreboard 和测试 | [fifo-dv-verifier.md](fifo-dv-verifier.md) |

## 协作规则

- `fifo-architect` 是任务分发和状态收敛入口。
- `fifo-rtl-designer` 只负责 RTL，不修改 DV 期望。
- `fifo-dv-verifier` 只负责验证，不修改 RTL 实现。
- 任何影响接口、架构、状态语义、错误语义或验证准则的不确定点，必须回到用户确认。
- 任务状态、owner、验收条件和开放问题以 `TASKS.json` 为事实源。
