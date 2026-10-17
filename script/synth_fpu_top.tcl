# ==============================================================================
# Yosys ASIC Synthesis Script for FPU_top (SkyWater 130nm)
# Usage: yosys -s script/synth_fpu_top.tcl
# ==============================================================================

# 1. Read the Sky130 technology cell library from the root directory
read_liberty -lib sky130.lib

# 2. Read Verilog RTL source files (FPU_top and all subcomponents)
read_verilog component/param_adder_sub.v
read_verilog component/param_multiplier.v
read_verilog component/barrel_shifter.v
read_verilog component/leading_zero_detector.v
read_verilog component/input_convertor.v
read_verilog component/output_convertor.v

read_verilog rtl/FPU_adder.v
read_verilog rtl/FPU_multiplier.v
read_verilog rtl/FPU_division.v
read_verilog rtl/FPU_mac.v
read_verilog rtl/FPU_top.v

# 3. Elaborate and flatten the top module
hierarchy -top FPU_top
flatten

# 4. High-level synthesis pass (process RTL constructs, optimize, map memories)
proc; opt; memory; opt

# 5. Map design technology
techmap; opt

# 6. Map sequential flip-flops to Sky130 library
dfflibmap -liberty sky130.lib
opt

# 7. Map combinational logic to Sky130 standard cells
abc -fast -liberty sky130.lib
setundef -zero
splitnets -ports
opt_clean -purge

# 8. Print Area & Gate Count report directly in terminal and save to file
tee -o analysis/asic/fpu_top_area.txt stat -liberty sky130.lib

# 9. Save the synthesized gate-level netlist (used for OpenSTA timing/power)
write_verilog -noattr -noexpr -nohex -nodec script/fpu_top_mapped.v
