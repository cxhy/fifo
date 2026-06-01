module fifo_async_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16
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

    localparam logic [LEVEL_WIDTH-1:0] DEPTH_LEVEL    = LEVEL_WIDTH'(DEPTH);
    localparam logic [LEVEL_WIDTH:0]   DEPTH_LEVEL_EXT    = (LEVEL_WIDTH + 1)'(DEPTH);
    localparam logic [LEVEL_WIDTH:0]   DEPTH_M1_LEVEL_EXT = (LEVEL_WIDTH + 1)'(DEPTH - 1);

    logic [DATA_WIDTH-1:0]      storage [0:DEPTH-1];

    logic [PTR_WIDTH-1:0]       wr_bin;
    logic [PTR_WIDTH-1:0]       wr_gray;
    logic [PTR_WIDTH-1:0]       wr_gray_rd_sync1;
    logic [PTR_WIDTH-1:0]       wr_gray_rd_sync2;
    logic [PTR_WIDTH-1:0]       wr_bin_rd_sync;

    logic [PTR_WIDTH-1:0]       rd_bin;
    logic [PTR_WIDTH-1:0]       rd_gray;
    logic [PTR_WIDTH-1:0]       rd_gray_wr_sync1;
    logic [PTR_WIDTH-1:0]       rd_gray_wr_sync2;
    logic [PTR_WIDTH-1:0]       rd_bin_wr_sync;

    logic [PTR_WIDTH-1:0]       wr_level_raw;
    logic [PTR_WIDTH-1:0]       rd_level_raw;
    logic [ADDR_WIDTH-1:0]      wr_addr;
    logic [ADDR_WIDTH-1:0]      rd_addr;
    logic [LEVEL_WIDTH:0]       cfg_almost_full_level_ext;
    logic [LEVEL_WIDTH:0]       cfg_almost_empty_level_ext;
    logic                       wr_align_pending;
    logic                       rd_align_pending;

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
    end

    assign rd_bin_wr_sync = gray_to_bin(rd_gray_wr_sync2);
    assign wr_bin_rd_sync = gray_to_bin(wr_gray_rd_sync2);

    assign wr_level_raw = wr_bin - rd_bin_wr_sync;
    assign rd_level_raw = wr_bin_rd_sync - rd_bin;

    assign wr_level = wr_align_pending ? '0 : wr_level_raw[LEVEL_WIDTH-1:0];
    assign rd_level = rd_align_pending ? '0 : rd_level_raw[LEVEL_WIDTH-1:0];

    assign wr_full         = !wr_align_pending && (wr_level == DEPTH_LEVEL);
    assign rd_empty        = rd_align_pending || (rd_level == '0);
    assign wr_almost_full  = (wr_level >= cfg_almost_full_level);
    assign rd_almost_empty = (rd_level <= cfg_almost_empty_level);
    assign cfg_almost_full_level_ext  = {1'b0, cfg_almost_full_level};
    assign cfg_almost_empty_level_ext = {1'b0, cfg_almost_empty_level};

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_wr_sync1 <= rd_gray;
            rd_gray_wr_sync2 <= '0;
            wr_bin          <= '0;
            wr_gray         <= '0;
            wr_align_pending <= 1'b1;
            overflow        <= 1'b0;
        end else begin
            assert ((cfg_almost_full_level_ext >= {{LEVEL_WIDTH{1'b0}}, 1'b1}) &&
                    (cfg_almost_full_level_ext <= DEPTH_LEVEL_EXT))
                else $fatal(1, "fifo_async_mem: cfg_almost_full_level out of range");

            rd_gray_wr_sync1 <= rd_gray;
            rd_gray_wr_sync2 <= rd_gray_wr_sync1;

            if (wr_align_pending) begin
                overflow <= 1'b0;
                wr_bin   <= gray_to_bin(rd_gray_wr_sync1);
                wr_gray  <= rd_gray_wr_sync1;
                wr_align_pending <= 1'b0;
            end else begin
                overflow <= push && wr_full;
            end

            if (!wr_align_pending && push && !wr_full) begin
                storage[wr_addr] <= push_data;
                wr_bin  <= ptr_inc(wr_bin);
                wr_gray <= bin_to_gray(ptr_inc(wr_bin));
            end
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_rd_sync1 <= wr_gray;
            wr_gray_rd_sync2 <= '0;
            rd_bin          <= '0;
            rd_gray         <= '0;
            rd_align_pending <= 1'b1;
            pop_data        <= '0;
            underrun        <= 1'b0;
        end else begin
            assert (cfg_almost_empty_level_ext <= DEPTH_M1_LEVEL_EXT)
                else $fatal(1, "fifo_async_mem: cfg_almost_empty_level out of range");

            wr_gray_rd_sync1 <= wr_gray;
            wr_gray_rd_sync2 <= wr_gray_rd_sync1;

            if (rd_align_pending) begin
                underrun <= 1'b0;
                rd_bin   <= gray_to_bin(wr_gray_rd_sync1);
                rd_gray  <= wr_gray_rd_sync1;
                rd_align_pending <= 1'b0;
            end else begin
                underrun <= pop && rd_empty;
            end

            if (!rd_align_pending && pop && !rd_empty) begin
                pop_data <= storage[rd_addr];
                rd_bin   <= ptr_inc(rd_bin);
                rd_gray  <= bin_to_gray(ptr_inc(rd_bin));
            end
        end
    end

endmodule
