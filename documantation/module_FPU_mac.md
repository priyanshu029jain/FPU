# Module Specification: `FPU_mac`

---

## 1. Overview & Architectural Role

`FPU_mac` is a 4-stage synchronous pipelined Fused Multiply-Add (FMA / MAC) unit for IEEE 754 binary32. It computes:

$$Y = A \times B + C$$

It is **not fully IEEE 754 compliant**. It has an alignment bug for large exponent gaps and no subnormal support (see [§5](#5-known-limitations-measured)).

### Key FMA Advantage:
Unlike a discrete multiplier followed by an adder (two roundings), the exact 48-bit product is added to `C` in a 100-bit datapath and **rounded only once** at the final stage. Note that the alignment shifters' sticky outputs are not connected, so bits shifted below bit 0 of the 100-bit field are discarded rather than folded into the sticky bit.

### Key Features:
- **4-Stage Synchronous Pipeline**: 4 register stages; `valid_out` rises on the 4th rising edge counting the edge that captures the input.
- **Sustained Throughput**: Accepts 1 new operation per clock cycle (verified with 32 back-to-back operations).
- **Subcomponent Instantiation**: Uses `param_multiplier`, 100-bit `barrel_shifter`s, a 100-bit `param_adder_sub`, a 100-bit `leading_zero_detector`, and smaller `param_adder_sub`s for exponents and rounding.
- **Status Flags**: `flag_overflow`, `flag_underflow`, `flag_invalid`, `flag_zero`, `flag_inexact`.
- **Timing (Sky130, pre-layout)**: 29.3 ns path (~34 MHz).

Source file: [`rtl/FPU_mac.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/rtl/FPU_mac.v)  
Testbench: [`tb/sim_tb/tb_fpu_mac.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_fpu_mac.v)

---

## 2. Port Interface Specification

```verilog
module FPU_mac (
    input  wire        clk,            // System Clock
    input  wire        rst_n,          // Active-low Asynchronous Reset
    input  wire        valid_in,       // Input Data Valid Strobe
    input  wire [31:0] A,              // IEEE 754 Float Multiplicand A
    input  wire [31:0] B,              // IEEE 754 Float Multiplier B
    input  wire [31:0] C,              // IEEE 754 Float Addend C
    output reg  [31:0] Y,              // IEEE 754 Float FMA Result
    output reg         valid_out,      // Output Data Valid Strobe (4 Cycles Latency)
    output reg         flag_overflow,  // Exponent Overflowed (> 254)
    output reg         flag_underflow, // Exponent Underflowed (< 1)
    output reg         flag_invalid,   // Invalid Operation (e.g. Inf - Inf, NaN)
    output reg         flag_zero,      // Result is Exact Zero
    output reg         flag_inexact    // Bits Discarded During Rounding
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `clk` | 1 | Input | Positive-edge triggered system clock. |
| `rst_n` | 1 | Input | Active-low asynchronous system reset. |
| `valid_in` | 1 | Input | Input valid handshake strobe. |
| `A`, `B`, `C` | 32 | Input | 32-bit single-precision floating-point inputs ($Y = A \times B + C$). |
| `Y` | 32 | Output | 32-bit single-precision floating-point FMA result. |
| `valid_out` | 1 | Output | Asserted 4 clock cycles after `valid_in`. |
| `flag_overflow` | 1 | Output | Exponent $\ge 255$; output saturates to $\pm\infty$. |
| `flag_underflow` | 1 | Output | Exponent $\le 0$; the result is **flushed to ±0** (no subnormal output). |
| `flag_invalid` | 1 | Output | $(0 \times \infty) + C$, $(\pm\infty) + (\mp\infty)$, or any NaN operand (quiet or signaling). |
| `flag_zero` | 1 | Output | Result cancels to exact zero. |
| `flag_inexact` | 1 | Output | Truncation occurred during wide alignment or final rounding. |

---

## 3. Pipeline Datapath Architecture

```mermaid
graph TD
    subgraph Stage 1: Unpack & Product
        In[Operands A, B, C] --> Mul[param_multiplier: 24x24-bit Product -> 48 bits]
        In --> ExpP[param_adder_sub: E_prod = Ea + Eb - 127]
        Mul --> R1[Registers r1_*]
        ExpP --> R1
    end

    subgraph Stage 2: Wide Alignment
        R1 --> ExpCmp[param_adder_sub: E_prod - E_c]
        ExpCmp --> Align[barrel_shifter x2: 100-bit Right Shift of smaller-exponent operand]
        Align --> R2[Registers r2_*]
    end

    subgraph Stage 3: Wide Add/Sub & LZD
        R2 --> WideAdd[param_adder_sub: 100-bit Sum P +/- C]
        WideAdd --> WideLZD[leading_zero_detector: 100-bit Zero Count]
        WideLZD --> R3[Registers r3_*]
    end

    subgraph Stage 4: Shifting, RNE Rounding & Pack
        R3 --> WideShift[barrel_shifter: Left Shift by LZD count]
        WideShift --> RNE[param_adder_sub: RNE Rounding Increment]
        RNE --> Pack[Assemble Sign, Exponent, Mantissa]
        Pack --> Out[Outputs Y, valid_out, flags]
    end
```

### Stage-by-Stage Implementation Details

#### Stage 1: Unpack & Product Generation
- Unpacks $A$, $B$, $C$ and detects special cases (NaN, $0 \times \infty$, $\infty - \infty$, infinities).
- Computes 48-bit unsigned product of $A$ and $B$ significands using `param_multiplier`:
  $$P_{raw}[47:0] = F_A \times F_B$$
- Product exponent: $E_{prod} = E_A + E_B - 127$ (10-bit signed).

#### Stage 2: Wide Alignment
- Computes $E_{prod} - E_C$ with `param_adder_sub` (10-bit signed).
- Places the product at bits [99:52] and $C$'s significand at bits [99:76] of 100-bit fields. Right-shifts the operand with the smaller exponent by $d = |E_{prod} - E_C|$ (saturated at 98) using a 100-bit `barrel_shifter`.
- **Bug:** $|E_{prod} - E_C|$ is computed into the 8-bit `s2_abs_diff`. The signed difference can exceed ±255, so it wraps modulo 256 and the shift is far too small. Example: $-279 \rightarrow 23$. A product that should be negligible is then added at a much higher weight.
- Shifter sticky outputs are unconnected; bits shifted below bit 0 are lost.

#### Stage 3: 100-bit Add/Subtract & Cancellation Detection
- Effective operation: subtract if $S_A \oplus S_B \ne S_C$. The larger-magnitude operand is placed first.
- Executes 100-bit wide addition or subtraction using `param_adder_sub` (carry-out kept as bit 100).
- Scans the 100-bit sum using the 100-bit `leading_zero_detector` and registers the sum, LZD count and tentative exponent into `r3_*`.

#### Stage 4: Normalization Shifting, Rounding & Packing
- Shifts the 100-bit accumulator left by the LZD shift count using 100-bit `barrel_shifter`.
- Extracts 24-bit normalized significand along with Guard ($G$), Round ($R$), and Sticky ($S$) bits.
- Adds RNE rounding increment via `param_adder_sub`.
- Handles rounding overflow and formats 32-bit output: $Y = \{S_{final}, E_{final}[7:0], M_{final}[22:0]\}$.

---

## 4. Verification & Simulation Guide

To compile, lint, simulate, and view waveforms in GTKWave:

```bash
./run fpu_mac
```

### Verified Test Categories (19/19 Tests Pass):
1. **Direct FMA Operations**:
   - $1.0 \times 1.0 + 1.0 = 2.0$
   - $2.0 \times 3.0 + 4.0 = 10.0$
   - $2.5 \times 4.0 - 2.5 = 7.5$
   - $4.0 \times 5.0 + 6.0 = 26.0$
   - $10.0 \times 10.0 + 50.0 = 150.0$
2. **Cancellation to Zero**: $2.0 \times 2.0 - 4.0 = 0.0$ (`flag_zero = 1`).
3. **Corner Cases**: $0.0 \times 0.0 + 0.0 = 0.0$.
4. **Streaming Throughput**: 5 back-to-back vectors on consecutive cycles sustaining 1 op/cycle.

The project's random stimulus (CRV and cocotb) keeps exponents within roughly 115–135, so the product/addend exponent gap never gets large enough to trigger the alignment bug below.

---

## 5. Known Limitations (measured)

Independent bit-exact audit against an exact IEEE 754 reference (2026-10-18):

| Stimulus | Bit-exact | Failures |
|---|:---:|---|
| Normal inputs, full exponent range | 2,981 / 3,000 | all 19: **wrong normal result**, product exponent far below C's |
| Mixed (incl. subnormal operands and specials) | 4,824 / 5,044 | 205 flushed subnormals, 15 wrong values |

| Case | Expected | Got |
|---|---|---|
| `A=9B4E99D0, B=13D13455, C=7AAC7742` | `7AAC7742` | `7AAC773F` |
| `fma(0x00800000, 0.5, +0)` | `0x00400000` | `0x00000000` (`flag_underflow=1`) |

**Fix for the alignment bug:** compute the absolute difference from the full 10-bit signed `s2_exp_diff`, and saturate the shift amount to 98 from that value instead of from an 8-bit truncation.
