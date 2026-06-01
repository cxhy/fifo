.PHONY: verilator lint

VERILATOR ?= verilator

verilator:
	bash scripts/run_fifo_sync_reg.sh
	bash scripts/run_fifo_sync_mem.sh
	bash scripts/run_fifo_async_reg.sh
	bash scripts/run_fifo_async_mem.sh

lint:
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_sync_reg rtl/fifo_sync_reg.sv
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_sync_mem rtl/fifo_sync_mem.sv
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_async_reg rtl/fifo_async_reg.sv
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_async_mem rtl/fifo_async_mem.sv
