# Module Specification: `param_adder_sub`

---

## 1. Overview & Architectural Role

`param_adder_sub` is a synthesizable, parameterized $N$-bit adder-subtractor used for integer and floating-point datapath arithmetic. It serves as a foundational building block throughout the FPU:
- **`FPU_adder`**: Computes exponent differences ($|E_A - E_B|$), adds/subtracts the 27-bit aligned significands, and applies Round-to-Nearest-Even (RNE) significand increments.
- **`FPU_multiplier`**: Adds exponents ($E_A + E_B$), subtracts bias ($127$), and applies rounding increments.
- **`FPU_division`**: Subtracts exponents ($E_A - E_B$), adds bias ($127$), and handles quotient rounding.
- **`FPU_mac`**: Executes 100-bit wide accumulation ($A \times B \pm C$) and 24-bit rounding.

Source file: [`component/param_adder_sub.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/param_adder_sub.v)  
Testbench: [`tb/sim_tb/tb_adder.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_adder.v)

---

## 2. Port Interface Specification

```verilog
module param_adder_sub #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] A,          // Operand A
    input  wire [WIDTH-1:0] B,          // Operand B
    input  wire             sub,        // 0 = Add (A + B), 1 = Subtract (A - B)
    input  wire             is_signed,  // 0 = Unsigned, 1 = Signed (two's complement)
    output wire [WIDTH-1:0] result,     // Arithmetic result
    output wire             carry_out,  // Carry-out of bit WIDTH-1 (no-borrow in subtraction)
    output wire             overflow    // Signed overflow if is_signed, else equals carry_out
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `A` | `WIDTH` | Input | Primary arithmetic operand $A$. |
| `B` | `WIDTH` | Input | Secondary arithmetic operand $B$. In subtraction, computes $A - B$. |
| `sub` | 1 | Input | Mode control: `1'b0` for addition ($A + B$), `1'b1` for subtraction ($A - B$). |
| `is_signed` | 1 | Input | Selects the meaning of `overflow`: signed two's-complement overflow (`1`) or unsigned carry (`0`). |
| `result` | `WIDTH` | Output | Lower `WIDTH` bits of the operation. |
| `carry_out` | 1 | Output | **Unsigned carry-out**: $A + B \ge 2^{\text{WIDTH}}$ in addition, or *no borrow* ($A \ge B$) in subtraction. |
| `overflow` | 1 | Output | If `is_signed = 1`: result does not fit in $[-2^{W-1}, 2^{W-1}-1]$. If `is_signed = 0`: same as `carry_out`. |

---

## 3. Mathematical & Logical Formulation

The RTL uses a single $(W+1)$-bit adder with conditional inversion of $B$:

$$b' = \text{sub} \ ? \ \sim B : B, \qquad c_{in} = \text{sub}$$
$$\text{sum\_ext} = \{1'b0, A\} + \{1'b0, b'\} + c_{in}$$
$$\text{result} = \text{sum\_ext}[W-1:0], \qquad \text{carry\_out} = \text{sum\_ext}[W]$$

### Overflow
Signed overflow is detected on the effective operands $A$ and $b'$:

$$\text{ovf}_{signed} = (A[W-1] = b'[W-1]) \land (\text{result}[W-1] \ne A[W-1])$$
$$\text{overflow} = \text{is\_signed} \ ? \ \text{ovf}_{signed} : \text{carry\_out}$$

Because $b' = \sim B$ in subtraction, this is equivalent to the usual subtraction rule $(A[W-1] \ne B[W-1]) \land (\text{result}[W-1] \ne A[W-1])$.

The adder is written behaviourally (`+`), so its gate structure (ripple, carry-lookahead, etc.) is chosen by the synthesis tool.

---

## 4. Verification & Simulation Guide

To verify `param_adder_sub` with direct, corner, and random vectors:

```bash
./run adder
```

### Verified Scenarios:
- Zero operand additions: $0 + 0 = 0$, $A + 0 = A$.
- Maximum unsigned boundary: $0xFF + 0x01 = 0x100$ (`cout = 1`).
- Signed two's-complement overflow: $+30 + (+99) = +129$ in 8-bit (`overflow = 1`).
- Subtraction borrow conditions: $50 - 10 = 40$, $10 - 50 = -40$.
- 50 pseudo-random vectors verified against a behavioral golden model.
