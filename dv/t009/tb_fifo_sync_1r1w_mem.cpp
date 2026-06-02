#include "Vfifo_sync_1r1w_mem.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <string>

namespace {

vluint64_t g_time = 0;

void fail(const std::string &msg) {
    std::fprintf(stderr, "FAIL: %s\n", msg.c_str());
    std::exit(1);
}

void expect_eq(const char *name, uint32_t got, uint32_t exp) {
    if (got != exp) {
        char buf[256];
        std::snprintf(buf, sizeof(buf), "%s got 0x%x expected 0x%x", name, got, exp);
        fail(buf);
    }
}

void eval(Vfifo_sync_1r1w_mem &dut) {
    dut.eval();
    ++g_time;
}

void tick(Vfifo_sync_1r1w_mem &dut) {
    dut.clk = 0;
    eval(dut);
    dut.clk = 1;
    eval(dut);
    dut.clk = 0;
    eval(dut);
}

} // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo_sync_1r1w_mem dut;

    dut.clk = 0;
    dut.rst_n = 0;
    dut.wr_en = 0;
    dut.wr_addr = 0;
    dut.wr_data = 0;
    dut.rd_en = 0;
    dut.rd_addr = 0;
    eval(dut);
    tick(dut);
    expect_eq("reset rd_data", dut.rd_data, 0);

    dut.rst_n = 1;
    dut.wr_en = 1;
    dut.wr_addr = 1;
    dut.wr_data = 0x5a;
    tick(dut);

    dut.wr_en = 0;
    dut.rd_en = 1;
    dut.rd_addr = 1;
    tick(dut);
    expect_eq("read updated rd_data", dut.rd_data, 0x5a);

    dut.rd_en = 0;
    dut.rd_addr = 2;
    tick(dut);
    expect_eq("held rd_data", dut.rd_data, 0x5a);

    std::puts("PASS fifo_sync_1r1w_mem T009 contract");
    return 0;
}
