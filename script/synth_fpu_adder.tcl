# ==============================================================================
# Yosys ASIC Synthesis Script for FPU_adder (SkyWater 130nm)
# Usage: yosys -c script/synth_fpu_adder.tcl
# ==============================================================================

# 1. Read the Sky130 technology cell library from the root directory
read_liberty -lib sky130.lib

# 2. Read Verilog RTL source files (FPU_adder and its subcomponents)
read_verilog component/param_adder_sub.v
read_verilog component/barrel_shifter.v
read_verilog component/leading_zero_detector.v
read_verilog rtl/FPU_adder.v

# 3. Elaborate the top module
hierarchy -top FPU_adder

# 4. High-level synthesis pass (process RTL constructs, optimize, map memories)
proc; opt; memory; opt

# 5. Map sequential flip-flops to Sky130 library
dfflibmap -liberty sky130.lib
opt

# 6. Map design technology and combinational logic to Sky130 standard cells
techmap; opt
abc -liberty sky130.lib
opt_clean -purge

# 7. Print Area & Gate Count report directly in terminal and save to file
tee -o script/area_report_adder.txt stat -liberty sky130.lib

# 8. Save the synthesized gate-level netlist (used for OpenSTA timing/power)
write_verilog -noattr script/fpu_adder_mapped.v
