#include "Vfifo_async_mem.h"
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

#ifndef CDC_SYNC_STAGES_VALUE
#define CDC_SYNC_STAGES_VALUE 2
#endif

constexpr int kDataWidth = DATA_WIDTH_VALUE;
constexpr int kDepth = DEPTH_VALUE;
constexpr int kCdcSyncStages = CDC_SYNC_STAGES_VALUE;
static_assert(kDataWidth > 0 && kDataWidth <= 32, "DATA_WIDTH_VALUE must be 1..32");
static_assert(kDepth > 0, "DEPTH_VALUE must be greater than 0");
static_assert(kCdcSyncStages >= 2, "CDC_SYNC_STAGES_VALUE must be at least 2");

constexpr uint32_t data_mask(int width) {
    return width >= 32 ? 0xffffffffu : ((uint32_t{1} << width) - 1u);
}

constexpr uint32_t kMask = data_mask(kDataWidth);
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

struct AsyncMemScoreboard {
    std::deque<uint32_t> q;
    uint32_t last_pop_data = 0;

    void reset_all() {
        q.clear();
        last_pop_data = 0;
    }
};

void eval(Vfifo_async_mem &dut) {
    dut.eval();
    ++g_time;
}

void check_wr_status(Vfifo_async_mem &dut, const AsyncMemScoreboard &ref) {
    if (dut.wr_level > kDepth) {
        fail("wr_level above DEPTH");
    }
    if (dut.wr_level < ref.q.size()) {
        fail("wr_level underestimates actual occupancy");
    }
    expect_eq("wr_almost_full", dut.wr_almost_full, dut.wr_level >= dut.cfg_almost_full_level);
    if (dut.wr_full && dut.wr_level != kDepth) {
        fail("wr_full asserted without full conservative level");
    }
}

void check_rd_status(Vfifo_async_mem &dut, const AsyncMemScoreboard &ref) {
    if (dut.rd_level > kDepth) {
        fail("rd_level above DEPTH");
    }
    if (dut.rd_level > ref.q.size()) {
        fail("rd_level overestimates actual readable occupancy");
    }
    expect_eq("rd_almost_empty", dut.rd_almost_empty, dut.rd_level <= dut.cfg_almost_empty_level);
    if (dut.rd_empty && dut.rd_level != 0) {
        fail("rd_empty asserted with nonzero rd_level");
    }
}

void wr_tick(Vfifo_async_mem &dut, AsyncMemScoreboard &ref, bool push, uint32_t data) {
    const bool was_full = dut.wr_full;
    dut.push = push;
    dut.push_data = data & kMask;
    dut.wr_clk = 0;
    eval(dut);
    dut.wr_clk = 1;
    eval(dut);

    const bool exp_overflow = push && was_full;
    expect_eq("overflow", dut.overflow, exp_overflow);
    if (push && !was_full) {
        if (ref.q.size() >= kDepth) {
            fail("scoreboard accepted push beyond DEPTH");
        }
        ref.q.push_back(data & kMask);
    }
    check_wr_status(dut, ref);

    dut.wr_clk = 0;
    eval(dut);
}

void rd_tick(Vfifo_async_mem &dut, AsyncMemScoreboard &ref, bool pop) {
    const bool was_empty = dut.rd_empty;
    dut.pop = pop;
    dut.rd_clk = 0;
    eval(dut);
    dut.rd_clk = 1;
    eval(dut);

    const bool exp_underrun = pop && was_empty;
    expect_eq("underrun", dut.underrun, exp_underrun);
    if (pop && !was_empty) {
        if (ref.q.empty()) {
            fail("rd_empty deasserted while no accepted data exists");
        }
        ref.last_pop_data = ref.q.front();
        ref.q.pop_front();
    }
    expect_eq("pop_data", dut.pop_data, ref.last_pop_data);
    check_rd_status(dut, ref);

    dut.rd_clk = 0;
    eval(dut);
}

void drive_reset(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    dut.wr_clk = 0;
    dut.rd_clk = 0;
    dut.wr_rst_n = 0;
    dut.rd_rst_n = 0;
    dut.push = 0;
    dut.pop = 0;
    dut.push_data = 0;
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = 0;
    eval(dut);
    for (int i = 0; i < 2; ++i) {
        dut.wr_clk = 1;
        eval(dut);
        dut.wr_clk = 0;
        eval(dut);
    }
    for (int i = 0; i < 2; ++i) {
        dut.rd_clk = 1;
        eval(dut);
        dut.rd_clk = 0;
        eval(dut);
    }
    ref.reset_all();
    expect_eq("reset pop_data", dut.pop_data, 0);
    expect_eq("reset wr_full", dut.wr_full, 0);
    expect_eq("reset rd_empty", dut.rd_empty, 1);

    dut.wr_rst_n = 1;
    for (int i = 0; i < kCdcSyncStages + 1; ++i) {
        wr_tick(dut, ref, false, 0);
    }
    dut.rd_rst_n = 1;
    for (int i = 0; i < kCdcSyncStages + 1; ++i) {
        rd_tick(dut, ref, false);
    }
}

