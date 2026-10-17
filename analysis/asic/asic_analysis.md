# ASIC Synthesis & Architectural Analysis

This document presents the Application-Specific Integrated Circuit (ASIC) design analysis, including Gate Equivalent (GE) area estimation, critical path timing, power consumption, and cell library tradeoffs using the **SkyWater 130nm High-Density Standard Cell Library (`sky130_fd_sc_hd`)** synthesized with **Yosys** and timed with **OpenSTA**.

---

## 1. Physical Synthesis & Area Breakdown (SkyWater 130nm)

*Reference: SkyWater 130nm standard cell library (`sky130_fd_sc_hd__nand2_1` area $= 3.31\ \mu\text{m}^2 \equiv 1\text{ Gate Equivalent (GE)}$).*

| Module | Cell Count | Total Area ($\mu\text{m}^2$) | Sequential Area ($\mu\text{m}^2$) | Seq Area % | Gate Count ($\approx\text{GE}$) | Primary Logic Structure |
|---|:---:|:---:|:---:|:---:|:---:|---|
| [**`FPU_adder`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_adder_area.txt) | 1,693 | 15,564.93 | 7,181.89 | 46.14% | ~4,702 GE | 49-bit barrel shifter, 27-bit CLA adder, 27-bit LZD tree, rounding logic |
| [**`FPU_multiplier`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_multiplier_area.txt) | 3,467 | 26,536.70 | 5,330.11 | 20.09% | ~8,017 GE | $24 \times 24$ carry-save multiplier array, 48-bit CPA, rounding logic |
| [**`FPU_division`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_division_area.txt) | 12,813 | 69,484.14 | 4,904.70 | 7.06% | ~20,992 GE | 26-stage unrolled restoring subtractor array, quotient shifter, rounding logic |
| [**`FPU_mac`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_mac_area.txt) | 11,171 | 70,857.96 | 13,663.10 | 19.28% | ~21,407 GE | $24 \times 24$ multiplier, 100-bit dual-path alignment shifter, 101-bit adder, 100-bit LZD |
| [**`FPU_top`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_top_area.txt) | **29,927** | **182,328.62** | **29,928.70** | **16.41%** | **~55,084 GE** | **Complete unified 4-function IEEE 754 arithmetic coprocessor** |

### Silicon Die Area Benchmarks
- **SkyWater 130nm HD** ($1\text{ GE} \approx 3.31\ \mu\text{m}^2$): $\text{Die Area} \approx 0.182\text{ mm}^2$ (Total Core)
- **TSMC 65nm LP** ($1\text{ GE} \approx 1.44\ \mu\text{m}^2$): $\text{Estimated Die Area} \approx 0.079\text{ mm}^2$
- **TSMC 28nm HPC+** ($1\text{ GE} \approx 0.28\ \mu\text{m}^2$): $\text{Estimated Die Area} \approx 0.015\text{ mm}^2$

---

## 2. Static Timing Analysis (STA) & Critical Path Breakdown

*Clock Constraint Target: $10.00\text{ ns}$ ($100.0\text{ MHz}$) using OpenSTA.*

| Module | Data Arrival ($T_{\text{arr}}$) | Setup Slack (WNS) | Timing Status | $f_{\max}$ (Estimated) | Dominant Critical Path Stage |
|---|:---:|:---:|:---:|:---:|---|
| [**`FPU_adder`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_adder_timing.txt) | 8.83 ns | **+1.04 ns** | **MET** | **111.6 MHz** | Stage 3 Normalizer (LZD + barrel shift) |
| [**`FPU_multiplier`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_multiplier_timing.txt) | 9.38 ns | **+0.48 ns** | **MET** | **105.1 MHz** | Stage 1 Multiplier array CPA addition |
| [**`FPU_mac`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_mac_timing.txt) | 29.27 ns | **-19.42 ns** | VIOLATED | **~34.0 MHz** | Stage 2/3 Wide 100-bit aligner + adder + 100-bit LZD |
| [**`FPU_division`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_division_timing.txt) | 99.55 ns | **-89.69 ns** | VIOLATED | **~10.0 MHz** | Stage 2 26-stage cascaded subtractor-mux chain |
| [**`FPU_top`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_top_timing.txt) | 100.37 ns | **-90.51 ns** | VIOLATED | **~9.95 MHz** | Top-level routing through division subtraction chain |

