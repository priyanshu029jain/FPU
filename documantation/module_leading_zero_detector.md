# Module Specification: `leading_zero_detector`

---

## 1. Overview & Architectural Role

`leading_zero_detector` (LZD) is a parameterized, synthesizable priority encoder that counts the number of consecutive zero bits starting from the Most Significant Bit (MSB) until the first `1` is encountered.

### Role in FPU Modules:
- **`FPU_adder`**: When subtracting two near-equal floating-point numbers ($A - B$ where $E_A \approx E_B$), catastrophic cancellation occurs, resulting in multiple leading zeros. The LZD determines the exact left-shift distance required to restore the implicit leading `1.0` in Stage 3.
- **`FPU_mac`**: Scans the 100-bit wide intermediate accumulation result to detect cancellation and restore normalized alignment.

Source file: [`component/leading_zero_detector.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/component/leading_zero_detector.v)  
Testbench: [`tb/sim_tb/tb_LZD.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_LZD.v)

---

## 2. Port Interface Specification

```verilog
module leading_zero_detector #(
    parameter WIDTH = 32,
    parameter CNT_W = $clog2(WIDTH + 1)
)(
    input  wire [WIDTH-1:0] data_in,   // Input data vector
    output reg  [CNT_W-1:0] zero_count,// Number of leading zeros
    output reg              all_zeros  // Set high if data_in is completely 0
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `data_in` | `WIDTH` | Input | Input vector to be scanned from MSB down to LSB. |
| `zero_count` | `CNT_W` | Output | Count of leading zeros ($0 \le \text{zero\_count} \le \text{WIDTH}$). |
| `all_zeros` | 1 | Output | Asserted `1'b1` if `data_in == {WIDTH{1'b0}}`. |

---

## 3. Mathematical & Logical Formulation

### 3.1 Scanning Algorithm
The scanning logic executes sequentially from MSB ($\text{WIDTH}-1$) down to LSB ($0$):

$$\text{zero\_count} = \begin{cases} 
0 & \text{if } data\_in[\text{WIDTH}-1] = 1 \\
1 & \text{if } data\_in[\text{WIDTH}-1] = 0 \land data\_in[\text{WIDTH}-2] = 1 \\
k & \text{if } \left(\bigwedge_{j=1}^{k} \overline{data\_in[\text{WIDTH}-j]}\right) \land data\_in[\text{WIDTH}-1-k] = 1 \\
\text{WIDTH} & \text{if } data\_in = 0 
\end{cases}$$

### 3.2 All-Zero Flag
$$\text{all\_zeros} = \overline{\bigvee_{i=0}^{\text{WIDTH}-1} data\_in[i]} = (data\_in == 0)$$

---

## 4. Verification & Simulation Guide

To verify `leading_zero_detector` with direct, corner, and random vectors:

```bash
./run LZD
```

### Verified Scenarios:
- Single-bit MSB: `0x80000000` (`zero_count = 0, all_zeros = 0`).
- Single-bit LSB: `0x00000001` (`zero_count = 31, all_zeros = 0`).
- Mid-range powers of two: Bit 30, Bit 16, Bit 8.
- Vectors with lower noisy bits: `0x8000FFFF` (`zero_count = 0`), `0x00801234` (`zero_count = 8`).
- All-zero vector: `0x00000000` (`zero_count = 32, all_zeros = 1`).
- All-one vector: `0xFFFFFFFF` (`zero_count = 0, all_zeros = 0`).
- Full 32-position one-hot sweep (sliding `1` through all 32 bit positions).
- 50 pseudo-random vectors verified against a golden model.
