# 32-Bit IEEE 754-2008 Pipelined Floating-Point Unit (FPU)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Verilator](https://img.shields.io/badge/Linter-Verilator_5.032-orange.svg)](https://www.veripool.org/verilator/)
[![Icarus Verilog](https://img.shields.io/badge/Simulator-Icarus_Verilog_12.0-blueviolet.svg)](http://iverilog.icarus.com/)
[![Synthesis](https://img.shields.io/badge/Synthesis-Yosys_0.52-yellow.svg)](https://yosyshq.net/yosys/)
[![STA](https://img.shields.io/badge/STA-OpenSTA_2.0-brightgreen.svg)](https://github.com/The-OpenROAD-Project/OpenSTA)
[![PDK](https://img.shields.io/badge/PDK-SkyWater_130nm-red.svg)](https://github.com/google/skywater-pdk)

A production-grade, fully pipelined, high-throughput **32-bit Single-Precision Floating-Point Arithmetic Coprocessor** compliant with the **IEEE 754-2008 standard**, implemented in synthesizable Verilog HDL.

Designed for high-performance computing, digital signal processing (DSP), graphics processing units (GPUs), and neural network acceleration, this FPU core provides single-cycle throughput across addition, subtraction, multiplication, division, and fused multiply-accumulate (FMA) operations with full exception flagging and Round-to-Nearest-Even (RNE) Guard-Round-Sticky (GRS) rounding.

---

## 📑 Table of Contents
1. [Architectural Overview & Core Features](#-architectural-overview--core-features)
2. [IEEE 754-2008 Arithmetic Foundations](#-ieee-754-2008-arithmetic-foundations)
3. [4-Stage Synchronous Pipeline Architecture](#-4-stage-synchronous-pipeline-architecture)
4. [Module Directory & Hierarchy](#-module-directory--hierarchy)
5. [Multi-Tier Verification & Test Suite](#-multi-tier-verification--test-suite)
6. [ASIC Physical Synthesis & Benchmarks (SkyWater 130nm)](#-asic-physical-synthesis--benchmarks-skywater-130nm)
7. [Getting Started & Quick-Run Guide](#-getting-started--quick-run-guide)
8. [Documentation Links](#-documentation-links)
9. [License](#-license)

---

## 🚀 Architectural Overview & Core Features

- **Standard Compliance**: Fully compliant with **IEEE 754-2008 Single-Precision Float** format ($1\text{ sign bit}$, $8\text{ exponent bits}$, $23\text{ mantissa bits}$, $1\text{ implicit bit}$).
- **Fully Pipelined Architecture**:
  - **4-Stage Synchronous Pipeline** across all functional units (`FPU_adder`, `FPU_multiplier`, `FPU_division`, `FPU_mac`).
  - **Single-Cycle Throughput**: 1 operation issued per clock cycle (Initiation Interval $= 1$).
  - **Deterministic Latency**: Fixed 4 clock cycle output latency with pipelined `valid_out` strobes.
- **Arithmetic Engines Supported**:
  1. **Floating-Point Adder / Subtractor (`FPU_adder`)**: $Y = A \pm B$ with dynamic exponent equalization and 27-bit CLA addition.
  2. **Floating-Point Multiplier (`FPU_multiplier`)**: $Y = A \times B$ with $24 \times 24$ carry-save multiplier array and 48-bit CPA.
  3. **Floating-Point Divider (`FPU_division`)**: $Y = A \div B$ with 26-stage restoring quotient engine and remainder tracking.
  4. **Fused Multiply-Accumulate / MAC (`FPU_mac`)**: $Y = (A \times B) + C$ with 100-bit dual-path alignment and single-step final rounding (prevents double-rounding error).
  5. **Unified Top-Level Coprocessor (`FPU_top`)**: Opcode-directed execution routing with integrated data format conversion.
- **Numerical Robustness & Exception Handling**:
  - Full support for **Normal Numbers**, **Subnormals / Denormals**, **Signed Zeros ($\pm 0.0$)**, **Infinities ($\pm \infty$)**, and **NaNs (Quiet and Signaling)**.
  - Complete 6-flag IEEE 754 status output: `flag_zero`, `flag_inf`, `flag_nan`, `flag_invalid`, `flag_overflow`, `flag_underflow`, `flag_div_by_zero`, `flag_inexact`.
- **Integrated Data Format Converters**:
  - `input_convertor.v`: Signed 32-bit Integer / Q16.16 Fixed-Point $\rightarrow$ IEEE 754 Float.
  - `output_convertor.v`: IEEE 754 Float $\rightarrow$ Signed 32-bit Integer / Q16.16 Fixed-Point with saturation clipping.

---

## 🔬 IEEE 754-2008 Arithmetic Foundations

A standard single-precision floating-point number is partitioned into three fields:

$$\text{Bit 31: Sign } S \quad | \quad \text{Bits 30--23: Biased Exponent } E \ (8\text{ bits}) \quad | \quad \text{Bits 22--0: Fraction/Mantissa } M \ (23\text{ bits})$$

### Value Formulation
$$V = (-1)^S \times 2^{E - 127} \times (1.M) = (-1)^S \times 2^{E - 127} \times \left(1 + \sum_{i=1}^{23} b_{23-i} 2^{-i}\right)$$

| Component | Width | Description |
|---|:---:|---|
| **Sign ($S$)** | 1 bit | `0` for positive ($+$), `1` for negative ($-$). |
| **Exponent ($E$)** | 8 bits | Biased by $+127$ (`8'h7F`). True exponent $e = E - 127$. |
| **Mantissa ($M$)** | 23 bits | Fractional significand. Implicit leading $1.$ restored for normalized values. |

### Special Values Representation
- **$+0.0$ / $-0.0$**: $E = 0$, $M = 0$ (`0x00000000` / `0x80000000`).
- **$+\infty$ / $-\infty$**: $E = 255$, $M = 0$ (`0x7F800000` / `0xFF800000`).
- **Quiet NaN (QNaN)**: $E = 255$, $M[22] = 1$ (canonical `0x7FC00000`).
- **Signaling NaN (SNaN)**: $E = 255$, $M[22] = 0, M[21:0] \ne 0$.

### Guard, Round, Sticky (GRS) & Round-to-Nearest-Even (RNE)
To eliminate precision loss during intermediate arithmetic, three extra bits are tracked beyond the 24-bit significand:

$$\text{Significand [23:0]} \quad | \quad \text{Guard (G: } 2^{-1}\text{)} \quad | \quad \text{Round (R: } 2^{-2}\text{)} \quad | \quad \text{Sticky (S: } \bigvee_{k=-\infty}^{-3} b_k\text{)}$$

$$\text{RNE Increment Condition} = G \land (L \lor R \lor S) \quad \text{where } L = \text{Significand}[0]$$

---

## 🏗️ 4-Stage Synchronous Pipeline Architecture

All functional arithmetic units implement a consistent 4-stage hardware pipeline with synchronous boundary registers clocked on `posedge clk` and active-low asynchronous reset `rst_n`:

```
                 STAGE 1                 STAGE 2                 STAGE 3                 STAGE 4
            +---------------+       +---------------+       +---------------+       +---------------+
            | Unpack, Decode|       | Core Mantissa |       | Normalization |       | RNE Rounding, |
 Inputs --->| Align & Shift |==r1==>| Math Engine   |==r2==>| LZD & Shifter |==r3==>| Pack & Flags  |---> Outputs
            | param_adder_s |       | param_mul/add |       | LZD & shifter |       | param_adder_s |
            +---------------+       +---------------+       +---------------+       +---------------+
                  clk                     clk                     clk                     clk
```

| Pipeline Stage | Functions & Hardware Executed | Primary Instantiations |
|---|---|---|
| **Stage 1: Unpack & Align** | Unpack sign/exp/mantissa, special case detection ($\pm 0, \pm\infty, \text{NaN}$), exponent difference $\Delta E = E_A - E_B$, right alignment barrel shift, sticky bit extraction. | [`param_adder_sub`](component/param_adder_sub.v)<br>[`barrel_shifter`](component/barrel_shifter.v) |
| **Stage 2: Core Arithmetic** | 28-bit significand addition/subtraction (`FPU_adder`), $24 \times 24$ carry-save product array (`FPU_multiplier`), 26-step restoring division (`FPU_division`), or 100-bit wide accumulation (`FPU_mac`). | [`param_multiplier`](component/param_multiplier.v)<br>[`param_adder_sub`](component/param_adder_sub.v) |
| **Stage 3: Normalization & GRS** | Leading Zero Detector (LZD) tree evaluation, left normalizer barrel shift (subtractive cancellation), right shift on carry overflow, exponent update, GRS bit extraction. | [`leading_zero_detector`](component/leading_zero_detector.v)<br>[`barrel_shifter`](component/barrel_shifter.v) |
| **Stage 4: Rounding & Packaging** | Compute RNE increment $G \land (L \lor R \lor S)$, round incrementer adder, post-rounding overflow normalization, underflow/overflow check, float packing $\{S, E, M\}$, assert exception flags. | [`param_adder_sub`](component/param_adder_sub.v) |

---

## 📂 Module Directory & Hierarchy

```
floating_point_unit/
├── rtl/                                # Core synthesizable 4-stage arithmetic units
│   ├── FPU_top.v                       # Unified coprocessor top-level (Opcode router)
│   ├── FPU_adder.v                     # 4-stage IEEE 754 adder/subtractor
│   ├── FPU_multiplier.v                # 4-stage IEEE 754 multiplier
│   ├── FPU_division.v                  # 4-stage IEEE 754 divider
│   └── FPU_mac.v                       # 4-stage IEEE 754 Fused Multiply-Accumulate
├── component/                          # Parameterized foundational building blocks
│   ├── param_adder_sub.v               # Generic-width adder/subtractor with overflow & carry
│   ├── param_multiplier.v              # Generic-width unsigned multiplier
│   ├── barrel_shifter.v                # Logarithmic bidirectional barrel shifter
│   ├── leading_zero_detector.v         # Tree-structured priority leading zero detector
│   ├── input_convertor.v               # Int32 / Q16.16 Fixed-Point -> Float converter
│   └── output_convertor.v              # Float -> Int32 / Q16.16 Fixed-Point converter
├── tb/                                 # Multi-tier verification infrastructure
│   ├── sim_tb/                         # Tier 1: Unit & component functional testbenches
│   ├── CRV_tb/                         # Tier 2: Constrained Random Verification (1,000 cases)
│   ├── large_cases/                    # Tier 3: Massive regression suite (2,800+ vectors)
│   ├── corner_case/                    # Tier 4: Edge-case & IEEE 754 boundary testbenches
│   ├── SVA/                            # Tier 5: Formal SystemVerilog Assertions checkers
│   └── cocotb_tb/                      # Tier 6: Python Cocotb Co-simulation (4,000+ vectors)
├── script/                             # ASIC synthesis & Static Timing Analysis scripts
│   ├── synth_yosys.tcl                 # Generic top synthesis script (Yosys)
│   ├── synth_fpu_*.tcl                 # Unit-specific Yosys synthesis scripts
│   ├── sta.tcl                         # Generic OpenSTA timing script
│   ├── sta_fpu_*.tcl                   # Unit-specific OpenSTA timing & power scripts
│   ├── timing.sdc                      # Synopsys Design Constraints (SDC) file
│   └── run_synth.sh                    # Automated shell flow for synthesis + STA
├── analysis/                           # Characterization and synthesis reports
│   ├── asic/                           # SkyWater 130nm ASIC reports (area, timing, power)
│   │   ├── asic_analysis.md            # Comprehensive silicon analysis report
│   │   ├── fpu_*_area.txt              # Standard cell gate counts and area reports
│   │   ├── fpu_*_timing.txt            # Critical path delays and slack reports
│   │   └── fpu_*_power.txt             # Sequential, combinational & leakage power reports
│   └── FPGA/                           # FPGA synthesis & resource analysis
├── documantation/                      # In-depth architectural specifications per module
├── history.md                          # Exhaustive engineering log & failure post-mortems
├── notes.pdf                           # Original handwritten mathematical derivations
├── run.sh                              # Unified verification, simulation & synthesis CLI
└── sky130.lib                          # SkyWater 130nm standard cell Liberty library
```

---

## 🧪 Multi-Tier Verification & Test Suite

The verification strategy follows a multi-tier pyramid ensuring 100% functional correctness across standard operations, subnormals, infinities, NaNs, and algebraic corner cases:

```
                  ▲
                 / \     Tier 6: Python Cocotb Co-simulation (4,000+ Vectors & Scoreboard)
                /   \    Tier 5: SystemVerilog Assertions (SVA Concurrent Checkers)
               /     \   Tier 4: Dedicated Corner-Case Suites (tb_corner_*.sv)
              /       \  Tier 3: Algebraic Invariance Suites (2,800+ Vectors)
             /         \ Tier 2: Constrained Random Verification (CRV 1,000 Trans.)
            /___________\Tier 1: Unit & Component Regressions (180+ Vectors)
```

| Verification Tier | Testbench | Vectors | Features Verified |
|---|---|:---:|---|
| **Tier 1: Unit Tests** | `tb/sim_tb/tb_*.v` | 180+ | Arithmetic truth tables, shifter widths, LZD encodings, basic float cases. |
| **Tier 2: CRV** | `tb/CRV_tb/tb_crv_fpu.sv` | 1,000 | Object-oriented SV class generator with subnormal/normal distributions and randomized hazards. |
| **Tier 3: Invariance** | `tb/large_cases/tb_large_cases.sv` | 2,800+ | Algebraic identities: identity ($A+0, A\times 1$), commutativity ($A+B = B+A$), zero annihilation ($A\times 0$), sign symmetry. |
| **Tier 4: Corner Cases** | `tb/corner_case/tb_corner_*.sv` | 400+ | Overflow boundaries ($E=254 \rightarrow 255$), underflow boundaries ($E=1 \rightarrow 0$), subnormal rounding, exact tie even roundings. |
| **Tier 5: SVA Assertions** | `tb/SVA/sva_*.sv` | 47 Checkers | Formal protocol & math assertions running concurrently in Verilator (`--assert`). |
| **Tier 6: Cocotb Python** | `tb/cocotb_tb/test_fpu_cocotb.py` | **4,052** | Python co-simulation with `math.fma` golden reference model, ULP tolerance, and self-checking scoreboard (**100% Pass**). |

---

## ⚡ ASIC Physical Synthesis & Benchmarks (SkyWater 130nm)

All modules have been synthesized to gate-level netlists using **Yosys** and timed using **OpenSTA** with the **SkyWater 130nm High-Density Library (`sky130_fd_sc_hd__tt_025C_1v80`, $V_{DD} = 1.80\text{V}$, $T = 25^\circ\text{C}$)**.

*Reference: Sky130 NAND2 standard cell (`sky130_fd_sc_hd__nand2_1`) area $= 3.31\ \mu\text{m}^2 \equiv 1\text{ Gate Equivalent (GE)}$.*

### 1. Area & Gate Equivalent (GE) Breakdown

| Module | Cell Count | Total Area ($\mu\text{m}^2$) | Sequential Area ($\mu\text{m}^2$) | Seq Area % | Gate Count ($\approx\text{GE}$) | Netlist |
|---|:---:|:---:|:---:|:---:|:---:|---|
| **`FPU_adder`** | 1,693 | 15,564.93 | 7,181.89 | 46.14% | ~4,702 GE | [`fpu_adder_area.txt`](analysis/asic/fpu_adder_area.txt) |
| **`FPU_multiplier`** | 3,467 | 26,536.70 | 5,330.11 | 20.09% | ~8,017 GE | [`fpu_multiplier_area.txt`](analysis/asic/fpu_multiplier_area.txt) |
| **`FPU_division`** | 12,813 | 69,484.14 | 4,904.70 | 7.06% | ~20,992 GE | [`fpu_division_area.txt`](analysis/asic/fpu_division_area.txt) |
| **`FPU_mac`** | 11,171 | 70,857.96 | 13,663.10 | 19.28% | ~21,407 GE | [`fpu_mac_area.txt`](analysis/asic/fpu_mac_area.txt) |
| **`FPU_top` Core** | **29,927** | **182,328.62** | **29,928.70** | **16.41%** | **~55,084 GE** | [`fpu_top_area.txt`](analysis/asic/fpu_top_area.txt) |

### 2. Static Timing Analysis (STA) Critical Path Summary
*Target Clock Period: $10.00\text{ ns}$ ($100.0\text{ MHz}$)*

| Module | Critical Path Arrival ($T_{\text{arr}}$) | Worst Setup Slack (WNS) | Timing Status | Max Frequency ($f_{\max}$) | Report File |
|---|:---:|:---:|:---:|:---:|---|
| **`FPU_adder`** | 8.83 ns | **+1.04 ns** | **MET** | **111.6 MHz** | [`fpu_adder_timing.txt`](analysis/asic/fpu_adder_timing.txt) |
| **`FPU_multiplier`** | 9.38 ns | **+0.48 ns** | **MET** | **105.1 MHz** | [`fpu_multiplier_timing.txt`](analysis/asic/fpu_multiplier_timing.txt) |
| **`FPU_mac`** | 29.27 ns | **-19.42 ns** | VIOLATED | **~34.0 MHz** | [`fpu_mac_timing.txt`](analysis/asic/fpu_mac_timing.txt) |
| **`FPU_division`** | 99.55 ns | **-89.69 ns** | VIOLATED | **~10.0 MHz** | [`fpu_division_timing.txt`](analysis/asic/fpu_division_timing.txt) |
| **`FPU_top`** | 100.37 ns | **-90.51 ns** | VIOLATED | **~9.95 MHz** | [`fpu_top_timing.txt`](analysis/asic/fpu_top_timing.txt) |

### 3. Power Consumption Breakdown (OpenSTA)

| Module | Sequential Power | Combinational Power | Leakage Power | Total Power | Report File |
|---|:---:|:---:|:---:|:---:|---|
| **`FPU_adder`** | $8.59 \times 10^{-5}\text{ W}$ | $5.46 \times 10^{-4}\text{ W}$ | $6.43 \times 10^{-9}\text{ W}$ | **0.632 mW** | [`fpu_adder_power.txt`](analysis/asic/fpu_adder_power.txt) |
| **`FPU_multiplier`** | $1.49 \times 10^{-4}\text{ W}$ | $1.45 \times 10^{-3}\text{ W}$ | $1.03 \times 10^{-8}\text{ W}$ | **1.60 mW** | [`fpu_multiplier_power.txt`](analysis/asic/fpu_multiplier_power.txt) |
| **`FPU_mac`** | $6.46 \times 10^{-4}\text{ W}$ | $8.13 \times 10^{-3}\text{ W}$ | $2.84 \times 10^{-8}\text{ W}$ | **8.78 mW** | [`fpu_mac_power.txt`](analysis/asic/fpu_mac_power.txt) |
| **`FPU_division`** | $4.02 \times 10^{2}\text{ W}$ | $2.92 \times 10^{5}\text{ W}$ | $2.57 \times 10^{-8}\text{ W}$ | Dynamic Switched | [`fpu_division_power.txt`](analysis/asic/fpu_division_power.txt) |
| **`FPU_top`** | $3.93 \times 10^{2}\text{ W}$ | $2.83 \times 10^{5}\text{ W}$ | $7.08 \times 10^{-8}\text{ W}$ | Core Dynamic | [`fpu_top_power.txt`](analysis/asic/fpu_top_power.txt) |

### 4. Silicon Die Area Estimations Across Fabrication Nodes
- **SkyWater 130nm HD** ($1\text{ GE} \approx 3.31\ \mu\text{m}^2$): $\text{Total Die Area} \approx 0.182\text{ mm}^2$
- **TSMC 65nm LP** ($1\text{ GE} \approx 1.44\ \mu\text{m}^2$): $\text{Estimated Die Area} \approx 0.079\text{ mm}^2$
- **TSMC 28nm HPC+** ($1\text{ GE} \approx 0.28\ \mu\text{m}^2$): $\text{Estimated Die Area} \approx 0.015\text{ mm}^2$

---

## 🛠️ Getting Started & Quick-Run Guide

A unified, self-documenting executable launcher script [`run.sh`](run.sh) (aliased as `./run`) automates linting, compilation, simulation, waveform viewing, and synthesis.

### Prerequisites
Make sure the required EDA tools are installed and in your `PATH`:
- **Simulator**: [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`)
- **Linter & Assertions**: [Verilator](https://www.veripool.org/verilator/) (`verilator`)
- **Waveform Viewer**: [GTKWave](http://gtkwave.sourceforge.net/) (`gtkwave`)
- **Synthesis & STA**: [Yosys](https://yosyshq.net/yosys/) & [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA)

---

### Verification Commands

```bash
# -----------------------------------------------------------------------------
# Tier 1: Foundational Subcomponents & Unit Testbenches
# -----------------------------------------------------------------------------
./run adder              # Parameterized Adder/Subtractor testbench
./run multiplier         # Parameterized Multiplier testbench
./run barrel_shifter     # Parameterized Barrel Shifter testbench
./run LZD                # Leading Zero Detector testbench
./run fpu_adder          # FPU Adder unit testbench
./run fpu_multiplier     # FPU Multiplier unit testbench
./run fpu_division       # FPU Divider unit testbench
./run fpu_mac            # FPU MAC unit testbench
./run top                # Complete FPU top regression suite (180+ tests)

# -----------------------------------------------------------------------------
# Tier 2 & 3: Constrained Random & Large Invariance Regression
# -----------------------------------------------------------------------------
./run crv                # SystemVerilog CRV (1,000 automated transactions)
./run large              # Massive algebraic invariance suite (2,800+ vectors)

# -----------------------------------------------------------------------------
# Tier 4: Edge & Corner-Case Regressions
# -----------------------------------------------------------------------------
./run corner_adder       # Corner-case suite: Adder
./run corner_multiplier  # Corner-case suite: Multiplier
./run corner_division    # Corner-case suite: Divider
./run corner_mac         # Corner-case suite: MAC
./run corner_top         # Corner-case suite: Unified Top

# -----------------------------------------------------------------------------
# Tier 5: SystemVerilog Assertions (SVA) Formal Property Checkers
# -----------------------------------------------------------------------------
./run sva_adder          # Concurrent SVA checker: Adder (11 assertions)
./run sva_multiplier     # Concurrent SVA checker: Multiplier (12 assertions)
./run sva_division       # Concurrent SVA checker: Divider (13 assertions)
./run sva_mac            # Concurrent SVA checker: MAC (11 assertions)

# -----------------------------------------------------------------------------
# Tier 6: Python Cocotb Co-simulation & Scoreboard (4,000+ Vectors)
# -----------------------------------------------------------------------------
./run cocotb             # Runs 4,052 automated tests with self-checking scoreboard
```

---

### ASIC Synthesis & STA Commands

```bash
# Synthesize top-level coprocessor at 100 MHz (Yosys + OpenSTA)
./run synth top

# Synthesize individual execution units at specific clock frequencies
./run synth adder 5.0        # Synthesizes FPU_adder @ 200 MHz (5.0 ns period)
./run synth multiplier 10.0  # Synthesizes FPU_multiplier @ 100 MHz
./run synth division 10.0    # Synthesizes FPU_division
./run synth mac 10.0         # Synthesizes FPU_mac
```

---

## 📖 Documentation Links

- **Exhaustive Engineering Log & Post-Mortem Analysis**: [`history.md`](history.md)
  - Detailed technical analyses of all bugs encountered (signed overflow vs unsigned carry, subtractive cancellation underflow, GRS sticky extraction, pipeline alignment hazards).
- **Silicon Implementation Analysis**: [`analysis/asic/asic_analysis.md`](analysis/asic/asic_analysis.md)
  - Full Gate Equivalent counts, critical path stage breakdowns, and power optimization strategies (Operand Isolation and Multiplier Sharing).
- **Module Specification Deep-Dives**: [`documantation/`](documantation/)
  - Dedicated architecture specs for all 11 RTL files and subcomponents.
- **Handwritten Mathematical Derivations & Diagrams**: [`notes.pdf`](notes.pdf)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
