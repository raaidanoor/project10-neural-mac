`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb #(
  parameter integer ACCW = 24,
  parameter integer ENTRIES = 16
) ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg host_drives;
  reg [7:0] host_data;
  tri [7:0] shared_bus;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  assign shared_bus = host_drives ? host_data : 8'hzz;
  genvar pin;
  for (pin = 0; pin < 8; pin = pin + 1) begin : bus_driver
    assign shared_bus[pin] = uio_oe[pin] ? uio_out[pin] : 1'bz;
  end
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_raaidanoor_neural_mac
`ifndef GL_TEST
  #(.ACCW(ACCW), .ENTRIES(ENTRIES))
`endif
  user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (shared_bus),
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule
