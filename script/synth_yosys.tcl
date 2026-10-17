# ==============================================================================
# Script  : synth_yosys.tcl
# Tool    : Yosys Open SYnthesis Suite
# Target  : SkyWater 130nm High-Density Standard Cell Library (sky130_fd_sc_hd)
# Purpose : ASIC RTL-to-Gate-Level Synthesis for IEEE 754 Floating-Point Units
# Usage   : yosys -c script/synth_yosys.tcl
#           (Environment variables TOP_MODULE and LIB_FILE can override defaults)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Environment and Configuration Variables
# ------------------------------------------------------------------------------
if {[info exists env(TOP_MODULE)]} {
    set TOP_MODULE $env(TOP_MODULE)
} else {
    set TOP_MODULE "FPU_top"
}

if {[info exists env(LIB_FILE)]} {
    set LIB_FILE $env(LIB_FILE)
} else {
    set LIB_FILE "sky130.lib"
}

if {[info exists env(OUTPUT_DIR)]} {
    set OUTPUT_DIR $env(OUTPUT_DIR)
} else {
    set OUTPUT_DIR "synth"
}

file mkdir $OUTPUT_DIR

puts "========================================================================"
puts "  STARTING ASIC SYNTHESIS FLOW (YOSYS + SKY130)"
puts "  Top Module  : $TOP_MODULE"
puts "  Target PDK  : SkyWater 130nm (sky130_fd_sc_hd)"
puts "  Liberty File: $LIB_FILE"
puts "  Output Dir  : $OUTPUT_DIR"
puts "========================================================================"

# ------------------------------------------------------------------------------
# 2. Read Verilog RTL Source Files
# ------------------------------------------------------------------------------
puts "\n[STEP 1/6] Reading RTL source files..."

# Foundational Parameterized Components
read_verilog -sv component/param_adder_sub.v
read_verilog -sv component/param_multiplier.v
read_verilog -sv component/barrel_shifter.v
read_verilog -sv component/leading_zero_detector.v
read_verilog -sv component/input_convertor.v
read_verilog -sv component/output_convertor.v

# 4-Stage Synchronous Pipelined Arithmetic Engines
read_verilog -sv rtl/FPU_adder.v
read_verilog -sv rtl/FPU_multiplier.v
read_verilog -sv rtl/FPU_division.v
read_verilog -sv rtl/FPU_mac.v

# Unified Top-Level Module
read_verilog -sv rtl/FPU_top.v

# ------------------------------------------------------------------------------
# 3. Elaborate and Check Design Hierarchy
# ------------------------------------------------------------------------------
puts "\n[STEP 2/6] Elaborating design hierarchy for top module: $TOP_MODULE..."
hierarchy -check -top $TOP_MODULE

# ------------------------------------------------------------------------------
# 4. RTL Optimization and Generic Synthesis
# ------------------------------------------------------------------------------
puts "\n[STEP 3/6] Performing generic synthesis and behavioral extraction..."
# Convert processes to multiplexers and flip-flops
proc
opt

# Extract and optimize Finite State Machines (if any)
fsm
opt

# Memory extraction and mapping to registers
memory
opt

# High-level behavioral mapping
techmap
opt

# ------------------------------------------------------------------------------
# 5. Technology Mapping to Sky130 Standard Cells
# ------------------------------------------------------------------------------
puts "\n[STEP 4/6] Mapping sequential elements to Sky130 flip-flops..."
# Map DFFs to Liberty gates in sky130
dfflibmap -liberty $LIB_FILE
opt

puts "\n[STEP 5/6] Performing logic synthesis and mapping combinational gates via ABC..."
# Map combinational gates to Sky130 Liberty library
abc -liberty $LIB_FILE

# Clean up unused nets and optimize
setundef -zero
splitnets -ports
opt_clean -purge

# ------------------------------------------------------------------------------
# 6. Generate Netlist, Statistics and Reports
# ------------------------------------------------------------------------------
puts "\n[STEP 6/6] Generating reports and structural gate-level netlist..."

# Design verification check report
tee -o "$OUTPUT_DIR/${TOP_MODULE}_check.rpt" check

# Detailed cell count and gate area statistics report
tee -o "$OUTPUT_DIR/${TOP_MODULE}_synth.rpt" stat -liberty $LIB_FILE

# Write structural gate-level Verilog netlist for OpenSTA & PnR
write_verilog -noattr -noexpr -nohex -nodec "$OUTPUT_DIR/${TOP_MODULE}_netlist.v"

# Write JSON netlist for visualizers / downstream tools
write_json "$OUTPUT_DIR/${TOP_MODULE}_netlist.json"

puts "\n========================================================================"
puts "  ASIC SYNTHESIS COMPLETED SUCCESSFULLY!"
puts "  Structural Netlist : $OUTPUT_DIR/${TOP_MODULE}_netlist.v"
puts "  Synthesis Report   : $OUTPUT_DIR/${TOP_MODULE}_synth.rpt"
puts "  Hierarchy Check    : $OUTPUT_DIR/${TOP_MODULE}_check.rpt"
puts "========================================================================"
