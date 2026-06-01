#include "Vfifo_sync_reg.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <string>

namespace {

#ifndef DATA_WIDTH_VALUE
#define DATA_WIDTH_VALUE 8
#endif

#ifndef DEPTH_VALUE
#define DEPTH_VALUE 4
#endif

#ifndef FALL_THROUGH_VALUE
#define FALL_THROUGH_VALUE 0
#endif

constexpr int kDataWidth = DATA_WIDTH_VALUE;
constexpr int kDepth = DEPTH_VALUE;
static_assert(kDataWidth > 0 && kDataWidth <= 32, "DATA_WIDTH_VALUE must be 1..32");
static_assert(kDepth > 0, "DEPTH_VALUE must be greater than 0");

constexpr uint32_t data_mask(int width) {
    return width >= 32 ? 0xffffffffu : ((uint32_t{1} << width) - 1u);
}

constexpr uint32_t kMask = data_mask(kDataWidth);
constexpr bool kFallThrough = FALL_THROUGH_VALUE != 0;

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

struct Expected {
    uint32_t pop_data = 0;
    uint32_t level = 0;
    bool full = false;
    bool empty = true;
    bool almost_full = false;
    bool almost_empty = true;
    bool overflow = false;
    bool underrun = false;
};

struct SyncScoreboard {
    std::deque<uint32_t> q;
    uint32_t last_pop_data = 0;

    void reset() {
        q.clear();
        last_pop_data = 0;
    }

    Expected step(bool push, uint32_t push_data, bool pop, uint32_t cfg_af, uint32_t cfg_ae) {
        const bool was_empty = q.empty();
        const bool was_full = q.size() == kDepth;
        Expected exp;

        exp.overflow = push && was_full && !pop;
        exp.underrun = pop && was_empty && !(kFallThrough && push);

        if (pop && !was_empty) {
            last_pop_data = q.front();
            q.pop_front();
        } else if (pop && was_empty && kFallThrough && push) {
            last_pop_data = push_data & kMask;
        }

        if (push && !exp.overflow) {
            if (!(kFallThrough && was_empty && pop)) {
                if (q.size() >= kDepth) {
                    fail("reference queue overflow");
                }
                q.push_back(push_data & kMask);
            }
        }

        exp.pop_data = last_pop_data;
        exp.level = static_cast<uint32_t>(q.size());
        exp.full = q.size() == kDepth;
        exp.empty = q.empty();
        exp.almost_full = exp.level >= cfg_af;
        exp.almost_empty = exp.level <= cfg_ae;
        return exp;
    }
};

void eval(Vfifo_sync_reg &dut) {
    dut.eval();
    ++g_time;
}

void drive_reset(Vfifo_sync_reg &dut, SyncScoreboard &ref) {
    dut.clk = 0;
    dut.rst_n = 0;
    dut.push = 0;
    dut.push_data = 0;
    dut.pop = 0;
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = 0;
    eval(dut);
    for (int i = 0; i < 2; ++i) {
        dut.clk = 1;
        eval(dut);
        dut.clk = 0;
        eval(dut);
    }
    ref.reset();
    expect_eq("reset pop_data", dut.pop_data, 0);
    expect_eq("reset empty", dut.empty, 1);
    expect_eq("reset full", dut.full, 0);
    expect_eq("reset level", dut.level, 0);
    dut.rst_n = 1;
    eval(dut);
}

void tick(Vfifo_sync_reg &dut, SyncScoreboard &ref, bool push, uint32_t data, bool pop,
          uint32_t cfg_af = kDepth, uint32_t cfg_ae = 0) {
    dut.push = push;
    dut.push_data = data & kMask;
    dut.pop = pop;
    dut.cfg_almost_full_level = cfg_af;
    dut.cfg_almost_empty_level = cfg_ae;
    dut.clk = 0;
    eval(dut);

    Expected exp = ref.step(push, data, pop, cfg_af, cfg_ae);

    dut.clk = 1;
    eval(dut);
    expect_eq("pop_data", dut.pop_data, exp.pop_data);
    expect_eq("level", dut.level, exp.level);
    expect_eq("full", dut.full, exp.full);
    expect_eq("empty", dut.empty, exp.empty);
    expect_eq("almost_full", dut.almost_full, exp.almost_full);
    expect_eq("almost_empty", dut.almost_empty, exp.almost_empty);
    expect_eq("overflow", dut.overflow, exp.overflow);
    expect_eq("underrun", dut.underrun, exp.underrun);

    dut.clk = 0;
    eval(dut);
}

void test_order_and_reset(Vfifo_sync_reg &dut, SyncScoreboard &ref) {
    drive_reset(dut, ref);
    tick(dut, ref, false, 0, false, 1, 0);
    const int entries = kDepth < 3 ? kDepth : 3;
    for (int i = 0; i < entries; ++i) {
        tick(dut, ref, true, 0x11u + static_cast<uint32_t>(i * 0x11), false, 1, 0);
    }
    for (int i = 0; i < entries; ++i) {
        tick(dut, ref, false, 0, true, 1, 0);
    }
    tick(dut, ref, false, 0, false, 1, 0);
}

void test_full_empty_errors_and_hold(Vfifo_sync_reg &dut, SyncScoreboard &ref) {
    drive_reset(dut, ref);
    for (uint32_t i = 0; i < kDepth; ++i) {
        tick(dut, ref, true, 0x40 + i, false, kDepth, kDepth - 1);
    }
    tick(dut, ref, true, 0x99, false, kDepth, kDepth - 1);
    tick(dut, ref, false, 0, false, kDepth, kDepth - 1);
    for (uint32_t i = 0; i < kDepth; ++i) {
        tick(dut, ref, false, 0, true, kDepth, kDepth - 1);
    }
    tick(dut, ref, false, 0, true, kDepth, kDepth - 1);
    tick(dut, ref, false, 0, false, kDepth, kDepth - 1);
}

void test_full_replacement(Vfifo_sync_reg &dut, SyncScoreboard &ref) {
    drive_reset(dut, ref);
    for (uint32_t i = 0; i < kDepth; ++i) {
        tick(dut, ref, true, 0x60 + i, false);
    }
    tick(dut, ref, true, 0xa5, true);
    for (uint32_t i = 0; i < kDepth; ++i) {
        tick(dut, ref, false, 0, true);
    }
}

void test_fall_through_case(Vfifo_sync_reg &dut, SyncScoreboard &ref) {
    drive_reset(dut, ref);
    tick(dut, ref, true, 0x5a, true);
    tick(dut, ref, false, 0, false);
    if (!kFallThrough) {
        tick(dut, ref, false, 0, true);
    }
    tick(dut, ref, false, 0, false);
}

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo_sync_reg dut;
    SyncScoreboard ref;

    test_order_and_reset(dut, ref);
    test_full_empty_errors_and_hold(dut, ref);
    test_full_replacement(dut, ref);
    test_fall_through_case(dut, ref);

    std::printf("PASS fifo_sync_reg DATA_WIDTH=%d DEPTH=%d FALL_THROUGH=%d\n",
                kDataWidth, kDepth, kFallThrough ? 1 : 0);
    return 0;
}
