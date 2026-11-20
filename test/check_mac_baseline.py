"""Run from the repository root with Python 3.12 and Icarus Verilog."""

from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from golden_model import calculate


def test_steps(width):
    """Generate RTL checks from the Stage 2 model, using each accepted prefix."""
    codebook = [-128, 127, -2, 0, 1, -1, 2, 5]
    sequences = [
        [(2, 5), (2, 4)],
        [(0, -128)] * 16,
        [(0, 127), (1, -128), (6, -128), (5, 1)] + [(3, 127)] * 28,
        [(index % 8, (-128, -1, 0, 1, 127)[index % 5]) for index in range(32)],
    ]
    for sequence in sequences:
        yield "step(0, 0, 1, 127, 127, 0, 0, 0);"
        yield "step(1, 1, 1, 127, 127, 0, 0, 0);"
        yield "step(1, 0, 0, 127, 127, 0, 0, 0);"
        for count, (index, feature) in enumerate(sequence, 1):
            result = calculate(codebook, sequence[:count], width)
            expected = f"{feature}, {codebook[index]}, {result.value}, {int(result.overflow)}"
            yield f"step(1, 0, 1, {expected}, 1);"
            if count == 2:
                yield f"step(1, 0, 0, {expected}, 0);"


def run(width, directory):
    bench = directory / "tb_baseline.v"
    steps = "\n        ".join(test_steps(width))
    bench.write_text(f"""
`timescale 1ns/1ps
module tb_baseline;
    reg clk = 0;
    reg rst_n = 1, clear = 0, valid = 0;
    reg signed [7:0] feature = 0, weight = 0;
    wire ready, overflow, result_valid;
    wire signed [{width}-1:0] total;

    always #10 clk = ~clk;
    mac_baseline #(.ACCW({width})) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .valid(valid), .ready(ready),
        .feature(feature), .weight(weight), .total(total), .overflow(overflow),
        .result_valid(result_valid)
    );

    task step;
        input reset_n_next, clear_next, valid_next;
        input signed [7:0] feature_next, weight_next;
        input signed [{width}-1:0] expected_total;
        input expected_overflow, expected_valid;
        begin
            @(negedge clk);
            rst_n = reset_n_next;
            clear = clear_next;
            valid = valid_next;
            feature = feature_next;
            weight = weight_next;
            #1;
            if (ready !== (reset_n_next && !clear_next))
                $fatal(1, "t=%0t ready=%b", $time, ready);
            @(posedge clk);
            #1;
            if (total !== expected_total || overflow !== expected_overflow ||
                result_valid !== expected_valid)
                $fatal(1, "t=%0t total=%0d expected=%0d overflow=%b valid=%b",
                       $time, total, expected_total, overflow, result_valid);
        end
    endtask

    initial begin
        {steps}
        $display("PASS: {width}-bit baseline matches Python model");
        $finish;
    end
endmodule
""", encoding="utf-8")

    executable = directory / "baseline.vvp"
    subprocess.run(
        ["iverilog", "-g2012", "-Wall", "-Wno-timescale", "-s", "tb_baseline",
         "-o", executable, "src/signed_mac.v", "src/mac_baseline.v", bench],
        cwd=ROOT, check=True,
    )
    subprocess.run(["vvp", executable], cwd=ROOT, check=True)


if __name__ == "__main__":
    with TemporaryDirectory() as temporary:
        for accumulator_width in (16, 24):
            run(accumulator_width, Path(temporary))
