# Module Specification: `param_adder_sub`

---

## 1. Overview & Architectural Role

`param_adder_sub` is a synthesizable, parameterized $N$-bit adder-subtractor designed for high-performance integer and floating-point datapath arithmetic. It serves as a foundational building block throughout the FPU:
- **`FPU_adder`**: Computes exponent differences ($|E_A - E_B|$), adds/subtracts 28-bit aligned significands, and applies Round-to-Nearest-Even (RNE) significand increments.
- **`FPU_multiplier`**: Adds exponents ($E_A + E_B$), subtracts bias ($127$), and applies rounding increments.
- **`FPU_division`**: Subtracts exponents ($E_A - E_B$), adds bias ($127$), and handles quotient rounding.
- **`FPU_mac`**: Executes 100-bit wide accumulation ($A \times B \pm C$) and 24-bit rounding.

Source file: [`component/param_adder_sub.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/param_adder_sub.v)  
Testbench: [`tb/sim_tb/tb_adder.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_adder.v)

---

## 2. Port Interface Specification

```verilog
module param_adder_sub #(
    parameter DATA_WIDTH = 32
)(
    input  wire [DATA_WIDTH-1:0] data_a,   // Operand A
    input  wire [DATA_WIDTH-1:0] data_b,   // Operand B
    input  wire                  sub,      // Operation select: 0 = Add, 1 = Subtract
    output wire [DATA_WIDTH-1:0] result,   // Arithmetic result
    output wire                  cout,     // Unsigned carry-out (Bit DATA_WIDTH)
    output wire                  overflow  // Signed two's-complement overflow
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `data_a` | `DATA_WIDTH` | Input | Primary arithmetic operand $A$. |
| `data_b` | `DATA_WIDTH` | Input | Secondary arithmetic operand $B$. In subtraction, computes $A - B$. |
| `sub` | 1 | Input | Mode control: `1'b0` for addition ($A + B$), `1'b1` for subtraction ($A - B$). |
| `result` | `DATA_WIDTH` | Output | Lower `DATA_WIDTH` bits of the operation. |
| `cout` | 1 | Output | **Unsigned Carry-out**: Indicates $A + B \ge 2^{\text{DATA\_WIDTH}}$ or no-borrow in subtraction. |
| `overflow`| 1 | Output | **Signed Two's-Complement Overflow**: Indicates result cannot fit in signed range $[-2^{W-1}, 2^{W-1}-1]$. |

---

## 3. Mathematical & Logical Formulation

### 3.1 Addition Mode (`sub = 0`)
$$\text{full\_sum} = \{1'b0, data\_a\} + \{1'b0, data\_b\}$$
$$\text{result} = \text{full\_sum}[\text{DATA\_WIDTH}-1:0]$$
$$\text{cout} = \text{full\_sum}[\text{DATA\_WIDTH}]$$

### 3.2 Subtraction Mode (`sub = 1`)
Using two's complement arithmetic:
$$A - B = A + (\sim B) + 1$$
$$\text{full\_sum} = \{1'b0, data\_a\} - \{1'b0, data\_b\}$$

### 3.3 Overflow Equations
Signed overflow occurs when the sign of the result contradicts the operand signs:

$$\text{overflow}_{\text{add}} = (data\_a[W-1] \equiv data\_b[W-1]) \land (result[W-1] \ne data\_a[W-1])$$
$$\text{overflow}_{\text{sub}} = (data\_a[W-1] \ne data\_b[W-1]) \land (result[W-1] \ne data\_a[W-1])$$

$$\text{overflow} = \text{sub} \ ? \ \text{overflow}_{\text{sub}} : \text{overflow}_{\text{add}}$$

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
