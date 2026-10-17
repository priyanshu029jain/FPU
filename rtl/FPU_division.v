// =============================================================================
// Module  : FPU_division
// Reference: IEEE 754-2008 Single-Precision Floating-Point Pipelined Divider
// Architecture: 4-Stage Synchronous Hardware Pipeline (Per Notes Pages 13-15)
// Latency     : 4 Clock Cycles
// Throughput  : 1 Operation / Cycle (Fully Pipelined)
//
// Pipeline Stages:
//   Stage 1: Unpack, Div-by-Zero / NaN Check & Exponent Subtraction (param_adder_sub)
//   Stage 2: Restoring Quotient Bit Engine & Remainder Tracking
//   Stage 3: Normalization Shifting (barrel_shifter) & GRS Extraction
//   Stage 4: IEEE 754 Round-to-Nearest-Even (param_adder_sub), Flags & Packing
// =============================================================================
`timescale 1ns/1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */

module FPU_division (
    input  wire        clk,
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        valid_in,       // Input data valid strobe
    input  wire [31:0] A,              // Dividend (IEEE 754 float)
    input  wire [31:0] B,              // Divisor (IEEE 754 float)
    output reg  [31:0] Y,              // Quotient (IEEE 754 float)
    output reg         valid_out,      // Output data valid strobe (4 cycles latency)
    // IEEE 754-2008 Exception & Status Flags
    output reg         flag_overflow,  // Overflow flag
    output reg         flag_underflow, // Underflow flag
    output reg         flag_invalid,   // Invalid operation (0/0, Inf/Inf, NaN)
    output reg         flag_div_by_zero,// Division by zero flag (x/0 where x != 0)
    output reg         flag_zero,      // Result is exactly zero
    output reg         flag_inexact    // Inexact flag (bits lost or non-zero remainder)
);

    // =========================================================================
    // STAGE 1: UNPACK, PRE-COMPUTATION CHECK & EXPONENT SUBTRACTION
    // =========================================================================
    wire        A_sign = A[31];
    wire [7:0]  A_expo = A[30:23];
    wire [22:0] A_mant = A[22:0];

    wire        B_sign = B[31];
    wire [7:0]  B_expo = B[30:23];
    wire [22:0] B_mant = B[22:0];

    wire A_is_zero = (A_expo == 8'h00) && (A_mant == 23'h0);
    wire B_is_zero = (B_expo == 8'h00) && (B_mant == 23'h0);
    wire A_is_inf  = (A_expo == 8'hFF) && (A_mant == 23'h0);
    wire B_is_inf  = (B_expo == 8'hFF) && (B_mant == 23'h0);
    wire A_is_nan  = (A_expo == 8'hFF) && (A_mant != 23'h0);
    wire B_is_nan  = (B_expo == 8'hFF) && (B_mant != 23'h0);

    wire s1_sign = A_sign ^ B_sign;

    // Special bypass checks
    wire [31:0] qnan = {1'b0, 8'hFF, 23'h400000};
    wire s1_nan  = A_is_nan | B_is_nan | (A_is_zero && B_is_zero) | (A_is_inf && B_is_inf);
    wire s1_div_by_zero = B_is_zero && !A_is_zero && !A_is_nan;
    wire s1_inf  = (A_is_inf | B_is_zero) && !s1_nan;
    wire s1_zero = (A_is_zero | B_is_inf) && !s1_nan;

    wire s1_special = s1_nan | s1_inf | s1_zero;
    wire [31:0] s1_special_val =
        s1_nan ? qnan :
        s1_inf ? {s1_sign, 8'hFF, 23'h0} :
                 {s1_sign, 31'h0}; // zero

    // Hidden bit append: 24-bit significands: 1.M (or 0.M for subnormal)
    wire [23:0] s1_sigA = (A_expo == 8'h00) ? {1'b0, A_mant} : {1'b1, A_mant};
    wire [23:0] s1_sigB = (B_expo == 8'h00) ? {1'b0, B_mant} : {1'b1, B_mant};

    // Sub-units: Exponent subtraction & bias addition via param_adder_sub
    // E_diff = Ea - Eb
    wire signed [9:0] s1_exp_diff;
    param_adder_sub #(.WIDTH(10)) u_exp_sub (
        .A({2'b00, A_expo}),
        .B({2'b00, B_expo}),
        .sub(1'b1),
        .is_signed(1'b1),
        .result(s1_exp_diff),
        .carry_out(),
        .overflow()
    );

    // Etemp = E_diff + 127
    wire signed [9:0] s1_Etemp;
    param_adder_sub #(.WIDTH(10)) u_exp_add_bias (
        .A(s1_exp_diff),
        .B(10'd127),
        .sub(1'b0),
        .is_signed(1'b1),
        .result(s1_Etemp),
        .carry_out(),
        .overflow()
    );

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
    reg              r1_div_by_zero;
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
            r1_div_by_zero <= 1'b0;
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
            r1_div_by_zero <= s1_div_by_zero;
            r1_zero        <= s1_zero;
        end
    end

    // =========================================================================
    // STAGE 2: RESTORING QUOTIENT ENGINE & REMAINDER
    // =========================================================================
    reg [49:0] s2_rem;
    reg [25:0] s2_Q_bits;
    integer    idx;

    always @(*) begin
        s2_rem    = {r1_sigA, 26'b0};
        s2_Q_bits = 26'b0;
        for (idx = 25; idx >= 0; idx = idx - 1) begin
            if (s2_rem >= ({r1_sigB, 26'b0} >> (25 - idx))) begin
                s2_Q_bits[idx] = 1'b1;
                s2_rem         = s2_rem - ({r1_sigB, 26'b0} >> (25 - idx));
            end else begin
                s2_Q_bits[idx] = 1'b0;
            end
        end
    end

    wire s2_has_remainder = (s2_rem != 50'b0);

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 2 (STAGE 2 -> STAGE 3)
    // -------------------------------------------------------------------------
    reg              r2_valid;
    reg [25:0]       r2_Q_bits;
    reg              r2_has_remainder;
    reg              r2_sign;
    reg signed [9:0] r2_Etemp;
    reg              r2_special;
    reg [31:0]       r2_special_val;
    reg              r2_nan;
    reg              r2_div_by_zero;
    reg              r2_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r2_valid         <= 1'b0;
            r2_Q_bits        <= 26'h0;
            r2_has_remainder <= 1'b0;
            r2_sign          <= 1'b0;
            r2_Etemp         <= 10'sd0;
            r2_special       <= 1'b0;
            r2_special_val   <= 32'h0;
            r2_nan           <= 1'b0;
            r2_div_by_zero   <= 1'b0;
            r2_zero          <= 1'b0;
        end else begin
            r2_valid         <= r1_valid;
            r2_Q_bits        <= s2_Q_bits;
            r2_has_remainder <= s2_has_remainder;
            r2_sign          <= r1_sign;
            r2_Etemp         <= r1_Etemp;
            r2_special       <= r1_special;
            r2_special_val   <= r1_special_val;
            r2_nan           <= r1_nan;
            r2_div_by_zero   <= r1_div_by_zero;
            r2_zero          <= r1_zero;
        end
    end

    // =========================================================================
    // STAGE 3: NORMALIZATION SHIFTING & GRS EXTRACTION
    // =========================================================================
    wire s3_case1 = r2_Q_bits[25]; // 1 if 1.0 <= Q < 2.0 (no shift required)

    // Sub-unit: Left shift by 1 if Case 2 (0.5 < Q < 1.0)
    wire [25:0] s3_norm_lshifted;
    barrel_shifter #(
        .DATA_WIDTH(26),
        .SHIFT_WIDTH(5)
    ) u_norm_lshift (
        .data_in(r2_Q_bits),
        .shift_amt(s3_case1 ? 5'd0 : 5'd1),
        .dir(1'b0), // Shift Left
        .arith(1'b0),
        .data_out(s3_norm_lshifted),
        .sticky()
    );

    wire [25:0] s3_norm_Q = s3_case1 ? r2_Q_bits : s3_norm_lshifted;

    // Sub-unit: Exponent decrement for Case 2
    wire signed [9:0] s3_exp_dec;
    param_adder_sub #(.WIDTH(10)) u_exp_norm_dec (
        .A(r2_Etemp),
        .B(10'd1),
        .sub(1'b1),
        .is_signed(1'b1),
        .result(s3_exp_dec),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s3_Efinal_norm = s3_case1 ? r2_Etemp : s3_exp_dec;

    wire [23:0] s3_pre_round_mant = s3_norm_Q[25:2];
    wire s3_G = s3_norm_Q[1];
    wire s3_R = s3_norm_Q[0];
    wire s3_S = r2_has_remainder;
    wire [2:0] s3_grs = {s3_G, s3_R, s3_S};

    wire s3_round_up = (s3_grs > 3'b100) ? 1'b1 :
                       (s3_grs < 3'b100) ? 1'b0 :
                       s3_pre_round_mant[0];

    // -------------------------------------------------------------------------
    // PIPELINE REGISTER 3 (STAGE 3 -> STAGE 4)
    // -------------------------------------------------------------------------
    reg              r3_valid;
    reg [23:0]       r3_pre_round_mant;
    reg              r3_round_up;
    reg [2:0]        r3_grs;
    reg signed [9:0] r3_Efinal_norm;
    reg              r3_sign;
    reg              r3_special;
    reg [31:0]       r3_special_val;
    reg              r3_nan;
    reg              r3_div_by_zero;
    reg              r3_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r3_valid          <= 1'b0;
            r3_pre_round_mant <= 24'h0;
            r3_round_up       <= 1'b0;
            r3_grs            <= 3'b0;
            r3_Efinal_norm    <= 10'sd0;
            r3_sign           <= 1'b0;
            r3_special        <= 1'b0;
            r3_special_val    <= 32'h0;
            r3_nan            <= 1'b0;
            r3_div_by_zero    <= 1'b0;
            r3_zero           <= 1'b0;
        end else begin
            r3_valid          <= r2_valid;
            r3_pre_round_mant <= s3_pre_round_mant;
            r3_round_up       <= s3_round_up;
            r3_grs            <= s3_grs;
            r3_Efinal_norm    <= s3_Efinal_norm;
            r3_sign           <= r2_sign;
            r3_special        <= r2_special;
            r3_special_val    <= r2_special_val;
            r3_nan            <= r2_nan;
            r3_div_by_zero    <= r2_div_by_zero;
            r3_zero           <= r2_zero;
        end
    end

    // =========================================================================
    // STAGE 4: ROUNDING, EXCEPTION HANDLING & OUTPUT PACKING
    // =========================================================================
    wire [23:0] s4_rounded_mant;
    wire        s4_round_cout;

    // Sub-unit: Rounding adder
    param_adder_sub #(
        .WIDTH(24)
    ) u_round_adder (
        .A(r3_pre_round_mant),
        .B({23'b0, r3_round_up}),
        .sub(1'b0),
        .is_signed(1'b0),
        .result(s4_rounded_mant),
        .carry_out(s4_round_cout),
        .overflow()
    );

    wire [24:0] s4_rounded_ext = {s4_round_cout, s4_rounded_mant};
    wire        s4_round_overflow = s4_rounded_ext[24];
    wire [22:0] s4_final_mant = s4_round_overflow ? s4_rounded_ext[23:1] : s4_rounded_ext[22:0];

    // Exponent post-rounding carry increment
    wire signed [9:0] s4_exp_round_inc;
    param_adder_sub #(.WIDTH(10)) u_exp_round_inc (
        .A(r3_Efinal_norm),
        .B(10'd1),
        .sub(1'b0),
        .is_signed(1'b1),
        .result(s4_exp_round_inc),
        .carry_out(),
        .overflow()
    );

    wire signed [9:0] s4_Efinal = s4_round_overflow ? s4_exp_round_inc : r3_Efinal_norm;

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
            Y                <= 32'h00000000;
            valid_out        <= 1'b0;
            flag_overflow    <= 1'b0;
            flag_underflow   <= 1'b0;
            flag_invalid     <= 1'b0;
            flag_div_by_zero <= 1'b0;
            flag_zero        <= 1'b0;
            flag_inexact     <= 1'b0;
        end else begin
            valid_out <= r3_valid;
            if (r3_valid) begin
                Y                <= s4_result;
                flag_overflow    <= !r3_special & s4_overflow;
                flag_underflow   <= !r3_special & s4_underflow & !r3_zero;
                flag_invalid     <= r3_nan;
                flag_div_by_zero <= r3_div_by_zero;
                flag_zero        <= r3_zero | (s4_result[30:0] == 31'b0);
                flag_inexact     <= !r3_special & (|r3_grs);
            end
        end
    end

endmodule
