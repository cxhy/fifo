#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

rtl="rtl/fifo_async_mem.sv"
if [[ ! -f "${rtl}" ]]; then
  echo "ERROR: ${rtl} not found; RTL agent has not produced fifo_async_mem yet." >&2
  exit 1
fi

run_main() {
  local mdir="build/fifo_async_mem/main"
  mkdir -p "${mdir}"
  verilator --cc "${rtl}" --top-module fifo_async_mem --exe dv/fifo_async_mem/tb_fifo_async_mem.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 \
    -CFLAGS "-std=c++17" --build
  "${mdir}/Vfifo_async_mem"
}

run_illegal_config() {
  local mdir="build/fifo_async_mem/illegal_config"
  mkdir -p "${mdir}"
  verilator --cc "${rtl}" --top-module fifo_async_mem --exe dv/fifo_async_mem/tb_illegal_config.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 \
    -CFLAGS "-std=c++17" --build
  if "${mdir}/Vfifo_async_mem"; then
    echo "ERROR: illegal waterline configuration did not trigger an assertion." >&2
    exit 1
  fi
  echo "PASS fifo_async_mem illegal waterline assertion"
}

run_main
run_illegal_config
