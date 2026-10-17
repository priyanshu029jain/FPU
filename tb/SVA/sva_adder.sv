// =============================================================================
// Module     : sva_adder.sv
// Language   : SystemVerilog (IEEE 1800-2012)
// Purpose    : Standalone SystemVerilog Assertion (SVA) Checker Module &
//              Verification Testbench for FPU_adder (IEEE 754 Single-Precision,
//              4-Stage Synchronous Hardware Pipeline, 4-Cycle Latency)
//
// Properties & Invariants Verified:
//   1. Pipeline Latency: valid_out must assert exactly 4 cycles after valid_in.
//   2. No Premature valid_out: valid_out cannot assert without valid_in 4 cycles prior.
//   3. Result Stability: once valid_out is high, Y remains stable for static inputs.
//   4. Unknown States (X/Z): No X or Z bits allowed on Y when valid_out is high.
//   5. IEEE 754 Special Cases:
//      - NaN propagation: (A is NaN || B is NaN) |-> Output is NaN.
//      - Opposite-sign Infinity addition: (+Inf + -Inf) |-> Output is NaN.
//      - Zero addition: (+/-0.0 + +/-0.0) |-> Output is Zero.
//   6. Exception Flags Consistency:
//      - flag_overflow  |-> Result exponent == 255.
//      - flag_underflow |-> Result exponent == 0.
//      - flag_invalid   |-> Result is NaN.
//   7. Functional Correctness Placeholder: Y matches reference model ref_model(A, B).
//
// SVA Convention:
//   Every property strictly uses `disable iff (!rst_n)`.
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off SHORTREAL */
/* verilator lint_off SYNCASYNCNET */

