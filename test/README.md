# Tiny Tapeout pin-level test

Run the tests from this directory with Icarus Verilog and the dependencies in
`requirements.txt` installed for Python 3.12.

```sh
make
```

The hardware defaults are 16 codebook entries and a 24-bit accumulator.
You can override the RTL parameters with `make ENTRIES=8 ACCW=16`, for example.
The testbench resolves the bus from the host driver and the project's eight
output enables. The tests compare the complete result and overflow flag with
`scripts/golden_model.py` and check status, bus ownership, and high impedance
around the readback edges.

For a gate-level run, place the default-configuration netlist at
`gate_level_netlist.v`, set `PDK_ROOT`, and run `make GATES=yes`.

The harness writes `tb.fst` by default. Run `make FST=` for a VCD-format dump
at the same path, and rename it to `tb.vcd` before opening it as a VCD.
