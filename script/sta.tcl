# ==============================================================================
# Script  : sta.tcl
# Tool    : OpenSTA (Static Timing Analyzer)
# Target  : SkyWater 130nm Standard Cells (sky130_fd_sc_hd)
# Purpose : Post-Synthesis Static Timing Analysis for Floating-Point Units
# Usage   : sta script/sta.tcl
#           (Environment variables TOP_MODULE, LIB_FILE, SDC_FILE override defaults)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Configuration & Variable Initialization
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

if {[info exists env(SDC_FILE)]} {
    set SDC_FILE $env(SDC_FILE)
} else {
    set SDC_FILE "script/timing.sdc"
}

set NETLIST_FILE "$OUTPUT_DIR/${TOP_MODULE}_netlist.v"
set REPORT_FILE  "$OUTPUT_DIR/${TOP_MODULE}_sta.rpt"

puts "========================================================================"
puts "  STARTING OPENSTA STATIC TIMING ANALYSIS"
puts "  Top Module  : $TOP_MODULE"
puts "  Liberty File: $LIB_FILE"
puts "  Netlist     : $NETLIST_FILE"
puts "  Constraints : $SDC_FILE"
puts "  Report Out  : $REPORT_FILE"
puts "========================================================================"

# ------------------------------------------------------------------------------
# 2. Read Technology Liberty File and Gate-Level Netlist
# ------------------------------------------------------------------------------
puts "\n[STEP 1/5] Reading Sky130 Liberty timing library..."
read_liberty $LIB_FILE

puts "\n[STEP 2/5] Reading structural synthesized Verilog netlist..."
read_verilog $NETLIST_FILE

puts "\n[STEP 3/5] Linking design to top-level module: $TOP_MODULE..."
link_design $TOP_MODULE

# ------------------------------------------------------------------------------
# 3. Apply Timing Constraints (SDC)
# ------------------------------------------------------------------------------
puts "\n[STEP 4/5] Reading Synopsys Design Constraints ($SDC_FILE)..."
read_sdc $SDC_FILE

# Check design constraints setup
puts "\nChecking setup constraints..."
check_setup -verbose

# ------------------------------------------------------------------------------
# 4. Generate Comprehensive Timing Reports
# ------------------------------------------------------------------------------
puts "\n[STEP 5/5] Performing static timing analysis & generating reports..."

# Open file channel for report logging
set fp [open $REPORT_FILE w]
puts $fp "========================================================================"
puts $fp "  OPENSTA STATIC TIMING ANALYSIS REPORT"
puts $fp "  Design      : $TOP_MODULE"
puts $fp "  Technology  : SkyWater 130nm (sky130_fd_sc_hd)"
puts $fp "  Generated on: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fp "========================================================================\n"

# 4.1 Design Area Report
puts "\n>>> Reporting Total Design Cell Area..."
puts $fp "\n------------------------------------------------------------------------"
puts $fp "1. TOTAL DESIGN CELL AREA"
puts $fp "------------------------------------------------------------------------"
report_design_area
set area_out [report_design_area]
puts $fp $area_out

# 4.2 Setup (Max Delay) Critical Path Analysis
puts "\n>>> Reporting Worst Setup (Max Delay) Critical Timing Paths..."
puts $fp "\n------------------------------------------------------------------------"
puts $fp "2. WORST SETUP (MAX DELAY) TIMING PATHS"
puts $fp "------------------------------------------------------------------------"
report_checks -path_delay max -fields {input_pin slew cap input net} -digits 3
set setup_out [report_checks -path_delay max -fields {input_pin slew cap input net} -digits 3]
puts $fp $setup_out

# 4.3 Hold (Min Delay) Timing Analysis
puts "\n>>> Reporting Worst Hold (Min Delay) Timing Paths..."
puts $fp "\n------------------------------------------------------------------------"
puts $fp "3. WORST HOLD (MIN DELAY) TIMING PATHS"
puts $fp "------------------------------------------------------------------------"
report_checks -path_delay min -fields {input_pin slew cap input net} -digits 3
set hold_out [report_checks -path_delay min -fields {input_pin slew cap input net} -digits 3]
puts $fp $hold_out

# 4.4 Slack Metrics: WNS & TNS
puts "\n>>> Reporting Worst Negative Slack (WNS) and Total Negative Slack (TNS)..."
puts $fp "\n------------------------------------------------------------------------"
puts $fp "4. SLACK SUMMARY"
puts $fp "------------------------------------------------------------------------"

set wns_setup [report_worst_slack -max]
set wns_hold  [report_worst_slack -min]
set tns_setup [report_tns -max]
set tns_hold  [report_tns -min]

puts $fp "  Worst Setup Slack (WNS max): $wns_setup ns"
puts $fp "  Total Setup Slack (TNS max): $tns_setup ns"
puts $fp "  Worst Hold Slack  (WNS min): $wns_hold ns"
puts $fp "  Total Hold Slack  (TNS min): $tns_hold ns"

puts "  Worst Setup Slack (WNS max): $wns_setup ns"
puts "  Total Setup Slack (TNS max): $tns_setup ns"
puts "  Worst Hold Slack  (WNS min): $wns_hold ns"
puts "  Total Hold Slack  (TNS min): $tns_hold ns"

# 4.5 Unconstrained Endpoints Check
puts "\n>>> Checking Unconstrained Endpoints..."
puts $fp "\n------------------------------------------------------------------------"
puts $fp "5. UNCONSTRAINED ENDPOINTS CHECK"
puts $fp "------------------------------------------------------------------------"
report_unconstrained
set unconst_out [report_unconstrained]
puts $fp $unconst_out

close $fp

puts "\n========================================================================"
puts "  OPENSTA TIMING ANALYSIS COMPLETED!"
puts "  Report saved at: $REPORT_FILE"
puts "========================================================================"

exit
