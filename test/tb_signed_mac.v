`timescale 1ns/1ps
`default_nettype none

module tb_signed_mac;
    reg clk = 0;
    reg rst_n = 1;
    reg clear = 0;
    reg accumulate = 0;
    reg signed [7:0] feature = 0;
    reg signed [7:0] weight = 0;
    wire signed [15:0] total16;
    wire signed [23:0] total24;
    wire overflow16, overflow24, valid16, valid24;

    always #10 clk = ~clk;

    signed_mac #(.ACCW(16)) mac16 (
        .clk(clk), .rst_n(rst_n), .clear(clear), .accumulate(accumulate),
        .feature(feature), .weight(weight), .total(total16),
        .overflow(overflow16), .result_valid(valid16)
    );
    signed_mac mac24 (
        .clk(clk), .rst_n(rst_n), .clear(clear), .accumulate(accumulate),
        .feature(feature), .weight(weight), .total(total24),
        .overflow(overflow24), .result_valid(valid24)
    );

    task check_result;
        input signed [15:0] expected16;
        input signed [23:0] expected24;
        input expected_overflow;
        input expected_valid;
        begin
            if (total16 !== expected16 || total24 !== expected24 ||
                overflow16 !== expected_overflow || overflow24 !== 1'b0 ||
                valid16 !== expected_valid || valid24 !== expected_valid)
                $fatal(1, "t=%0t totals=%0d/%0d overflow=%b/%b valid=%b/%b",
                       $time, total16, total24, overflow16, overflow24, valid16, valid24);
        end
    endtask

    task step;
        input clear_next;
        input accumulate_next;
        input signed [7:0] feature_next;
        input signed [7:0] weight_next;
        input signed [15:0] expected16;
        input signed [23:0] expected24;
        input expected_overflow;
        input expected_valid;
        begin
            @(negedge clk);
            clear = clear_next;
            accumulate = accumulate_next;
            feature = feature_next;
            weight = weight_next;
            @(posedge clk);
            #1;
            check_result(expected16, expected24, expected_overflow, expected_valid);
        end
    endtask

    initial begin
        #1 rst_n = 0;
        #1 check_result(0, 0, 0, 0);
        rst_n = 1;

        step(0, 1, 5, -2, -10, -10, 0, 1);
        step(0, 0, -128, -128, -10, -10, 0, 0);
        step(0, 1, 4, -2, -18, -18, 0, 1);
        step(1, 1, 127, 127, 0, 0, 0, 0);
        step(0, 1, -128, -128, 16384, 16384, 0, 1);
        step(0, 1, -128, -128, -32768, 32768, 1, 1);
        step(0, 0, 127, 127, -32768, 32768, 1, 0);
        step(0, 1, 1, 1, -32767, 32769, 1, 1);
        step(1, 0, 0, 0, 0, 0, 0, 0);

        step(0, 1, -128, 127, -16256, -16256, 0, 1);
        step(0, 1, 127, -128, -32512, -32512, 0, 1);
        step(0, 1, -128, 2, -32768, -32768, 0, 1);
        step(0, 1, 1, -1, 32767, -32769, 1, 1);
        #1 rst_n = 0;
        #1 check_result(0, 0, 0, 0);

        $display("PASS: signed MAC in 16- and 24-bit modes");
        $finish;
    end
endmodule

`default_nettype wire
