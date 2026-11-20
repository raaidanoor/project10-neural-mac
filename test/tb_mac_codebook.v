`timescale 1ns/1ps
`default_nettype none

module tb_mac_codebook;
    parameter integer ENTRIES = 16;
    localparam integer INDEX_WIDTH = $clog2(ENTRIES);

    reg clk = 0;
    reg rst_n = 1;
    reg clear = 0;
    reg valid = 0;
    reg write_enable = 0;
    reg [INDEX_WIDTH-1:0] index = 0, write_index = 0;
    reg signed [7:0] write_weight = 0;
    wire signed [7:0] read_weight;
    wire signed [23:0] total;
    wire ready, overflow, result_valid;
    integer slot;

    always #10 clk = ~clk;

    mac_codebook_core #(.ENTRIES(ENTRIES)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .valid(valid), .ready(ready),
        .feature(8'sd5), .index(index), .write_enable(write_enable),
        .write_index(write_index), .write_weight(write_weight),
        .read_weight(read_weight), .total(total), .overflow(overflow),
        .result_valid(result_valid)
    );

    task check_slot;
        input [INDEX_WIDTH-1:0] address;
        input signed [7:0] expected;
        begin
            index = address;
            #1;
            if (read_weight !== expected)
                $fatal(1, "slot %0d read %0d, expected %0d", index, read_weight, expected);
        end
    endtask

    task write_slot;
        input [INDEX_WIDTH-1:0] address;
        input signed [7:0] value;
        begin
            @(negedge clk);
            index = address;
            write_index = address;
            write_weight = value;
            write_enable = 1;
            valid = 1;
            #1;
            if (ready !== 1'b0)
                $fatal(1, "MAC ready during write");
            @(posedge clk);
            #1;
            if (result_valid !== 1'b0 || total !== 24'sd0 || overflow !== 1'b0)
                $fatal(1, "MAC state changed during write");
            check_slot(address, value);
        end
    endtask

    initial begin
        #1 rst_n = 0;
        #1;
        if (ready !== 1'b0)
            $fatal(1, "MAC ready during reset");
        for (slot = 0; slot < ENTRIES; slot = slot + 1)
            check_slot(slot, 0);
        @(negedge clk);
        rst_n = 1;

        for (slot = 0; slot < ENTRIES; slot = slot + 1)
            write_slot(slot, -128 + 8 * slot);
        write_slot(0, -2);

        @(negedge clk);
        write_enable = 0;
        valid = 0;
        for (slot = 1; slot < ENTRIES; slot = slot + 1)
            check_slot(slot, -128 + 8 * slot);

        @(negedge clk);
        clear = 1;
        write_enable = 1;
        write_index = 0;
        write_weight = 127;
        @(posedge clk);
        check_slot(0, -2);

        @(negedge clk);
        clear = 0;
        write_enable = 0;
        valid = 1;
        #1;
        if (ready !== 1'b1)
            $fatal(1, "MAC blocked after write");
        @(posedge clk);
        #1;
        if (result_valid !== 1'b1 || total !== -24'sd10 || overflow !== 1'b0)
            $fatal(1, "MAC did not consume the selected signed weight");

        #1 rst_n = 0;
        #1;
        if (total !== 24'sd0 || result_valid !== 1'b0 || overflow !== 1'b0)
            $fatal(1, "reset did not clear the MAC");
        for (slot = 0; slot < ENTRIES; slot = slot + 1)
            check_slot(slot, 0);

        $display("PASS: %0d-entry codebook", ENTRIES);
        $finish;
    end
endmodule

`default_nettype wire
