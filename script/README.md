# ASIC Synthesis & Static Timing Analysis (STA) Flow

This directory contains the automated **ASIC Synthesis and Static Timing Analysis (STA)** flow for the 32-bit IEEE 754-2008 Floating-Point Unit (FPU), targeting the open-source **SkyWater 130nm Standard Cell Library (`sky130_fd_sc_hd`)**.

---

## 1. Flow Overview & Architecture

```text
       +-----------------------+     +------------------------+
       |   Verilog RTL Files   |     | SkyWater 130nm Liberty |
       |  (rtl/*.v, comp/*.v)  |     |     (sky130.lib)       |
       +-----------+-----------+     +-----------+------------+
                   |                             |
                   +--------------+--------------+
                                  |
                                  v
                   +-----------------------------+
                   |        Yosys Synthesis      | <--- script/synth_yosys.tcl
                   |  (Elaboration, Techmapping) |
                   +--------------+--------------+
                                  |
             +--------------------+--------------------+
             |                                         |
             v                                         v
+--------------------------+             +--------------------------+
|  Structural Gate-Level   |             |     Synthesis Report     |
|     Verilog Netlist      |             | (Cell counts, Area um^2) |
| synth/<top>_netlist.v    |             | synth/<top>_synth.rpt    |
+------------+-------------+             +--------------------------+
             |
             |       +------------------------+
             +-----> |  OpenSTA Static Timing | <--- script/timing.sdc
                     |   (Setup, Hold, Slack) | <--- script/sta.tcl
                     +-----------+------------+
                                 |
                                 v
                     +------------------------+
                     |    STA Timing Report   |
                     | (WNS, TNS, Max Freq)   |
                     | synth/<top>_sta.rpt    |
                     +------------------------+
```

---

## 2. Directory Contents

| File | Purpose | Description |
|---|---|---|
| [`script/synth_yosys.tcl`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/script/synth_yosys.tcl) | **Yosys Synthesis Script** | Translates RTL Verilog to Sky130 gate-level netlist using `proc`, `opt`, `fsm`, `memory`, `dfflibmap`, and ABC logic synthesis. |
| [`script/timing.sdc`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/script/timing.sdc) | **SDC Timing Constraints** | Defines 100 MHz clock (10.0 ns), clock jitter uncertainty, driving cell (`sky130_fd_sc_hd__inv_2`), output load (35 fF), and I/O delays. |
| [`script/sta.tcl`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/script/sta.tcl) | **OpenSTA Analysis Script** | Links gate netlist to `sky130.lib`, checks setup/hold slack (WNS/TNS), critical data arrival paths, and total cell area. |
| [`script/run_synth.sh`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/script/run_synth.sh) | **Automated CLI Runner** | One-command orchestration script to synthesize any module at any target frequency. |

---

## 3. Tool Requirements

* **Yosys Open SYnthesis Suite** (v0.25+)
* **OpenSTA** (Static Timing Analyzer)
* **SkyWater 130nm Liberty File**: `sky130.lib` (included in workspace root, `sky130_fd_sc_hd__tt_025C_1v80`).

---

## 4. How to Run

### Synthesize the Unified Top-Level FPU (`FPU_top`):
```bash
./script/run_synth.sh top
```

### Synthesize Individual Units:
```bash
# 1. Pipelined FPU Adder
./script/run_synth.sh adder

# 2. Pipelined FPU Multiplier
./script/run_synth.sh multiplier

# 3. Pipelined FPU Divider
./script/run_synth.sh division

# 4. Pipelined FPU MAC
./script/run_synth.sh mac
```

### Specify a Custom Target Clock Period:
```bash
# Synthesize FPU_adder targeting 200 MHz (5.0 ns period)
./script/run_synth.sh adder 5.0

# Synthesize FPU_top targeting 125 MHz (8.0 ns period)
./script/run_synth.sh top 8.0
```

---

## 5. Generated Artifacts & Reports

Outputs are saved in the `synth/` directory:

* `synth/<module>_netlist.v` : Synthesized structural gate-level netlist mapped to Sky130 standard cells.
* `synth/<module>_netlist.json` : JSON netlist for visualizers or downstream toolchains.
* `synth/<module>_synth.rpt` : Yosys cell count breakdown (NAND, NOR, AND, XOR, DFFs) and total chip area in $\mu m^2$.
* `synth/<module>_check.rpt` : Yosys design rule and hierarchy verification log.
* `synth/<module>_sta.rpt` : OpenSTA timing report detailing Worst Negative Slack (WNS), Total Negative Slack (TNS), critical paths, and maximum operating frequency ($F_{max}$).
