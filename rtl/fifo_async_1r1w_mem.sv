module fifo_async_1r1w_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                         wr_clk,
    input  logic                         wr_rst_n,
    input  logic                         wr_en,
    input  logic [ADDR_WIDTH-1:0]        wr_addr,
    input  logic [DATA_WIDTH-1:0]        wr_data,

    input  logic                         rd_clk,
    input  logic                         rd_rst_n,
    input  logic                         rd_en,
    input  logic [ADDR_WIDTH-1:0]        rd_addr,
    output logic [DATA_WIDTH-1:0]        rd_data
);

    logic [DATA_WIDTH-1:0] storage [0:DEPTH-1];

    initial begin
        if (DATA_WIDTH <= 0) begin
            $fatal(1, "fifo_async_1r1w_mem: DATA_WIDTH must be greater than 0");
        end
        if (DEPTH <= 0) begin
            $fatal(1, "fifo_async_1r1w_mem: DEPTH must be greater than 0");
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "fifo_async_1r1w_mem: DEPTH must be a power of 2");
        end
    end

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
        end else if (wr_en) begin
            storage[wr_addr] <= wr_data;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_data <= '0;
        end else if (rd_en) begin
            rd_data <= storage[rd_addr];
        end
    end

endmodule
