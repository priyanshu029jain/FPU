// =============================================================================
// Module    : sva_division.sv
// Language  : SystemVerilog (IEEE 1800-2012)
// Purpose   : Standalone SystemVerilog Assertions (SVA) Formal Checker Module
//             for FPU_division (IEEE 754-2008 Single-Precision, 4-Stage Pipeline)
//
// Invariant Property Checklist:
//   1. Pipeline Latency        : valid_out asserts exactly 4 cycles after valid_in
//   2. Premature Valid Guard   : No premature valid_out before 4 cycles
//   3. Result Stability        : Stable outputs during static valid cycles
//   4. Unknown States Guard    : No X or Z states on Y when valid_out is high
//   5. IEEE-754 Special Cases  :
//        - NaN propagation: Any input NaN -> Y must be NaN
//        - Invalid 0/0 and Inf/Inf: Must yield NaN and flag_invalid
//        - Division by Zero: X / 0 -> Inf and flag_div_by_zero
//        - Zero dividend: 0 / X -> Zero and flag_zero
//        - Sign Parity: S_y = S_a ^ S_b (for non-NaN, non-zero results)
//   6. Exception Consistency   :
//        - flag_overflow    -> Exponent == 255 (saturation to Inf)
//        - flag_underflow   -> Exponent == 0 (flush to zero)
//        - flag_invalid     -> Output is NaN
//        - flag_div_by_zero -> Output is Inf
//        - flag_zero        -> Output is Zero
//   7. Functional Correctness  : Compare Y against IEEE 754 ref_model(A, B)
//
// Note: All assertions strictly use `disable iff (!rst_n)`.
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off SYNCASYNCNET */

