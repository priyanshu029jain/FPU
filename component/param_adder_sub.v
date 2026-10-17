// =============================================================================
// Module  : param_adder_sub
// Purpose : Parameterized Signed/Unsigned Adder-Subtractor
// Parameters:
//   WIDTH : Data bit-width (Default: 32 bits, can be configured for 27, 48, 100, etc.)
// Ports   :
//   A         : Input operand A
//   B         : Input operand B
//   sub       : 1'b0 = Addition (A + B), 1'b1 = Subtraction (A - B)
//   is_signed : 1'b0 = Unsigned arithmetic, 1'b1 = Signed (Two's complement)
//   result    : Result output (A + B or A - B)
//   carry_out : Carry-out from MSB (for unsigned addition) / Borrow
//   overflow  : Signed overflow flag
`timescale 1ns/1ps

module param_adder_sub #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    input  wire             sub,        // 0: Add, 1: Sub
    input  wire             is_signed,  // 0: Unsigned, 1: Signed
    output wire [WIDTH-1:0] result,
    output wire             carry_out,  // Carry / Borrow
    output wire             overflow    // Signed arithmetic overflow
);

    // Conditional inversion for subtraction (Two's complement: A - B = A + (~B) + 1)
    wire [WIDTH-1:0] b_operand = sub ? (~B) : B;
    wire             cin       = sub;

    // Internal (WIDTH+1)-bit adder to capture carry-out
    wire [WIDTH:0] sum_ext = {1'b0, A} + {1'b0, b_operand} + { {WIDTH{1'b0}}, cin};

    assign result    = sum_ext[WIDTH-1:0];
    assign carry_out = sum_ext[WIDTH];

    // Signed overflow occurs when:
    // Adding two positives yields a negative, OR
    // Adding two negatives yields a positive.
    wire sign_a = A[WIDTH-1];
    wire sign_b = b_operand[WIDTH-1];
    wire sign_r = result[WIDTH-1];

    assign overflow = is_signed ? ((sign_a == sign_b) && (sign_r != sign_a)) : carry_out;

endmodule
