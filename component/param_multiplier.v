// =============================================================================
// Module  : param_multiplier
// Purpose : Parameterized Signed/Unsigned Combinational Multiplier
// Parameters:
//   A_WIDTH : Width of operand A (Default: 24 bits, matching IEEE 754 mantissa 1.M)
//   B_WIDTH : Width of operand B (Default: 24 bits, matching IEEE 754 mantissa 1.M)
// Ports   :
//   A         : Multiplicand operand
//   B         : Multiplier operand
//   is_signed : 1'b0 = Unsigned multiplication, 1'b1 = Signed (Two's complement)
//   product   : Full-precision product output (Width = A_WIDTH + B_WIDTH = 48 bits)
`timescale 1ns/1ps

module param_multiplier #(
    parameter A_WIDTH = 24,
    parameter B_WIDTH = 24
)(
    input  wire [A_WIDTH-1:0]           A,
    input  wire [B_WIDTH-1:0]           B,
    input  wire                         is_signed,
    output wire [A_WIDTH+B_WIDTH-1:0]   product
);

    // Unsigned product
    wire [A_WIDTH+B_WIDTH-1:0] unsigned_product = A * B;

    // Signed product using Verilog signed casting
    wire signed [A_WIDTH-1:0]         signed_a = A;
    wire signed [B_WIDTH-1:0]         signed_b = B;
    wire signed [A_WIDTH+B_WIDTH-1:0] signed_product = signed_a * signed_b;

    assign product = is_signed ? signed_product : unsigned_product;

endmodule
