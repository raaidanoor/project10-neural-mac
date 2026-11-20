`default_nettype none

module mac_codebook_core #(
    parameter integer ACCW = 24,
    parameter integer ENTRIES = 16
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire valid,
    output wire ready,
    input wire signed [7:0] feature,
    input wire [$clog2(ENTRIES)-1:0] index,
    input wire write_enable,
    input wire [$clog2(ENTRIES)-1:0] write_index,
    input wire signed [7:0] write_weight,
    output wire signed [7:0] read_weight,
    output wire signed [ACCW-1:0] total,
    output wire overflow,
    output wire result_valid
);
    reg signed [7:0] codebook [0:ENTRIES-1];
    integer slot;

    assign read_weight = codebook[index];
    assign ready = rst_n && !clear && !write_enable;

    // Clear starts a new calculation and preserves the programmed weights.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (slot = 0; slot < ENTRIES; slot = slot + 1)
                codebook[slot] <= 8'sd0;
        end else if (!clear && write_enable) begin
            codebook[write_index] <= write_weight;
        end
    end

    signed_mac #(.ACCW(ACCW)) mac (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .accumulate(valid && ready),
        .feature(feature),
        .weight(read_weight),
        .total(total),
        .overflow(overflow),
        .result_valid(result_valid)
    );
endmodule

`default_nettype wire
