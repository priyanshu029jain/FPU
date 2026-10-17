// =============================================================================
// Module  : FPU_mac
// Reference: IEEE 754-2008 Single-Precision Fused Multiply-Accumulate (FMA)
// Architecture: 4-Stage Synchronous Hardware Pipeline (Per Notes Pages 10-12)
// Operation   : Y = A * B + C (Computed with Single Final Rounding)
// Latency     : 4 Clock Cycles
// Throughput  : 1 Operation / Cycle (Fully Pipelined)
//
// Pipeline Stages:
//   Stage 1: Unpack, 24x24 Multiplier (param_multiplier) & Product Exponent
//   Stage 2: Dual-path 100-bit Alignment Shifter (barrel_shifter)
//   Stage 3: Wide 100-bit Add/Sub (param_adder_sub) & LZD (leading_zero_detector)
//   Stage 4: Normalization Shifter (barrel_shifter), Rounding (param_adder_sub) & Packing
// =============================================================================
`timescale 1ns/1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */

module FPU_mac (
    input  wire        clk,
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        valid_in,       // Input data valid strobe
    input  wire [31:0] A,              // Multiplicand (IEEE 754 float)
    input  wire [31:0] B,              // Multiplier (IEEE 754 float)
    input  wire [31:0] C,              // Addend (IEEE 754 float)
    output reg  [31:0] Y,              // FMA Result (IEEE 754 float)
    output reg         valid_out,      // Output data valid strobe (4 cycles latency)
    // IEEE 754-2008 Exception & Status Flags
    output reg         flag_overflow,  // Overflow flag
    output reg         flag_underflow, // Underflow flag
    output reg         flag_invalid,   // Invalid operation (NaN, 0*Inf, Inf - Inf)
    output reg         flag_zero,      // Result is exactly zero
    output reg         flag_inexact    // Inexact flag (bits lost to rounding)
);

    // =========================================================================
    // STAGE 1: UNPACK, MULTIPLIER & PRODUCT EXPONENT
    // =========================================================================
    wire        A_sign = A[31];
    wire [7:0]  A_expo = A[30:23];
    wire [22:0] A_mant = A[22:0];

    wire        B_sign = B[31];
    wire [7:0]  B_expo = B[30:23];
    wire [22:0] B_mant = B[22:0];

    wire        C_sign = C[31];
    wire [7:0]  C_expo = C[30:23];
    wire [22:0] C_mant = C[22:0];

    // Special cases checks
    wire A_is_zero = (A_expo == 8'h00) && (A_mant == 23'h0);
    wire B_is_zero = (B_expo == 8'h00) && (B_mant == 23'h0);
    wire C_is_zero = (C_expo == 8'h00) && (C_mant == 23'h0);

    wire A_is_inf  = (A_expo == 8'hFF) && (A_mant == 23'h0);
    wire B_is_inf  = (B_expo == 8'hFF) && (B_mant == 23'h0);
    wire C_is_inf  = (C_expo == 8'hFF) && (C_mant == 23'h0);

    wire A_is_nan  = (A_expo == 8'hFF) && (A_mant != 23'h0);
    wire B_is_nan  = (B_expo == 8'hFF) && (B_mant != 23'h0);
    wire C_is_nan  = (C_expo == 8'hFF) && (C_mant != 23'h0);

    wire s1_prod_zero = A_is_zero | B_is_zero;
    wire s1_prod_nan  = A_is_nan | B_is_nan | (A_is_zero && B_is_inf) | (A_is_inf && B_is_zero);
    wire s1_prod_inf  = (A_is_inf | B_is_inf) && !s1_prod_nan;

    wire s1_P_sign = A_sign ^ B_sign;
    wire [31:0] qnan = {1'b0, 8'hFF, 23'h400000};

    wire s1_nan = s1_prod_nan | C_is_nan | (s1_prod_inf && C_is_inf && (s1_P_sign ^ C_sign));
    wire s1_inf = (s1_prod_inf | C_is_inf) && !s1_nan;
    wire s1_both_zero = s1_prod_zero && C_is_zero;

    wire s1_special = s1_nan | s1_inf | s1_both_zero;
    wire [31:0] s1_special_val =
        s1_nan                    ? qnan :
        (s1_prod_inf && C_is_inf) ? {s1_P_sign, 8'hFF, 23'h0} :
        s1_prod_inf               ? {s1_P_sign, 8'hFF, 23'h0} :
        C_is_inf                  ? {C_sign, 8'hFF, 23'h0} :
                                    {s1_P_sign & C_sign, 31'h0}; // both zero

    // Hidden bit append: 24-bit significands
    wire [23:0] s1_sigA = (A_expo == 8'h00) ? {1'b0, A_mant} : {1'b1, A_mant};
    wire [23:0] s1_sigB = (B_expo == 8'h00) ? {1'b0, B_mant} : {1'b1, B_mant};
    wire [23:0] s1_sigC = (C_expo == 8'h00) ? {1'b0, C_mant} : {1'b1, C_mant};

    // Sub-unit: 24x24 Multiplier
    wire [47:0] s1_P_raw;
    param_multiplier #(
        .A_WIDTH(24),
        .B_WIDTH(24)
    ) u_sig_multiplier (
        .A(s1_sigA),
        .B(s1_sigB),
        .is_signed(1'b0),
        .product(s1_P_raw)
    );

    wire        s1_P_has_carry = s1_P_raw[47];
    wire [47:0] s1_P_norm      = s1_P_has_carry ? s1_P_raw : {s1_P_raw[46:0], 1'b0};

    // Exponent calculation for product
    wire [9:0] s1_exp_ab_sum;
    param_adder_sub #(.WIDTH(10)) u_exp_add_ab (
        .A({2'b00, A_expo}),
        .B({2'b00, B_expo}),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s1_exp_ab_sum),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s1_exp_unbiased;
    param_adder_sub #(.WIDTH(10)) u_exp_sub_bias (
        .A(s1_exp_ab_sum),
        .B(10'd127),
        .sub(1'b1),
        .is_signed(1'b1),
        .result(s1_exp_unbiased),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s1_Eprod = s1_exp_unbiased + (s1_P_has_carry ? 10'sd1 : 10'sd0);
    wire signed [9:0] s1_Ec    = {2'b00, C_expo};

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 1 (STAGE 1 -> STAGE 2)
    // -------------------------------------------------------------------------
    reg              r1_valid;
    reg [47:0]       r1_P_norm;
    reg [23:0]       r1_sigC;
    reg              r1_P_sign;
    reg              r1_C_sign;
    reg signed [9:0] r1_Eprod;
    reg signed [9:0] r1_Ec;
    reg              r1_special;
    reg [31:0]       r1_special_val;
    reg              r1_nan;
    reg              r1_zero;
    reg              r1_prod_zero;
    reg              r1_C_zero;
    reg [31:0]       r1_C_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_valid       <= 1'b0;
            r1_P_norm      <= 48'h0;
            r1_sigC        <= 24'h0;
            r1_P_sign      <= 1'b0;
            r1_C_sign      <= 1'b0;
            r1_Eprod       <= 10'sd0;
            r1_Ec          <= 10'sd0;
            r1_special     <= 1'b0;
            r1_special_val <= 32'h0;
            r1_nan         <= 1'b0;
            r1_zero        <= 1'b0;
            r1_prod_zero   <= 1'b0;
            r1_C_zero      <= 1'b0;
            r1_C_val       <= 32'h0;
        end else begin
            r1_valid       <= valid_in;
            r1_P_norm      <= s1_P_norm;
            r1_sigC        <= s1_sigC;
            r1_P_sign      <= s1_P_sign;
            r1_C_sign      <= C_sign;
            r1_Eprod       <= s1_Eprod;
            r1_Ec          <= s1_Ec;
            r1_special     <= s1_special;
            r1_special_val <= s1_special_val;
            r1_nan         <= s1_nan;
            r1_zero        <= s1_both_zero;
            r1_prod_zero   <= s1_prod_zero;
            r1_C_zero      <= C_is_zero;
            r1_C_val       <= C;
        end
    end

    // =========================================================================
    // STAGE 2: DUAL-PATH ALIGNMENT IN 100-BIT REGISTER SPACE
    // =========================================================================
    // Exponent difference calculation
    wire signed [9:0] s2_exp_diff;
    param_adder_sub #(.WIDTH(10)) u_exp_diff (
        .A(r1_Eprod),
        .B(r1_Ec),
        .sub(1'b1),
        .is_signed(1'b1),
        .result(s2_exp_diff),
        .carry_out(),
        .overflow()
    );

    wire s2_P_larger_exp = (s2_exp_diff >= 10'sd0);
    wire [7:0] s2_abs_diff = s2_P_larger_exp ? s2_exp_diff[7:0] : (-s2_exp_diff[7:0]);
    wire [6:0] s2_shift_amt = (s2_abs_diff > 8'd98) ? 7'd98 : s2_abs_diff[6:0];

    wire [99:0] s2_P_wide = {r1_P_norm, 52'b0};
    wire [99:0] s2_C_wide = {r1_sigC, 76'b0};

    // Sub-units: 100-bit Alignment Shifters
    wire [99:0] s2_P_shifted;
    barrel_shifter #(.DATA_WIDTH(100), .SHIFT_WIDTH(7)) u_align_P (
        .data_in(s2_P_wide),
        .shift_amt(s2_shift_amt),
        .dir(1'b1), // Shift Right
        .arith(1'b0),
        .data_out(s2_P_shifted),
        .sticky()
    );

    wire [99:0] s2_C_shifted;
    barrel_shifter #(.DATA_WIDTH(100), .SHIFT_WIDTH(7)) u_align_C (
        .data_in(s2_C_wide),
        .shift_amt(s2_shift_amt),
        .dir(1'b1), // Shift Right
        .arith(1'b0),
        .data_out(s2_C_shifted),
        .sticky()
    );

    wire [99:0] s2_P_aligned = s2_P_larger_exp ? s2_P_wide : s2_P_shifted;
    wire [99:0] s2_C_aligned = s2_P_larger_exp ? s2_C_shifted : s2_C_wide;
    wire signed [9:0] s2_tentative_expo = s2_P_larger_exp ? r1_Eprod : r1_Ec;

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 2 (STAGE 2 -> STAGE 3)
    // -------------------------------------------------------------------------
    reg              r2_valid;
    reg [99:0]       r2_P_aligned;
    reg [99:0]       r2_C_aligned;
    reg              r2_P_sign;
    reg              r2_C_sign;
    reg signed [9:0] r2_tentative_expo;
    reg              r2_special;
    reg [31:0]       r2_special_val;
    reg              r2_nan;
    reg              r2_zero;
    reg              r2_prod_zero;
    reg              r2_C_zero;
    reg [31:0]       r2_C_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r2_valid          <= 1'b0;
            r2_P_aligned      <= 100'h0;
            r2_C_aligned      <= 100'h0;
            r2_P_sign         <= 1'b0;
            r2_C_sign         <= 1'b0;
            r2_tentative_expo <= 10'sd0;
            r2_special        <= 1'b0;
            r2_special_val    <= 32'h0;
            r2_nan            <= 1'b0;
            r2_zero           <= 1'b0;
            r2_prod_zero      <= 1'b0;
            r2_C_zero         <= 1'b0;
            r2_C_val          <= 32'h0;
        end else begin
            r2_valid          <= r1_valid;
            r2_P_aligned      <= s2_P_aligned;
            r2_C_aligned      <= s2_C_aligned;
            r2_P_sign         <= r1_P_sign;
            r2_C_sign         <= r1_C_sign;
            r2_tentative_expo <= s2_tentative_expo;
            r2_special        <= r1_special;
            r2_special_val    <= r1_special_val;
            r2_nan            <= r1_nan;
            r2_zero           <= r1_zero;
            r2_prod_zero      <= r1_prod_zero;
            r2_C_zero         <= r1_C_zero;
            r2_C_val          <= r1_C_val;
        end
    end

    // =========================================================================
    // STAGE 3: WIDE 100-BIT ADD/SUB & UNIFIED LZD
    // =========================================================================
    wire s3_signs_equal = (r2_P_sign == r2_C_sign);
    wire s3_P_larger_mag = (r2_P_aligned >= r2_C_aligned);

    wire [99:0] s3_op_a = s3_P_larger_mag ? r2_P_aligned : r2_C_aligned;
    wire [99:0] s3_op_b = s3_P_larger_mag ? r2_C_aligned : r2_P_aligned;

    wire [99:0] s3_addsub_res;
    wire        s3_addsub_cout;

    // Sub-unit: Wide 100-bit Adder/Subtractor
    param_adder_sub #(
        .WIDTH(100)
    ) u_wide_adder (
        .A(s3_op_a),
        .B(s3_op_b),
        .sub(!s3_signs_equal),
        .is_signed(1'b0),
        .result(s3_addsub_res),
        .carry_out(s3_addsub_cout),
        .overflow()
    );

    wire [100:0] s3_sum_raw = s3_signs_equal ? {s3_addsub_cout, s3_addsub_res} :
                                               {1'b0, s3_addsub_res};

    wire s3_final_sign = s3_signs_equal ? r2_P_sign :
                         s3_P_larger_mag ? r2_P_sign : r2_C_sign;

    // Sub-unit: Leading Zero Detector for 100 bits
    wire [6:0] s3_lzd;
    wire       s3_lzd_all_zeros;

    leading_zero_detector #(
        .WIDTH(100),
        .COUNT_WIDTH(7)
    ) u_wide_lzd (
        .in_vector(s3_sum_raw[99:0]),
        .zero_count(s3_lzd),
        .all_zeros(s3_lzd_all_zeros)
    );

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 3 (STAGE 3 -> STAGE 4)
    // -------------------------------------------------------------------------
    reg              r3_valid;
    reg [100:0]      r3_sum_raw;
    reg [6:0]        r3_lzd;
    reg              r3_lzd_all_zeros;
    reg signed [9:0] r3_tentative_expo;
    reg              r3_final_sign;
    reg              r3_special;
    reg [31:0]       r3_special_val;
    reg              r3_nan;
    reg              r3_zero;
    reg              r3_prod_zero;
    reg              r3_C_zero;
    reg [31:0]       r3_C_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r3_valid          <= 1'b0;
            r3_sum_raw        <= 101'h0;
            r3_lzd            <= 7'h0;
            r3_lzd_all_zeros  <= 1'b0;
            r3_tentative_expo <= 10'sd0;
            r3_final_sign     <= 1'b0;
            r3_special        <= 1'b0;
            r3_special_val    <= 32'h0;
            r3_nan            <= 1'b0;
            r3_zero           <= 1'b0;
            r3_prod_zero      <= 1'b0;
            r3_C_zero         <= 1'b0;
            r3_C_val          <= 32'h0;
        end else begin
            r3_valid          <= r2_valid;
            r3_sum_raw        <= s3_sum_raw;
            r3_lzd            <= s3_lzd;
            r3_lzd_all_zeros  <= (s3_sum_raw == 101'b0);
            r3_tentative_expo <= r2_tentative_expo;
            r3_final_sign     <= s3_final_sign;
            r3_special        <= r2_special;
            r3_special_val    <= r2_special_val;
            r3_nan            <= r2_nan;
            r3_zero           <= r2_zero | (s3_sum_raw == 101'b0);
            r3_prod_zero      <= r2_prod_zero;
            r3_C_zero         <= r2_C_zero;
            r3_C_val          <= r2_C_val;
        end
    end

    // =========================================================================
    // STAGE 4: NORMALIZATION SHIFTING, ROUNDING & PACKING
    // =========================================================================
    // Left-shift for normalization cancellation
    wire [99:0] s4_norm_lshifted;
    barrel_shifter #(.DATA_WIDTH(100), .SHIFT_WIDTH(7)) u_norm_lshift (
        .data_in(r3_sum_raw[99:0]),
        .shift_amt(r3_lzd),
        .dir(1'b0), // Shift Left
        .arith(1'b0),
        .data_out(s4_norm_lshifted),
        .sticky()
    );

    // Exponent adjustment
    wire signed [9:0] s4_exp_inc;
    param_adder_sub #(.WIDTH(10)) u_exp_norm_inc (
        .A(r3_tentative_expo),
        .B(10'd1),
        .sub(1'b0),
        .is_signed(1'b1),
        .result(s4_exp_inc),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s4_exp_dec;
    param_adder_sub #(.WIDTH(10)) u_exp_norm_dec (
        .A(r3_tentative_expo),
        .B({3'b0, r3_lzd}),
        .sub(1'b1),
        .is_signed(1'b1),
        .result(s4_exp_dec),
        .carry_out(),
        .overflow()
    );

    reg signed [9:0] s4_norm_expo;
    reg [99:0]       s4_norm_sig;

    always @(*) begin
        if (r3_lzd_all_zeros || r3_sum_raw == 101'b0) begin
            s4_norm_expo = 10'sd0;
            s4_norm_sig  = 100'b0;
        end else if (r3_sum_raw[100]) begin
            // Addition carry overflow
            s4_norm_expo   = s4_exp_inc;
            s4_norm_sig    = r3_sum_raw[100:1];
            s4_norm_sig[0] = s4_norm_sig[0] | r3_sum_raw[0];
        end else begin
            s4_norm_expo = s4_exp_dec;
            s4_norm_sig  = s4_norm_lshifted;
        end
    end

    // GRS Extraction
    wire [23:0] s4_pre_round_mant = s4_norm_sig[99:76];
    wire s4_G = s4_norm_sig[75];
    wire s4_R = s4_norm_sig[74];
    wire s4_S = |s4_norm_sig[73:0];
    wire [2:0] s4_grs = {s4_G, s4_R, s4_S};

    wire s4_round_up = (s4_grs > 3'b100) ? 1'b1 :
                       (s4_grs < 3'b100) ? 1'b0 :
                       s4_pre_round_mant[0];

    // Sub-unit: Rounding adder
    wire [23:0] s4_rounded_mant;
    wire        s4_round_cout;

    param_adder_sub #(
        .WIDTH(24)
    ) u_round_adder (
        .A(s4_pre_round_mant),
        .B({23'b0, s4_round_up}),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s4_rounded_mant),
        .carry_out(s4_round_cout),
        .overflow()
    );

    wire [24:0] s4_rounded_ext = {s4_round_cout, s4_rounded_mant};
    wire        s4_round_carry = s4_rounded_ext[24];
    wire [22:0] s4_final_mant  = s4_round_carry ? s4_rounded_ext[23:1] : s4_rounded_ext[22:0];

    // Exponent post-rounding increment
    wire signed [9:0] s4_exp_post_round;
    param_adder_sub #(.WIDTH(10)) u_exp_post_round (
        .A(s4_norm_expo),
        .B(10'd1),
        .sub(1'b0),
        .is_signed(1'b1),
        .result(s4_exp_post_round),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s4_final_expo = s4_round_carry ? s4_exp_post_round : s4_norm_expo;

    wire s4_overflow  = (s4_final_expo >= 10'sd255);
    wire s4_underflow = (s4_final_expo <= 10'sd0);

    wire [31:0] s4_normal_result =
        (s4_norm_sig == 100'b0) ? 32'b0 :
        s4_overflow             ? {r3_final_sign, 8'hFF, 23'h0} :
        s4_underflow            ? {r3_final_sign, 31'b0} :
                                  {r3_final_sign, s4_final_expo[7:0], s4_final_mant};

    wire [31:0] s4_mac_result =
        r3_prod_zero ? r3_C_val :
        r3_C_zero    ? s4_normal_result :
                       s4_normal_result;

    wire [31:0] s4_result = r3_special ? r3_special_val : s4_mac_result;

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
                flag_inexact   <= !r3_special & (|s4_grs);
            end
        end
    end

endmodule
