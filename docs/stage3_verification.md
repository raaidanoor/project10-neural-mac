# Stage 3 standalone MAC verification

Run these commands from the repository root with Icarus Verilog and the course Python environment. The bench clocks at 20 ns for functional simulation.

```bash
stage3_evidence=results/stage3_20261120
mkdir -p "$stage3_evidence"
(
    set -e
    ~/ccen621/tt-env/bin/python --version
    iverilog -V | sed -n '1p'
    ~/ccen621/tt-env/bin/python -B scripts/golden_model.py

    stage3_build=$(mktemp -d)
    trap 'rm -r -- "$stage3_build"' EXIT
    iverilog -g2012 -Wall -Wno-timescale -s tb_signed_mac \
        -o "$stage3_build/arithmetic" src/signed_mac.v test/tb_signed_mac.v
    vvp "$stage3_build/arithmetic"

    for entries in 8 16 32; do
        iverilog -g2012 -Wall -Wno-timescale -s tb_mac_codebook \
            -Ptb_mac_codebook.ENTRIES="$entries" -o "$stage3_build/codebook" \
            src/signed_mac.v src/mac_codebook_core.v test/tb_mac_codebook.v
        vvp "$stage3_build/codebook"
    done

    ~/ccen621/tt-env/bin/python -B test/check_mac_baseline.py
    ~/ccen621/tt-env/bin/python -B test/check_mac_equivalence.py --evidence "$stage3_evidence"
) > "$stage3_evidence/regression.log" 2>&1
status=$?
cat "$stage3_evidence/regression.log"
test "$status" -eq 0
```

The paired regression checks 112 accepted operations per configuration across all six combinations of codebook size and accumulator width. Each combination exercises all indices, 16- and 32-input sequences, idle cycles, reset, clear, signed extrema, and positive and negative overflow cases in 16-bit mode. The test checks the running total, sticky overflow and result-valid after each cycle. The explicit weight comes from the software copy of the codebook.

The evidence directory contains the log, generated vectors, and waveforms for both accumulator widths with the default 16-entry codebook. The vector columns are reset_n, clear, write_enable, valid, index, input, explicit weight, expected total, and expected overflow. In the 16-bit waveform, the second consecutive product of 16,384 wraps the total to −32,768 and sets overflow. The same operation produces 32,768 in the 24-bit waveform with overflow clear.
