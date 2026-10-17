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
    echo "  ./run.sh fpu_top"
    echo "  ./run.sh synth [top|adder|multiplier|division|mac]"
    echo "================================================================="
    exit 1
fi

if [ "$TARGET" = "synth" ] || [ "$TARGET" = "synthesis" ]; then
    bash script/run_synth.sh "$2" "$3"
    exit 0
fi

if [ "$TARGET" = "cocotb" ] || [ "$TARGET" = "python" ]; then
    PYTHON_CMD=""
    if command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    elif command -v python.exe >/dev/null 2>&1; then
        PYTHON_CMD="python.exe"
    elif [ -f "/mnt/c/Users/LENOVO/AppData/Local/Programs/Python/Python313/python.exe" ]; then
        PYTHON_CMD="/mnt/c/Users/LENOVO/AppData/Local/Programs/Python/Python313/python.exe"
    elif [ -f "/c/Users/LENOVO/AppData/Local/Programs/Python/Python313/python.exe" ]; then
        PYTHON_CMD="/c/Users/LENOVO/AppData/Local/Programs/Python/Python313/python.exe"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    fi
    $PYTHON_CMD tb/cocotb_tb/run_cocotb.py
    exit 0
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
        TB="tb/CRV_tb/tb_crv_fpu.sv"
        VCD="waveform_crv.vcd"
        MOD_NAME="SystemVerilog Constrained Random Verification CRV (1,000 Iterations / 250+ Per Unit)"
        ;;
    large|large_cases|tb_large)
        RTL="rtl/FPU_top.v rtl/FPU_adder.v rtl/FPU_multiplier.v rtl/FPU_division.v rtl/FPU_mac.v component/param_adder_sub.v component/param_multiplier.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/large_cases/tb_large_cases.sv"
        VCD="waveform_large_cases.vcd"
        MOD_NAME="Massive Regression Suite (2,800+ Test Vectors Across All Units)"
        ;;
    corner_adder|corneradder)
        RTL="rtl/FPU_adder.v component/param_adder_sub.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/corner_case/tb_corner_adder.sv"
        VCD="waveform_corner_adder.vcd"
        MOD_NAME="Corner-Case Regression: FPU Adder (IEEE 754)"
        ;;
    corner_multiplier|cornermultiplier|corner_mul)
        RTL="rtl/FPU_multiplier.v component/param_multiplier.v component/param_adder_sub.v component/barrel_shifter.v"
        TB="tb/corner_case/tb_corner_multiplier.sv"
        VCD="waveform_corner_multiplier.vcd"
        MOD_NAME="Corner-Case Regression: FPU Multiplier (IEEE 754)"
        ;;
    corner_division|cornerdivision|corner_div)
        RTL="rtl/FPU_division.v component/param_adder_sub.v component/barrel_shifter.v"
        TB="tb/corner_case/tb_corner_division.sv"
        VCD="waveform_corner_division.vcd"
        MOD_NAME="Corner-Case Regression: FPU Divider (IEEE 754)"
        ;;
    corner_mac|cornermac)
        RTL="rtl/FPU_mac.v component/param_multiplier.v component/param_adder_sub.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/corner_case/tb_corner_mac.sv"
        VCD="waveform_corner_mac.vcd"
        MOD_NAME="Corner-Case Regression: FPU MAC (IEEE 754)"
        ;;
    corner_top|cornertop|corner|corner_cases)
        RTL="rtl/FPU_top.v rtl/FPU_adder.v rtl/FPU_multiplier.v rtl/FPU_division.v rtl/FPU_mac.v component/param_adder_sub.v component/param_multiplier.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/corner_case/tb_corner_top.sv"
        VCD="waveform_corner_top.vcd"
        MOD_NAME="Corner-Case Regression: Unified FPU Top (IEEE 754)"
        ;;
    sva_adder|svaadder)
        RTL="rtl/FPU_adder.v component/param_adder_sub.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/SVA/sva_adder.sv"
        VCD="waveform_sva_adder.vcd"
        MOD_NAME="SystemVerilog Assertions (SVA) Checker: FPU Adder"
        ;;
    sva_multiplier|svamultiplier|sva_mul)
        RTL="rtl/FPU_multiplier.v component/param_multiplier.v component/param_adder_sub.v component/barrel_shifter.v"
        TB="tb/SVA/sva_multiplier.sv"
        VCD="waveform_sva_multiplier.vcd"
        MOD_NAME="SystemVerilog Assertions (SVA) Checker: FPU Multiplier"
        ;;
    sva_division|svadivision|sva_div)
        RTL="rtl/FPU_division.v component/param_adder_sub.v component/barrel_shifter.v"
        TB="tb/SVA/sva_division.sv"
        VCD="waveform_sva_division.vcd"
        MOD_NAME="SystemVerilog Assertions (SVA) Checker: FPU Divider"
        ;;
    sva_mac|svamac)
        RTL="rtl/FPU_mac.v component/param_multiplier.v component/param_adder_sub.v component/barrel_shifter.v component/leading_zero_detector.v"
        TB="tb/SVA/sva_mac.sv"
        VCD="waveform_sva_mac.vcd"
        MOD_NAME="SystemVerilog Assertions (SVA) Checker: FPU MAC"
        ;;
    *)
        echo "Error: Unknown target '$1'!"
        echo "Valid targets: adder, multiplier, barrel_shifter, LZD, fpu_adder, fpu_multiplier, fpu_division, fpu_mac, top, crv, large, corner_adder, corner_multiplier, corner_division, corner_mac, corner_top, sva_adder, sva_multiplier, sva_division, sva_mac"
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

if [[ "$TARGET" =~ ^sva ]]; then
    echo "[STEP 1/2] Compiling SVA Checker with Verilator (Concurrent Assertions Engine)..."
    verilator --binary --timing -Wall --assert --trace $RTL "$TB" -o sva_sim
    echo ">> SVA Compilation successful!"
    echo "[STEP 2/2] Running SVA simulation with active assertion checks..."
    ./obj_dir/sva_sim
    echo ">> SVA Simulation execution completed successfully!"
else
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
fi

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
