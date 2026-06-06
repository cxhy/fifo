module fifo_async_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int CDC_SYNC_STAGES = 2
) (
    input  logic                         wr_clk,
    input  logic                         wr_rst_n,
    input  logic                         push,
    input  logic [DATA_WIDTH-1:0]        push_data,
    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_full_level,
    output logic                         wr_full,
    output logic                         wr_almost_full,
    output logic [$clog2(DEPTH+1)-1:0]   wr_level,
    output logic                         overflow,

    input  logic                         rd_clk,
    input  logic                         rd_rst_n,
    input  logic                         pop,
    output logic [DATA_WIDTH-1:0]        pop_data,
    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_empty_level,
    output logic                         rd_empty,
    output logic                         rd_almost_empty,
    output logic [$clog2(DEPTH+1)-1:0]   rd_level,
    output logic                         underrun
);

    localparam int ADDR_WIDTH  = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int PTR_WIDTH   = (DEPTH <= 1) ? 1 : (ADDR_WIDTH + 1);
    localparam int LEVEL_WIDTH = $clog2(DEPTH + 1);
    localparam int ALIGN_COUNT_WIDTH = $clog2(CDC_SYNC_STAGES + 1);

    localparam logic [LEVEL_WIDTH-1:0] DEPTH_LEVEL    = LEVEL_WIDTH'(DEPTH);
    localparam logic [PTR_WIDTH-1:0]   DEPTH_PTR      = PTR_WIDTH'(DEPTH);
    localparam logic [LEVEL_WIDTH:0]   DEPTH_LEVEL_EXT    = (LEVEL_WIDTH + 1)'(DEPTH);
    localparam logic [LEVEL_WIDTH:0]   DEPTH_M1_LEVEL_EXT = (LEVEL_WIDTH + 1)'(DEPTH - 1);
    localparam logic [ALIGN_COUNT_WIDTH-1:0] ALIGN_COUNT_LAST =
        ALIGN_COUNT_WIDTH'(CDC_SYNC_STAGES - 1);

    logic [PTR_WIDTH-1:0]       wr_bin;
    logic [PTR_WIDTH-1:0]       wr_gray;
    logic [PTR_WIDTH-1:0]       wr_gray_rd_sync;
    logic [PTR_WIDTH-1:0]       wr_bin_rd_sync;

    logic [PTR_WIDTH-1:0]       rd_bin;
    logic [PTR_WIDTH-1:0]       rd_gray;
    logic [PTR_WIDTH-1:0]       rd_gray_wr_sync;
    logic [PTR_WIDTH-1:0]       rd_bin_wr_sync;

    logic [PTR_WIDTH-1:0]       wr_level_raw;
    logic [PTR_WIDTH-1:0]       rd_level_raw;
    logic [LEVEL_WIDTH-1:0]     wr_level_clamped;
    logic [LEVEL_WIDTH-1:0]     rd_level_clamped;
    logic [ADDR_WIDTH-1:0]      wr_addr;
    logic [ADDR_WIDTH-1:0]      rd_addr;
    logic [DATA_WIDTH-1:0]      mem_rd_data;
    logic [LEVEL_WIDTH:0]       cfg_almost_full_level_ext;
    logic [LEVEL_WIDTH:0]       cfg_almost_empty_level_ext;
    logic                       wr_reset_done;
    logic                       rd_reset_done;
    logic                       rd_reset_done_wr_sync;
    logic                       wr_reset_done_rd_sync;
    logic                       wr_flush_active;
    logic                       rd_flush_active;
    logic                       overflow_q;
    logic                       underrun_q;
    logic                       wr_align_pending;
    logic                       rd_align_pending;
    logic [ALIGN_COUNT_WIDTH-1:0] wr_align_count;
    logic [ALIGN_COUNT_WIDTH-1:0] rd_align_count;

    function automatic logic [PTR_WIDTH-1:0] bin_to_gray(input logic [PTR_WIDTH-1:0] bin);
        bin_to_gray = (bin >> 1) ^ bin;
    endfunction

    function automatic logic [PTR_WIDTH-1:0] gray_to_bin(input logic [PTR_WIDTH-1:0] gray);
        gray_to_bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
        for (int i = PTR_WIDTH - 2; i >= 0; i--) begin
            gray_to_bin[i] = gray_to_bin[i+1] ^ gray[i];
        end
    endfunction

    function automatic logic [PTR_WIDTH-1:0] ptr_inc(input logic [PTR_WIDTH-1:0] ptr);
        ptr_inc = ptr + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
    endfunction

    function automatic logic [LEVEL_WIDTH-1:0] clamp_level(input logic [PTR_WIDTH-1:0] level_raw);
        if (level_raw > DEPTH_PTR) begin
            clamp_level = DEPTH_LEVEL;
        end else begin
            clamp_level = level_raw[LEVEL_WIDTH-1:0];
        end
    endfunction

    generate
        if (DEPTH == 1) begin : gen_single_entry_addr
            assign wr_addr = '0;
            assign rd_addr = '0;
        end else begin : gen_multi_entry_addr
            assign wr_addr = wr_bin[ADDR_WIDTH-1:0];
            assign rd_addr = rd_bin[ADDR_WIDTH-1:0];
        end
    endgenerate

    initial begin
        if (DATA_WIDTH <= 0) begin
            $fatal(1, "fifo_async_mem: DATA_WIDTH must be greater than 0");
        end
        if (DEPTH <= 0) begin
            $fatal(1, "fifo_async_mem: DEPTH must be greater than 0");
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "fifo_async_mem: DEPTH must be a power of 2");
        end
        if (CDC_SYNC_STAGES < 2) begin
            $fatal(1, "fifo_async_mem: CDC_SYNC_STAGES must be at least 2");
        end
    end

    fifo_cdc_sync #(
        .WIDTH(PTR_WIDTH),
        .STAGES(CDC_SYNC_STAGES)
    ) u_rd_gray_wr_sync (
        .clk(wr_clk),
        .rst_n(wr_rst_n),
        .async_i(rd_gray),
        .sync_o(rd_gray_wr_sync)
    );

    fifo_cdc_sync #(
        .WIDTH(PTR_WIDTH),
        .STAGES(CDC_SYNC_STAGES)
    ) u_wr_gray_rd_sync (
        .clk(rd_clk),
        .rst_n(rd_rst_n),
        .async_i(wr_gray),
        .sync_o(wr_gray_rd_sync)
    );

    fifo_cdc_sync #(
        .WIDTH(1),
        .STAGES(CDC_SYNC_STAGES)
    ) u_rd_reset_done_wr_sync (
        .clk(wr_clk),
        .rst_n(wr_rst_n),
        .async_i(rd_reset_done),
        .sync_o(rd_reset_done_wr_sync)
    );

    fifo_cdc_sync #(
        .WIDTH(1),
        .STAGES(CDC_SYNC_STAGES)
    ) u_wr_reset_done_rd_sync (
        .clk(rd_clk),
        .rst_n(rd_rst_n),
        .async_i(wr_reset_done),
        .sync_o(wr_reset_done_rd_sync)
    );

    fifo_async_1r1w_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_mem (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .wr_en(!wr_flush_active && push && !wr_full),
        .wr_addr(wr_addr),
        .wr_data(push_data),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .rd_en(!rd_flush_active && pop && !rd_empty),
        .rd_addr(rd_addr),
        .rd_data(mem_rd_data)
    );

    assign pop_data = mem_rd_data;

    assign rd_bin_wr_sync = gray_to_bin(rd_gray_wr_sync);
    assign wr_bin_rd_sync = gray_to_bin(wr_gray_rd_sync);

    assign wr_level_raw = wr_bin - rd_bin_wr_sync;
    assign rd_level_raw = wr_bin_rd_sync - rd_bin;
    assign wr_level_clamped = clamp_level(wr_level_raw);
    assign rd_level_clamped = clamp_level(rd_level_raw);

    assign wr_flush_active = wr_align_pending || !rd_reset_done_wr_sync;
    assign rd_flush_active = rd_align_pending || !wr_reset_done_rd_sync;

    assign wr_level = wr_flush_active ? DEPTH_LEVEL : wr_level_clamped;
    assign rd_level = rd_flush_active ? '0 : rd_level_clamped;

    assign wr_full         = wr_flush_active || (wr_level == DEPTH_LEVEL);
    assign rd_empty        = rd_flush_active || (rd_level == '0);
    assign wr_almost_full  = (wr_level >= cfg_almost_full_level);
    assign rd_almost_empty = (rd_level <= cfg_almost_empty_level);
    assign overflow        = wr_flush_active ? 1'b0 : overflow_q;
    assign underrun        = rd_flush_active ? 1'b0 : underrun_q;
    assign cfg_almost_full_level_ext  = {1'b0, cfg_almost_full_level};
    assign cfg_almost_empty_level_ext = {1'b0, cfg_almost_empty_level};

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_reset_done  <= 1'b0;
            wr_bin          <= '0;
            wr_gray         <= '0;
            wr_align_pending <= 1'b1;
            wr_align_count  <= '0;
            overflow_q      <= 1'b0;
        end else begin
            wr_reset_done <= 1'b1;

            assert ((cfg_almost_full_level_ext >= {{LEVEL_WIDTH{1'b0}}, 1'b1}) &&
                    (cfg_almost_full_level_ext <= DEPTH_LEVEL_EXT))
                else $fatal(1, "fifo_async_mem: cfg_almost_full_level out of range");

            if (!rd_reset_done_wr_sync) begin
                wr_bin <= '0;
                wr_gray <= '0;
                wr_align_pending <= 1'b1;
                wr_align_count <= '0;
                overflow_q <= 1'b0;
            end else if (wr_align_pending) begin
                wr_bin <= '0;
                wr_gray <= '0;
                overflow_q <= 1'b0;
                if (wr_align_count == ALIGN_COUNT_LAST) begin
                    wr_align_pending <= 1'b0;
                    wr_align_count <= '0;
                end else begin
                    wr_align_count <= wr_align_count + {{(ALIGN_COUNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end else begin
                overflow_q <= push && wr_full;

                if (push && !wr_full) begin
                    wr_bin  <= ptr_inc(wr_bin);
                    wr_gray <= bin_to_gray(ptr_inc(wr_bin));
                end
            end
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_reset_done  <= 1'b0;
            rd_bin          <= '0;
            rd_gray         <= '0;
            rd_align_pending <= 1'b1;
            rd_align_count  <= '0;
            underrun_q      <= 1'b0;
        end else begin
            rd_reset_done <= 1'b1;

            assert (cfg_almost_empty_level_ext <= DEPTH_M1_LEVEL_EXT)
                else $fatal(1, "fifo_async_mem: cfg_almost_empty_level out of range");

            if (!wr_reset_done_rd_sync) begin
                rd_bin <= '0;
                rd_gray <= '0;
                rd_align_pending <= 1'b1;
                rd_align_count <= '0;
                underrun_q <= 1'b0;
            end else if (rd_align_pending) begin
                rd_bin <= '0;
                rd_gray <= '0;
                underrun_q <= 1'b0;
                if (rd_align_count == ALIGN_COUNT_LAST) begin
                    rd_align_pending <= 1'b0;
                    rd_align_count <= '0;
                end else begin
                    rd_align_count <= rd_align_count + {{(ALIGN_COUNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end else begin
                underrun_q <= pop && rd_empty;

                if (pop && !rd_empty) begin
                    rd_bin   <= ptr_inc(rd_bin);
                    rd_gray  <= bin_to_gray(ptr_inc(rd_bin));
                end
            end
        end
    end

endmodule
