/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_raaidanoor_neural_mac #(
    parameter integer ACCW = 24,
    parameter integer ENTRIES = 16
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // High when this project is selected
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    localparam integer INDEX_WIDTH = $clog2(ENTRIES);
    localparam integer LAST_RESULT_BYTE = ACCW / 8 - 1;
    localparam [2:0] BETWEEN_CALCULATIONS = 3'd0,
                     WAIT_WEIGHT          = 3'd1,
                     WAIT_INDEX           = 3'd2,
                     WAIT_INPUT           = 3'd3,
                     HANDOFF_TO_CHIP      = 3'd4,
                     READ_RESULT          = 3'd5,
                     HANDOFF_TO_HOST      = 3'd6;
    localparam [2:0] WRITE = 3'b000, STREAM = 3'b001, READ = 3'b010;

    reg [2:0] state;
    reg [INDEX_WIDTH-1:0] pending_address;
    reg [1:0] result_byte;
    reg done, error;
    wire signed [ACCW-1:0] total;
    wire overflow;

    wire selected = rst_n && ena;
    wire busy = state == HANDOFF_TO_CHIP || state == READ_RESULT ||
                state == HANDOFF_TO_HOST;
    wire ready = selected && !busy;
    wire result_byte_valid = selected && state == READ_RESULT;

    wire [2:0] opcode = ui_in[7:5];
    wire last = ui_in[1];
    wire start = ui_in[0];
    wire command_present = ready && ui_in[2];
    wire framed = command_present && ui_in[4:3] == 2'b00;
    wire write_command = framed && opcode == WRITE && !start && !last;
    wire stream_byte = framed && opcode == STREAM && !start;
    wire address_in_range = uio_in < ENTRIES[7:0];
    wire accept_start = framed && opcode == STREAM && start && !last;
    wire accept_slot = write_command && state == BETWEEN_CALCULATIONS && address_in_range;
    wire accept_weight = write_command && state == WAIT_WEIGHT;
    wire accept_index = stream_byte && state == WAIT_INDEX && !last && address_in_range;
    wire accept_input = stream_byte && state == WAIT_INPUT;
    wire accept_read = framed && opcode == READ && !start && !last &&
                       state == BETWEEN_CALCULATIONS && done;

    mac_codebook_core #(.ACCW(ACCW), .ENTRIES(ENTRIES)) core (
        .clk(clk),
        .rst_n(rst_n),
        .clear(accept_start),
        .valid(accept_input),
        .ready(),
        .feature(uio_in),
        .index(pending_address),
        .write_enable(accept_weight),
        .write_index(pending_address),
        .write_weight(uio_in),
        .read_weight(),
        .total(total),
        .overflow(overflow),
        .result_valid()
    );

    assign uo_out = selected ? {2'b00, overflow, result_byte_valid, error, done, busy, ready}
                             : 8'h00;
    assign uio_out = result_byte_valid ? total[{result_byte, 3'b000} +: 8] : 8'h00;
    assign uio_oe = result_byte_valid ? 8'hff : 8'h00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= BETWEEN_CALCULATIONS;
            pending_address <= 0;
            result_byte <= 0;
            done <= 1'b0;
            error <= 1'b0;
        end else if (!ena) begin
            if (busy)
                state <= BETWEEN_CALCULATIONS;
        end else if (accept_start) begin
            state <= WAIT_INDEX;
            done <= 1'b0;
            error <= 1'b0;
        end else if (accept_slot) begin
            pending_address <= uio_in[INDEX_WIDTH-1:0];
            state <= WAIT_WEIGHT;
        end else if (accept_weight) begin
            state <= BETWEEN_CALCULATIONS;
        end else if (accept_index) begin
            pending_address <= uio_in[INDEX_WIDTH-1:0];
            state <= WAIT_INPUT;
        end else if (accept_input) begin
            if (last) begin
                state <= BETWEEN_CALCULATIONS;
                done <= 1'b1;
            end else begin
                state <= WAIT_INDEX;
            end
        end else if (accept_read) begin
            result_byte <= 0;
            state <= HANDOFF_TO_CHIP;
        end else begin
            case (state)
                HANDOFF_TO_CHIP: state <= READ_RESULT;
                READ_RESULT: begin
                    if (result_byte == LAST_RESULT_BYTE[1:0])
                        state <= HANDOFF_TO_HOST;
                    else
                        result_byte <= result_byte + 1'b1;
                end
                HANDOFF_TO_HOST: state <= BETWEEN_CALCULATIONS;
                default: if (command_present)
                    error <= 1'b1;
            endcase
        end
    end

endmodule

`default_nettype wire
