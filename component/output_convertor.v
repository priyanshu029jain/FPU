// =============================================================================
// Module  : output_convertor
// Purpose : Converts an IEEE 754 32-bit single-precision floating-point number
//           into standard signed binary format (Integer or Q16.16 Fixed-Point)
//           and unpacks internal fields for easy testing, debugging & waveforms.
// Modes   :
//   mode = 1'b0 : Float to 32-bit signed two's complement integer
//   mode = 1'b1 : Float to signed Q16.16 fixed-point (16-bit integer, 16-bit fraction)
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */

module output_convertor (
    input  wire [31:0] float_in,      // IEEE 754 single-precision float
    input  wire        mode,          // 0: Float -> Signed Int, 1: Float -> Q16.16
    output wire [31:0] binary_out,    // Converted signed binary result
    output wire        sign,          // Extracted sign bit
    output wire signed [8:0] unbiased_exp, // E - 127 (true base-2 exponent)
    output wire [23:0] significand,   // 24-bit significand with implicit 1 restored
    output wire        is_zero,       // Input is zero
    output wire        is_inf,        // Input is infinity
    output wire        is_nan,        // Input is NaN
    output wire        overflow       // Result overflows 32-bit binary container
);

    // 1. Unpack fields
    assign sign     = float_in[31];
    wire [7:0]  expo = float_in[30:23];
    wire [22:0] mant = float_in[22:0];

    // 2. Exception and status flags
    assign is_zero = (expo == 8'h00) && (mant == 23'h0);
    assign is_inf  = (expo == 8'hFF) && (mant == 23'h0);
    assign is_nan  = (expo == 8'hFF) && (mant != 23'h0);

    // 3. Significand with implicit 1 restored
    assign significand = (expo == 8'h00) ? {1'b0, mant} : {1'b1, mant};

    // 4. True unbiased exponent (E - 127)
    assign unbiased_exp = {1'b0, expo} - 9'sd127;

    // 5. Convert to Fixed-Point / Integer
    // Significand is currently 1.M (implicit binary point after bit 23)
    // Mode 0 (Integer):
    //   Value = significand * 2^(unbiased_exp - 23)
    //   If unbiased_exp >= 23: shift left by (unbiased_exp - 23)
    //   If unbiased_exp < 23:  shift right by (23 - unbiased_exp)
    // Mode 1 (Q16.16 Fixed-Point):
    //   Value has 16 fractional bits. Target shift = unbiased_exp - 23 + 16 = unbiased_exp - 7
    //   If unbiased_exp >= 7: shift left by (unbiased_exp - 7)
    //   If unbiased_exp < 7:  shift right by (7 - unbiased_exp)

    wire signed [8:0] shift_val = mode ? (unbiased_exp - 9'sd7) : (unbiased_exp - 9'sd23);

    // Overflow check: if positive exponent is too large to fit in 31 bits magnitude
    wire too_large = mode ? (unbiased_exp >= 9'sd15) : (unbiased_exp >= 9'sd31);
    assign overflow = too_large | is_inf | is_nan;

    reg [31:0] unsigned_val;

    always @(*) begin
        if (is_zero || is_nan) begin
            unsigned_val = 32'b0;
        end else if (too_large) begin
            unsigned_val = 32'h7FFFFFFF; // saturate on overflow
        end else if (shift_val >= 9'sd0) begin
            // Shift left
            unsigned_val = {8'b0, significand} << shift_val[4:0];
        end else begin
            // Shift right (value < 1 or fraction)
            if ((-shift_val) >= 9'sd32)
                unsigned_val = 32'b0;
            else
                unsigned_val = {8'b0, significand} >> (-shift_val[4:0]);
        end
    end

    // Apply two's complement sign
    assign binary_out = sign ? (-unsigned_val) : unsigned_val;

endmodule
