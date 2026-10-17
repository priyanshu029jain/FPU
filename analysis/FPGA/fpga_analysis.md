# FPGA Synthesis & Resource Utilization Analysis

This analysis evaluates the hardware footprint, resource utilization, and timing characteristics of the Floating-Point Unit when targeted to modern FPGA architectures (e.g., AMD/Xilinx 7-Series & UltraScale+, Intel Cyclone V).

---

## 1. Estimated FPGA Resource Utilization

Target: **Xilinx Artix-7 (XC7A35T-1CPG236C)** / **Kintex-7**

| Module | 6-LUTs | Flip-Flops (FF) | DSP48E1 Slices | Block RAM (BRAM) |
|---|:---:|:---:|:---:|:---:|
| **`FPU_adder`** | ~380 | Combinational (0) | 0 | 0 |
| **`FPU_multiplier`** | ~240 | Combinational (0) | 2 | 0 |
| **`FPU_mac`** | ~780 | Combinational (0) | 2 | 0 |
| **`FPU_division`** | ~690 | Combinational (0) | 0 | 0 |
| **`input_convertor`** | ~85 | Combinational (0) | 0 | 0 |
| **`output_convertor`** | ~110 | Combinational (0) | 0 | 0 |
| **`FPU_top` (Unified)** | **~2,200** | **0 (Combinational)** | **2 - 4** | **0** |

*Note: In `FPU_top`, if DSP sharing is enabled by synthesis tool mapping, the multiplier inside `FPU_multiplier` and `FPU_mac` can share the same DSP48 tiles.*

---

## 2. DSP Block Mapping for Mantissa Multiplication
- In IEEE 754 single-precision, the significand multiplication is unsigned $24 \times 24$ bits.
- **Xilinx DSP48E1 Slice**: Features an $18 \times 25$ two's-complement multiplier.
  - An unsigned $24 \times 24$ multiplication requires **two DSP48E1 slices** cascaded:
    - DSP 1: $17 \times 24$ bits
    - DSP 2: $7 \times 24$ bits (shifted and summed)
- **Xilinx UltraScale+ DSP48E2 Slice**: Features a $27 \times 18$ multiplier, fitting $24 \times 24$ in **1 to 2 DSP slices**.

---

## 3. Timing & Critical Path Analysis

### Critical Path Hotspots
1. **Divider (`FPU_division.v`)**:
   - The 26-step restoring divider creates a combinatorial carry cascade through 26 successive subtract-and-multiplex stages.
   - Longest combinatorial delay: $\approx 14.5\text{ ns}$ (Speed grade -1).
2. **Fused MAC (`FPU_mac.v`)**:
   - Path: $24 \times 24$ multiply $\rightarrow$ 100-bit wide alignment shift $\rightarrow$ 100-bit add/sub $\rightarrow$ 100-bit LZD $\rightarrow$ rounding.
   - Longest delay: $\approx 16.2\text{ ns}$.

### Clock Frequency Estimation
- **Pure Combinational (Single-cycle)**:
  - Max Operating Frequency ($F_{max}$): **$\approx 60\text{ MHz} - 75\text{ MHz}$** on Artix-7 (-1).
- **Recommended 4-Stage Pipelining**:
  - Stage 1: Unpack + $24 \times 24$ Significand Multiply / Align Shift
  - Stage 2: Wide Addition / Subtraction
  - Stage 3: Leading Zero Detection (LZD)
  - Stage 4: Round-to-Nearest-Even + Pack
  - **Pipelined $F_{max}$**: **$> 250\text{ MHz}$** on 7-Series, **$> 400\text{ MHz}$** on UltraScale+.
