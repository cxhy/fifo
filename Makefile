.PHONY: verilator lint t009-boundaries

VERILATOR ?= verilator

verilator:
	bash scripts/run_fifo_sync_reg.sh
	bash scripts/run_fifo_sync_mem.sh
	bash scripts/run_fifo_async_reg.sh
	bash scripts/run_fifo_async_mem.sh
	bash scripts/run_t009_boundaries.sh

lint:
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_sync_reg rtl/fifo_sync_reg.sv
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_sync_mem rtl/fifo_sync_1r1w_mem.sv rtl/fifo_sync_mem.sv
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_async_reg rtl/fifo_cdc_sync.sv rtl/fifo_async_reg.sv
	$(VERILATOR) --lint-only -Wall --timing --top-module fifo_async_mem rtl/fifo_cdc_sync.sv rtl/fifo_async_1r1w_mem.sv rtl/fifo_async_mem.sv

t009-boundaries:
	bash scripts/run_t009_boundaries.sh
