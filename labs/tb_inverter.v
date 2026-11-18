`timescale 1ns/1ps
module tb_inverter;
    reg a;
    wire y;
    inverter dut (.a(a), .y(y));

    initial begin
        $dumpfile("build/inverter.vcd");
        $dumpvars(0, tb_inverter);
        a = 0;
        #1;
        if (y !== 1'b1) $fatal(1, "a=0: expected y=1");
        $display("a=0 y=%b", y);
        a = 1;
        #1;
        if (y !== 1'b0) $fatal(1, "a=1: expected y=0");
        $display("a=1 y=%b", y);
        $display("PASS: inverter");
        $finish;
    end
endmodule
