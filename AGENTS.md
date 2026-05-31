# FIFO 子项目规则

本子项目完整继承 workspace 根目录 `AGENTS.md`。如无用户更新指令，
交流、文档和任务记录优先使用中文。

## 范围

- 本仓库只维护 FIFO 公共组件的设计、RTL、验证 collateral、构建脚本和局部文档。
- 变更应聚焦可复用 FIFO 逻辑，不把上层协议转换、SoC 集成或无关实验混入本仓库。
- 不削弱根 workspace 对 Git 安全、验证、项目记忆和工具链的要求。

## 工具链

- Python 环境、依赖和脚本执行使用 `uv`。
- Verilog/SystemVerilog 仿真使用 Verilator。
- 修改 RTL 或验证代码后，优先运行最窄相关仿真，再扩展到更大测试集合。

## 硬件设计约定

- 第一阶段目标是同步单时钟 FIFO，接口采用 `ready/valid` 握手。
- 初始 RTL 优先使用可综合 SystemVerilog；如后续改用 Chisel 或其他 HDL，需要保持同等接口语义并记录决策。
- 参数化设计需要覆盖数据宽度、深度、可选 fall-through 行为和状态观测信号。
- 验证必须覆盖满、空、同时入队出队、背压、复位和非 2 次幂深度。
