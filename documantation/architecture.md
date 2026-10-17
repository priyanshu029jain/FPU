# IEEE 754 Floating-Point Unit (FPU) Architecture Specification

This document describes the architecture and algorithms of the synthesizable Verilog modules in this repository. The design implements IEEE 754 binary32 arithmetic for **normal numbers and special values** with Round-to-Nearest-Even. It is **not fully IEEE 754 compliant**: see [§4 Deviations from IEEE 754](#4-deviations-from-ieee-754), which is based on an independent bit-exact audit (2026-10-18).

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
- **Subnormal**: $E = 0$, $M \ne 0$. Value $= (-1)^S \times (0.M) \times 2^{-126}$. **Not supported by this design** (see §4).
- **Infinity ($\pm\infty$)**: $E = 255$ (`0xFF`), $M = 0$.
- **Not a Number (NaN)**: $E = 255$ (`0xFF`), $M \ne 0$. All NaN results are the canonical quiet NaN `0x7FC00000`.

---

## 2. Core Functional Modules

All four units share the same interface style (`clk`, async active-low `rst_n`, `valid_in` → `valid_out`) and have **4 register stages**: `valid_out` rises on the 4th rising edge counting the edge that captures the input. A new operation can be issued every cycle (verified with back-to-back streams). Special operands (zero, ∞, NaN) are detected in Stage 1 and carried down the pipeline as a bypass value that replaces the computed result in Stage 4.

### 2.1 Floating-Point Adder / Subtractor (`rtl/FPU_adder.v`)
- **Stage 1 (Unpack & Alignment)**: Appends the implicit bit (1 for $E \ne 0$, 0 for $E = 0$), compares exponents with `param_adder_sub`, and right-shifts the smaller significand by $d = |E_a - E_b|$ (saturated at 49) in a 49-bit `barrel_shifter`. Both operands become 27-bit values: 24-bit significand + Guard + Round + Sticky.
- **Stage 2 (Add/Subtract & LZD)**: 27-bit add or subtract (`param_adder_sub`, carry-out gives a 28-bit sum). The 27-bit `leading_zero_detector` runs on the sum in the same stage.
- **Stage 3 (Normalization)**: A carry-out shifts right by 1 and increments the exponent; otherwise a `barrel_shifter` shifts left by the LZD count and decrements the exponent (clamped to 0).
- **Stage 4 (Rounding & Packing)**: Round-to-Nearest-Even on the GRS bits ($GRS > 100_2 \rightarrow +1$, $< 100_2 \rightarrow 0$, $= 100_2 \rightarrow$ round to even). Handles rounding carry-out, overflow to ±∞, and packs the result. A final biased exponent of 0 is packed as ±0 (flush-to-zero).

### 2.2 Floating-Point Multiplier (`rtl/FPU_multiplier.v`)
- **Stage 1**: Unpack, special-case detection, sign $S_a \oplus S_b$, exponent $E_a + E_b - 127$ (10-bit, via `param_adder_sub`).
- **Stage 2**: 24×24 → 48-bit significand product (`param_multiplier`).
- **Stage 3**: If product bit 47 is set, shift right by 1 (`barrel_shifter`) and increment the exponent. Extract the 24-bit significand plus $G$, $R$, $S$.
- **Stage 4**: RNE rounding increment, rounding-overflow renormalization, overflow (→ ±∞) / underflow (→ ±0) packing and flags.

### 2.3 Fused Multiply-Add (`rtl/FPU_mac.v`)
Computes $Y = A \times B + C$ with **a single rounding step** at the end.
- **Stage 1**: Unpack all three operands, 24×24 → 48-bit product (`param_multiplier`), product exponent $E_a + E_b - 127$.
- **Stage 2**: Exponent difference $E_{prod} - E_c$; the operand with the smaller exponent is right-shifted (two 100-bit `barrel_shifter`s) inside a 100-bit field. **Known bug:** the absolute difference is truncated to 8 bits, so differences beyond ±255 wrap around (see §4). The shifters' sticky outputs are not connected, so any bits shifted below bit 0 are discarded.
- **Stage 3**: 100-bit add/subtract (`param_adder_sub`) and 100-bit `leading_zero_detector`.
- **Stage 4**: 100-bit normalization shift (`barrel_shifter`), GRS extraction, RNE rounding, packing and flags.

### 2.4 Floating-Point Divider (`rtl/FPU_division.v`)
- **Stage 1**: Detects division by zero ($B = 0, A \ne 0 \rightarrow \pm\infty$, `flag_div_by_zero`), invalid forms ($0/0$, $\infty/\infty$, NaN → QNaN) and $\infty$ / zero results. Exponent $E_a - E_b + 127$.
- **Stage 2**: 26-bit quotient by **restoring division, with all 26 iterations unrolled in a single combinational `always` block**. The pipeline does not split this loop, so it is the longest path in the whole FPU (~100 ns in Sky130 synthesis).
- **Stage 3**: For normal inputs the quotient lies in $(0.5, 2)$, so normalization is at most a 1-bit left shift with exponent decrement. GRS extraction, with Sticky = (remainder ≠ 0).
- **Stage 4**: RNE rounding, packing and flags.

### 2.5 Top Level (`rtl/FPU_top.v`)
Instantiates all four units in parallel. `valid_in` is gated per unit by `op`; `op` is delayed through a 4-deep register chain (`op_pipe1..4`), and a combinational multiplexer selects the matching unit's `Y`, `valid_out` and flags. `flag_inf` and `flag_nan` are derived from the selected `Y`. Because the units run in parallel on the same clock, the divider sets the `FPU_top` clock period.

---

## 3. Peripheral Convertors (`component/`)

These are **standalone combinational blocks**. They are tested in `tb/sim_tb/tb_fpu_top.v` but are **not instantiated in `FPU_top`**.

- **`input_convertor.v`**: Converts a signed 32-bit integer (`mode=0`) or signed Q16.16 value (`mode=1`) to binary32. Magnitudes needing more than 24 significant bits are **truncated, not rounded** (e.g. `0x7FFFFFFF` → `0x4EFFFFFF`; RNE gives `0x4F000000`).
- **`output_convertor.v`**: Converts binary32 to signed integer or Q16.16 by **truncation toward zero** (2.7 → 2). It also unpacks sign, unbiased exponent and 24-bit significand, and raises `is_zero` / `is_inf` / `is_nan` / `overflow`. Out-of-range values saturate to ±`0x7FFFFFFF`, so negative overflow gives `0x80000001` rather than INT_MIN, and exactly −2³¹ is reported as overflow.

---

## 4. Deviations from IEEE 754

Measured with an exact-arithmetic reference on `FPU_top` (bit-exact comparison).

| # | Behaviour | Affected units | Example |
|---|---|---|---|
| 1 | **No subnormal results.** A result whose biased exponent would be 0 is packed as ±0 with `flag_underflow = 1` (flush-to-zero). | All | `0x00800000 × 0.5` → `0x00000000` (expected `0x00400000`) |
| 2 | **Subnormal inputs mishandled.** The significand gets a 0 hidden bit, but the exponent stays at the field value 0 instead of the effective exponent 1, and the significand is not normalized. | All | `0x00400000 × 2.0` → `0x00C00000` (expected `0x00800000`) |
| 3 | **FMA alignment wrap-around.** `s2_abs_diff` in `FPU_mac.v` is 8 bits; signed exponent differences beyond ±255 wrap modulo 256. | FMA | `A=9B4E99D0, B=13D13455, C=7AAC7742` → `7AAC773F` (expected `7AAC7742`) |
| 4 | **`+0 + −0` returns `−0`** (IEEE RNE requires `+0`). The zero bypass returns `B` when `A` is zero. | Adder | `00000000 + 80000000` → `80000000` |
| 5 | **`flag_invalid` set for quiet-NaN inputs.** IEEE signals invalid only for signaling NaNs and invalid operations. | All | `qNaN + 1` → `invalid = 1` |
| 6 | **Round-to-Nearest-Even only.** No RTZ / RUP / RDN modes. | All | — |

With normal inputs over the full exponent range, ADD was bit-exact on 3,000/3,000 operations. MUL and DIV were bit-exact on every result that lands in the normal range. FMA was bit-exact except for deviation #3.
