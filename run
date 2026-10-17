#!/usr/bin/env bash
# ==============================================================================
# Script  : run.sh
# Purpose : Dynamic compilation, simulation, and GTKWave launcher for FPU units
# Usage   :
#   ./run.sh adder          -> Simulates param_adder_sub & opens GTKWave
#   ./run.sh multiplier     -> Simulates param_multiplier & opens GTKWave
#   ./run.sh barrel_shifter -> Simulates barrel_shifter & opens GTKWave
#   ./run.sh LZD            -> Simulates leading_zero_detector & opens GTKWave
# ==============================================================================

set -e  # Exit immediately if any command returns a non-zero error code

# 1. Check target argument
TARGET=$(echo "$1" | tr '[:upper:]' '[:lower:]')

if [ -z "$TARGET" ]; then
    echo "================================================================="
    echo "Error: No target module specified!"
    echo "Usage: ./run.sh <target>"
    echo "Available targets:"
    echo "  ./run.sh adder"
    echo "  ./run.sh multiplier"
    echo "  ./run.sh barrel_shifter"
    echo "  ./run.sh LZD"
    echo "================================================================="
    exit 1
fi

# 2. Map target to RTL, Testbench, and VCD output
case "$TARGET" in
    adder|param_adder_sub)
        RTL="component/param_adder_sub.v"
        TB="tb/sim_tb/tb_adder.v"
        VCD="waveform_adder.vcd"
        MOD_NAME="Parameterized Adder-Subtractor"
        ;;
    multiplier|param_multiplier|mul)
        RTL="component/param_multiplier.v"
        TB="tb/sim_tb/tb_multiplier.v"
        VCD="waveform_multiplier.vcd"
        MOD_NAME="Parameterized Multiplier"
        ;;
    barrel_shifter|shifter|barrel)
        RTL="component/barrel_shifter.v"
        TB="tb/sim_tb/tb_barrel_shifter.v"
        VCD="waveform_barrel_shifter.vcd"
        MOD_NAME="Parameterized Barrel Shifter"
        ;;
    lzd|leading_zero_detector)
        RTL="component/leading_zero_detector.v"
        TB="tb/sim_tb/tb_LZD.v"
        VCD="waveform_lzd.vcd"
        MOD_NAME="Leading Zero Detector"
        ;;
    fpu_adder|fpuadder)
        RTL="rtl/FPU_adder.v component/param_adder_sub.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/sim_tb/tb_fpu_adder.v"
        VCD="waveform_fpu_adder.vcd"
        MOD_NAME="Modular FPU Adder (IEEE 754)"
        ;;
    fpu_multiplier|fpumultiplier|fpumul)
        RTL="rtl/FPU_multiplier.v component/param_multiplier.v component/param_adder_sub.v component/barrel_shifter.v"
        TB="tb/sim_tb/tb_fpu_multiplier.v"
        VCD="waveform_fpu_multiplier.vcd"
        MOD_NAME="Modular FPU Multiplier (IEEE 754)"
        ;;
    fpu_division|fpudivision|fpudiv|div)
        RTL="rtl/FPU_division.v component/param_adder_sub.v component/barrel_shifter.v"
        TB="tb/sim_tb/tb_fpu_division.v"
        VCD="waveform_fpu_division.vcd"
        MOD_NAME="Modular FPU Divider (IEEE 754)"
        ;;
    fpu_mac|fpumac|mac)
        RTL="rtl/FPU_mac.v component/param_multiplier.v component/param_adder_sub.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/sim_tb/tb_fpu_mac.v"
        VCD="waveform_fpu_mac.vcd"
        MOD_NAME="Modular FPU MAC / FMA (IEEE 754)"
        ;;
    top|fpu_top|all)
        RTL="rtl/FPU_top.v rtl/FPU_adder.v rtl/FPU_multiplier.v rtl/FPU_division.v rtl/FPU_mac.v component/input_convertor.v component/output_convertor.v component/param_adder_sub.v component/param_multiplier.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/sim_tb/tb_fpu_top.v"
        VCD="waveform_fpu_top.vcd"
        MOD_NAME="FPU Full Suite Regression (180+ Tests)"
        ;;
    crv|tb_crv_fpu|tb_crv)
        RTL="rtl/FPU_top.v rtl/FPU_adder.v rtl/FPU_multiplier.v rtl/FPU_division.v rtl/FPU_mac.v component/param_adder_sub.v component/param_multiplier.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/CRV_tb/tb_crv_fpu.v"
        VCD="waveform_crv.vcd"
        MOD_NAME="Constrained Random Verification CRV (1,000 Iterations / 250+ Per Unit)"
        ;;
    *)
        echo "Error: Unknown target '$1'!"
        echo "Valid targets: adder, multiplier, barrel_shifter, LZD, fpu_adder, fpu_multiplier, fpu_division, fpu_mac, top, crv"
        exit 1
        ;;
esac

echo "================================================================="
echo "Running verification flow for: $MOD_NAME"
echo "RTL Source : $RTL"
echo "Testbench  : $TB"
echo "Waveform   : $VCD"
echo "================================================================="

# Clean any existing VCD
rm -f "$VCD" sim.vvp

# 3. Optional Verilator Lint Stage
if command -v verilator >/dev/null 2>&1; then
    echo "[STEP 1/3] Running Verilator lint check..."
    verilator --lint-only -Wall --timing $RTL "$TB"
    echo ">> Verilator lint check passed!"
else
    echo "[STEP 1/3] Verilator not found in PATH; skipping Verilator lint."
fi

# 4. Icarus Verilog Compilation Stage
echo "[STEP 2/3] Compiling with Icarus Verilog (iverilog)..."
iverilog -Wall -g2012 -o sim.vvp "$TB" $RTL
echo ">> Compilation successful!"

# 5. Simulation Execution Stage
echo "[STEP 3/3] Running simulation (vvp)..."
vvp sim.vvp
echo ">> Simulation execution completed successfully!"

# 6. Launch GTKWave
if [ -f "$VCD" ]; then
    echo "================================================================="
    echo "Opening GTKWave with waveform: $VCD"
    echo "================================================================="

    # Locate gtkwave executable
    if command -v gtkwave >/dev/null 2>&1; then
        gtkwave "$VCD" &
    elif command -v gtkwave.exe >/dev/null 2>&1; then
        gtkwave.exe "$VCD" &
    elif [ -f "/d/iverilog/gtkwave/bin/gtkwave.exe" ]; then
        /d/iverilog/gtkwave/bin/gtkwave.exe "$VCD" &
    elif [ -f "D:/iverilog/gtkwave/bin/gtkwave.exe" ]; then
        "D:/iverilog/gtkwave/bin/gtkwave.exe" "$VCD" &
    else
        echo "Warning: gtkwave executable not found in PATH. Waveform saved at $VCD"
    fi
else
    echo "Error: Waveform file $VCD was not generated by testbench!"
    exit 1
fi

rm -f sim.vvp
echo ">> Done!"
