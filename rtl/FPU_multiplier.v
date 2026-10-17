// =============================================================================
// Module  : FPU_multiplier
// Reference: IEEE 754-2008 Single-Precision Floating-Point Pipelined Multiplier
// Architecture: 4-Stage Synchronous Hardware Pipeline (Per Notes Pages 6-9)
// Latency     : 4 Clock Cycles
// Throughput  : 1 Operation / Cycle (Fully Pipelined)
//
// Pipeline Stages:
//   Stage 1: Unpack, Special Cases Check & Exponent Addition (param_adder_sub)
//   Stage 2: 24x24 Significand Multiplication (param_multiplier)
//   Stage 3: Normalization Shifting (barrel_shifter) & GRS Extraction
//   Stage 4: IEEE 754 Round-to-Nearest-Even (param_adder_sub), Flags & Packing
// =============================================================================
`timescale 1ns/1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */

module FPU_multiplier (
    input  wire        clk,
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        valid_in,       // Input data valid strobe
    input  wire [31:0] A,              // Multiplicand (IEEE 754 float)
    input  wire [31:0] B,              // Multiplier (IEEE 754 float)
    output reg  [31:0] Y,              // Product (IEEE 754 float)
    output reg         valid_out,      // Output data valid strobe (4 cycles latency)
    // IEEE 754-2008 Exception & Status Flags
    output reg         flag_overflow,  // Overflow flag
    output reg         flag_underflow, // Underflow flag
    output reg         flag_invalid,   // Invalid operation (NaN operand or 0 * Inf)
    output reg         flag_zero,      // Result is exactly zero
    output reg         flag_inexact    // Inexact flag (bits lost to rounding)
);

    // =========================================================================
    // STAGE 1: UNPACK, SPECIAL CASES & EXPONENT ADDITION
    // =========================================================================
    wire        A_sign = A[31];
    wire [7:0]  A_expo = A[30:23];
    wire [22:0] A_mant = A[22:0];

    wire        B_sign = B[31];
    wire [7:0]  B_expo = B[30:23];
    wire [22:0] B_mant = B[22:0];

    // Special cases check
    wire A_is_zero = (A_expo == 8'h00) && (A_mant == 23'h0);
    wire B_is_zero = (B_expo == 8'h00) && (B_mant == 23'h0);
    wire A_is_inf  = (A_expo == 8'hFF) && (A_mant == 23'h0);
    wire B_is_inf  = (B_expo == 8'hFF) && (B_mant == 23'h0);
    wire A_is_nan  = (A_expo == 8'hFF) && (A_mant != 23'h0);
    wire B_is_nan  = (B_expo == 8'hFF) && (B_mant != 23'h0);

    // Implicit leading 1 (24-bit significand)
    wire [23:0] s1_sigA = (A_expo == 8'h00) ? {1'b0, A_mant} : {1'b1, A_mant};
    wire [23:0] s1_sigB = (B_expo == 8'h00) ? {1'b0, B_mant} : {1'b1, B_mant};

    wire s1_sign = A_sign ^ B_sign;

    // Sub-units: Exponent Addition & Bias Subtraction via param_adder_sub
    // E_sum = Ea + Eb
    wire [9:0] s1_exp_sum;
    param_adder_sub #(.WIDTH(10)) u_exp_add (
        .A({2'b00, A_expo}),
        .B({2'b00, B_expo}),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s1_exp_sum),
        .carry_out(),
        .overflow()
    );

    // Etemp = E_sum - 127
    wire signed [9:0] s1_Etemp;
    param_adder_sub #(.WIDTH(10)) u_exp_sub_bias (
        .A(s1_exp_sum),
        .B(10'd127),
        .sub(1'b1),
        .is_signed(1'b1),
        .result(s1_Etemp),
        .carry_out(),
        .overflow()
    );

    wire [31:0] qnan = {1'b0, 8'hFF, 23'h400000};
    wire s1_nan  = A_is_nan | B_is_nan | (A_is_zero && B_is_inf) | (A_is_inf && B_is_zero);
    wire s1_inf  = (A_is_inf | B_is_inf) && !s1_nan;
    wire s1_zero = (A_is_zero | B_is_zero) && !s1_nan;

    wire s1_special = s1_nan | s1_inf | s1_zero;
    wire [31:0] s1_special_val =
        s1_nan ? qnan :
        s1_inf ? {s1_sign, 8'hFF, 23'h0} :
                 {s1_sign, 31'h0}; // zero

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 1 (STAGE 1 -> STAGE 2)
    // -------------------------------------------------------------------------
    reg              r1_valid;
    reg [23:0]       r1_sigA;
    reg [23:0]       r1_sigB;
    reg              r1_sign;
    reg signed [9:0] r1_Etemp;
    reg              r1_special;
    reg [31:0]       r1_special_val;
    reg              r1_nan;
    reg              r1_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_valid       <= 1'b0;
            r1_sigA        <= 24'h0;
            r1_sigB        <= 24'h0;
            r1_sign        <= 1'b0;
            r1_Etemp       <= 10'sd0;
            r1_special     <= 1'b0;
            r1_special_val <= 32'h0;
            r1_nan         <= 1'b0;
            r1_zero        <= 1'b0;
        end else begin
            r1_valid       <= valid_in;
            r1_sigA        <= s1_sigA;
            r1_sigB        <= s1_sigB;
            r1_sign        <= s1_sign;
            r1_Etemp       <= s1_Etemp;
            r1_special     <= s1_special;
            r1_special_val <= s1_special_val;
            r1_nan         <= s1_nan;
            r1_zero        <= s1_zero;
        end
    end

    // =========================================================================
    // STAGE 2: SIGNIFICAND MULTIPLICATION
    // =========================================================================
    wire [47:0] s2_product_raw;

    // Sub-unit: 24x24 Multiplier
    param_multiplier #(
        .A_WIDTH(24),
        .B_WIDTH(24)
    ) u_sig_multiplier (
        .A(r1_sigA),
        .B(r1_sigB),
        .is_signed(1'b0),
        .product(s2_product_raw)
    );

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 2 (STAGE 2 -> STAGE 3)
    // -------------------------------------------------------------------------
    reg              r2_valid;
    reg [47:0]       r2_product;
    reg              r2_sign;
    reg signed [9:0] r2_Etemp;
    reg              r2_special;
    reg [31:0]       r2_special_val;
    reg              r2_nan;
    reg              r2_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r2_valid       <= 1'b0;
            r2_product     <= 48'h0;
            r2_sign        <= 1'b0;
            r2_Etemp       <= 10'sd0;
            r2_special     <= 1'b0;
            r2_special_val <= 32'h0;
            r2_nan         <= 1'b0;
            r2_zero        <= 1'b0;
        end else begin
            r2_valid       <= r1_valid;
            r2_product     <= s2_product_raw;
            r2_sign        <= r1_sign;
            r2_Etemp       <= r1_Etemp;
            r2_special     <= r1_special;
            r2_special_val <= r1_special_val;
            r2_nan         <= r1_nan;
            r2_zero        <= r1_zero;
        end
    end

    // =========================================================================
    // STAGE 3: NORMALIZATION & GRS EXTRACTION
    // =========================================================================
    wire s3_shift_req = r2_product[47]; // If MSB is 1, right-shift by 1

    // Sub-unit: Normalization Shifter
    wire [47:0] s3_norm_shifted;
    wire        s3_shift_sticky;

    barrel_shifter #(
        .DATA_WIDTH(48),
        .SHIFT_WIDTH(6)
    ) u_norm_shifter (
        .data_in(r2_product),
        .shift_amt(s3_shift_req ? 6'd1 : 6'd0),
        .dir(1'b1), // Shift Right
        .arith(1'b0),
        .data_out(s3_norm_shifted),
        .sticky(s3_shift_sticky)
    );

    wire [46:0] s3_norm_product = s3_shift_req ? s3_norm_shifted[46:0] : r2_product[46:0];

    // Exponent adjustment
    wire signed [9:0] s3_exp_inc;
    param_adder_sub #(.WIDTH(10)) u_exp_norm_inc (
        .A(r2_Etemp),
        .B(10'd1),
        .sub(1'b0),
        .is_signed(1'b1),
        .result(s3_exp_inc),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s3_Efinal_temp = s3_shift_req ? s3_exp_inc : r2_Etemp;

    // GRS bits extraction
    wire [23:0] s3_pre_round_sig = s3_norm_product[46:23];
    wire s3_G = s3_norm_product[22];
    wire s3_R = s3_norm_product[21];
    wire s3_S = s3_shift_req ? (|s3_norm_product[20:0] | r2_product[0]) : (|s3_norm_product[20:0]);
    wire [2:0] s3_grs = {s3_G, s3_R, s3_S};

    wire s3_round_up = (s3_grs > 3'b100) ? 1'b1 :
                       (s3_grs < 3'b100) ? 1'b0 :
                       s3_pre_round_sig[0];

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 3 (STAGE 3 -> STAGE 4)
    // -------------------------------------------------------------------------
    reg              r3_valid;
    reg [23:0]       r3_pre_round_sig;
    reg              r3_round_up;
    reg [2:0]        r3_grs;
    reg signed [9:0] r3_Efinal_temp;
    reg              r3_sign;
    reg              r3_special;
    reg [31:0]       r3_special_val;
    reg              r3_nan;
    reg              r3_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r3_valid         <= 1'b0;
            r3_pre_round_sig <= 24'h0;
            r3_round_up      <= 1'b0;
            r3_grs           <= 3'b0;
            r3_Efinal_temp   <= 10'sd0;
            r3_sign          <= 1'b0;
            r3_special       <= 1'b0;
            r3_special_val   <= 32'h0;
            r3_nan           <= 1'b0;
            r3_zero          <= 1'b0;
        end else begin
            r3_valid         <= r2_valid;
            r3_pre_round_sig <= s3_pre_round_sig;
            r3_round_up      <= s3_round_up;
            r3_grs           <= s3_grs;
            r3_Efinal_temp   <= s3_Efinal_temp;
            r3_sign          <= r2_sign;
            r3_special       <= r2_special;
            r3_special_val   <= r2_special_val;
            r3_nan           <= r2_nan;
            r3_zero          <= r2_zero;
        end
    end

    // =========================================================================
    // STAGE 4: ROUNDING, EXCEPTION HANDLING & OUTPUT PACKING
    // =========================================================================
    wire [23:0] s4_rounded_sig;
    wire        s4_round_cout;

    // Sub-unit: Rounding adder
    param_adder_sub #(
        .WIDTH(24)
    ) u_round_adder (
        .A(r3_pre_round_sig),
        .B({23'b0, r3_round_up}),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s4_rounded_sig),
        .carry_out(s4_round_cout),
        .overflow()
    );

    wire [24:0] s4_rounded_ext = {s4_round_cout, s4_rounded_sig};
    wire        s4_round_overflow = s4_rounded_ext[24];
    wire [22:0] s4_final_mant = s4_round_overflow ? s4_rounded_ext[23:1] : s4_rounded_ext[22:0];

    // Exponent post-rounding carry increment
    wire signed [9:0] s4_exp_round_inc;
    param_adder_sub #(.WIDTH(10)) u_exp_round_inc (
        .A(r3_Efinal_temp),
        .B(10'd1),
        .sub(1'b0),
        .is_signed(1'b1),
        .result(s4_exp_round_inc),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s4_Efinal = s4_round_overflow ? s4_exp_round_inc : r3_Efinal_temp;

    wire s4_overflow  = (s4_Efinal >= 10'sd255);
    wire s4_underflow = (s4_Efinal <= 10'sd0);

    wire [31:0] s4_normal_result =
        s4_overflow  ? {r3_sign, 8'hFF, 23'h0} :
        s4_underflow ? {r3_sign, 31'h0}        :
                       {r3_sign, s4_Efinal[7:0], s4_final_mant};

    wire [31:0] s4_result = r3_special ? r3_special_val : s4_normal_result;

    // -------------------------------------------------------------------------
    // STAGE 4 OUTPUT REGISTERS & EXCEPTION FLAGS
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Y              <= 32'h00000000;
            valid_out      <= 1'b0;
            flag_overflow  <= 1'b0;
            flag_underflow <= 1'b0;
            flag_invalid   <= 1'b0;
            flag_zero      <= 1'b0;
            flag_inexact   <= 1'b0;
        end else begin
            valid_out <= r3_valid;
            if (r3_valid) begin
                Y              <= s4_result;
                flag_overflow  <= !r3_special & s4_overflow;
                flag_underflow <= !r3_special & s4_underflow & !r3_zero;
                flag_invalid   <= r3_nan;
                flag_zero      <= r3_zero | (s4_result[30:0] == 31'b0);
                flag_inexact   <= !r3_special & (|r3_grs);
            end
        end
    end

endmodule
