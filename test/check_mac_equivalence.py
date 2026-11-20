"""Compare both standalone MACs against the Stage 2 model with Icarus."""

import argparse
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from golden_model import calculate


def vectors(entries, width):
    # Independent software copy. RTL lookup is never used to drive the baseline.
    codebook = [-128, 127, -2, 2] + [-125 + 8 * index for index in range(4, entries)]
    yield (0, 0, 0, 0, 0, 0, 0, 0, 0)
    for index, weight in enumerate(codebook):
        yield (1, 0, 1, 0, index, 0, weight, 0, 0)

    signed_features = (-128, -1, 1, 127)
    sequences = [
        [(i % entries, signed_features[i % len(signed_features)]) for i in range(32)],
        [(2, 5), (2, 4)] + [(2, 0)] * 14,
        [(0, -128)] * 32,
        [(0, 127), (1, -128), (3, -128), (2, 1)] + [(1, 0)] * 28,
    ]
    for pairs in sequences:
        yield (1, 1, 0, 0, 0, 0, 0, 0, 0)
        for count, (index, feature) in enumerate(pairs, 1):
            result = calculate(codebook, pairs[:count], width)
            yield (1, 0, 0, 1, index, feature, codebook[index], result.value, int(result.overflow))
            if count == 2:
                yield (1, 0, 0, 0, 0, 127, 127, result.value, int(result.overflow))
    yield (0, 0, 0, 0, 0, 0, 0, 0, 0)


def simulate(directory, entries, width, evidence):
    stem = f"cb{entries}_acc{width}"
    vector_path = (evidence or directory) / f"{stem}.txt"
    vector_path.write_text(
        "".join(" ".join(map(str, row)) + "\n" for row in vectors(entries, width)),
        encoding="utf-8",
    )
    executable = directory / "equivalence.vvp"
    subprocess.run(
        ["iverilog", "-g2012", "-Wall", "-Wno-timescale", "-s", "tb_mac_equivalence",
         f"-Ptb_mac_equivalence.ENTRIES={entries}", f"-Ptb_mac_equivalence.ACCW={width}",
         "-o", executable, "src/signed_mac.v", "src/mac_baseline.v",
         "src/mac_codebook_core.v", "test/tb_mac_equivalence.v"],
        cwd=ROOT, check=True,
    )
    command = ["vvp", executable, f"+vectors={vector_path}"]
    if evidence and entries == 16:
        command.append(f"+waveform={evidence / (stem + '.vcd')}")
    subprocess.run(command, cwd=ROOT, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, help="Save vectors and default-size waveforms here")
    evidence = parser.parse_args().evidence
    if evidence:
        evidence = evidence.resolve()
        evidence.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory() as temporary:
        for entries in (8, 16, 32):
            for width in (16, 24):
                simulate(Path(temporary), entries, width, evidence)