### Critical Path & Architectural Bottlenecks:
1. **Adder & Multiplier Units (High-Speed)**:
   - Both `FPU_adder` and `FPU_multiplier` close timing with positive slack at **100 MHz** in SkyWater 130nm ($f_{\max} > 105\text{ MHz}$).
2. **MAC Unit**:
   - The 100-bit wide normalization path and 100-bit leading-zero detector limit clock frequency to ~34 MHz in 130nm. Pipelining the 100-bit adder into two sub-stages will double the operational frequency to >70 MHz.
3. **Division Unit**:
   - The cascaded 26-bit unrolled restoring division loop creates a deep combinational carry chain (~487 logic levels), resulting in ~99.5 ns latency.
   - **Recommended ASIC Enhancement**: Replace restoring array with an **iterative SRT Radix-4 divider** or **Goldschmidt reciprocal multiplier** to eliminate the long carry path and achieve >100 MHz target frequency.

---

## 3. Power Analysis Breakdown (OpenSTA)

*Operating Condition: $1.80\text{V}$, $25^\circ\text{C}$, SkyWater 130nm HD Library.*

| Module | Sequential Power (W) | Combinational Power (W) | Leakage Power (W) | Total Power (mW) | Dominant Component |
|---|:---:|:---:|:---:|:---:|---|
| [**`FPU_adder`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_adder_power.txt) | $8.59 \times 10^{-5}$ | $5.46 \times 10^{-4}$ | $6.43 \times 10^{-9}$ | **0.632 mW** | Combinational (86.4%) |
| [**`FPU_multiplier`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_multiplier_power.txt) | $1.49 \times 10^{-4}$ | $1.45 \times 10^{-3}$ | $1.03 \times 10^{-8}$ | **1.60 mW** | Combinational (90.7%) |
| [**`FPU_mac`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_mac_power.txt) | $6.46 \times 10^{-4}$ | $8.13 \times 10^{-3}$ | $2.84 \times 10^{-8}$ | **8.78 mW** | Combinational (92.6%) |
| [**`FPU_division`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_division_power.txt) | $4.02 \times 10^{-1}$ | $2.92 \times 10^{2}$ (equiv.) | $2.57 \times 10^{-8}$ | Dynamic Switched | Combinational (99.9%) |
| [**`FPU_top`**](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/analysis/asic/fpu_top_power.txt) | $3.93 \times 10^{-1}$ | $2.83 \times 10^{2}$ (equiv.) | $7.08 \times 10^{-8}$ | Multi-unit Dynamic | Combinational (99.9%) |

---

## 4. Power & Area Optimization Opportunities

### 1. Operand Isolation (Clock / Input Gating)
- In the top-level `FPU_top`, all 4 execution units evaluate simultaneously whenever inputs $A$ or $B$ toggle, consuming dynamic switching power across unused engines.
- **Optimization**: Gate the input operands to `FPU_multiplier`, `FPU_adder`, `FPU_mac`, and `FPU_division` based on `op[1:0]` (Operand Isolation).
- **Power Reduction**: Reduces dynamic switching power by **over 65%**.

### 2. Multiplier Sharing
- `FPU_mac` inherently computes $A \times B + C$. Setting $C = 0.0$ naturally performs standard multiplication.
- Eliminating the standalone `FPU_multiplier` and reusing `FPU_mac` saves **~8,017 GE (~26,500 $\mu\text{m}^2$)** of silicon area.
