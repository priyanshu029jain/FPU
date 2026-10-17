# Module Specification: `FPU_mac`

---

## 1. Overview & Architectural Role

`FPU_mac` is a 4-stage synchronous pipelined Fused Multiply-Accumulate (FMA / MAC) unit compliant with the IEEE 754-2008 standard. It computes:

$$Y = A \times B + C$$

### Key FMA Advantage:
Unlike a discrete multiplier followed by an adder (which introduces two separate rounding stages and double-rounding errors), this unit maintains **full 100-bit precision across the accumulation datapath** and executes **only a single rounding step** at the final stage, delivering higher numerical accuracy.

### Key Features:
- **4-Stage Synchronous Pipeline**: Deterministic 4-cycle latency from `valid_in` to `valid_out`.
- **Sustained Throughput**: Accepts 1 new operation per clock cycle (100% throughput).
- **Subcomponent Instantiation**: Fully integrates `param_multiplier`, 100-bit `barrel_shifter`, 100-bit `param_adder_sub`, 100-bit `leading_zero_detector`, and `param_adder_sub`.
- **Full IEEE 754-2008 Exception Handling**: `flag_overflow`, `flag_underflow`, `flag_invalid`, `flag_zero`, `flag_inexact`.

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
| `flag_underflow` | 1 | Output | Exponent $\le 0$; underflow detected. |
| `flag_invalid` | 1 | Output | $(0 \times \infty) + C$, $(+\infty) + (-\infty)$, or NaN operands. |
| `flag_zero` | 1 | Output | Result cancels to exact zero. |
| `flag_inexact` | 1 | Output | Truncation occurred during wide alignment or final rounding. |

---

## 3. Pipeline Datapath Architecture

```mermaid
graph TD
    subgraph Stage 1: Product & Wide Alignment
        In[Operands A, B, C] --> Mul[param_multiplier: 24x24-bit Product -> 48 bits]
        In --> ExpCmp[Compare E_prod vs E_c]
        ExpCmp --> AlignC[barrel_shifter: 100-bit Right Shift of smaller operand]
        Mul --> R1[Registers r1_*]
        AlignC --> R1
    end

    subgraph Stage 2: 100-bit Wide Accumulation
        R1 --> WideAdd[param_adder_sub: 100-bit Sum Product +/- C]
        WideAdd --> R2[Registers r2_*]
    end

    subgraph Stage 3: Wide Cancellation & Normalization
        R2 --> WideLZD[leading_zero_detector: 100-bit Zero Count]
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

#### Stage 1: Product Generation & Wide Alignment
- Computes 48-bit unsigned product of $A$ and $B$ significands using `param_multiplier`:
  $$P_{raw}[47:0] = F_A \times F_B$$
- Unbiased product exponent: $E_{prod} = E_A + E_B - 127$.
- Compares $E_{prod}$ with $E_C$ to calculate alignment shift distance $d = |E_{prod} - E_C|$.
- Places the larger operand at the upper end of a 100-bit vector and right-shifts the smaller operand by $d$ positions using 100-bit `barrel_shifter`.

#### Stage 2: 100-bit Wide Accumulation
- Determines effective operation: $\text{eff\_sub} = (S_A \oplus S_B) \oplus S_C$.
- Executes 100-bit wide addition or subtraction using `param_adder_sub`:
  $$\text{sum\_100} = \text{aligned\_prod} \pm \text{aligned\_C}$$
- Registers the 100-bit sum and tentative exponent into `r2_*`.

#### Stage 3: Wide Cancellation Detection
- Scans the 100-bit accumulator using 100-bit `leading_zero_detector`.
- Evaluates whether subtractive cancellation occurred and stores the shift count into `r3_*`.

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
