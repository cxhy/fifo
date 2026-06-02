module fifo_sync_1r1w_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         wr_en,
    input  logic [ADDR_WIDTH-1:0]        wr_addr,
    input  logic [DATA_WIDTH-1:0]        wr_data,

    input  logic                         rd_en,
    input  logic [ADDR_WIDTH-1:0]        rd_addr,
    output logic [DATA_WIDTH-1:0]        rd_data
);

    logic [DATA_WIDTH-1:0] storage [0:DEPTH-1];

    initial begin
        if (DATA_WIDTH <= 0) begin
            $fatal(1, "fifo_sync_1r1w_mem: DATA_WIDTH must be greater than 0");
        end
        if (DEPTH <= 0) begin
            $fatal(1, "fifo_sync_1r1w_mem: DEPTH must be greater than 0");
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "fifo_sync_1r1w_mem: DEPTH must be a power of 2");
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data <= '0;
        end else begin
            if (rd_en) begin
                rd_data <= storage[rd_addr];
            end
            if (wr_en) begin
                storage[wr_addr] <= wr_data;
            end
        end
    end

endmodule
