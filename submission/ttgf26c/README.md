# TTGF26c candidate

These files preserve the Stage 8 `repair_final` layout, LEF and powered
gate-level Verilog for `tt_um_raaidanoor_neural_mac`.

| Item | Value |
| --- | --- |
| Stage 8 source revision | `5fd4c95a0a12fe415d7498463bf60bdde3d473ab` |
| Configuration | `cb8_acc16`, 8 codebook entries, 3-bit index, 16-bit accumulator |
| Tile | 1×1 |
| Verified clock period | 60 ns |
| Build and gate-level model PDK | GF180MCU-D `54435919abffb937387ec956209f9cf5fd2dfbee` |
| Shuttle precheck PDK | GF180MCU-D `e8daeda73ca8f5814dbc0b11d1d05802251a3750` |
| Standard-cell library | `gf180mcu_fd_sc_mcu7t5v0` |

From this directory, verify the package with `sha256sum -c candidate.sha256`.
Stage 8 evidence is stored locally under `results/stage8_20261126_5fd4c95/`.
The build lineage is in `s8.5/manifest.md`. Physical checks are documented
in `s8.4/README.md` and the powered regression in `s8.5/README.md`.
