# Stage 5 Tiny Tapeout wrapper verification

Run from the repository root with Icarus Verilog and `uv`. The cocotb runner
uses a temporary environment created from the course Python 3.12 interpreter.
The standalone checks use the course interpreter directly.

## Reproduce the regression

```bash
set -e -o pipefail
stage5_python="$HOME/ccen621/tt-env/bin/python"
"$stage5_python" --version
"$stage5_python" -B -c 'import sys; assert sys.version_info[:2] == (3, 12)'
stage5_evidence=results/stage5_20261120
mkdir -p "$stage5_evidence"
stage5_build=$(mktemp -d)
trap 'rm -r -- "$stage5_build"' EXIT

(
    "$stage5_python" --version
    iverilog -V
    "$stage5_python" -B scripts/golden_model.py
    iverilog -g2012 -Wall -Wno-timescale -s tb_signed_mac \
        -o "$stage5_build/arithmetic" src/signed_mac.v test/tb_signed_mac.v
    vvp "$stage5_build/arithmetic"
    for entries in 8 16 32; do
        iverilog -g2012 -Wall -Wno-timescale -s tb_mac_codebook \
            -Ptb_mac_codebook.ENTRIES="$entries" -o "$stage5_build/codebook" \
            src/signed_mac.v src/mac_codebook_core.v test/tb_mac_codebook.v
        vvp "$stage5_build/codebook"
    done
    "$stage5_python" -B test/check_mac_baseline.py
    for seed in 621 785; do
        "$stage5_python" -B test/check_mac_equivalence.py --seed "$seed" \
            --evidence "$stage5_evidence/standalone_seed$seed"
    done
) 2>&1 | tee "$stage5_evidence/standalone.log"

uv venv --python "$stage5_python" "$stage5_build/venv"
uv pip install --python "$stage5_build/venv/bin/python" -r test/requirements.txt
(
    source "$stage5_build/venv/bin/activate"
    export PYTHONDONTWRITEBYTECODE=1
    python --version
    cocotb-config --version
    git log -1 --format='Base commit %h %s'
    for entries in 8 16 32; do
        for width in 16 24; do
            name="cb${entries}_acc${width}"
            make -C test -B ENTRIES="$entries" ACCW="$width" FST= \
                2>&1 | tee "$stage5_evidence/host_$name.log"
            python -B -m cocotb_tools.check_results test/results.xml
            if [[ "$name" == cb16_acc24 ]]; then
                cp test/tb.fst "$stage5_evidence/host_$name.vcd"
            fi
        done
    done
) 2>&1 | tee "$stage5_evidence/host_regression.log"
```

## Results and evidence

The pin-level tests passed with 8, 16, and 32 entries at both accumulator
widths. They exercised 16- and 32-pair workloads, every programmed index,
repeated indices, signed results, sticky overflow, malformed commands,
cancellation by START, reset, and deselection. The testbench resolves both
drivers on the same eight pins and checks chip output enables and bus
high impedance through both handoffs.

Two products of `(-128) × (-128)` produced `00 80` (−32,768) with overflow
set in 16-bit mode and `00 80 00` (+32,768) with overflow clear in 24-bit
mode. Both readbacks matched the Python model.

The standalone signed MAC, codebook, baseline, and equivalence suites
also passed. Each of the six configurations avoided 75 of 121 directed
lookups. Randomized equivalence passed for 128 pairs per configuration
with each of seeds 621 and 785.

The artifacts are local under `results/stage5_20261120/`, following the
repository's ignored-results convention. This run used Icarus Verilog 10.3
and cocotb 2.1.0 with Python 3.12. The source was the Stage 5 working tree
based on commit `c33e349`.

| Artifact | Contents |
| --- | --- |
| `host_regression.log` | Combined transcript of the six pin-level runs |
| `host_cb16_acc24.log` | Default configuration transcript including the −18 example |
| `host_cb16_acc16.log` | Two-byte readback and signed overflow transcript |
| `host_cb16_acc24.vcd` | Default configuration waveform with host drives, resolved bus, chip output enables, and status |
| `standalone.log` | Signed MAC, codebook, baseline, and indexed equivalence results |
| `standalone_seed621/`, `standalone_seed785/` | Standalone vectors, cache metrics, and default-size waveforms |

## Annotated pin transaction

Open `host_cb16_acc24.vcd` and zoom to 25–285 ns. Inspect `tb.clk`,
`tb.ui_in`, `tb.uo_out`, `tb.host_drives`, `tb.shared_bus`, and
`tb.uio_oe`. The actions in the table use values immediately before
each rising edge. The last three columns show values immediately after
the edge. All byte and status values are hexadecimal.

| Edge (ns) | Action at edge | Bus after edge | Chip OE | Status |
| ---: | --- | --- | --- | --- |
| 35 | Write slot address `03` | Host `03` | `00` | `01` |
| 55 | Write weight `FE` (−2) | Host `FE` | `00` | `01` |
| 75 | Accept START | Released | `00` | `01` |
| 95 | Accept index `03` | Host `03` | `00` | `01` |
| 115 | Accept input `05`, total becomes −10 | Host `05` | `00` | `01` |
| 135 | Accept index `03` again | Host `03` | `00` | `01` |
| 155 | Accept input `04` with LAST, total becomes −18 | Host `04` | `00` | `05` |
| 175 | Accept READ with the host released | Released | `00` | `06` |
| 195 | End handoff to chip | Chip `EE` | `FF` | `16` |
| 215 | Host samples `EE` | Chip `FF` | `FF` | `16` |
| 235 | Host samples `FF` | Chip `FF` | `FF` | `16` |
| 255 | Host samples final `FF` | Released | `00` | `06` |
| 275 | End handoff to host | Released | `00` | `05` |

The host driver stays disabled from before the READ edge through the end
of the return handoff. The test also presents command bits during BUSY
to check that the wrapper ignores them. Immediately before the 155 ns
edge, `tb.user_project.core.reuse_hit` is high and all
`tb.user_project.core.slot_select` bits are low. The cache supplies the
weight for the new input, which contributes −8 to the running total.
