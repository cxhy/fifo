#include "Vfifo_sync_mem.h"
#include "verilated.h"

namespace {
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
    dut.cfg_almost_full_level = 4;
    dut.cfg_almost_empty_level = 0;
    cycle(dut);
    dut.rst_n = 1;
    cycle(dut);

    dut.cfg_almost_full_level = 0;
    cycle(dut);
    dut.cfg_almost_full_level = 4;
    dut.cfg_almost_empty_level = 4;
    cycle(dut);
    return 0;
}
