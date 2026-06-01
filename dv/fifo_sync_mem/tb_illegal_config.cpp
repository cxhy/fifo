#include "Vfifo_sync_mem.h"
#include "verilated.h"

namespace {

#ifndef DEPTH_VALUE
#define DEPTH_VALUE 4
#endif

#ifndef ILLEGAL_ALMOST_FULL
#define ILLEGAL_ALMOST_FULL 0
#endif

#ifndef ILLEGAL_ALMOST_EMPTY
#define ILLEGAL_ALMOST_EMPTY 0
#endif

#ifndef ILLEGAL_POWER_OF_TWO_DEPTH
#define ILLEGAL_POWER_OF_TWO_DEPTH 0
#endif

#if (ILLEGAL_ALMOST_FULL + ILLEGAL_ALMOST_EMPTY + ILLEGAL_POWER_OF_TWO_DEPTH) != 1
#error "Define exactly one illegal configuration mode"
#endif

constexpr int kDepth = DEPTH_VALUE;

void cycle(Vfifo_sync_mem &dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.clk = 0;
    dut.eval();
}
}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo_sync_mem dut;
    dut.rst_n = 0;
    dut.push = 0;
    dut.pop = 0;
    dut.push_data = 0;
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = 0;

#if ILLEGAL_POWER_OF_TWO_DEPTH
    cycle(dut);
    return 0;
#else
    cycle(dut);
    dut.rst_n = 1;
    cycle(dut);

#if ILLEGAL_ALMOST_FULL
    dut.cfg_almost_full_level = 0;
    cycle(dut);
#elif ILLEGAL_ALMOST_EMPTY
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = kDepth;
    cycle(dut);
#endif
    return 0;
#endif
}
