`default_nettype none

module signed_mac #(
    parameter integer ACCW = 24
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire accumulate,
    input wire signed [7:0] feature,
    input wire signed [7:0] weight,
    output reg signed [ACCW-1:0] total,
    output reg overflow,
    output reg result_valid
);
    wire signed [15:0] product = feature * weight;
    wire signed [ACCW:0] extended_product =
        {{(ACCW-15){product[15]}}, product};
    wire signed [ACCW:0] extended_total = {total[ACCW-1], total};
    wire signed [ACCW:0] sum = extended_total + extended_product;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total <= 0;
            overflow <= 1'b0;
            result_valid <= 1'b0;
        end else if (clear) begin
            total <= 0;
            overflow <= 1'b0;
            result_valid <= 1'b0;
        end else begin
            result_valid <= accumulate;
            if (accumulate) begin
                total <= sum[ACCW-1:0];
                overflow <= overflow | (sum[ACCW] ^ sum[ACCW-1]);
            end
        end
    end
endmodule

`default_nettype wire
