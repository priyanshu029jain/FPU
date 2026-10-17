# ==============================================================================
# File    : timing.sdc
# Format  : Synopsys Design Constraints (SDC)
# Target  : SkyWater 130nm Standard Cells (sky130_fd_sc_hd)
# Purpose : Timing constraints for OpenSTA static timing analysis
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Primary Clock Definition
# Target Frequency: 100 MHz (Clock Period = 10.00 ns)
# (Can be overridden by SDC_CLK_PERIOD env variable in scripts)
# ------------------------------------------------------------------------------
set CLK_PORT "clk"
set CLK_NAME "clk"

if {[info exists env(CLK_PERIOD)]} {
    set CLK_PERIOD $env(CLK_PERIOD)
} else {
    set CLK_PERIOD 10.00
}

create_clock -name $CLK_NAME -period $CLK_PERIOD [get_ports $CLK_PORT]

# ------------------------------------------------------------------------------
# 2. Clock Uncertainties, Latency & Transition
# ------------------------------------------------------------------------------
# 250 ps clock jitter / margin for setup; 100 ps for hold
set_clock_uncertainty -setup 0.250 [get_clocks $CLK_NAME]
set_clock_uncertainty -hold  0.100 [get_clocks $CLK_NAME]

# Clock transition / slew rate (150 ps)
set_clock_transition 0.150 [get_clocks $CLK_NAME]

# ------------------------------------------------------------------------------
# 3. Input Ports Constraints
# ------------------------------------------------------------------------------
# Set input arrival delay: 15% of clock cycle relative to rising clock edge
set_input_delay -clock $CLK_NAME -max [expr {$CLK_PERIOD * 0.15}] [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]
set_input_delay -clock $CLK_NAME -min 0.200                       [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]

# Model external driving cell (Sky130 standard inverter with 2x drive strength)
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]

# ------------------------------------------------------------------------------
# 4. Output Ports Constraints
# ------------------------------------------------------------------------------
# Set required output delay: 15% of clock cycle
set_output_delay -clock $CLK_NAME -max [expr {$CLK_PERIOD * 0.15}] [all_outputs]
set_output_delay -clock $CLK_NAME -min 0.200                       [all_outputs]

# Model external capacitive pin load: 35 fF typical board/downstream gate load
set_load 0.035 [all_outputs]

# ------------------------------------------------------------------------------
# 5. Timing Derate (Process, Voltage & Temperature variations margin)
# ------------------------------------------------------------------------------
set_timing_derate -early 0.95
set_timing_derate -late  1.05
