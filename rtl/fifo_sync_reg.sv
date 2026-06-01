module fifo_sync_reg #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter bit FALL_THROUGH = 1'b0
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         push,
    input  logic [DATA_WIDTH-1:0]        push_data,
    input  logic                         pop,
    output logic [DATA_WIDTH-1:0]        pop_data,

    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_full_level,
    input  logic [$clog2(DEPTH+1)-1:0]   cfg_almost_empty_level,

    output logic                         full,
    output logic                         empty,
    output logic                         almost_full,
    output logic                         almost_empty,
    output logic [$clog2(DEPTH+1)-1:0]   level,

    output logic                         overflow,
    output logic                         underrun
);

    localparam int ADDR_WIDTH  = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int LEVEL_WIDTH = $clog2(DEPTH + 1);

    localparam logic [LEVEL_WIDTH-1:0] DEPTH_LEVEL    = LEVEL_WIDTH'(DEPTH);
    localparam logic [LEVEL_WIDTH:0]   DEPTH_LEVEL_EXT    = (LEVEL_WIDTH + 1)'(DEPTH);
    localparam logic [LEVEL_WIDTH:0]   DEPTH_M1_LEVEL_EXT = (LEVEL_WIDTH + 1)'(DEPTH - 1);

    logic [DATA_WIDTH-1:0]      storage [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0]      wr_ptr;
    logic [ADDR_WIDTH-1:0]      rd_ptr;
    logic [LEVEL_WIDTH:0]       cfg_almost_full_level_ext;
    logic [LEVEL_WIDTH:0]       cfg_almost_empty_level_ext;

    logic                       fall_through_read;
    logic                       storage_pop;
    logic                       storage_push;

    function automatic logic [ADDR_WIDTH-1:0] next_ptr(input logic [ADDR_WIDTH-1:0] ptr);
        if (DEPTH <= 1) begin
            next_ptr = '0;
        end else begin
            next_ptr = ptr + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    initial begin
        if (DATA_WIDTH <= 0) begin
            $fatal(1, "fifo_sync_reg: DATA_WIDTH must be greater than 0");
        end
        if (DEPTH <= 0) begin
            $fatal(1, "fifo_sync_reg: DEPTH must be greater than 0");
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "fifo_sync_reg: DEPTH must be a power of 2");
        end
    end

    assign full         = (level == DEPTH_LEVEL);
    assign empty        = (level == '0);
    assign almost_full  = (level >= cfg_almost_full_level);
    assign almost_empty = (level <= cfg_almost_empty_level);
    assign cfg_almost_full_level_ext  = {1'b0, cfg_almost_full_level};
    assign cfg_almost_empty_level_ext = {1'b0, cfg_almost_empty_level};

    assign fall_through_read = FALL_THROUGH && empty && push && pop;
    assign storage_pop       = pop && !empty;
    assign storage_push      = push && (!full || storage_pop) && !fall_through_read;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= '0;
            rd_ptr    <= '0;
            level     <= '0;
            pop_data  <= '0;
            overflow  <= 1'b0;
            underrun  <= 1'b0;
        end else begin
            assert ((cfg_almost_full_level_ext >= {{LEVEL_WIDTH{1'b0}}, 1'b1}) &&
                    (cfg_almost_full_level_ext <= DEPTH_LEVEL_EXT))
                else $fatal(1, "fifo_sync_reg: cfg_almost_full_level out of range");
            assert (cfg_almost_empty_level_ext <= DEPTH_M1_LEVEL_EXT)
                else $fatal(1, "fifo_sync_reg: cfg_almost_empty_level out of range");

            overflow <= push && full && !pop;
            underrun <= pop && empty && !(FALL_THROUGH && push);

            if (fall_through_read) begin
                pop_data <= push_data;
            end else if (storage_pop) begin
                pop_data <= storage[rd_ptr];
            end

            if (storage_push) begin
                storage[wr_ptr] <= push_data;
            end

            if (storage_push) begin
                wr_ptr <= next_ptr(wr_ptr);
            end
            if (storage_pop) begin
                rd_ptr <= next_ptr(rd_ptr);
            end

            unique case ({storage_push, storage_pop})
                2'b10: level <= level + {{(LEVEL_WIDTH-1){1'b0}}, 1'b1};
                2'b01: level <= level - {{(LEVEL_WIDTH-1){1'b0}}, 1'b1};
                default: level <= level;
            endcase
        end
    end

endmodule
