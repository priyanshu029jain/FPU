// =============================================================================
// Module  : input_convertor
// Purpose : Converts standard signed binary numbers into IEEE 754 32-bit
//           single-precision floating-point format for easy testing & verification.
// Modes   :
//   mode = 1'b0 : 32-bit signed two's complement integer to float
//   mode = 1'b1 : Signed Q16.16 fixed-point (16-bit integer, 16-bit fraction) to float
//                 (as demonstrated in PDF Page 1 with numbers like -6.625)
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDSIGNAL */

module input_convertor (
    input  wire [31:0] binary_in,  // Signed input binary
    input  wire        mode,       // 0: 32-bit Int -> Float, 1: Q16.16 -> Float
    output wire [31:0] float_out   // IEEE 754 Single-Precision Float
);

    // 1. Sign detection and absolute magnitude
    wire sign = binary_in[31];
    wire [31:0] mag = sign ? (-binary_in) : binary_in;

    // 2. Priority encoder / Leading Zero Detection on magnitude
    reg [4:0] msb_pos;
    reg       is_non_zero;
    integer   i;

    always @(*) begin
        msb_pos     = 5'd0;
        is_non_zero = 1'b0;
        for (i = 31; i >= 0; i = i - 1) begin
            if (mag[i] == 1'b1 && !is_non_zero) begin
                msb_pos     = i[4:0];
                is_non_zero = 1'b1;
            end
        end
    end

    // 3. Exponent calculation with bias (127)
    // Mode 0 (Integer):   Bit msb_pos has weight 2^(msb_pos), exp = msb_pos + 127
    // Mode 1 (Q16.16):    Bit msb_pos has weight 2^(msb_pos - 16), exp = (msb_pos - 16) + 127 = msb_pos + 111
    wire signed [8:0] raw_expo = mode ? ({4'b0, msb_pos} - 9'sd16 + 9'sd127) :
                                        ({4'b0, msb_pos} + 9'sd127);

    // 4. Align significand to 23 bits (with implicit 1 removed)
    // mag[msb_pos] is the implicit 1
    reg [22:0] mantissa;
    always @(*) begin
        if (msb_pos >= 5'd23) begin
            // Shift right and drop lower bits
            mantissa = mag[msb_pos-1 -: 23];
        end else begin
            // Shift left and zero-pad lower bits
            mantissa = (mag << (5'd23 - msb_pos));
        end
    end

    // 5. Pack into IEEE 754 format
    assign float_out = (!is_non_zero) ? 32'b0 : {sign, raw_expo[7:0], mantissa};

endmodule
