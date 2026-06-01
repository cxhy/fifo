# FIFO 公共组件

本仓库用于维护 harness workspace 下的可复用 FIFO 组件。它以 submodule
形式挂载在 workspace 根目录下，组件设计、验证用例和子项目本地规则都在
本仓库内维护。

## 当前设计焦点

- 第一阶段规划通用 `push/pop` FIFO 组件族，覆盖同步 FIFO、异步 FIFO，以及
  register/memory 两种实现后端。
- 默认使用 SystemVerilog RTL 描述硬件行为。
- 使用 Verilator 做仿真验证。
- 使用 `uv` 管理 Python 脚本、测试辅助工具和依赖。

## 设计入口

- [docs/fifo-common-design.md](docs/fifo-common-design.md): FIFO 公共组件第一版设计规格。
- [TASKS.json](TASKS.json): FIFO 子项目任务、模块功能点、设计约束和验证项事实源。
- [agents/](agents/): 架构规划、RTL 设计和 DV 验证三个 agent 的职责与 prompt。

## 验证入口

- `make lint`: 对四个 FIFO RTL 分别运行 Verilator lint。
- `make verilator`: 运行四个 FIFO 的 Verilator 定向测试和非法水线 assertion 测试。
