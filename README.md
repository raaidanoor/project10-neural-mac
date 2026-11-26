# Codebook-Shared Neural MAC

Tiny Tapeout TTGF26c submission for `tt_um_raaidanoor_neural_mac`, a
GF180MCU-D 1×1 tile. The design uses eight programmable signed 8-bit weights,
a 3-bit index, and a 16-bit accumulator. The layout was verified at 60 ns.

- [Datasheet and host interface](docs/info.md)
- [Signed-off layout, LEF, powered netlist, and checksums](submission/ttgf26c/)
- [RTL and powered gate-level test instructions](test/README.md)

The [GDS workflow](.github/workflows/gds.yaml) publishes the frozen candidate
as `tt_submission`. It checks the package before upload and checks the
downloaded artifact before running the powered gate-level regression.
