"""Compare both standalone MACs against the Stage 2 model with Icarus."""

import argparse
import csv
from pathlib import Path
import random
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from golden_model import calculate


def vectors(entries, width):
    # Independent software copy. RTL lookup is never used to drive the baseline.
    codebook = [-128, 127, -2, 2] + [-125 + 8 * index for index in range(4, entries)]
    yield (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    for index, weight in enumerate(codebook):
        yield (1, 0, 1, 0, index, 0, weight, 0, 0, 0)

    signed_features = (-128, -1, 1, 127)
    sequences = [
        [(i % entries, signed_features[i % len(signed_features)]) for i in range(32)],
        [(2, 5), (2, 4)] + [(2, 0)] * 14,
        [(0, -128)] * 32,
        [(0, 127), (1, -128), (3, -128), (2, 1)] + [(1, 0)] * 28,
    ]
    for pairs in sequences:
        yield (1, 1, 0, 0, 0, 0, 0, 0, 0, 0)
        for count, (index, feature) in enumerate(pairs, 1):
            result = calculate(codebook, pairs[:count], width)
            hit = count > 1 and index == pairs[count - 2][0]
            yield (1, 0, 0, 1, index, feature, codebook[index],
                   result.value, int(result.overflow), int(hit))
            if count == 2:
                yield (1, 0, 0, 0, 0, 127, 127, result.value, int(result.overflow), 0)

    # Directed totals across writes use the weight in effect at each acceptance.
    # reset_n, clear, write, valid, index, feature, weight, total, overflow, hit
    yield from (
        (1, 1, 0, 1, 2,   5,   -2,   0, 0, 0),
        (1, 0, 0, 1, 2,   5,   -2, -10, 0, 0),
        (1, 0, 0, 0, 3, 127,    2, -10, 0, 0),
        (1, 0, 0, 1, 2,   4,   -2, -18, 0, 1),
        (1, 0, 1, 1, 3,   4,    1, -18, 0, 0),  # Write a different slot.
        (1, 0, 0, 1, 2,   1,   -2, -20, 0, 0),
        (1, 0, 1, 1, 2,   4,   -1, -20, 0, 0),  # Overwrite the cached slot.
        (1, 0, 0, 1, 2,  -1,   -1, -19, 0, 0),
        (1, 0, 0, 1, 3,   1,    1, -18, 0, 0),
        (1, 0, 0, 1, 2,   1,   -1, -19, 0, 0),
        (1, 1, 1, 1, 2,   1,  127,   0, 0, 0),  # Clear wins over write and valid.
        (1, 0, 0, 1, 2,   1,   -1,  -1, 0, 0),
        (0, 0, 0, 1, 2,   1,   -1,   0, 0, 0),  # Reset between rising edges.
        (1, 0, 0, 1, 2, 127,    0,   0, 0, 0),
        (1, 0, 0, 1, 2,   0,    0,   0, 0, 1),
    )


def randomized_vectors(entries, width, seed):
    rng = random.Random(seed)
    codebook = [rng.randint(-128, 127) for _ in range(entries)]
    yield (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    for index, weight in enumerate(codebook):
        yield (1, 0, 1, 0, index, 0, weight, 0, 0, 0)

    for _ in range(4):
        yield (1, 1, 0, 0, 0, 0, 0, 0, 0, 0)
        pairs = []
        previous_index = rng.randrange(entries)
        result = calculate(codebook, pairs, width)
        for _ in range(32):
            if rng.randrange(4) == 0:
                idle_index = rng.randrange(entries)
                yield (1, 0, 0, 0, idle_index, rng.randint(-128, 127),
                       codebook[idle_index], result.value, int(result.overflow), 0)
            index = previous_index if rng.randrange(3) == 0 else rng.randrange(entries)
            feature = rng.randint(-128, 127)
            hit = bool(pairs) and index == previous_index
            pairs.append((index, feature))
            result = calculate(codebook, pairs, width)
            yield (1, 0, 0, 1, index, feature, codebook[index],
                   result.value, int(result.overflow), int(hit))
            previous_index = index


def selector_transitions(path):
    """Count bit transitions between known VCD values for the two selectors."""
    names = ("tb_mac_equivalence.indexed.slot_select",
             "tb_mac_equivalence.uncached_slot_select")
    scope = []
    codes = {}
    previous = {}
    transitions = dict.fromkeys(names, 0)
    with path.open(encoding="utf-8") as waveform:
        for line in waveform:
            fields = line.split()
            if not fields:
                continue
            if fields[0] == "$scope":
                scope.append(fields[2])
            elif fields[0] == "$upscope":
                scope.pop()
            elif fields[0] == "$var":
                name = ".".join([*scope, fields[4]])
                if name in transitions:
                    codes[fields[3]] = name
            elif fields[0] == "$enddefinitions":
                break
        if set(codes.values()) != set(names):
            raise ValueError(f"Missing selector declarations in {path}")
        for line in waveform:
            if not line.startswith("b"):
                continue
            bits, code = line[1:].split()
            if code not in codes:
                continue
            if "x" in bits or "z" in bits:
                previous.pop(code, None)
                continue
            value = int(bits, 2)
            if code in previous:
                transitions[codes[code]] += (value ^ previous[code]).bit_count()
            previous[code] = value
    return tuple(transitions[name] for name in names)


def run_vectors(directory, evidence, executable, stem, rows, expected_pairs, label, keep_waveform):
    vector_path = (evidence or directory) / f"{stem}.txt"
    lines = [" ".join(map(str, row)) for row in rows]
    vector_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    waveform_dir = evidence if evidence and keep_waveform else directory
    waveform_path = waveform_dir / f"{stem}.vcd"
    command = ["vvp", executable, f"+vectors={vector_path}", f"+expected_pairs={expected_pairs}",
               f"+waveform={waveform_path}"]
    print(f"{stem} ({label})", flush=True)
    run = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True)
    print(run.stdout, end="", flush=True)
    if run.returncode:
        match = re.search(r"\bcycle (\d+)", run.stdout, re.IGNORECASE)
        if match and 1 <= (cycle := int(match[1])) <= len(lines):
            print("reset_n clear write valid index feature weight total overflow hit", file=sys.stderr)
            print(lines[cycle - 1], file=sys.stderr)
        run.check_returncode()
    cached, uncached = selector_transitions(waveform_path)
    print(f"Slot-select bit transitions (VCD) cached={cached} uncached_reference={uncached}")
    counts = re.search(r"Lookups performed=(\d+) avoided=(\d+) reuse_fraction=([\d.]+)",
                       run.stdout)
    if not counts:
        raise ValueError(f"Missing lookup counts for {stem}")
    return (expected_pairs, *counts.groups(), cached, uncached)


def simulate(directory, entries, width, evidence, seed):
    stem = f"cb{entries}_acc{width}"
    executable = directory / "equivalence.vvp"
    subprocess.run(
        ["iverilog", "-g2012", "-Wall", "-Wno-timescale", "-s", "tb_mac_equivalence",
         f"-Ptb_mac_equivalence.ENTRIES={entries}", f"-Ptb_mac_equivalence.ACCW={width}",
         "-o", executable, "src/signed_mac.v", "src/mac_baseline.v",
         "src/mac_codebook_core.v", "test/tb_mac_equivalence.v"],
        cwd=ROOT, check=True,
    )
    directed = run_vectors(directory, evidence, executable, stem, vectors(entries, width),
                           121, "directed", keep_waveform=entries == 16)
    randomized = run_vectors(directory, evidence, executable, f"{stem}_random",
                             randomized_vectors(entries, width, seed), 128, f"seed {seed}",
                             keep_waveform=entries == 16)
    return [(entries, width, "directed", "", *directed),
            (entries, width, "randomized", seed, *randomized)]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, help="Save metrics, vectors, and default-size waveforms here")
    parser.add_argument("--seed", type=int, default=621, help="Randomized vector seed (default: 621)")
    args = parser.parse_args()
    evidence = args.evidence
    if evidence:
        evidence = evidence.resolve()
        evidence.mkdir(parents=True, exist_ok=True)
    metrics = []
    with TemporaryDirectory() as temporary:
        for entries in (8, 16, 32):
            for width in (16, 24):
                metrics.extend(simulate(Path(temporary), entries, width, evidence, args.seed))
    if evidence:
        with (evidence / "cache_hit_counts.csv").open("w", encoding="utf-8", newline="") as output:
            writer = csv.writer(output)
            writer.writerow(("entries", "accumulator_width", "workload", "seed",
                             "accepted_pairs", "lookups_performed", "lookups_avoided", "reuse_fraction",
                             "cached_selector_transitions", "uncached_reference_transitions"))
            writer.writerows(metrics)
