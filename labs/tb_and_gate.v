`timescale 1ns/1ps
module tb_and_gate;
    reg a, b;
    wire y;
    integer pattern;
    and_gate dut (.a(a), .b(b), .y(y));

    initial begin
        for (pattern = 0; pattern < 4; pattern = pattern + 1) begin
            {a, b} = pattern[1:0];
            #1;
            if (y !== (pattern == 3))
                $fatal(1, "AND mismatch: a=%b b=%b y=%b", a, b, y);
            $display("a=%b b=%b y=%b", a, b, y);
        end
        $display("PASS: AND gate");
        $finish;
    end
endmodule
