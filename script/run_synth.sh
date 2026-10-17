#!/usr/bin/env bash
# ==============================================================================
# Script  : run_synth.sh
# Purpose : Automated ASIC Synthesis and Static Timing Analysis (STA) Flow
# Tools   : Yosys (Synthesis) + OpenSTA (Timing) + SkyWater 130nm PDK (sky130)
# Usage   :
#   ./script/run_synth.sh [target] [clock_period_ns]
# Examples:
#   ./script/run_synth.sh top               # Synthesize FPU_top @ 100 MHz (10ns)
#   ./script/run_synth.sh adder 5.0         # Synthesize FPU_adder @ 200 MHz (5ns)
#   ./script/run_synth.sh multiplier        # Synthesize FPU_multiplier
#   ./script/run_synth.sh division          # Synthesize FPU_division
#   ./script/run_synth.sh mac               # Synthesize FPU_mac
# ==============================================================================

set -e

# Target Module Mapping
TARGET_INPUT=$(echo "$1" | tr '[:upper:]' '[:lower:]')
CLK_PERIOD_INPUT="$2"

case "$TARGET_INPUT" in
    ""|top|fpu_top)
        export TOP_MODULE="FPU_top"
        ;;
    adder|fpu_adder)
        export TOP_MODULE="FPU_adder"
        ;;
    multiplier|mul|fpu_multiplier)
        export TOP_MODULE="FPU_multiplier"
        ;;
    division|div|fpu_division)
        export TOP_MODULE="FPU_division"
        ;;
    mac|fpu_mac)
        export TOP_MODULE="FPU_mac"
        ;;
    *)
        export TOP_MODULE="$1"
        ;;
esac

# Clock Period Setting (Default: 10.0 ns -> 100 MHz)
if [ -n "$CLK_PERIOD_INPUT" ]; then
    export CLK_PERIOD="$CLK_PERIOD_INPUT"
else
    export CLK_PERIOD="10.00"
fi

export LIB_FILE="sky130.lib"
export SDC_FILE="script/timing.sdc"
export OUTPUT_DIR="synth"

echo "================================================================================"
echo "           ASIC SYNTHESIS & TIMING ANALYSIS FLOW (YOSYS + OPENSTA)"
echo "================================================================================"
echo " Top-Level Module : $TOP_MODULE"
echo " Clock Period     : $CLK_PERIOD ns (~ $(awk "BEGIN {print 1000/$CLK_PERIOD}") MHz)"
echo " Standard Cells   : SkyWater 130nm (sky130_fd_sc_hd)"
echo " Liberty Library  : $LIB_FILE"
echo " Output Directory : $OUTPUT_DIR"
echo "================================================================================"

mkdir -p "$OUTPUT_DIR"

# ------------------------------------------------------------------------------
# STEP 1: Check Prerequisites
# ------------------------------------------------------------------------------
if [ ! -f "$LIB_FILE" ]; then
    echo "Error: Liberty file '$LIB_FILE' not found in workspace root!"
    exit 1
fi

if ! command -v yosys >/dev/null 2>&1; then
    echo "================================================================================"
    echo "Error: 'yosys' command was not found in PATH."
    echo "Please install Yosys using your package manager, e.g.:"
    echo "  Ubuntu/Debian: sudo apt-get install yosys"
    echo "  OSS-CAD-Suite: https://github.com/YosysHQ/oss-cad-suite-build"
    echo "================================================================================"
    exit 1
fi

# ------------------------------------------------------------------------------
# STEP 2: Run Yosys Synthesis
# ------------------------------------------------------------------------------
echo -e "\n[STEP 1/2] Executing Yosys ASIC Synthesis for $TOP_MODULE..."
yosys -c script/synth_yosys.tcl | tee "$OUTPUT_DIR/${TOP_MODULE}_yosys.log"

if [ ! -f "$OUTPUT_DIR/${TOP_MODULE}_netlist.v" ]; then
    echo "Error: Synthesis failed. Gate-level netlist was not generated."
    exit 1
fi
echo ">> Synthesis succeeded! Netlist generated at: $OUTPUT_DIR/${TOP_MODULE}_netlist.v"

# ------------------------------------------------------------------------------
# STEP 3: Run OpenSTA Static Timing Analysis
# ------------------------------------------------------------------------------
STA_CMD=""
if command -v sta >/dev/null 2>&1; then
    STA_CMD="sta"
elif command -v opensta >/dev/null 2>&1; then
    STA_CMD="opensta"
fi

if [ -n "$STA_CMD" ]; then
    echo -e "\n[STEP 2/2] Executing OpenSTA Static Timing Analysis using '$STA_CMD'..."
    $STA_CMD script/sta.tcl | tee "$OUTPUT_DIR/${TOP_MODULE}_opensta.log"
    echo ">> Static Timing Analysis completed! Report saved at: $OUTPUT_DIR/${TOP_MODULE}_sta.rpt"
else
    echo -e "\n[STEP 2/2] OpenSTA ('sta' / 'opensta') executable not found in PATH."
    echo "Skipping automated timing analysis. Netlist is ready for manual OpenSTA run."
    echo "To run OpenSTA manually once installed:"
    echo "  sta script/sta.tcl"
fi

# ------------------------------------------------------------------------------
# STEP 4: Print Summary Table
# ------------------------------------------------------------------------------
echo -e "\n================================================================================"
echo "                             FLOW SUMMARY: $TOP_MODULE"
echo "================================================================================"
echo " Synthesized Netlist : $OUTPUT_DIR/${TOP_MODULE}_netlist.v"
echo " Synthesis Statistics: $OUTPUT_DIR/${TOP_MODULE}_synth.rpt"

if [ -f "$OUTPUT_DIR/${TOP_MODULE}_synth.rpt" ]; then
    echo -e "\nKey Synthesis Metrics (from $OUTPUT_DIR/${TOP_MODULE}_synth.rpt):"
    grep -E "Number of cells:|Chip area for module" "$OUTPUT_DIR/${TOP_MODULE}_synth.rpt" || true
fi

if [ -f "$OUTPUT_DIR/${TOP_MODULE}_sta.rpt" ]; then
    echo " STA Timing Report   : $OUTPUT_DIR/${TOP_MODULE}_sta.rpt"
    echo -e "\nKey Timing Metrics (from $OUTPUT_DIR/${TOP_MODULE}_sta.rpt):"
    grep -E "Worst Setup Slack|Total Setup Slack|Worst Hold Slack" "$OUTPUT_DIR/${TOP_MODULE}_sta.rpt" || true
fi

echo "================================================================================"
echo ">> Flow complete!"
