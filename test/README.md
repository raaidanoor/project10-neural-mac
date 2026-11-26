# Tiny Tapeout pin-level test

Run the tests from this directory with Icarus Verilog and the dependencies in
`requirements.txt` installed for Python 3.12.

```sh
make ENTRIES=8 ACCW=16
```

The testbench resolves the bus from the host driver and the project's eight
output enables. The tests compare the complete result and overflow flag with
`scripts/golden_model.py` and check status, bus ownership, and high impedance
around the readback edges.

For a powered gate-level run, copy the packaged Verilog to
`gate_level_netlist.v`, set `PDK_ROOT` to the directory containing
`gf180mcuD` at the [recorded build revision](../submission/ttgf26c/README.md),
and run `make GATES=yes`. The gate-level harness defaults to eight entries,
a 16-bit accumulator, and a 60 ns clock.

The harness writes `tb.fst` by default. Run `make FST=` for a VCD-format dump
at the same path, and rename it to `tb.vcd` before opening it as a VCD.
