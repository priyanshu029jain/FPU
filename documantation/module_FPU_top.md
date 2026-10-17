# Module Specification: `FPU_top`

---

## 1. Overview & Architectural Role

`FPU_top` is the top-level integration wrapper for the entire 32-bit IEEE 754-2008 Floating-Point Unit. It unifies the 4 execution blocks (`FPU_adder`, `FPU_multiplier`, `FPU_mac`, and `FPU_division`) under a centralized 2-bit opcode interface.

### Opcode Mapping:
- `op = 2'b00` : **Addition / Subtraction** ($Y = A + B$)
- `op = 2'b01` : **Multiplication** ($Y = A \times B$)
- `op = 2'b10` : **Fused Multiply-Add / MAC** ($Y = A \times B + C$)
- `op = 2'b11` : **Division** ($Y = A \div B$)

### Key Features:
- **Unified 4-Stage Latency**: Every operation across all 4 opcodes is aligned to a deterministic 4-clock-cycle latency.
- **Clocked Opcode Pipeline**: An internal 4-cycle shift register tracks `op` across the pipeline to multiplex the correct execution engine output onto the top-level bus.
- **Complete IEEE 754 Status Flags**: Aggregates and drives `flag_zero`, `flag_inf`, `flag_nan`, `flag_invalid`, `flag_overflow`, `flag_underflow`, `flag_inexact`, and `flag_div_by_zero`.

