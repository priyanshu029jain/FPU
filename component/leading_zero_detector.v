// =============================================================================
// Module  : leading_zero_detector
// Purpose : Parameterized Leading Zero Detector (LZD) / Priority Encoder
//           Counts consecutive zeros starting from the MSB down to the first '1'.
// Parameters:
//   WIDTH       : Input data vector width (Default: 32 bits)
//   COUNT_WIDTH : Bit-width of the zero count output (Default: 5 bits)
// Ports   :
//   in_vector : Vector to scan for leading zeros
//   zero_count: Number of leading zeros (0 to WIDTH)
//   all_zeros : Flag set high if the input vector contains only zeros
`timescale 1ns/1ps

module leading_zero_detector #(
    parameter WIDTH       = 32,
    parameter COUNT_WIDTH = 5
)(
    input  wire [WIDTH-1:0]       in_vector,
    output reg  [COUNT_WIDTH-1:0] zero_count,
    output reg                    all_zeros
);

    integer idx;
    reg     found;

    always @(*) begin
        zero_count = WIDTH[COUNT_WIDTH-1:0];
        all_zeros  = 1'b1;
        found      = 1'b0;

        for (idx = WIDTH - 1; idx >= 0; idx = idx - 1) begin
            if (in_vector[idx] == 1'b1 && !found) begin
                /* verilator lint_off WIDTHTRUNC */
                zero_count = (WIDTH - 1 - idx);
                /* verilator lint_on WIDTHTRUNC */
                all_zeros  = 1'b0;
                found      = 1'b1;
            end
        end
    end

endmodule
