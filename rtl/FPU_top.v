// =============================================================================
// Module  : FPU_top
// Purpose : Unified 32-bit IEEE 754 Pipelined Floating-Point Unit Top-Level
// Opcode  :
//   2'b00 : Addition / Subtraction  (Y = A + B)
//   2'b01 : Multiplication          (Y = A * B)
//   2'b10 : Fused Multiply-Add      (Y = A * B + C)
//   2'b11 : Division                (Y = A / B)
// Latency : 4 Clock Cycles
// Throughput : 1 Operation / Cycle (Fully Pipelined)
// Features: Full special case detection, GRS rounding, decomposed status flags.
// =============================================================================
`timescale 1ns/1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */

module FPU_top (
    input  wire        clk,
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        valid_in,       // Input data valid strobe
    input  wire [1:0]  op,             // 00: Add, 01: Mul, 10: MAC, 11: Div
    input  wire [31:0] A,              // Operand A (IEEE 754 float)
    input  wire [31:0] B,              // Operand B (IEEE 754 float)
    input  wire [31:0] C,              // Operand C (used in MAC: A*B + C)
    output reg  [31:0] Y,              // IEEE 754 Float Output
    output reg         valid_out,      // Valid output strobe (4 cycles latency)
    output reg         flag_zero,      // Output is Zero
    output reg         flag_inf,       // Output is Infinity
    output reg         flag_nan,       // Output is NaN
    output reg         flag_invalid,   // Invalid operation
    output reg         flag_overflow,  // Output Exponent Overflowed
    output reg         flag_underflow, // Output Exponent Underflowed
    output reg         flag_inexact,   // Inexact flag (bits lost in rounding)
    output reg         flag_div_by_zero// Division-by-Zero flag
);

    // Sub-unit outputs
    wire [31:0] y_add, y_mul, y_mac, y_div;
    wire        v_add, v_mul, v_mac, v_div;
    wire        ovf_add, ovf_mul, ovf_mac, ovf_div;
    wire        unf_add, unf_mul, unf_mac, unf_div;
    wire        inv_add, inv_mul, inv_mac, inv_div;
    wire        z_add, z_mul, z_mac, z_div;
    wire        inex_add, inex_mul, inex_mac, inex_div;
    wire        dz_div;

    // 1. Floating-Point Adder / Subtractor (4-Stage Pipelined)
    FPU_adder u_adder (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (valid_in && (op == 2'b00)),
        .A             (A),
        .B             (B),
        .Y             (y_add),
        .valid_out     (v_add),
        .flag_overflow (ovf_add),
        .flag_underflow(unf_add),
        .flag_invalid  (inv_add),
        .flag_zero     (z_add),
        .flag_inexact  (inex_add)
    );

    // 2. Floating-Point Multiplier (4-Stage Pipelined)
    FPU_multiplier u_multiplier (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (valid_in && (op == 2'b01)),
        .A             (A),
        .B             (B),
        .Y             (y_mul),
        .valid_out     (v_mul),
        .flag_overflow (ovf_mul),
        .flag_underflow(unf_mul),
        .flag_invalid  (inv_mul),
        .flag_zero     (z_mul),
        .flag_inexact  (inex_mul)
    );

    // 3. Fused Multiply-Accumulate (4-Stage Pipelined)
    FPU_mac u_mac (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (valid_in && (op == 2'b10)),
        .A             (A),
        .B             (B),
        .C             (C),
        .Y             (y_mac),
        .valid_out     (v_mac),
        .flag_overflow (ovf_mac),
        .flag_underflow(unf_mac),
        .flag_invalid  (inv_mac),
        .flag_zero     (z_mac),
        .flag_inexact  (inex_mac)
    );

    // 4. Floating-Point Divider (4-Stage Pipelined)
    FPU_division u_division (
        .clk             (clk),
        .rst_n           (rst_n),
        .valid_in        (valid_in && (op == 2'b11)),
        .A               (A),
        .B               (B),
        .Y               (y_div),
        .valid_out       (v_div),
        .flag_overflow   (ovf_div),
        .flag_underflow  (unf_div),
        .flag_invalid    (inv_div),
        .flag_div_by_zero(dz_div),
        .flag_zero       (z_div),
        .flag_inexact    (inex_div)
    );

    // Opcode pipeline shift register (4 cycles to match pipeline latency)
    reg [1:0] op_pipe1, op_pipe2, op_pipe3, op_pipe4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_pipe1 <= 2'b00;
            op_pipe2 <= 2'b00;
            op_pipe3 <= 2'b00;
            op_pipe4 <= 2'b00;
        end else begin
            op_pipe1 <= op;
            op_pipe2 <= op_pipe1;
            op_pipe3 <= op_pipe2;
            op_pipe4 <= op_pipe3;
        end
    end

    // Output selection multiplexer based on matching delayed opcode
    always @(*) begin
        case (op_pipe4)
            2'b00: begin
                Y                = y_add;
                valid_out        = v_add;
                flag_zero        = z_add;
                flag_overflow    = ovf_add;
                flag_underflow   = unf_add;
                flag_invalid     = inv_add;
                flag_inexact     = inex_add;
                flag_div_by_zero = 1'b0;
            end
            2'b01: begin
                Y                = y_mul;
                valid_out        = v_mul;
                flag_zero        = z_mul;
                flag_overflow    = ovf_mul;
                flag_underflow   = unf_mul;
                flag_invalid     = inv_mul;
                flag_inexact     = inex_mul;
                flag_div_by_zero = 1'b0;
            end
            2'b10: begin
                Y                = y_mac;
                valid_out        = v_mac;
                flag_zero        = z_mac;
                flag_overflow    = ovf_mac;
                flag_underflow   = unf_mac;
                flag_invalid     = inv_mac;
                flag_inexact     = inex_mac;
                flag_div_by_zero = 1'b0;
            end
            2'b11: begin
                Y                = y_div;
                valid_out        = v_div;
                flag_zero        = z_div;
                flag_overflow    = ovf_div;
                flag_underflow   = unf_div;
                flag_invalid     = inv_div;
                flag_inexact     = inex_div;
                flag_div_by_zero = dz_div;
            end
            default: begin
                Y                = 32'h0;
                valid_out        = 1'b0;
                flag_zero        = 1'b0;
                flag_overflow    = 1'b0;
                flag_underflow   = 1'b0;
                flag_invalid     = 1'b0;
                flag_inexact     = 1'b0;
                flag_div_by_zero = 1'b0;
            end
        endcase

        flag_inf = (Y[30:23] == 8'hFF) && (Y[22:0] == 23'h0);
        flag_nan = (Y[30:23] == 8'hFF) && (Y[22:0] != 23'h0);
    end

endmodule