Source file: [`rtl/FPU_top.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/rtl/FPU_top.v)  
Testbench: [`tb/sim_tb/tb_fpu_top.v`](file:///c:/Users/LENOVO/Documents/GitHub/floating_point_unit/tb/sim_tb/tb_fpu_top.v)

---

## 2. Port Interface Specification

```verilog
module FPU_top (
    input  wire        clk,             // System Clock
    input  wire        rst_n,           // Active-low Asynchronous Reset
    input  wire        valid_in,        // Input Data Valid Strobe
    input  wire [1:0]  op,              // Operation Select (00:Add, 01:Mul, 10:MAC, 11:Div)
    input  wire [31:0] A,               // IEEE 754 Float Operand A
    input  wire [31:0] B,               // IEEE 754 Float Operand B
    input  wire [31:0] C,               // IEEE 754 Float Operand C (used in MAC: A*B + C)
    output reg  [31:0] Y,               // IEEE 754 Float Result Output
    output reg         valid_out,       // Output Valid Strobe (4 Cycles Latency)
    output reg         flag_zero,       // Output is Zero
    output reg         flag_inf,        // Output is Infinity
    output reg         flag_nan,        // Output is NaN
    output reg         flag_invalid,    // Invalid Operation (e.g. Inf - Inf, 0/0)
    output reg         flag_overflow,   // Exponent Overflowed (> 254)
    output reg         flag_underflow,  // Exponent Underflowed (< 1)
    output reg         flag_inexact,    // Bits Discarded During Rounding
    output reg         flag_div_by_zero // Division by Zero (B == 0)
);
```

### Signal Descriptions

| Port | Width | Direction | Description |
| :--- | :---: | :---: | :--- |
| `clk` | 1 | Input | Positive-edge triggered system clock. |
| `rst_n` | 1 | Input | Active-low asynchronous system reset. |
| `valid_in` | 1 | Input | Strobe indicating valid inputs on `A`, `B`, `C`, and `op`. |
| `op` | 2 | Input | Opcode: `00` = Add/Sub, `01` = Mul, `10` = MAC, `11` = Div. |
| `A`, `B`, `C` | 32 | Input | 32-bit single-precision float inputs. |
| `Y` | 32 | Output | 32-bit single-precision float output. |
| `valid_out` | 1 | Output | Valid strobe asserted 4 clock cycles after `valid_in`. |
| `flag_*` | 1 | Output | Decomposed IEEE 754 status and exception flags. |

---

## 3. Top-Level Datapath Architecture

```mermaid
graph TD
    In[Inputs: clk, rst_n, valid_in, op, A, B, C] --> Demux[Opcode Input Gating]
    
    Demux -->|op == 00| Adder[FPU_adder: 4-Stage Pipeline]
    Demux -->|op == 01| Mul[FPU_multiplier: 4-Stage Pipeline]
    Demux -->|op == 10| MAC[FPU_mac: 4-Stage Pipeline]
    Demux -->|op == 11| Div[FPU_division: 4-Stage Pipeline]

    In --> OpPipe[4-Cycle Opcode Pipeline Shift Register: op_pipe_d4]

    Adder --> Mux[Output Multiplexer]
    Mul --> Mux
    MAC --> Mux
    Div --> Mux
    OpPipe --> Mux

    Mux --> Out[Outputs: Y, valid_out, IEEE 754 Exception Flags]
```

### Opcode Delay Pipeline
To ensure that the output multiplexer selects the result corresponding to the operation initiated 4 clock cycles prior, `op` and `valid_in` are shifted across internal pipeline registers:
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        op_d1 <= 2'b00; op_d2 <= 2'b00; op_d3 <= 2'b00; op_d4 <= 2'b00;
        v_d1  <= 1'b0;  v_d2  <= 1'b0;  v_d3  <= 1'b0;  v_d4  <= 1'b0;
    end else begin
        op_d1 <= op;    op_d2 <= op_d1; op_d3 <= op_d2; op_d4 <= op_d3;
        v_d1  <= valid_in; v_d2 <= v_d1; v_d3 <= v_d2; v_d4 <= v_d3;
    end
end
```

### Output Routing:
```verilog
always @(*) begin
    case (op_d4)
        2'b00: begin // ADD / SUB
            Y = y_add; valid_out = v_add; flag_overflow = ovf_add;
            flag_underflow = unf_add; flag_invalid = inv_add; flag_zero = z_add;
            flag_inexact = inex_add; flag_div_by_zero = 1'b0;
        end
        2'b01: begin // MULTIPLY
            Y = y_mul; valid_out = v_mul; flag_overflow = ovf_mul;
            flag_underflow = unf_mul; flag_invalid = inv_mul; flag_zero = z_mul;
            flag_inexact = inex_mul; flag_div_by_zero = 1'b0;
        end
        2'b10: begin // MAC / FMA
            Y = y_mac; valid_out = v_mac; flag_overflow = ovf_mac;
            flag_underflow = unf_mac; flag_invalid = inv_mac; flag_zero = z_mac;
            flag_inexact = inex_mac; flag_div_by_zero = 1'b0;
        end
        2'b11: begin // DIVISION
            Y = y_div; valid_out = v_div; flag_overflow = ovf_div;
            flag_underflow = unf_div; flag_invalid = inv_div; flag_zero = z_div;
            flag_inexact = inex_div; flag_div_by_zero = dz_div;
        end
    endcase
end
```

---

## 4. Verification & Simulation Guide

To compile, lint, simulate, and view waveforms for the entire suite in GTKWave:

```bash
./run top
```

### Summary of Full 180+ Test Suite:
- **`input_convertor`**: 25 tests (Integers & Q16.16 fixed-point to float).
- **`output_convertor`**: 25 tests (Float to integer & Q16.16, field unpacking, flags).
- **`FPU_adder`**: 36 tests (Direct, corner, subtraction, infinities, NaNs, streaming).
- **`FPU_multiplier`**: 25 tests (Direct, fractions, signs, corners, streaming).
- **`FPU_mac`**: 19 tests (FMA, cancellation, corners, streaming).
- **`FPU_division`**: 25 tests (Direct quotients, signs, corners, div-by-zero, streaming).
- **`FPU_top`**: 4 operational tests verifying opcode multiplexing across all 4 modes.
- **Master Result**: **180/180 TESTS PASSED (100% SUCCESS)**.
