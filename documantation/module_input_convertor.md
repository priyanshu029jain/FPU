# Module Specification: `input_convertor`

---

## 1. Overview & Architectural Role

`input_convertor` transforms standard signed binary representations into the IEEE 754-2008 single-precision 32-bit floating-point format. It provides seamless interoperability between integer / fixed-point processors and the floating-point pipeline.

### Supported Conversion Modes:
1. **Mode 0 (Integer to Float)**: Converts a 32-bit signed two's-complement integer into IEEE 754 single-precision float.
2. **Mode 1 (Q16.16 Fixed-Point to Float)**: Converts a signed fixed-point number with a 16-bit integer part and a 16-bit fractional part into IEEE 754 float (e.g., `-6.625` encoded as `32'hFFF9_6000`).

Source file: [`component/input_convertor.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/input_convertor.v)  
Testbench: [`tb/sim_tb/tb_fpu_top.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_fpu_top.v)

---

## 2. Port Interface Specification

```verilog
module input_convertor (
    input  wire [31:0] binary_in,  // Signed input binary number
    input  wire        mode,       // 0: 32-bit Integer -> Float, 1: Q16.16 -> Float
    output wire [31:0] float_out   // Converted IEEE 754 single-precision float
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `binary_in` | 32 | Input | 32-bit signed binary input (two's complement). |
| `mode` | 1 | Input | `1'b0`: 32-bit Integer to Float; `1'b1`: Signed Q16.16 to Float. |
| `float_out` | 32 | Output | 32-bit IEEE 754 single-precision floating-point output. |

---

## 3. Mathematical & Logical Formulation

### 3.1 Sign and Absolute Magnitude
$$\text{sign} = \text{binary\_in}[31]$$
$$\text{mag} = \text{sign} \ ? \ (-\text{binary\_in}) : \text{binary\_in}$$

### 3.2 Finding the Most Significant Set Bit ($MSB$)
A priority encoder locates $msb\_pos = \max \{i \mid mag[i] = 1\}$ for $i \in [31:0]$.

### 3.3 Exponent Calculation with Bias (+127)
- **Mode 0 (Integer)**: Bit $msb\_pos$ has weight $2^{msb\_pos}$.
  $$\text{Exponent} = msb\_pos + 127$$
- **Mode 1 (Q16.16)**: Bit $msb\_pos$ has weight $2^{msb\_pos - 16}$.
  $$\text{Exponent} = (msb\_pos - 16) + 127 = msb\_pos + 111$$

### 3.4 Significand Normalization
The implicit leading bit at $msb\_pos$ is removed, and the remaining bits are shifted to fill the 23-bit mantissa space:
$$\text{mantissa} = \begin{cases}
mag[msb\_pos-1 : msb\_pos-23] & \text{if } msb\_pos \ge 23 \\
mag \ll (23 - msb\_pos) & \text{if } msb\_pos < 23 
\end{cases}$$

### 3.5 Output Assembly
$$\text{float\_out} = (mag == 0) \ ? \ 32\text{'h00000000} : \{\text{sign}, \text{Exponent}[7:0], \text{mantissa}[22:0]\}$$

---

## 4. Verification & Simulation Guide

Verified as part of the unified regression suite:
```bash
./run top
```

### Sample Conversions Verified:
- Integer $0 \rightarrow \text{0x00000000}$
- Integer $1 \rightarrow \text{0x3F800000}$ ($1.0$)
- Integer $2 \rightarrow \text{0x40000000}$ ($2.0$)
- Integer $10 \rightarrow \text{0x41200000}$ ($10.0$)
- Q16.16 $1.5 \rightarrow \text{0x3FC00000}$
- Q16.16 $-6.625 \rightarrow \text{0xC0D40000}$
