#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

rtl_files=(rtl/fifo_cdc_sync.sv rtl/fifo_async_1r1w_mem.sv rtl/fifo_async_mem.sv)
for rtl in "${rtl_files[@]}"; do
  if [[ ! -f "${rtl}" ]]; then
    echo "ERROR: ${rtl} not found; RTL agent has not produced T009 fifo_async_mem dependencies." >&2
    exit 1
  fi
done

data_widths=(${FIFO_DATA_WIDTHS:-1 8 17})
depths=(${FIFO_DEPTHS:-1 2 4 8})
cdc_sync_stages="${FIFO_CDC_SYNC_STAGES:-2}"
positive_count=0
negative_count=0

run_case() {
  local dw="$1"
  local depth="$2"
  local name="dw${dw}_d${depth}_s${cdc_sync_stages}"
  local mdir="build/fifo_async_mem/${name}"
  mkdir -p "${mdir}"
  verilator --cc "${rtl_files[@]}" --top-module fifo_async_mem --exe dv/fifo_async_mem/tb_fifo_async_mem.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH="${dw}" -GDEPTH="${depth}" -GCDC_SYNC_STAGES="${cdc_sync_stages}" \
    -CFLAGS "-std=c++17 -DDATA_WIDTH_VALUE=${dw} -DDEPTH_VALUE=${depth} -DCDC_SYNC_STAGES_VALUE=${cdc_sync_stages}" --build
  "${mdir}/Vfifo_async_mem"
  positive_count=$((positive_count + 1))
  echo "COVER fifo_async_mem positive DATA_WIDTH=${dw} DEPTH=${depth}"
}

run_illegal_waterline() {
  local case_name="$1"
  local mode_macro="$2"
  local mdir="build/fifo_async_mem/negative_${case_name}"
  mkdir -p "${mdir}"
  verilator --cc "${rtl_files[@]}" --top-module fifo_async_mem --exe dv/fifo_async_mem/tb_illegal_config.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=4 -GCDC_SYNC_STAGES="${cdc_sync_stages}" \
    -CFLAGS "-std=c++17 -DDEPTH_VALUE=4 -D${mode_macro}=1" --build
  if "${mdir}/Vfifo_async_mem"; then
    echo "ERROR: ${case_name} did not trigger an assertion." >&2
    exit 1
  fi
  negative_count=$((negative_count + 1))
  echo "COVER fifo_async_mem negative ${case_name}=hit"
}

run_illegal_depth() {
  local mdir="build/fifo_async_mem/negative_non_power_of_two_depth"
  mkdir -p "${mdir}"
  set +e
  verilator --cc "${rtl_files[@]}" --top-module fifo_async_mem --exe dv/fifo_async_mem/tb_illegal_config.cpp \
    --Mdir "${mdir}" --assert -Wall -Wno-fatal \
    -GDATA_WIDTH=8 -GDEPTH=3 -GCDC_SYNC_STAGES="${cdc_sync_stages}" \
    -CFLAGS "-std=c++17 -DDEPTH_VALUE=3 -DILLEGAL_POWER_OF_TWO_DEPTH=1" --build
  local build_rc=$?
  set -e
  if [[ "${build_rc}" -ne 0 ]]; then
    negative_count=$((negative_count + 1))
    echo "COVER fifo_async_mem negative non_power_of_two_depth=elaboration_rejected"
    return
  fi
  if "${mdir}/Vfifo_async_mem"; then
    echo "ERROR: non-power-of-two DEPTH did not trigger an assertion." >&2
    exit 1
  fi
  negative_count=$((negative_count + 1))
  echo "COVER fifo_async_mem negative non_power_of_two_depth=runtime_assertion"
}

for dw in "${data_widths[@]}"; do
  for depth in "${depths[@]}"; do
    run_case "${dw}" "${depth}"
  done
done

run_illegal_waterline "illegal_almost_full" "ILLEGAL_ALMOST_FULL"
run_illegal_waterline "illegal_almost_empty" "ILLEGAL_ALMOST_EMPTY"
run_illegal_depth

expected_positive=$((${#data_widths[@]} * ${#depths[@]}))
expected_negative=3
echo "COVERAGE fifo_async_mem positive_matrix=${positive_count}/${expected_positive} data_widths=${data_widths[*]} depths=${depths[*]} cdc_sync_stages=${cdc_sync_stages} negative_cases=${negative_count}/${expected_negative}"
echo "PASS fifo_async_mem T008/T009 regression"
