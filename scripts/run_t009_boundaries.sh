#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

rtl_files=(
  rtl/fifo_sync_1r1w_mem.sv
  rtl/fifo_async_1r1w_mem.sv
  rtl/fifo_cdc_sync.sv
  rtl/fifo_sync_mem.sv
  rtl/fifo_async_reg.sv
  rtl/fifo_async_mem.sv
)

for rtl in "${rtl_files[@]}"; do
  if [[ ! -f "${rtl}" ]]; then
    echo "ERROR: ${rtl} not found for T009 boundary check." >&2
    exit 1
  fi
done

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq "${pattern}" "${file}"; then
    echo "ERROR: missing ${label} in ${file}" >&2
    exit 1
  fi
  echo "COVER t009 structure ${label}=hit"
}

forbid_top_header_pattern() {
  local file="$1"
  local module="$2"
  local pattern="$3"
  local label="$4"
  if awk "/^module ${module} #\\(/,/^\\);/" "${file}" | grep -Eq "${pattern}"; then
    echo "ERROR: forbidden ${label} found in ${module} top header" >&2
    exit 1
  fi
  echo "COVER t009 top_header ${module}_${label}=absent"
}

require_top_port() {
  local file="$1"
  local module="$2"
  local port="$3"
  if ! awk "/^module ${module} #\\(/,/^\\);/" "${file}" | grep -Eq "\\b(input|output)\\b.*\\b${port}\\b"; then
    echo "ERROR: expected port ${port} missing from ${module}" >&2
    exit 1
  fi
}

for port in clk rst_n push push_data pop pop_data cfg_almost_full_level cfg_almost_empty_level full empty almost_full almost_empty level overflow underrun; do
  require_top_port rtl/fifo_sync_mem.sv fifo_sync_mem "${port}"
done

for port in wr_clk wr_rst_n push push_data cfg_almost_full_level wr_full wr_almost_full wr_level overflow rd_clk rd_rst_n pop pop_data cfg_almost_empty_level rd_empty rd_almost_empty rd_level underrun; do
  require_top_port rtl/fifo_async_mem.sv fifo_async_mem "${port}"
  require_top_port rtl/fifo_async_reg.sv fifo_async_reg "${port}"
done

forbid_top_header_pattern rtl/fifo_sync_mem.sv fifo_sync_mem "\\b(wr_en|wr_addr|rd_en|rd_addr|rd_data)\\b" "memory_ports"
forbid_top_header_pattern rtl/fifo_async_mem.sv fifo_async_mem "\\b(wr_en|wr_addr|rd_en|rd_addr|rd_data)\\b" "memory_ports"

require_pattern rtl/fifo_sync_mem.sv "\\bfifo_sync_1r1w_mem\\b" "fifo_sync_mem_instantiates_sync_memory_wrapper"
require_pattern rtl/fifo_async_mem.sv "\\bfifo_async_1r1w_mem\\b" "fifo_async_mem_instantiates_async_memory_wrapper"
require_pattern rtl/fifo_async_reg.sv "\\bfifo_cdc_sync\\b" "fifo_async_reg_instantiates_cdc_sync"
require_pattern rtl/fifo_async_mem.sv "\\bfifo_cdc_sync\\b" "fifo_async_mem_instantiates_cdc_sync"

verilator --lint-only -Wall --timing --top-module fifo_sync_1r1w_mem rtl/fifo_sync_1r1w_mem.sv
verilator --lint-only -Wall --timing --top-module fifo_async_1r1w_mem rtl/fifo_async_1r1w_mem.sv
verilator --lint-only -Wall --timing --top-module fifo_cdc_sync rtl/fifo_cdc_sync.sv

run_sync_mem_contract() {
  local mdir="build/t009/fifo_sync_1r1w_mem"
  mkdir -p "${mdir}"
  verilator --cc rtl/fifo_sync_1r1w_mem.sv --top-module fifo_sync_1r1w_mem --exe dv/t009/tb_fifo_sync_1r1w_mem.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 \
    -CFLAGS "-std=c++17" --build
  "${mdir}/Vfifo_sync_1r1w_mem"
}

run_async_mem_contract() {
  local mdir="build/t009/fifo_async_1r1w_mem"
  mkdir -p "${mdir}"
  verilator --cc rtl/fifo_async_1r1w_mem.sv --top-module fifo_async_1r1w_mem --exe dv/t009/tb_fifo_async_1r1w_mem.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 \
    -CFLAGS "-std=c++17" --build
  "${mdir}/Vfifo_async_1r1w_mem"
}

run_cdc_sync_contract() {
  local stages="$1"
  local mdir="build/t009/fifo_cdc_sync_s${stages}"
  mkdir -p "${mdir}"
  verilator --cc rtl/fifo_cdc_sync.sv --top-module fifo_cdc_sync --exe dv/t009/tb_fifo_cdc_sync.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GWIDTH=4 -GSTAGES="${stages}" \
    -CFLAGS "-std=c++17 -DWIDTH_VALUE=4 -DSTAGES_VALUE=${stages}" --build
  "${mdir}/Vfifo_cdc_sync"
}

run_cdc_sync_illegal_stages() {
  local mdir="build/t009/fifo_cdc_sync_illegal_stages"
  mkdir -p "${mdir}"
  verilator --cc rtl/fifo_cdc_sync.sv --top-module fifo_cdc_sync --exe dv/t009/tb_fifo_cdc_sync_illegal.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GWIDTH=4 -GSTAGES=1 \
    -CFLAGS "-std=c++17" --build
  set +e
  "${mdir}/Vfifo_cdc_sync"
  local rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    echo "ERROR: fifo_cdc_sync STAGES=1 did not trigger a fatal check." >&2
    exit 1
  fi
  echo "COVER t009 cdc_sync illegal_stages=hit"
}

run_sync_mem_contract
run_async_mem_contract
run_cdc_sync_contract 2
run_cdc_sync_contract 3
run_cdc_sync_illegal_stages

echo "COVERAGE t009_boundaries structure=6/6 wrapper_contracts=2/2 cdc_sync_stage_configs=2/2 cdc_sync_illegal_configs=1/1 top_port_checks=3/3"
echo "PASS T009 ASIC replacement boundary checks"
