# FIFO 公共组件

本仓库用于维护 harness workspace 下的可复用 FIFO 组件。它以 submodule
形式挂载在 workspace 根目录下，组件设计、验证用例和子项目本地规则都在
本仓库内维护。

## 当前设计焦点

- 第一阶段实现同步单时钟 `ready/valid` FIFO。
- 默认使用 SystemVerilog RTL 描述硬件行为。
- 使用 Verilator 做仿真验证。
- 使用 `uv` 管理 Python 脚本、测试辅助工具和依赖。

## 设计入口

- [docs/fifo-common-design.md](docs/fifo-common-design.md): FIFO 公共组件第一版设计规格。