void wait_rd_visible(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    for (int i = 0; i < 12 && dut.rd_empty; ++i) {
        rd_tick(dut, ref, false);
    }
    if (dut.rd_empty && !ref.q.empty()) {
        fail("written data did not become visible in read domain");
    }
}

void wait_wr_full(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    for (int i = 0; i < 12 && !dut.wr_full; ++i) {
        wr_tick(dut, ref, false, 0);
    }
    if (!dut.wr_full) {
        fail("full FIFO did not assert wr_full");
    }
}

void wait_wr_not_full(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    for (int i = 0; i < 12 && dut.wr_full; ++i) {
        wr_tick(dut, ref, false, 0);
    }
    if (dut.wr_full) {
        fail("read space did not become visible in write domain");
    }
}

void drain_all(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    while (!ref.q.empty()) {
        wait_rd_visible(dut, ref);
        rd_tick(dut, ref, true);
        if ((g_time & 1u) == 0) {
            wr_tick(dut, ref, false, 0);
        }
    }
    for (int i = 0; i < 4; ++i) {
        rd_tick(dut, ref, false);
    }
}

void test_independent_reset_and_hold(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    drive_reset(dut, ref);
    wr_tick(dut, ref, true, 0x31);
    wait_rd_visible(dut, ref);
    rd_tick(dut, ref, true);
    rd_tick(dut, ref, false);
    expect_eq("held pop_data after drain", dut.pop_data, 0x31u & kMask);

    dut.rd_rst_n = 0;
    ref.last_pop_data = 0;
    rd_tick(dut, ref, false);
    expect_eq("rd reset pop_data", dut.pop_data, 0);
    dut.rd_rst_n = 1;
    rd_tick(dut, ref, false);
    expect_eq("rd reset release held zero", dut.pop_data, 0);

    dut.wr_rst_n = 0;
    wr_tick(dut, ref, false, 0);
    expect_eq("wr reset wr_full", dut.wr_full, 0);
    dut.wr_rst_n = 1;
    wr_tick(dut, ref, false, 0);
    ref.reset_all();
}

void test_async_mem_order_errors_and_read_latency(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    drive_reset(dut, ref);
    dut.cfg_almost_full_level = 1;
    dut.cfg_almost_empty_level = 0;

    for (int i = 0; i < kDepth; ++i) {
        wr_tick(dut, ref, true, 0x10u + static_cast<uint32_t>(i));
        if ((i % 2) == 0) {
            rd_tick(dut, ref, false);
        }
    }
    wait_wr_full(dut, ref);
    wr_tick(dut, ref, true, 0xee);
    wr_tick(dut, ref, false, 0);

    wait_rd_visible(dut, ref);
    drain_all(dut, ref);
    wait_wr_not_full(dut, ref);

    rd_tick(dut, ref, true);
    rd_tick(dut, ref, false);
}

void test_memory_conflict_wraparound(Vfifo_async_mem &dut, AsyncMemScoreboard &ref) {
    drive_reset(dut, ref);
    dut.cfg_almost_full_level = kDepth;
    dut.cfg_almost_empty_level = kDepth - 1;

    uint32_t next = 0x80;
    for (int i = 0; i < 24; ++i) {
        if (!dut.wr_full) {
            wr_tick(dut, ref, true, next++);
        } else {
            wr_tick(dut, ref, false, 0);
        }
        if ((i % 3) != 0) {
            rd_tick(dut, ref, false);
        }
        if (!dut.rd_empty && (i % 2) == 0) {
            rd_tick(dut, ref, true);
        }
    }
    drain_all(dut, ref);
}

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vfifo_async_mem dut;
    AsyncMemScoreboard ref;

    test_independent_reset_and_hold(dut, ref);
    test_async_mem_order_errors_and_read_latency(dut, ref);
    test_memory_conflict_wraparound(dut, ref);

    std::printf("PASS fifo_async_mem DATA_WIDTH=%d DEPTH=%d\n", kDataWidth, kDepth);
    return 0;
}
