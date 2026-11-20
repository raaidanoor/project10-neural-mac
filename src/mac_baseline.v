`default_nettype none

module mac_baseline #(
    parameter integer ACCW = 24
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire valid,
    output wire ready,
    input wire signed [7:0] feature,
    input wire signed [7:0] weight,
    output wire signed [ACCW-1:0] total,
    output wire overflow,
    output wire result_valid
);
    assign ready = rst_n && !clear;

    signed_mac #(.ACCW(ACCW)) mac (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .accumulate(valid && ready),
        .feature(feature),
        .weight(weight),
        .total(total),
        .overflow(overflow),
        .result_valid(result_valid)
    );
endmodule

`default_nettype wire
