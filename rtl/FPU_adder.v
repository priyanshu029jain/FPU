// =============================================================================
// Module  : FPU_adder
// Reference: IEEE 754-2008 Single-Precision Floating-Point Pipelined Adder
// Architecture: 4-Stage Synchronous Hardware Pipeline (Per Notes Page 5)
// Latency     : 4 Clock Cycles
// Throughput  : 1 Operation / Cycle (Fully Pipelined)
//
// Pipeline Stages:
//   Stage 1: Unpack, Compare Exponents & Significand Alignment (Barrel Shifter GRS)
//   Stage 2: 27-bit Significand Add/Sub & Parallel Leading Zero Detection (LZD)
//   Stage 3: Normalization Shifting (Barrel Shifter) & Exponent Adjustment
//   Stage 4: IEEE 754 Round-to-Nearest-Even, Exception Flags & Packing
// =============================================================================
`timescale 1ns/1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */

module FPU_adder (
    input  wire        clk,
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        valid_in,       // Input data valid strobe
    input  wire [31:0] A,              // Operand A (IEEE 754 float)
    input  wire [31:0] B,              // Operand B (IEEE 754 float)
    output reg  [31:0] Y,              // Output Result (IEEE 754 float)
    output reg         valid_out,      // Output data valid strobe (4 cycles latency)
    // IEEE 754-2008 Exception & Status Flags
    output reg         flag_overflow,  // Overflow flag (exponent >= 255)
    output reg         flag_underflow, // Underflow flag (exponent == 0)
    output reg         flag_invalid,   // Invalid operation (NaN operand or Inf - Inf)
    output reg         flag_zero,      // Result is exactly zero
    output reg         flag_inexact    // Inexact flag (bits lost to rounding)
);

    // =========================================================================
    // STAGE 1: UNPACK, COMPARE & ALIGN
    // =========================================================================
    wire        A_sign = A[31];
    wire [7:0]  A_expo = A[30:23];
    wire [22:0] A_mant = A[22:0];

    wire        B_sign = B[31];
    wire [7:0]  B_expo = B[30:23];
    wire [22:0] B_mant = B[22:0];

    // Special cases detection
    wire A_is_zero = (A_expo == 8'h00) && (A_mant == 23'h0);
    wire B_is_zero = (B_expo == 8'h00) && (B_mant == 23'h0);
    wire A_is_inf  = (A_expo == 8'hFF) && (A_mant == 23'h0);
    wire B_is_inf  = (B_expo == 8'hFF) && (B_mant == 23'h0);
    wire A_is_nan  = (A_expo == 8'hFF) && (A_mant != 23'h0);
    wire B_is_nan  = (B_expo == 8'hFF) && (B_mant != 23'h0);

    wire [31:0] qnan = {1'b0, 8'hFF, 23'h400000};

    wire s1_invalid = A_is_nan | B_is_nan | (A_is_inf & B_is_inf & (A_sign ^ B_sign));
    wire s1_special = s1_invalid | A_is_inf | B_is_inf | A_is_zero | B_is_zero;
    wire [31:0] s1_special_val =
        (A_is_nan | B_is_nan)                       ? qnan :
        (A_is_inf && B_is_inf && (A_sign ^ B_sign)) ? qnan :
        A_is_inf                                    ? A    :
        B_is_inf                                    ? B    :
        A_is_zero                                   ? B    :
        B_is_zero                                   ? A    :
        32'h0;

    // Append implicit leading 1 for normal numbers (0 for subnormals)
    wire [23:0] A_mant_app = (A_expo == 8'b0) ? {1'b0, A_mant} : {1'b1, A_mant};
    wire [23:0] B_mant_app = (B_expo == 8'b0) ? {1'b0, B_mant} : {1'b1, B_mant};

    // Sub-units: Exponent comparison via param_adder_sub instances
    wire [7:0] s1_diff_ab, s1_diff_ba;
    wire       s1_ab_cout, s1_ba_cout;

    param_adder_sub #(.WIDTH(8)) u_exp_sub_ab (
        .A(A_expo),
        .B(B_expo),
        .sub(1'b1),
        .is_signed(1'b0),
        .result(s1_diff_ab),
        .carry_out(s1_ab_cout), // 1 if A_expo >= B_expo (no borrow)
        .overflow()
    );

    param_adder_sub #(.WIDTH(8)) u_exp_sub_ba (
        .A(B_expo),
        .B(A_expo),
        .sub(1'b1),
        .is_signed(1'b0),
        .result(s1_diff_ba),
        .carry_out(s1_ba_cout),
        .overflow()
    );

    wire s1_A_expo_ge = s1_ab_cout;
    wire [7:0] s1_expo_diff = s1_A_expo_ge ? s1_diff_ab : s1_diff_ba;
    wire [7:0] s1_tentative_expo = s1_A_expo_ge ? A_expo : B_expo;

    // Magnitude comparator
    wire s1_A_larger = (A_expo > B_expo) ? 1'b1 :
                       (A_expo < B_expo) ? 1'b0 :
                       (A_mant_app >= B_mant_app);

    wire s1_result_sign = s1_A_larger ? A_sign : B_sign;
    wire s1_is_sub      = (A_sign ^ B_sign);

    // Significand alignment via barrel_shifter
    wire [23:0] s1_smaller_mant = s1_A_larger ? B_mant_app : A_mant_app;
    wire [23:0] s1_larger_mant  = s1_A_larger ? A_mant_app : B_mant_app;

    wire [48:0] s1_smaller_ext = {s1_smaller_mant, 25'b0};
    wire [5:0]  s1_align_shift = (s1_expo_diff >= 8'd49) ? 6'd49 : s1_expo_diff[5:0];

    wire [48:0] s1_smaller_shifted;
    wire        s1_smaller_shifted_sticky;

    barrel_shifter #(
        .DATA_WIDTH(49),
        .SHIFT_WIDTH(6)
    ) u_align_shifter (
        .data_in(s1_smaller_ext),
        .shift_amt(s1_align_shift),
        .dir(1'b1), // Shift Right
        .arith(1'b0),
        .data_out(s1_smaller_shifted),
        .sticky(s1_smaller_shifted_sticky)
    );

    wire s1_sticky = (|s1_smaller_shifted[22:0]) | s1_smaller_shifted_sticky;
    wire [26:0] s1_larger_sigf  = {s1_larger_mant, 2'b00, 1'b0};
    wire [26:0] s1_smaller_sigf = {s1_smaller_shifted[48:23], s1_sticky};

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 1 (STAGE 1 -> STAGE 2)
    // -------------------------------------------------------------------------
    reg        r1_valid;
    reg [26:0] r1_larger_sigf;
    reg [26:0] r1_smaller_sigf;
    reg        r1_is_sub;
    reg        r1_sign;
    reg [7:0]  r1_expo;
    reg        r1_special;
    reg [31:0] r1_special_val;
    reg        r1_invalid;
    reg        r1_is_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_valid        <= 1'b0;
            r1_larger_sigf  <= 27'h0;
            r1_smaller_sigf <= 27'h0;
            r1_is_sub       <= 1'b0;
            r1_sign         <= 1'b0;
            r1_expo         <= 8'h0;
            r1_special      <= 1'b0;
            r1_special_val  <= 32'h0;
            r1_invalid      <= 1'b0;
            r1_is_zero      <= 1'b0;
        end else begin
            r1_valid        <= valid_in;
            r1_larger_sigf  <= s1_larger_sigf;
            r1_smaller_sigf <= s1_smaller_sigf;
            r1_is_sub       <= s1_is_sub;
            r1_sign         <= s1_result_sign;
            r1_expo         <= s1_tentative_expo;
            r1_special      <= s1_special;
            r1_special_val  <= s1_special_val;
            r1_invalid      <= s1_invalid;
            r1_is_zero      <= (A_is_zero && B_is_zero);
        end
    end

    // =========================================================================
    // STAGE 2: SIGNIFICAND ADD/SUBTRACT & LZD
    // =========================================================================
    wire [26:0] s2_addsub_res;
    wire        s2_addsub_cout;

    // Sub-unit: 27-bit Adder/Subtractor
    param_adder_sub #(
        .WIDTH(27)
    ) u_sigf_adder (
        .A(r1_larger_sigf),
        .B(r1_smaller_sigf),
        .sub(r1_is_sub),
        .is_signed(1'b0),
        .result(s2_addsub_res),
        .carry_out(s2_addsub_cout),
        .overflow()
    );

    wire [27:0] s2_sum_sigf = r1_is_sub ? {1'b0, s2_addsub_res} :
                                          {s2_addsub_cout, s2_addsub_res};

    // Sub-unit: Leading Zero Detector
    wire [4:0] s2_lzd_count;
    wire       s2_lzd_all_zeros;

    leading_zero_detector #(
        .WIDTH(27),
        .COUNT_WIDTH(5)
    ) u_lzd (
        .in_vector(s2_sum_sigf[26:0]),
        .zero_count(s2_lzd_count),
        .all_zeros(s2_lzd_all_zeros)
    );

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 2 (STAGE 2 -> STAGE 3)
    // -------------------------------------------------------------------------
    reg        r2_valid;
    reg [27:0] r2_sum_sigf;
    reg [4:0]  r2_lzd_count;
    reg        r2_all_zeros;
    reg        r2_sign;
    reg [7:0]  r2_expo;
    reg        r2_special;
    reg [31:0] r2_special_val;
    reg        r2_invalid;
    reg        r2_is_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r2_valid       <= 1'b0;
            r2_sum_sigf    <= 28'h0;
            r2_lzd_count   <= 5'h0;
            r2_all_zeros   <= 1'b0;
            r2_sign        <= 1'b0;
            r2_expo        <= 8'h0;
            r2_special     <= 1'b0;
            r2_special_val <= 32'h0;
            r2_invalid     <= 1'b0;
            r2_is_zero     <= 1'b0;
        end else begin
            r2_valid       <= r1_valid;
            r2_sum_sigf    <= s2_sum_sigf;
            r2_lzd_count   <= s2_lzd_count;
            r2_all_zeros   <= (s2_sum_sigf == 28'b0);
            r2_sign        <= r1_sign;
            r2_expo        <= r1_expo;
            r2_special     <= r1_special;
            r2_special_val <= r1_special_val;
            r2_invalid     <= r1_invalid;
            r2_is_zero     <= r1_is_zero | (!r1_special && (s2_sum_sigf == 28'b0));
        end
    end

    // =========================================================================
    // STAGE 3: NORMALIZATION SHIFTING & EXPONENT ADJUSTMENT
    // =========================================================================
    // Sub-unit: Normalization Left Shifter
    wire [27:0] s3_norm_lshift;

    barrel_shifter #(
        .DATA_WIDTH(28),
        .SHIFT_WIDTH(5)
    ) u_norm_shifter (
        .data_in(r2_sum_sigf),
        .shift_amt(r2_lzd_count),
        .dir(1'b0), // Shift Left
        .arith(1'b0),
        .data_out(s3_norm_lshift),
        .sticky()
    );

    // Sub-units: Exponent adjustments
    wire [7:0] s3_expo_inc;
    param_adder_sub #(.WIDTH(8)) u_exp_inc (
        .A(r2_expo),
        .B(8'd1),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s3_expo_inc),
        .carry_out(),
        .overflow()
    );

    wire [7:0] s3_expo_dec;
    param_adder_sub #(.WIDTH(8)) u_exp_dec (
        .A(r2_expo),
        .B({3'b0, r2_lzd_count}),
        .sub(1'b1),
        .is_signed(1'b0),
        .result(s3_expo_dec),
        .carry_out(),
        .overflow()
    );

    reg [7:0]  s3_norm_expo;
    reg [27:0] s3_norm_sigf;

    always @(*) begin
        if (r2_all_zeros || r2_sum_sigf == 28'b0) begin
            s3_norm_expo = 8'b0;
            s3_norm_sigf = 28'b0;
        end else if (r2_sum_sigf[27]) begin
            // Addition overflow carry: shift right by 1 and increment exponent
            s3_norm_expo = s3_expo_inc;
            s3_norm_sigf = {1'b0, r2_sum_sigf[27:1]};
            s3_norm_sigf[0] = s3_norm_sigf[0] | r2_sum_sigf[0]; // Retain sticky
        end else begin
            // Subtraction cancellation: shift left by LZD count and decrement exponent
            if (r2_expo > {3'b0, r2_lzd_count})
                s3_norm_expo = s3_expo_dec;
            else
                s3_norm_expo = 8'b0;
            s3_norm_sigf = s3_norm_lshift;
        end
    end

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 3 (STAGE 3 -> STAGE 4)
    // -------------------------------------------------------------------------
    reg        r3_valid;
    reg [27:0] r3_norm_sigf;
    reg [7:0]  r3_norm_expo;
    reg        r3_sign;
    reg        r3_special;
    reg [31:0] r3_special_val;
    reg        r3_invalid;
    reg        r3_is_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r3_valid       <= 1'b0;
            r3_norm_sigf   <= 28'h0;
            r3_norm_expo   <= 8'h0;
            r3_sign        <= 1'b0;
            r3_special     <= 1'b0;
            r3_special_val <= 32'h0;
            r3_invalid     <= 1'b0;
            r3_is_zero     <= 1'b0;
        end else begin
            r3_valid       <= r2_valid;
            r3_norm_sigf   <= s3_norm_sigf;
            r3_norm_expo   <= s3_norm_expo;
            r3_sign        <= r2_sign;
            r3_special     <= r2_special;
            r3_special_val <= r2_special_val;
            r3_invalid     <= r2_invalid;
            r3_is_zero     <= r2_is_zero;
        end
    end

    // =========================================================================
    // STAGE 4: ROUNDING, EXCEPTION HANDLING & OUTPUT PACKING
    // =========================================================================
    wire [23:0] s4_pre_round_mant = r3_norm_sigf[26:3];
    wire [2:0]  s4_grs            = r3_norm_sigf[2:0];

    // Round-to-Nearest-Even rule
    wire s4_round_up = (s4_grs > 3'b100) ? 1'b1 :
                       (s4_grs < 3'b100) ? 1'b0 :
                       s4_pre_round_mant[0];

    wire [23:0] s4_rounded_mant;
    wire        s4_round_cout;

    // Sub-unit: Rounding increment adder
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
    wire [22:0] s4_final_mant  = s4_rounded_ext[24] ? s4_rounded_ext[23:1] : s4_rounded_ext[22:0];

    wire [7:0] s4_expo_round_inc;
    param_adder_sub #(.WIDTH(8)) u_exp_round_inc (
        .A(r3_norm_expo),
        .B(8'd1),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s4_expo_round_inc),
        .carry_out(),
        .overflow()
    );

    wire [7:0] s4_final_expo = s4_rounded_ext[24] ? s4_expo_round_inc : r3_norm_expo;

    wire s4_overflow  = (s4_final_expo >= 8'd255);
    wire s4_underflow = (r3_norm_expo == 8'd0);

    wire [31:0] s4_normal_result =
        (r3_norm_sigf == 28'b0) ? 32'h0 :
        s4_overflow             ? {r3_sign, 8'hFF, 23'h0} :
        s4_underflow            ? {r3_sign, 8'h00, 23'h0} :
                                  {r3_sign, s4_final_expo, s4_final_mant};

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
                flag_underflow <= !r3_special & s4_underflow & (r3_norm_sigf != 28'b0);
                flag_invalid   <= r3_invalid;
                flag_zero      <= r3_special ? (r3_special_val[30:0] == 31'b0) : (r3_is_zero | (s4_result[30:0] == 31'b0));
                flag_inexact   <= !r3_special & (|s4_grs);
            end
        end
    end

endmodule
