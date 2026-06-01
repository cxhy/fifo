#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

rtl="rtl/fifo_sync_reg.sv"
if [[ ! -f "${rtl}" ]]; then
  echo "ERROR: ${rtl} not found; RTL agent has not produced fifo_sync_reg yet." >&2
  exit 1
fi

run_case() {
  local name="$1"
  local ft="$2"
  local mdir="build/fifo_sync_reg/${name}"
  mkdir -p "${mdir}"
  verilator --cc "${rtl}" --top-module fifo_sync_reg --exe dv/fifo_sync_reg/tb_fifo_sync_reg.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 -GFALL_THROUGH="${ft}" \
    -CFLAGS "-std=c++17 -DFALL_THROUGH_VALUE=${ft}" --build
  "${mdir}/Vfifo_sync_reg"
}

run_illegal_config() {
  local mdir="build/fifo_sync_reg/illegal_config"
  mkdir -p "${mdir}"
  verilator --cc "${rtl}" --top-module fifo_sync_reg --exe dv/fifo_sync_reg/tb_illegal_config.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 -GFALL_THROUGH=0 \
    -CFLAGS "-std=c++17" --build
  if "${mdir}/Vfifo_sync_reg"; then
    echo "ERROR: illegal waterline configuration did not trigger an assertion." >&2
    exit 1
  fi
  echo "PASS fifo_sync_reg illegal waterline assertion"
}

run_case ft0 0
run_case ft1 1
run_illegal_config
