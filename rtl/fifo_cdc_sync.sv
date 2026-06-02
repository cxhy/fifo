module fifo_cdc_sync #(
    parameter int WIDTH = 1,
    parameter int STAGES = 2
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] async_i,
    output logic [WIDTH-1:0] sync_o
);

    (* async_reg = "true" *) logic [WIDTH-1:0] sync_chain [0:STAGES-1];

    initial begin
        if (WIDTH <= 0) begin
            $fatal(1, "fifo_cdc_sync: WIDTH must be greater than 0");
        end
        if (STAGES < 2) begin
            $fatal(1, "fifo_cdc_sync: STAGES must be at least 2");
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int stage_idx = 0; stage_idx < STAGES; stage_idx++) begin
                sync_chain[stage_idx] <= '0;
            end
        end else begin
            sync_chain[0] <= async_i;
            for (int stage_idx = 1; stage_idx < STAGES; stage_idx++) begin
                sync_chain[stage_idx] <= sync_chain[stage_idx-1];
            end
        end
    end

    assign sync_o = sync_chain[STAGES-1];

endmodule
