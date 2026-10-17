# Module Specification: `output_convertor`

---

## 1. Overview & Architectural Role

`output_convertor` decodes and converts an IEEE 754-2008 single-precision 32-bit float into signed integer or signed Q16.16 fixed-point representations. Simultaneously, it unpacks internal fields (sign, unbiased true base-2 exponent, and full 24-bit significand with implicit 1 restored) and generates classification flags (Zero, Infinity, NaN, and Integer Overflow) for system-level debugging and waveform inspection.

Source file: [`component/output_convertor.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/output_convertor.v)  
Testbench: [`tb/sim_tb/tb_fpu_top.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_fpu_top.v)

---

## 2. Port Interface Specification

```verilog
module output_convertor (
    input  wire [31:0] float_in,           // IEEE 754 single-precision float
    input  wire        mode,               // 0: Float -> Signed Int, 1: Float -> Q16.16
    output wire [31:0] binary_out,         // Converted signed binary result
    output wire        sign,               // Extracted sign bit
    output wire signed [8:0] unbiased_exp, // E - 127 (true base-2 exponent)
    output wire [23:0] significand,        // 24-bit significand (implicit 1 restored)
    output wire        is_zero,            // Asserted if input is 0.0
    output wire        is_inf,             // Asserted if input is +/- Infinity
    output wire        is_nan,             // Asserted if input is NaN
    output wire        overflow            // Asserted if float exceeds 32-bit binary container
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `float_in` | 32 | Input | 32-bit IEEE 754 single-precision floating-point input. |
| `mode` | 1 | Input | Conversion target: `1'b0` = Signed 32-bit Integer, `1'b1` = Signed Q16.16. |
| `binary_out` | 32 | Output | Converted signed two's-complement binary value. |
| `sign` | 1 | Output | Float sign bit (`float_in[31]`). |
| `unbiased_exp`| 9 | Output | True signed exponent: $E - 127$. |
| `significand` | 24 | Output | Restored 24-bit significand: $\{1'b1, M\}$ for normal, $\{1'b0, M\}$ for subnormal. |
| `is_zero` | 1 | Output | Input is $+0.0$ or $-0.0$. |
| `is_inf` | 1 | Output | Input is $+\infty$ or $-\infty$. |
| `is_nan` | 1 | Output | Input is a Quiet or Signaling NaN. |
| `overflow` | 1 | Output | Converted value saturates or overflows 32-bit output container. |

---

## 3. Mathematical & Logical Formulation

### 3.1 Field Unpacking
$$\text{sign} = \text{float\_in}[31]$$
$$\text{expo} = \text{float\_in}[30:23]$$
$$\text{mant} = \text{float\_in}[22:0]$$
$$\text{unbiased\_exp} = \$signed(\{1'b0, \text{expo}\}) - 9'sd127$$
$$\text{significand} = (\text{expo} == 8'h00) \ ? \ \{1'b0, \text{mant}\} : \{1'b1, \text{mant}\}$$

### 3.2 Classification Flags
- $\text{is\_zero} = (\text{expo} == 8'h00) \land (\text{mant} == 0)$
- $\text{is\_inf} = (\text{expo} == 8'hFF) \land (\text{mant} == 0)$
- $\text{is\_nan} = (\text{expo} == 8'hFF) \land (\text{mant} \ne 0)$

### 3.3 Conversion to Binary
- **Integer Mode (`mode = 0`)**:
  - If $\text{unbiased\_exp} < 0$: Magnitude is strictly fractional ($< 1.0$), so `mag = 0`.
  - If $0 \le \text{unbiased\_exp} \le 23$: Shift right: $mag = \text{significand} \gg (23 - \text{unbiased\_exp})$.
  - If $23 < \text{unbiased\_exp} \le 30$: Shift left: $mag = \text{significand} \ll (\text{unbiased\_exp} - 23)$.
  - If $\text{unbiased\_exp} \ge 31$: Assert `overflow = 1`.
- **Two's Complement Negation**:
  $$\text{binary\_out} = \text{sign} \ ? \ (-\text{mag}) : \text{mag}$$

---

## 4. Verification & Simulation Guide

Verified as part of the unified regression suite:
```bash
./run top
```

### Verified Conversions:
- Float $1.0$ (`0x3F800000`) $\rightarrow$ Integer `1`
- Float $10.0$ (`0x41200000`) $\rightarrow$ Integer `10`
- Float $-50.0$ (`0xC2480000`) $\rightarrow$ Integer `-50`
- Float $1.5$ (`0x3FC00000`) $\rightarrow$ Q16.16 `0x00018000`
- Float $+0.0$ $\rightarrow$ `is_zero = 1`
- Float $+\infty$ $\rightarrow$ `is_inf = 1`
- Float NaN $\rightarrow$ `is_nan = 1`