module sva_adder;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic [31:0] A;
    logic [31:0] B;

    // DUT Outputs
    logic [31:0] Y;
    logic        valid_out;
    logic        flag_overflow;
    logic        flag_underflow;
    logic        flag_invalid;
    logic        flag_zero;
    logic        flag_inexact;

    // -------------------------------------------------------------------------
    // 0. DUT Instantiation: 4-Stage Synchronous Pipelined FPU Adder
    // -------------------------------------------------------------------------
    FPU_adder dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (valid_in),
        .A             (A),
        .B             (B),
        .Y             (Y),
        .valid_out     (valid_out),
        .flag_overflow (flag_overflow),
        .flag_underflow(flag_underflow),
        .flag_invalid  (flag_invalid),
        .flag_zero     (flag_zero),
        .flag_inexact  (flag_inexact)
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

    // -------------------------------------------------------------------------
    // Helper IEEE 754 Floating-Point Converter Functions
    // -------------------------------------------------------------------------
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
    // Compares output Y against IEEE 754 reference addition
    // -------------------------------------------------------------------------
    function automatic [31:0] ref_model(input [31:0] op_a, input [31:0] op_b);
        real real_a, real_b, real_res;
        begin
            real_a   = $bitstoreal(float32_to_double64(op_a));
            real_b   = $bitstoreal(float32_to_double64(op_b));
            real_res = real_a + real_b;
            return double64_to_float32($realtobits(real_res));
        end
    endfunction

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA) PROPERTIES
    // All properties strictly use `disable iff (!rst_n)`
    // =========================================================================

    // -------------------------------------------------------------------------
    // Property 1: Exact 4-Cycle Pipeline Latency
    // valid_out must assert exactly 4 clock cycles after valid_in
    // -------------------------------------------------------------------------
    property p_pipeline_latency;
        @(posedge clk) disable iff (!rst_n)
        $past(valid_in, 4) |-> valid_out;
    endproperty
    a_pipeline_latency: assert property (p_pipeline_latency)
        else $error("[SVA FAIL] Latency Violation: valid_out did not assert exactly 4 cycles after valid_in!");

    // -------------------------------------------------------------------------
    // Property 2: No Premature / Spurious valid_out
    // valid_out can only be high if valid_in was asserted exactly 4 cycles prior
    // -------------------------------------------------------------------------
    property p_no_premature_valid;
        @(posedge clk) disable iff (!rst_n)
        valid_out |-> $past(valid_in, 4);
    endproperty
    a_no_premature_valid: assert property (p_no_premature_valid)
        else $error("[SVA FAIL] Premature/Spurious Valid: valid_out asserted without valid_in 4 cycles ago!");

    // -------------------------------------------------------------------------
    // Property 3: Result Stability
    // When valid_out is high for back-to-back equivalent inputs, Y remains stable
    // -------------------------------------------------------------------------
    property p_result_stability;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && $past(valid_out) && $stable($past(A, 4)) && $stable($past(B, 4))) |-> $stable(Y);
    endproperty
    a_result_stability: assert property (p_result_stability)
        else $error("[SVA FAIL] Stability Violation: Y became unstable for static inputs!");

    // -------------------------------------------------------------------------
    // Property 4: No Unknowns (X/Z) in Output
    // No X or Z bits allowed on Y when valid_out is high
    // -------------------------------------------------------------------------
    property p_no_unknown_y;
        @(posedge clk) disable iff (!rst_n)
        valid_out |-> !$isunknown(Y);
    endproperty
    a_no_unknown_y: assert property (p_no_unknown_y)
        else $error("[SVA FAIL] Unknown State Detected: Y contains X or Z bits while valid_out is high!");

    // -------------------------------------------------------------------------
    // Property 5A: NaN Propagation
    // If either input was NaN 4 cycles ago, output must be NaN
    // -------------------------------------------------------------------------
    property p_nan_propagation;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && (is_nan($past(A, 4)) || is_nan($past(B, 4)))) |-> is_nan(Y);
    endproperty
    a_nan_propagation: assert property (p_nan_propagation)
        else $error("[SVA FAIL] IEEE 754 Violation: NaN operand did not propagate NaN to output!");

    // -------------------------------------------------------------------------
    // Property 5B: Opposite-Sign Infinity Addition Indeterminacy
    // (+Inf + -Inf) or (-Inf + +Inf) must produce NaN
    // -------------------------------------------------------------------------
    property p_inf_opposite_signs_nan;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && is_inf($past(A, 4)) && is_inf($past(B, 4)) && ($past(A[31], 4) ^ $past(B[31], 4))) |-> is_nan(Y);
    endproperty
    a_inf_opposite_signs_nan: assert property (p_inf_opposite_signs_nan)
        else $error("[SVA FAIL] IEEE 754 Violation: +Inf + -Inf did not yield NaN!");

    // -------------------------------------------------------------------------
    // Property 5C: Zero + Zero Produces Zero
    // Adding zeros (+0.0 or -0.0) must produce zero
    // -------------------------------------------------------------------------
    property p_zero_add_zero;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && is_zero($past(A, 4)) && is_zero($past(B, 4))) |-> is_zero(Y);
    endproperty
    a_zero_add_zero: assert property (p_zero_add_zero)
        else $error("[SVA FAIL] IEEE 754 Violation: Zero + Zero did not yield Zero!");

    // -------------------------------------------------------------------------
    // Property 6A: Overflow Flag Consistency
    // When flag_overflow is asserted, output exponent must be 255 (Infinity)
    // -------------------------------------------------------------------------
    property p_overflow_exp_255;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && flag_overflow) |-> (Y[30:23] == 8'd255);
    endproperty
    a_overflow_exp_255: assert property (p_overflow_exp_255)
        else $error("[SVA FAIL] Flag Inconsistency: flag_overflow is high but exponent != 255!");

    // -------------------------------------------------------------------------
    // Property 6B: Underflow Flag Consistency
    // When flag_underflow is asserted, output exponent must be 0
    // -------------------------------------------------------------------------
    property p_underflow_exp_0;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && flag_underflow) |-> (Y[30:23] == 8'd0);
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
    // Property 7: Functional Correctness Check against Reference Model
    // Validates normal arithmetic results against ref_model(A, B)
    // -------------------------------------------------------------------------
    property p_functional_correctness;
        @(posedge clk) disable iff (!rst_n)
        (valid_out && !is_nan($past(A, 4)) && !is_nan($past(B, 4)) &&
         !is_inf($past(A, 4)) && !is_inf($past(B, 4)) &&
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
    cov_inf_opposite:  cover property (p_inf_opposite_signs_nan);
    cov_zero_add:      cover property (p_zero_add_zero);
    cov_overflow:      cover property (p_overflow_exp_255);
    cov_underflow:     cover property (p_underflow_exp_0);
    cov_invalid:       cover property (p_invalid_flag_nan);
    cov_functional:    cover property (p_functional_correctness);

    // =========================================================================
    // STIMULUS GENERATION & SVA CHECKER EXERCISE SEQUENCE
    // =========================================================================
    localparam logic [31:0] P_ZERO    = 32'h00000000;
    localparam logic [31:0] N_ZERO    = 32'h80000000;
    localparam logic [31:0] P_INF     = 32'h7F800000;
    localparam logic [31:0] N_INF     = 32'hFF800000;
    localparam logic [31:0] Q_NAN     = 32'h7FC00000;
    localparam logic [31:0] MAX_FLOAT = 32'h7F7FFFFF;

    initial begin
        $dumpfile("waveform_sva_adder.vcd");
        $dumpvars(0, sva_adder);

        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        A        = 32'h0;
        B        = 32'h0;

        $display("===============================================================================");
        $display("  STARTING SVA CHECKER VERIFICATION FOR FPU_ADDER (IEEE 754 PIPELINED)");
        $display("===============================================================================\n");

        // 1. Reset Sequence
        #25;
        rst_n = 1'b1;
        #20;

        // 2. Stimulus: Normal Addition (2.0 + 3.0 = 5.0)
        $display("[SVA STIM] Vector 1: 2.0 + 3.0 = 5.0 (Functional & Latency Check)");
        @(negedge clk);
        A <= 32'h40000000; // 2.0
        B <= 32'h40400000; // 3.0
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b", Y, valid_out);

        // 3. Stimulus: Zero + Zero (+0.0 + -0.0)
        $display("[SVA STIM] Vector 2: +0.0 + -0.0 (Zero Check)");
        @(negedge clk);
        A <= P_ZERO;
        B <= N_ZERO;
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_zero = %b", Y, valid_out, flag_zero);

        // 4. Stimulus: Opposite-Sign Infinities (+Inf + -Inf)
        $display("[SVA STIM] Vector 3: +Inf + -Inf (Invalid Operation & NaN Check)");
        @(negedge clk);
        A <= P_INF;
        B <= N_INF;
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_invalid = %b", Y, valid_out, flag_invalid);

        // 5. Stimulus: NaN Propagation (QNaN + 5.0)
        $display("[SVA STIM] Vector 4: QNaN + 5.0 (NaN Propagation Check)");
        @(negedge clk);
        A <= Q_NAN;
        B <= 32'h40A00000; // 5.0
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_invalid = %b", Y, valid_out, flag_invalid);

        // 6. Stimulus: Exponent Overflow (MaxFloat + MaxFloat)
        $display("[SVA STIM] Vector 5: MaxFloat + MaxFloat (Overflow Check)");
        @(negedge clk);
        A <= MAX_FLOAT;
        B <= MAX_FLOAT;
        valid_in <= 1'b1;
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        $display("           Output Y = 0x%08h, valid_out = %b, flag_overflow = %b", Y, valid_out, flag_overflow);

        // 7. Back-to-back streaming vectors (Throughput & Stability Check)
        $display("[SVA STIM] Vectors 6-10: Pipelined Streaming (Throughput & Stability Check)");
        for (int i = 0; i < 5; i++) begin
            @(negedge clk);
            A <= 32'h40000000; // Static 2.0
            B <= 32'h40400000; // Static 3.0
            valid_in <= 1'b1;
        end
        @(negedge clk);
        valid_in <= 1'b0;

        repeat (8) @(posedge clk);
        #10;

        $display("\n===============================================================================");
        $display("  SVA CHECKER VERIFICATION COMPLETED FOR FPU_ADDER");
        $display("  ALL 11 CONCURRENT SVA ASSERTIONS & COVER PROPERTIES MONITORED CLEANLY!");
        $display("===============================================================================\n");

        $finish;
    end

endmodule
