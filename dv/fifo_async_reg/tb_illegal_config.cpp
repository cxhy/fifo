#include "Vfifo_async_reg.h"
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

#ifndef ILLEGAL_CDC_SYNC_STAGES
#define ILLEGAL_CDC_SYNC_STAGES 0
#endif

#if (ILLEGAL_ALMOST_FULL + ILLEGAL_ALMOST_EMPTY + ILLEGAL_POWER_OF_TWO_DEPTH + ILLEGAL_CDC_SYNC_STAGES) != 1
#error "Define exactly one illegal configuration mode"
#endif

constexpr int kDepth = DEPTH_VALUE;

void wr_cycle(Vfifo_async_reg &dut) {
    dut.wr_clk = 0;
    dut.eval();
    dut.wr_clk = 1;
    dut.eval();
    dut.wr_clk = 0;
    dut.eval();
}

void rd_cycle(Vfifo_async_reg &dut) {
    dut.rd_clk = 0;
    dut.eval();
    dut.rd_clk = 1;
    dut.eval();
    dut.rd_clk = 0;
    dut.eval();
}
}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo_async_reg dut;
    dut.wr_rst_n = 0;
    dut.rd_rst_n = 0;
    dut.push = 0;
    dut.pop = 0;
    dut.push_data = 0;
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = 0;

#if ILLEGAL_POWER_OF_TWO_DEPTH || ILLEGAL_CDC_SYNC_STAGES
    wr_cycle(dut);
    rd_cycle(dut);
    return 0;
#else
    wr_cycle(dut);
    rd_cycle(dut);
    dut.wr_rst_n = 1;
    dut.rd_rst_n = 1;
    wr_cycle(dut);
    rd_cycle(dut);

#if ILLEGAL_ALMOST_FULL
    dut.cfg_almost_full_level = 0;
    wr_cycle(dut);
#elif ILLEGAL_ALMOST_EMPTY
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = kDepth;
    rd_cycle(dut);
#endif
    return 0;
#endif
}
