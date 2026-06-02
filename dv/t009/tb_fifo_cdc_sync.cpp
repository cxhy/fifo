#include "Vfifo_cdc_sync.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <string>

namespace {

#ifndef WIDTH_VALUE
#define WIDTH_VALUE 4
#endif

#ifndef STAGES_VALUE
#define STAGES_VALUE 2
#endif

constexpr uint32_t kMask = (WIDTH_VALUE >= 32) ? 0xffffffffu : ((uint32_t{1} << WIDTH_VALUE) - 1u);
constexpr int kStages = STAGES_VALUE;
static_assert(kStages >= 2, "STAGES_VALUE must be at least 2");

vluint64_t g_time = 0;

void fail(const std::string &msg) {
    std::fprintf(stderr, "FAIL: %s\n", msg.c_str());
    std::exit(1);
}

void expect_eq(const char *name, uint32_t got, uint32_t exp) {
    got &= kMask;
    exp &= kMask;
    if (got != exp) {
        char buf[256];
        std::snprintf(buf, sizeof(buf), "%s got 0x%x expected 0x%x", name, got, exp);
        fail(buf);
    }
}

void eval(Vfifo_cdc_sync &dut) {
    dut.eval();
    ++g_time;
}

void tick(Vfifo_cdc_sync &dut) {
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
    Vfifo_cdc_sync dut;

    dut.clk = 0;
    dut.rst_n = 0;
    dut.async_i = 0xf & kMask;
    eval(dut);
    tick(dut);
    expect_eq("reset sync_o", dut.sync_o, 0);

    dut.rst_n = 1;
    dut.async_i = 0x6 & kMask;
    for (int i = 0; i < kStages - 1; ++i) {
        tick(dut);
        expect_eq("pipeline not yet visible", dut.sync_o, 0);
    }
    tick(dut);
    expect_eq("pipeline visible", dut.sync_o, 0x6);

    dut.async_i = 0x9 & kMask;
    for (int i = 0; i < kStages; ++i) {
        tick(dut);
    }
    expect_eq("second value visible", dut.sync_o, 0x9);

    std::puts("PASS fifo_cdc_sync T009 contract");
    return 0;
}
