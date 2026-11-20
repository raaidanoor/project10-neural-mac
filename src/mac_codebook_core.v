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
    reg cache_valid;
    reg [$clog2(ENTRIES)-1:0] cached_index;
    reg signed [7:0] cached_weight;
    reg signed [7:0] lookup_weight;
    wire [ENTRIES-1:0] slot_select;
    integer slot;
    integer read_slot;

    assign ready = rst_n && !clear && !write_enable;
    wire accept_pair = valid && ready;
    wire reuse_hit = accept_pair && cache_valid && (index == cached_index);

    // Disable every slot on a hit. Otherwise retain the combinational read probe.
    genvar entry;
    for (entry = 0; entry < ENTRIES; entry = entry + 1) begin : select_slot
        localparam [$clog2(ENTRIES)-1:0] ADDRESS = entry;
        assign slot_select[entry] = !reuse_hit && (index == ADDRESS);
    end

    always @* begin
        lookup_weight = 8'sd0;
        for (read_slot = 0; read_slot < ENTRIES; read_slot = read_slot + 1)
            lookup_weight = lookup_weight | (codebook[read_slot] & {8{slot_select[read_slot]}});
    end

    assign read_weight = reuse_hit ? cached_weight : lookup_weight;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_valid <= 1'b0;
            cached_index <= 0;
            cached_weight <= 8'sd0;
        end else if (clear || write_enable) begin
            cache_valid <= 1'b0;
        end else if (accept_pair && !reuse_hit) begin
            cache_valid <= 1'b1;
            cached_index <= index;
            cached_weight <= lookup_weight;
        end
    end

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
        .accumulate(accept_pair),
        .feature(feature),
        .weight(read_weight),
        .total(total),
        .overflow(overflow),
        .result_valid(result_valid)
    );
endmodule

`default_nettype wire
