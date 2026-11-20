# Stage 4 standalone reuse verification

The indexed core caches the last accepted index and decoded signed weight. It disables all codebook slot selects on an accepted hit and multiplies the cached weight by the incoming input. Reset, clear, and every accepted codebook write invalidate the cache. An idle cycle preserves it.

## Reproduce the regression

Run from the repository root. Confirm the first output line reports Python 3.12.

```bash
stage4_evidence=results/stage4_20261120
mkdir -p "$stage4_evidence"
(
    set -e -o pipefail
    ~/ccen621/tt-env/bin/python --version
    iverilog -V
    ~/ccen621/tt-env/bin/python -B scripts/golden_model.py
    stage4_build=$(mktemp -d)
    trap 'rm -r -- "$stage4_build"' EXIT
    iverilog -g2012 -Wall -Wno-timescale -s tb_signed_mac \
        -o "$stage4_build/arithmetic" src/signed_mac.v test/tb_signed_mac.v
    vvp "$stage4_build/arithmetic"
    for entries in 8 16 32; do
        iverilog -g2012 -Wall -Wno-timescale -s tb_mac_codebook \
            -Ptb_mac_codebook.ENTRIES="$entries" -o "$stage4_build/codebook" \
            src/signed_mac.v src/mac_codebook_core.v test/tb_mac_codebook.v
        vvp "$stage4_build/codebook"
    done
    ~/ccen621/tt-env/bin/python -B test/check_mac_baseline.py
    ~/ccen621/tt-env/bin/python -B test/check_mac_equivalence.py --seed 621 --evidence "$stage4_evidence"
    ~/ccen621/tt-env/bin/python -B test/check_mac_equivalence.py --seed 785 --evidence "$stage4_evidence/seed785"
) > "$stage4_evidence/regression.log" 2>&1
status=$?
cat "$stage4_evidence/regression.log"
test "$status" -eq 0
```

The regression passed for 8, 16, and 32 entries with both 16- and 24-bit accumulators. Each configuration exercises 121 directed accepted pairs and 128 randomized accepted pairs per seed. The scoreboard checks running totals, sticky overflow, result-valid, cache hits, and slot selection. The standalone signed MAC, codebook, and explicit-weight baseline checks also pass.

## Evidence

The local evidence directory is `results/stage4_20261120/`. It contains `regression.log`, the seed 621 `cache_hit_counts.csv`, vector files for all configurations, and directed and randomized VCDs for both accumulator widths with 16 entries. The `seed785/` subdirectory contains the second run's metrics, vectors, and waveforms.

The vector columns are reset_n, clear, write_enable, valid, index, input, weight, expected total, expected overflow, and expected reuse hit. On write rows, weight is the value presented to the codebook write port.

Avoided lookups count accepted pairs whose hit signal is asserted and whose slot selects are all off. Reuse fraction divides that count by all accepted pairs. Selector transitions are bit changes between known VCD values over the entire trace, including non-accepting cycles. The comparison signal is a testbench one-hot selector driven by the same index stream and enabled throughout.

| Workload, 16 entries | Accepted pairs | Lookups performed | Lookups avoided | Reuse fraction | Cached selector transitions | Uncached reference transitions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Directed | 121 | 46 | 75 | 61.98% | 137 | 130 |
| Randomized, seed 621 | 128 | 86 | 42 | 32.81% | 277 | 294 |

The directed workload skips lookups while producing more selector transitions than the reference. The randomized workload produces fewer selector transitions. These counts describe the RTL selector signals. Physical switching and power need separate measurement.

## Annotated waveform

Open `cb16_acc16.vcd` and zoom to 2780–2840 ns. Inspect `clk`, `valid`, `index`, `feature`, `indexed.reuse_hit`, `indexed.slot_select`, `indexed.read_weight`, both totals, and both overflow flags. Read the combinational values immediately **before** each rising edge and the totals immediately **after** it. The cache fills on the first edge, so combinational signals can change again after that edge.

| Rising edge | Vector row | Input | Hit before edge | Slot selects before edge | MAC weight before edge | Both totals after edge | Both overflow flags |
| ---: | ---: | --- | ---: | --- | ---: | ---: | ---: |
| 2790 ns | 139 | Index 2, input 5 | 0 | `0x0004` | −2 | −10 | 0 |
| 2810 ns | 140 | Idle, index bus driven to 3 | 0 | `0x0008` | 2 | −10 | 0 |
| 2830 ns | 141 | Index 2, input 4 | 1 | `0x0000` | −2 | −18 | 0 |

The first pair selects slot 2 and saves its weight. The idle cycle leaves the cache and both totals untouched. At the next accepted edge the slot selects are all low, and the new input contributes `4 × (−2) = −8` using the cached weight.
