#include "Vfifo_cdc_sync.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo_cdc_sync dut;

    dut.clk = 0;
    dut.rst_n = 0;
    dut.async_i = 0;
    dut.eval();

    return 0;
}
