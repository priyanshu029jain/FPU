# IEEE 754 Floating-Point Unit (FPU) Architecture Specification

This document details the architectural design and algorithms used across all synthesizable Verilog modules in this repository, designed strictly adhering to the IEEE 754-2008 single-precision floating-point specification.

---

## 1. IEEE 754 Single-Precision Format (32-bit)

A 32-bit float is structured into three fields:

$$\text{Value} = (-1)^S \times (1.M) \times 2^{E - 127}$$

| Field | Width | Bit Range | Description |
|---|:---:|:---:|---|
| **Sign ($S$)** | 1 bit | `[31]` | $0 = \text{Positive}$, $1 = \text{Negative}$ |
| **Exponent ($E$)** | 8 bits | `[30:23]` | Biased by $+127$. Range $[1, 254]$ for normal numbers. |
| **Mantissa ($M$)** | 23 bits | `[22:0]` | Fractional significand. Implicit leading $1$ is restored ($1.M$) for normal floats. |

### Special Values Encoding
- **Zero ($\pm 0.0$)**: $E = 0$, $M = 0$.
- **Subnormal**: $E = 0$, $M \ne 0$. Value $= (-1)^S \times (0.M) \times 2^{-126}$.
- **Infinity ($\pm\infty$)**: $E = 255$ (`0xFF`), $M = 0$.
- **Not a Number (NaN)**: $E = 255$ (`0xFF`), $M \ne 0$.

---

## 2. Core Functional Modules

### 2.1 Floating-Point Adder / Subtractor (`rtl/FPU_adder.v`)
- **Stage 1 (Unpack & Alignment)**: Appends implicit leading bit ($1.M$), compares exponents, and calculates shift distance $d = |E_a - E_b|$. The smaller operand's significand is right-shifted by $d$ into a 49-bit space preserving Guard ($G$), Round ($R$), and Sticky ($S$) bits ($27$ bits total: $24$ significand $+ G + R + S$).
- **Stage 2 (Significand Addition/Subtraction)**: If operand signs match, significands are added; otherwise subtracted using magnitude comparison.
- **Stage 3 (LZD & Normalization)**: Detects subtraction cancellation using a 27-bit synthesizable Leading Zero Detector (LZD) and shifts the result left while decrementing the exponent. Addition carries shift right by $1$ and increment the exponent.
- **Stage 4 (Rounding & Packing)**: Evaluates Guard, Round, and Sticky bits according to **Round-to-Nearest-Even** ($GRS > 100_2 \rightarrow +1$, $GRS < 100_2 \rightarrow 0$, $GRS = 100_2 \rightarrow \text{tie-breaker on LSB}$). Handles rounding carry-out and saturates on overflow ($\ge 255$).

### 2.2 Floating-Point Multiplier (`rtl/FPU_multiplier.v`)
- **Phase 1 (Unpack)**: Extracts sign, exponent, and forms 24-bit significands $1.M_a$ and $1.M_b$.
- **Phase 2 (Sign & Exponent)**: Output sign is $S_a \oplus S_b$. Exponent is $E_a + E_b - 127$.
- **Phase 3 (Multiplication)**: Computes 48-bit unsigned product $P_{raw} = \text{Sig}_A \times \text{Sig}_B$.
- **Phase 4 (Normalization)**: Since $\text{Sig} \in [1.0, 2.0)$, the product is in $[1.0, 4.0)$. If bit 47 is $1$, it shifts right by $1$ and increments the exponent.
- **Phase 5 (Rounding)**: Extracts $G$ (bit 22), $R$ (bit 21), and $S$ (OR-reduction of bits 20:0) for round-to-nearest-even.

### 2.3 Fused Multiply-Accumulate (`rtl/FPU_mac.v`)
- Computes $Y = A \times B + C$ with **a single rounding step** at the end.
- Product $A \times B$ is computed to full 48-bit precision.
- **Dual-Path Wide Alignment**: Operands $P$ and $C$ are aligned inside a 100-bit register space based on $d = E_{prod} - E_c$.
- Add/subtract performed in 100-bit precision, normalized via 100-bit LZD, and rounded in one unified step.

### 2.4 Floating-Point Divider (`rtl/FPU_division.v`)
- Detects division-by-zero ($B=0 \rightarrow \pm\infty$) and indeterminate forms ($0/0 \rightarrow \text{NaN}$).
- Subtracts exponents: $E_{temp} = E_a - E_b + 127$.
- Computes 26-bit quotient using restoring division. Since $0.5 < Q < 2.0$, normalizes in a single 1-bit step.
- Re-checks remainder: $\text{Remainder} \ne 0 \implies S = 1$.

---

## 3. Peripheral Convertors (`component/`)
- **`input_convertor.v`**: Converts signed 32-bit two's complement integers (`mode=0`) or signed Q16.16 fixed-point numbers (`mode=1`) into IEEE 754 floats.
- **`output_convertor.v`**: Converts IEEE 754 floats into signed integer or Q16.16 binary, and unpacks sign, unbiased exponent ($E - 127$), and 24-bit significand for debugging and waveform inspection.
