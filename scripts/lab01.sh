#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs

(
    date -Is
    set -x
    for gate in inverter and_gate; do
        iverilog -g2012 -s "tb_$gate" -o "build/$gate.vvp" "labs/$gate.v" "labs/tb_$gate.v"
        vvp "build/$gate.vvp"
    done
) 2>&1 | tee logs/lab01_sim.txt

(
    date -Is
    set -x
    for gate in inverter and_gate; do
        yosys -Q -p "read_verilog labs/$gate.v; synth -top $gate; check -assert; stat"
    done
) 2>&1 | tee logs/lab01_yosys.txt
