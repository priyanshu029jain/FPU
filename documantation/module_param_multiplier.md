# Module Specification: `param_multiplier`

---

## 1. Overview & Architectural Role

`param_multiplier` is a synthesizable, parameterized multiplier supporting arbitrary bit-widths (`WIDTH_A`, `WIDTH_B`) and signed or unsigned product modes. In the FPU architecture:
- **`FPU_multiplier`**: Computes the 48-bit unsigned product of two 24-bit normalized significands ($1.M_A \times 1.M_B$).
- **`FPU_mac`**: Multiplies operands $A$ and $B$ to 48-bit precision before wide alignment and accumulation with operand $C$.

Source file: [`component/param_multiplier.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/param_multiplier.v)  
Testbench: [`tb/sim_tb/tb_multiplier.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_multiplier.v)

---

## 2. Port Interface Specification

```verilog
module param_multiplier #(
    parameter WIDTH_A = 24,
    parameter WIDTH_B = 24
)(
    input  wire [WIDTH_A-1:0]           data_a,   // Multiplicand A
    input  wire [WIDTH_B-1:0]           data_b,   // Multiplier B
    input  wire                         is_signed,// 0: Unsigned, 1: Signed Two's-Complement
    output wire [WIDTH_A + WIDTH_B - 1:0] product // Product result
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `data_a` | `WIDTH_A` | Input | Multiplicand input operand $A$. |
| `data_b` | `WIDTH_B` | Input | Multiplier input operand $B$. |
| `is_signed` | 1 | Input | Mode flag: `1'b0` for unsigned multiplication, `1'b1` for signed multiplication. |
| `product` | `WIDTH_A + WIDTH_B` | Output | Full-precision product ($A \times B$). |

---

## 3. Mathematical & Logical Formulation

### 3.1 Unsigned Multiplication (`is_signed = 0`)
Both operands represent non-negative binary integers:
$$\text{product} = \text{data\_a} \times \text{data\_b}$$
For $24 \times 24$ bits ($1.M_A \times 1.M_B$ where $1.0 \le \text{sig} < 2.0$):
$$\text{Product Range} \in [1.0, 4.0)$$
- If $\text{product}[47] = 1$: Result is in $[2.0, 4.0)$, requiring a 1-bit right shift and exponent increment by 1.
- If $\text{product}[47] = 0$: Result is in $[1.0, 2.0)$, already normalized (leading 1 at bit 46).

### 3.2 Signed Multiplication (`is_signed = 1`)
Operands are sign-extended and multiplied as signed two's-complement values:
$$\text{product} = \$signed(\text{data\_a}) \times \$signed(\text{data\_b})$$

---

## 4. Verification & Simulation Guide

To verify `param_multiplier` with direct, corner, and random vectors:

```bash
./run multiplier
```

### Verified Scenarios:
- Zero products: $0 \times \text{Max} = 0$, $0 \times 0 = 0$.
- Unity multiplication: $1 \times \text{0xABCDEF} = \text{0xABCDEF}$.
- Floating-point significand tests: $1.0 \times 1.0$ (`0x400000000000`), $1.5 \times 1.5 = 2.25$ (`0x900000000000`).
- Full-width saturation: $2^{24}-1 \times 2^{24}-1 = \text{0xFFFFFE000001}$.
- Signed negative multiplication: $50 \times (-10) = -500$, $(-50) \times (-10) = 500$.
- 50 pseudo-random vectors verified against a golden model.