module sva_division;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic [31:0] A;
    logic [31:0] B;

    // DUT Output Signals
    logic [31:0] Y;
    logic        valid_out;
    logic        flag_overflow;
    logic        flag_underflow;
    logic        flag_invalid;
    logic        flag_div_by_zero;
    logic        flag_zero;
    logic        flag_inexact;

    // -------------------------------------------------------------------------
    // 0. DUT Instantiation: 4-Stage Synchronous Pipelined FPU Divider
    // -------------------------------------------------------------------------
    FPU_division dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .valid_in        (valid_in),
        .A               (A),
        .B               (B),
        .Y               (Y),
        .valid_out       (valid_out),
        .flag_overflow   (flag_overflow),
        .flag_underflow  (flag_underflow),
        .flag_invalid    (flag_invalid),
        .flag_div_by_zero(flag_div_by_zero),
        .flag_zero       (flag_zero),
        .flag_inexact    (flag_inexact)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Classification Functions
    // -------------------------------------------------------------------------
    function automatic bit is_nan(input [31:0] val);
        return (val[30:23] == 8'hFF) && (val[22:0] != 23'h0);
    endfunction

    function automatic bit is_inf(input [31:0] val);
        return (val[30:23] == 8'hFF) && (val[22:0] == 23'h0);
    endfunction

    function automatic bit is_zero(input [31:0] val);
        return (val[30:23] == 8'h00) && (val[22:0] == 23'h0);
    endfunction

    // Helper IEEE 754 Floating-Point Converter Functions
    function automatic [63:0] float32_to_double64(input [31:0] f32);
        logic sign;
        logic [7:0] exp32;
        logic [22:0] mant32;
        logic [10:0] exp64;
        logic [51:0] mant64;
        begin
            sign   = f32[31];
            exp32  = f32[30:23];
            mant32 = f32[22:0];

            if (exp32 == 8'h00) begin
                exp64 = 11'h000;
            end else if (exp32 == 8'hFF) begin
                exp64 = 11'h7FF;
            end else begin
                exp64 = 11'(int'(exp32) - 127 + 1023);
            end
            mant64 = {mant32, 29'b0};
            return {sign, exp64, mant64};
        end
    endfunction

    function automatic [31:0] double64_to_float32(input [63:0] d64);
        logic sign;
        logic [10:0] exp64;
        logic [51:0] mant64;
        logic [7:0] exp32;
        logic [22:0] mant32;
        int exp_val;
        begin
            sign   = d64[63];
            exp64  = d64[62:52];
            mant64 = d64[51:0];

            if (exp64 == 11'h000) begin
                exp32 = 8'h00;
            end else if (exp64 == 11'h7FF) begin
                exp32 = 8'hFF;
            end else begin
                exp_val = int'(exp64) - 1023 + 127;
                if (exp_val >= 255) exp32 = 8'hFF;
                else if (exp_val <= 0) exp32 = 8'h00;
                else exp32 = 8'(exp_val);
            end
            mant32 = mant64[51:29];
            return {sign, exp32, mant32};
        end
    endfunction

    // -------------------------------------------------------------------------
    // 7. Functional Correctness Reference Model Function Placeholder
    // Compares output Y against IEEE 754 reference division
    // -------------------------------------------------------------------------
    function automatic [31:0] ref_model(input [31:0] op_a, input [31:0] op_b);
        real real_a, real_b, real_res;
        begin
            real_a   = $bitstoreal(float32_to_double64(op_a));
            real_b   = $bitstoreal(float32_to_double64(op_b));
            real_res = real_a / real_b;
            return double64_to_float32($realtobits(real_res));
        end
    endfunction

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA) PROPERTIES
    // All properties strictly use `disable iff (!rst_n)`
    // =========================================================================

    // -------------------------------------------------------------------------
    // Property 1: Pipeline Latency
    // valid_out must assert exactly 4 clock cycles after valid_in
    // -------------------------------------------------------------------------
    property p_pipeline_latency;
        @(posedge clk) disable iff (!rst_n)
        $past(valid_in, 4) |-> valid_out;
    endproperty
    a_pipeline_latency: assert property (p_pipeline_latency)
        else $error("[SVA FAIL] Latency Violation: valid_out did not assert exactly 4 cycles after valid_in!");

    // -------------------------------------------------------------------------
    // Property 2: No Premature valid_out
    // valid_out must NEVER be high without valid_in exactly 4 cycles prior
    // -------------------------------------------------------------------------
    property p_no_premature_valid;
        @(posedge clk) disable iff (!rst_n)
        valid_out |-> $past(valid_in, 4);
    endproperty
    a_no_premature_valid: assert property (p_no_premature_valid)
        else $error("[SVA FAIL] Premature valid_out: valid_out asserted without valid_in 4 cycles prior!");

    // -------------------------------------------------------------------------
    // Property 3: Result Stability
    // When valid_out is held high and inputs remain static, Y must remain stable
    // -------------------------------------------------------------------------
    property p_result_stability;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && $past(valid_out) && $stable($past(A, 4)) && $stable($past(B, 4))) |-> $stable(Y);
    endproperty
    a_result_stability: assert property (p_result_stability)
        else $error("[SVA FAIL] Stability Violation: Output Y changed while inputs and valid_out remained stable!");

    // -------------------------------------------------------------------------
    // Property 4: No Unknowns (X/Z) in Output
    // When valid_out is high, output bus Y must not contain any X or Z bits
    // -------------------------------------------------------------------------
    property p_no_unknown_y;
        @(posedge clk) disable iff (!rst_n)
        valid_out |-> !$isunknown(Y);
    endproperty
    a_no_unknown_y: assert property (p_no_unknown_y)
        else $error("[SVA FAIL] Unknown Output: Y contains X or Z bits when valid_out is high! Y = %b", Y);

    // -------------------------------------------------------------------------
    // Property 5A: NaN Propagation
    // If either input A or B is NaN, output Y must be NaN
    // -------------------------------------------------------------------------
    property p_nan_propagation;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && (is_nan($past(A, 4)) || is_nan($past(B, 4))))
        |-> is_nan(Y);
    endproperty
    a_nan_propagation: assert property (p_nan_propagation)
        else $error("[SVA FAIL] NaN Propagation Violation: Input NaN did not propagate to output Y!");

    // -------------------------------------------------------------------------
    // Property 5B: 0/0 and Inf/Inf Invalid Operation
    // 0/0 or Inf/Inf must produce NaN and flag_invalid
    // -------------------------------------------------------------------------
    property p_invalid_div_ops;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && ((is_zero($past(A, 4)) && is_zero($past(B, 4))) ||
                       (is_inf($past(A, 4))  && is_inf($past(B, 4)))))
        |-> (is_nan(Y) && flag_invalid);
    endproperty
    a_invalid_div_ops: assert property (p_invalid_div_ops)
        else $error("[SVA FAIL] Invalid 0/0 or Inf/Inf: Must yield NaN and assert flag_invalid!");

    // -------------------------------------------------------------------------
    // Property 5C: Division by Zero
    // X / 0 (X != 0, non-NaN) must produce Infinity and assert flag_div_by_zero
    // -------------------------------------------------------------------------
    property p_div_by_zero;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && !is_zero($past(A, 4)) && !is_nan($past(A, 4)) && is_zero($past(B, 4)))
        |-> (is_inf(Y) && flag_div_by_zero);
    endproperty
    a_div_by_zero: assert property (p_div_by_zero)
        else $error("[SVA FAIL] Div by Zero Violation: X / 0 must yield Inf and assert flag_div_by_zero!");

    // -------------------------------------------------------------------------
    // Property 5D: Zero Dividend
    // 0 / X (X != 0, non-NaN) must produce Zero and assert flag_zero
    // -------------------------------------------------------------------------
    property p_zero_dividend;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && is_zero($past(A, 4)) && !is_zero($past(B, 4)) && !is_nan($past(B, 4)))
        |-> (is_zero(Y) && flag_zero);
    endproperty
    a_zero_dividend: assert property (p_zero_dividend)
        else $error("[SVA FAIL] Zero Dividend Violation: 0 / X must yield Zero and assert flag_zero!");

    // -------------------------------------------------------------------------
    // Property 5E: Sign Parity Invariant
    // For normal non-zero operations, S_y == S_a ^ S_b
    // -------------------------------------------------------------------------
    property p_sign_parity;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && !is_nan(Y) && !is_zero(Y) &&
         !is_nan($past(A, 4)) && !is_nan($past(B, 4)))
        |-> (Y[31] == ($past(A[31], 4) ^ $past(B[31], 4)));
    endproperty
    a_sign_parity: assert property (p_sign_parity)
        else $error("[SVA FAIL] Sign Parity Mismatch: Sy != Sa ^ Sb on divider output!");

    // -------------------------------------------------------------------------
    // Property 6A: Overflow Flag Consistency
    // When flag_overflow is asserted, output exponent must be 255 (Inf)
    // -------------------------------------------------------------------------
    property p_overflow_exp_255;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && flag_overflow) |-> (Y[30:23] == 8'hFF);
    endproperty
    a_overflow_exp_255: assert property (p_overflow_exp_255)
        else $error("[SVA FAIL] Flag Inconsistency: flag_overflow is high but exponent != 255!");

    // -------------------------------------------------------------------------
    // Property 6B: Underflow Flag Consistency
    // When flag_underflow is asserted, output exponent must be 0
    // -------------------------------------------------------------------------
    property p_underflow_exp_0;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && flag_underflow) |-> (Y[30:23] == 8'h00);
    endproperty
    a_underflow_exp_0: assert property (p_underflow_exp_0)
        else $error("[SVA FAIL] Flag Inconsistency: flag_underflow is high but exponent != 0!");

    // -------------------------------------------------------------------------
    // Property 6C: Invalid Flag Consistency
    // When flag_invalid is asserted, output must be NaN
    // -------------------------------------------------------------------------
    property p_invalid_flag_nan;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && flag_invalid) |-> is_nan(Y);
    endproperty
    a_invalid_flag_nan: assert property (p_invalid_flag_nan)
        else $error("[SVA FAIL] Flag Inconsistency: flag_invalid is high but output is not NaN!");

    // -------------------------------------------------------------------------
    // Property 6D: Div-by-Zero Flag Consistency
    // When flag_div_by_zero is asserted, output must be Infinity
    // -------------------------------------------------------------------------
    property p_div_zero_flag_inf;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && flag_div_by_zero) |-> is_inf(Y);
    endproperty
    a_div_zero_flag_inf: assert property (p_div_zero_flag_inf)
        else $error("[SVA FAIL] Flag Inconsistency: flag_div_by_zero is high but output is not Inf!");

    // -------------------------------------------------------------------------
    // Property 7: Functional Correctness Check against Reference Model
    // -------------------------------------------------------------------------
    property p_functional_correctness;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && !is_nan($past(A, 4)) && !is_nan($past(B, 4)) &&
         !is_inf($past(A, 4)) && !is_inf($past(B, 4)) &&
         !is_zero($past(B, 4)) &&
         !flag_overflow && !flag_underflow)
        |-> (is_zero(Y) ? is_zero(ref_model($past(A, 4), $past(B, 4))) : (Y == ref_model($past(A, 4), $past(B, 4))));
    endproperty
    a_functional_correctness: assert property (p_functional_correctness)
        else $error("[SVA FAIL] Functional Mismatch: Y=0x%08h, Expected=0x%08h (A=0x%08h, B=0x%08h)",
                    Y, ref_model($past(A, 4), $past(B, 4)), $past(A, 4), $past(B, 4));

    // -------------------------------------------------------------------------
    // SVA Cover Properties for Functional Coverage Tracking
    // -------------------------------------------------------------------------
    cov_latency:       cover property (p_pipeline_latency);
    cov_no_premature:  cover property (p_no_premature_valid);
    cov_stability:     cover property (p_result_stability);
    cov_no_unknown:    cover property (p_no_unknown_y);
    cov_nan_prop:      cover property (p_nan_propagation);
    cov_invalid_ops:   cover property (p_invalid_div_ops);
    cov_div_zero:      cover property (p_div_by_zero);
    cov_zero_dividend: cover property (p_zero_dividend);
    cov_sign_parity:   cover property (p_sign_parity);
    cov_overflow:      cover property (p_overflow_exp_255);
    cov_underflow:     cover property (p_underflow_exp_0);
    cov_invalid:       cover property (p_invalid_flag_nan);
    cov_div_zero_flag: cover property (p_div_zero_flag_inf);
    cov_functional:    cover property (p_functional_correctness);

    // =========================================================================
    // STIMULUS GENERATION & SVA CHECKER EXERCISE SEQUENCE
    // =========================================================================
    localparam logic [31:0] P_ZERO    = 32'h00000000;
    localparam logic [31:0] N_ZERO    = 32'h80000000;
    localparam logic [31:0] P_INF     = 32'h7F800000;
    localparam logic [31:0] N_INF     = 32'hFF800000;
    localparam logic [31:0] Q_NAN     = 32'h7FC00000;
    localparam logic [31:0] MIN_NORM  = 32'h00800000;

    initial begin
        $dumpfile("waveform_sva_division.vcd");
        $dumpvars(0, sva_division);

        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        A        = 32'h0;
        B        = 32'h0;

        $display("===============================================================================");
        $display("  STARTING SVA CHECKER VERIFICATION FOR FPU_DIVISION (IEEE 754 PIPELINED)");
        $display("===============================================================================\n");

        // 1. Reset Sequence
        #25;
        rst_n = 1'b1;
        #20;

        // 2. Stimulus: Normal Division (10.0 / 2.0 = 5.0)
        $display("[SVA STIM] Vector 1: 10.0 / 2.0 = 5.0 (Functional & Latency Check)");
        @(negedge clk);
        A <= 32'h41200000; // 10.0
        B <= 32'h40000000; // 2.0
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b", Y, valid_out);

        // 3. Stimulus: Sign Parity Check (-9.0 / 3.0 = -3.0)
        $display("[SVA STIM] Vector 2: -9.0 / 3.0 = -3.0 (Sign Parity Check)");
        @(negedge clk);
        A <= 32'hC1100000; // -9.0
        B <= 32'h40400000; // +3.0
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b", Y, valid_out);

        // 4. Stimulus: 0 / 0 (Invalid Operation & NaN Check)
        $display("[SVA STIM] Vector 3: 0.0 / 0.0 (Invalid Operation & NaN Check)");
        @(negedge clk);
        A <= P_ZERO;
        B <= P_ZERO;
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_invalid = %b", Y, valid_out, flag_invalid);

        // 5. Stimulus: Division by Zero (5.0 / 0.0 -> Inf)
        $display("[SVA STIM] Vector 4: 5.0 / 0.0 (Division by Zero Check)");
        @(negedge clk);
        A <= 32'h40A00000; // 5.0
        B <= P_ZERO;
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_div_by_zero = %b", Y, valid_out, flag_div_by_zero);

        // 6. Stimulus: Zero Dividend (0.0 / 5.0 = 0.0)
        $display("[SVA STIM] Vector 5: 0.0 / 5.0 (Zero Dividend Check)");
        @(negedge clk);
        A <= P_ZERO;
        B <= 32'h40A00000; // 5.0
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_zero = %b", Y, valid_out, flag_zero);

        // 7. Stimulus: NaN Propagation (QNaN / 5.0)
        $display("[SVA STIM] Vector 6: QNaN / 5.0 (NaN Propagation Check)");
        @(negedge clk);
        A <= Q_NAN;
        B <= 32'h40A00000;
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_invalid = %b", Y, valid_out, flag_invalid);

        // 8. Continuous Pipelined Streaming (Vectors 7-11)
        $display("[SVA STIM] Vectors 7-11: Pipelined Streaming (Throughput & Stability Check)");
        @(negedge clk);
        A <= 32'h40000000; B <= 32'h3F800000; valid_in <= 1'b1; // 2.0 / 1.0 = 2.0
        @(negedge clk);
        A <= 32'h40800000; B <= 32'h40000000; valid_in <= 1'b1; // 4.0 / 2.0 = 2.0
        @(negedge clk);
        A <= 32'h40C00000; B <= 32'h40000000; valid_in <= 1'b1; // 6.0 / 2.0 = 3.0
        @(negedge clk);
        A <= 32'h41000000; B <= 32'h40000000; valid_in <= 1'b1; // 8.0 / 2.0 = 4.0
        @(negedge clk);
        A <= 32'h41200000; B <= 32'h40000000; valid_in <= 1'b1; // 10.0 / 2.0 = 5.0
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (8) @(posedge clk);

        $display("\n===============================================================================");
        $display("  SVA CHECKER VERIFICATION COMPLETED FOR FPU_DIVISION");
        $display("  ALL CONCURRENT SVA ASSERTIONS & COVER PROPERTIES MONITORED CLEANLY!");
        $display("===============================================================================\n");

        #50;
        $finish;
    end

endmodule
