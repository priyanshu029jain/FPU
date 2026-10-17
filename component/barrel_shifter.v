// =============================================================================
// Module  : barrel_shifter
// Purpose : Parameterized Bidirectional Barrel Shifter with Sticky Bit Extraction
// Parameters:
//   DATA_WIDTH  : Width of data to shift (Default: 48 bits)
//   SHIFT_WIDTH : Width of shift amount signal (Default: 6 bits, up to 63 shifts)
// Ports   :
//   data_in   : Input data word
//   shift_amt : Number of positions to shift
//   dir       : 1'b0 = Shift Left (normalization), 1'b1 = Shift Right (alignment)
//   arith     : 1'b0 = Logical shift (zero fill), 1'b1 = Arithmetic (sign-extend)
//   data_out  : Shifted data output
//   sticky    : Reduction OR of all bits shifted off the right boundary (GRS sticky)
`timescale 1ns/1ps

module barrel_shifter #(
    parameter DATA_WIDTH  = 48,
    parameter SHIFT_WIDTH = 6
)(
    input  wire [DATA_WIDTH-1:0]  data_in,
    input  wire [SHIFT_WIDTH-1:0] shift_amt,
    input  wire                   dir,        // 0: Left, 1: Right
    input  wire                   arith,      // 0: Logical, 1: Arithmetic
    output reg  [DATA_WIDTH-1:0]  data_out,
    output reg                    sticky      // Set if any '1' bit was shifted out of LSB
);

    wire sign_bit = arith ? data_in[DATA_WIDTH-1] : 1'b0;

    integer i;
    reg [DATA_WIDTH-1:0] mask;

    always @(*) begin
        mask = {DATA_WIDTH{1'b0}};
        if (dir == 1'b0) begin
            // Shift Left
            data_out = data_in << shift_amt;
            sticky   = 1'b0;
        end else begin
            // Shift Right
            if (shift_amt >= DATA_WIDTH) begin
                data_out = {DATA_WIDTH{sign_bit}};
                sticky   = |data_in; // Everything shifted out
            end else begin
                if (arith && sign_bit) begin
                    data_out = (data_in >> shift_amt) | ({DATA_WIDTH{1'b1}} << (DATA_WIDTH - shift_amt));
                end else begin
                    data_out = (data_in >> shift_amt);
                end

                // Compute sticky bit: check if any bits below shift_amt were 1
                mask = {DATA_WIDTH{1'b0}};
                for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                    if (i < shift_amt)
                        mask[i] = 1'b1;
                end
                sticky = |(data_in & mask);
            end
        end
    end

endmodule
