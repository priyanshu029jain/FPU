# Module Specification: `barrel_shifter`

---

## 1. Overview & Architectural Role

`barrel_shifter` is a parameterized, single-cycle combinational barrel shifter capable of bidirectional (left/right) logical and arithmetic shifts. It also provides a **Sticky Bit Generator** which calculates the reduction OR of all bits shifted beyond the right boundary, an indispensable feature for IEEE 754 Guard-Round-Sticky (GRS) rounding.

### Role in FPU Modules:
- **`FPU_adder`**: Aligns the smaller significand rightwards by the exponent difference ($\Delta E$), capturing sticky bits. Post-normalizes the sum leftwards by the LZD cancellation count.
- **`FPU_multiplier`**: Shifts the 48-bit product right by 1 bit when bit 47 is set.
- **`FPU_division`**: Performs 1-bit normalization alignment on the computed quotient.
- **`FPU_mac`**: Two 100-bit instances right-align whichever of the product or $C$ has the smaller exponent; a third left-shifts the 100-bit sum for normalization. The `sticky` outputs of these instances are left unconnected, so bits shifted out are discarded.

Source file: [`component/barrel_shifter.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/barrel_shifter.v)  
Testbench: [`tb/sim_tb/tb_barrel_shifter.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_barrel_shifter.v)

---

## 2. Port Interface Specification

```verilog
module barrel_shifter #(
    parameter DATA_WIDTH  = 48,
    parameter SHIFT_WIDTH = 6
)(
    input  wire [DATA_WIDTH-1:0]  data_in,   // Input data vector
    input  wire [SHIFT_WIDTH-1:0] shift_amt, // Shift distance
    input  wire                   dir,       // 0: Shift Left, 1: Shift Right
    input  wire                   arith,     // 0: Logical (zero-fill), 1: Arithmetic (sign-extend)
    output reg  [DATA_WIDTH-1:0]  data_out,  // Shifted output
    output reg                    sticky     // 1 if any '1' bit was shifted off the right boundary
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `data_in` | `DATA_WIDTH` | Input | Input vector to be shifted. |
| `shift_amt`| `SHIFT_WIDTH`| Input | Number of bit positions to shift ($0 \le \text{shift\_amt} < 2^{\text{SHIFT\_WIDTH}}$). |
| `dir` | 1 | Input | Direction selector: `1'b0` = Shift Left ($\ll$), `1'b1` = Shift Right ($\gg$). |
| `arith` | 1 | Input | Fill mode: `1'b0` = Zero-fill (logical), `1'b1` = Sign-extension (arithmetic). |
| `data_out` | `DATA_WIDTH` | Output | Shifted result vector. |
| `sticky` | 1 | Output | Exact reduction OR of all discarded bits below LSB (GRS sticky bit). |

---

## 3. Mathematical & Logical Formulation

### 3.1 Left Shift (`dir = 0`)
$$\text{data\_out} = \text{data\_in} \ll \text{shift\_amt}$$
$$\text{sticky} = 1'b0$$

### 3.2 Right Shift (`dir = 1`)
- **Overshift Condition ($\text{shift\_amt} \ge \text{DATA\_WIDTH}$)**:
  - If logical (`arith = 0`): `data_out = 0`.
  - If arithmetic (`arith = 1`): `data_out = {DATA_WIDTH{sign_bit}}`.
  - `sticky = |data_in` (all non-zero bits were shifted out).

- **In-Range Shift ($\text{shift\_amt} < \text{DATA\_WIDTH}$)**:
  - **Logical**: `data_out = data_in >> shift_amt`.
  - **Arithmetic**: `data_out = (data_in >> shift_amt) | ({DATA_WIDTH{1'b1}} << (DATA_WIDTH - shift_amt))`.
  - **Sticky Bit Extraction**: A dynamic bitmask is evaluated across the lower `shift_amt` bits:
    $$\text{mask}[i] = 1'b1 \quad \forall \ i < \text{shift\_amt}$$
    $$\text{sticky} = \bigvee_{i=0}^{\text{shift\_amt}-1} \text{data\_in}[i] = |(\text{data\_in} \ \& \ \text{mask})$$

---

## 4. Verification & Simulation Guide

To verify `barrel_shifter` with direct, corner, and random vectors:

```bash
./run barrel_shifter
```

### Verified Scenarios:
- Left shifts: shift 4, shift 8 (`sticky = 0`).
- Right shifts without bit loss: `0xF0 >> 4` (`sticky = 0`).
- Right shifts with bit loss: `0xF5 >> 4 = 0x0F` (`sticky = 1`).
- Zero shift passthrough: `shift_amt = 0`.
- Maximum single-bit sweep: shift by `DATA_WIDTH - 1`.
- Overshift: shift by 48, shift by 55 (`sticky = |data_in`).
- 50 pseudo-random vectors verified against a golden model.
