#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs

pdk_root="${PDK_ROOT:-$HOME/ccen621/pdk}"
pdk_revision=54435919abffb937387ec956209f9cf5fd2dfbee
family=gf180mcu_fd_sc_mcu7t5v0
cell_views="$pdk_root/ciel/gf180mcu/versions/$pdk_revision/gf180mcuD/libs.ref/$family"
liberty="$cell_views/lib/${family}__tt_025C_3v30.lib"
lef="$cell_views/lef/$family.lef"

(
    set -x
    date -Is
    ls -l "$liberty" "$lef"
    for gate in inverter and_gate; do
        yosys -Q -p "read_liberty -lib \"$liberty\"; read_verilog labs/$gate.v; synth -top $gate -noabc; abc -liberty \"$liberty\"; clean; check -assert; stat -liberty \"$liberty\"; write_verilog -noattr build/$gate.gf180.v"
    done
) 2>&1 | tee logs/lab01_yosys_gf180.txt
