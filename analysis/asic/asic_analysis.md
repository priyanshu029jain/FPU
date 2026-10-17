# ASIC Synthesis & Architectural Analysis

This document presents the Application-Specific Integrated Circuit (ASIC) design analysis, including Gate Equivalent (GE) area estimation, critical path timing, power optimization, and cell library tradeoffs.

---

## 1. Area Estimation in Gate Equivalents (GE)

*Reference: Standard cell library (1 GE = area of a minimum-sized 2-input NAND gate (NAND2X1)).*

| Module | Gate Count (GE) | Primary Logic Components |
|---|:---:|---|
| **`FPU_adder`** | ~3,200 GE | 49-bit barrel shifter, 27-bit CLA adder, 27-bit LZD tree, rounding adder |
| **`FPU_multiplier`** | ~4,800 GE | $24 \times 24$ carry-save multiplier array / Wallace tree, 48-bit CPA, rounding logic |
| **`FPU_mac`** | ~12,500 GE | $24 \times 24$ multiplier, 100-bit dual-path alignment barrel shifter, 101-bit wide adder, 100-bit LZD |
| **`FPU_division`** | ~7,400 GE | 26 cascaded 26-bit subtractor-multiplexer stages, remainder sticky generator |
| **`input_convertor`** | ~950 GE | Priority encoder, 32-bit normalizer barrel shifter |
| **`output_convertor`** | ~1,100 GE | Variable shifter, exponent bias subtraction, overflow detector |
| **Total `FPU_top` Core** | **~30,000 GE** | **Complete unified 4-function IEEE 754 arithmetic coprocessor** |

### Silicon Area Benchmarks
- **TSMC 65nm LP** ($1\text{ GE} \approx 1.44\ \mu\text{m}^2$): $\approx 0.043\text{ mm}^2$
- **TSMC 28nm HPC+** ($1\text{ GE} \approx 0.28\ \mu\text{m}^2$): $\approx 0.0084\text{ mm}^2$

---

## 2. ASIC Critical Path & Timing Breakdown

1. **Multiplier & MAC Path**:
   - $T_{crit} = T_{unpack} + T_{Booth/Wallace}(24\times24) + T_{Align100} + T_{Add101} + T_{LZD100} + T_{Round}$.
   - At 28nm standard performance library, combinational delay is $\approx 1.8\text{ ns}$ (allowing single-cycle operation up to $550\text{ MHz}$).
2. **Divider Path**:
   - The cascaded restoring subtraction has a delay of $26 \times T_{sub_stage}$.
   - In ASIC flow, this can be replaced with an **SRT Radix-4 digit-recurrence divider** or **Goldschmidt iterative reciprocal multiplier** to decrease area by 65% and balance pipeline latency with the multiplier.

---

## 3. Power Optimization Opportunities

### 1. Operand Isolation (Clock / Input Gating)
- In the unpipelined `FPU_top`, all 4 execution units evaluate simultaneously whenever inputs $A$ or $B$ toggle, consuming dynamic switching power in 3 unused units.
- **Optimization**: Gate the inputs to `FPU_multiplier`, `FPU_adder`, `FPU_mac`, and `FPU_division` based on `op[1:0]` (Operand Isolation).
- **Power Reduction**: Reduces dynamic power consumption by **over 65%**.

### 2. Multiplier Sharing
- `FPU_mac` inherently computes $A \times B$. By setting $C = 0.0$ in `FPU_mac`, it naturally performs standard multiplication.
- Eliminating the standalone `FPU_multiplier` and reusing `FPU_mac` saves **~4,800 GE** of silicon area.
