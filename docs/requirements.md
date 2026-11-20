# Project 10 requirements

Course proposal ??1?2, 4.10 and 6 govern the MAC. Lab manual ??3?4 govern the workstation and Lab 01. The master plan supplies milestones and proposed design choices.

| ID | Course requirement | Planned evidence |
| --- | --- | --- |
| MAC-01 | 16-entry register codebook by default, 4-bit index, indexed signed MAC and accumulated result | `src/`, architecture and golden model under `docs/` and `scripts/` |
| MAC-02 | Detect consecutive repeated indices and demonstrate avoided redundant codebook selections | Directed reuse test and reuse counts in `results/` |
| MAC-03 | Compare against the identical MAC fed an explicit full 8-bit weight per operation | Baseline RTL, equal-stimulus tests and comparative tables |
| MAC-04 | Sweep 8/16/32 entries with 3/4/5-bit indices, 16/32 inputs and 16/24-bit accumulator | Parameter manifest, regression and experiment tables |
| IO-01 | Standard Tiny Tapeout wrapper with eight dedicated inputs, eight dedicated outputs, eight bidirectional pins, clock, active-low reset and enable. Drive outputs and output enables deterministically | Wrapper RTL, `info.yaml`, interface tests |
| IO-02 | Configure codebook, stream index/input pairs, read multi-byte output LSB first. Document packet fields, status and turnaround | `docs/protocol_v1.md`, host transaction tests |
| VER-01 | Exercise dictionary writes, every index, repeated indices, negative centroids, reset, idle, overflow, malformed commands and bus contention | `test/`, regression logs and annotated waveforms |
| MET-01 | Report bits per stored weight, cycles per output, reconstruction error, index reuse and placed cell area | Experiment manifests and tables under `results/`, plots under `figures/` |
| PHY-01 | One GF180 tile. Report functional placed area divided by tile and core areas, target at least 60% gross and document infeasibility if needed. Exclude unused padding and physical-only cells | Synthesis and post-CTS/final placement reports and utilization calculations |
| PHY-02 | Report worst setup and hold slack, routing, antenna, DRC/LVS and GDSII | Archived flow reports and GDSII under `results/`, final assessment in `report/` |

Stage 2 evidence is in the [architecture and worked examples](architecture_v1.md), [host protocol](protocol_v1.md), and [Python reference model](../scripts/golden_model.py).

Use paths such as `results/exp_YYYYMMDD_<commit>_cb16_n32_acc24/`. Record tool and PDK revisions, clock period, corner and commands for each physical experiment. Keep a local milestone archive and back up source daily.
