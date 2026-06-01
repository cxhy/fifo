#include "Vfifo_async_reg.h"
#include "verilated.h"

namespace {
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
    dut.cfg_almost_full_level = 4;
    dut.cfg_almost_empty_level = 0;
    wr_cycle(dut);
    rd_cycle(dut);
    dut.wr_rst_n = 1;
    dut.rd_rst_n = 1;
    wr_cycle(dut);
    rd_cycle(dut);

    dut.cfg_almost_full_level = 0;
    wr_cycle(dut);
    dut.cfg_almost_full_level = 4;
    dut.cfg_almost_empty_level = 4;
    rd_cycle(dut);
    return 0;
}
