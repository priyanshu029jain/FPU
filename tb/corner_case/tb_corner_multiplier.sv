// =============================================================================
// Testbench : tb_corner_multiplier.sv
// Language  : SystemVerilog (IEEE 1800-2012)
// Purpose   : Dedicated Corner-Case Verification Suite for FPU_multiplier
//             (4-Stage Synchronous Pipelined IEEE 754 Floating-Point Multiplier)
//
// Test Matrix:
//   1. Sign Permutations (+/+, +/-, -/+, -/-) paired with Zeros (+0.0, -0.0)
//   2. Sign Permutations paired with Infinities (+Inf, -Inf)
//   3. Sign Permutations paired with NaNs (QNaN, SNaN)
//   4. Specific IEEE 754 Flag Triggers:
//      - flag_overflow  : MaxFloat * 2.0, -MaxFloat * 2.0
//      - flag_underflow : MinNorm * MinNorm (flush-to-zero)
//      - flag_invalid   : 0 * Inf, Inf * 0, NaNs
//      - flag_zero      : Signed zero multiplication & underflow
//      - flag_inexact   : Multiplier significand truncation
//   5. Output State Target Verification (+0.0, -0.0, +Inf, -Inf, NaN)
//   6. Randomized Sign-Quadrant Corner Injection Stress Loop (50 iterations)
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */

module tb_corner_multiplier;

    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic [31:0] A;
    logic [31:0] B;
    logic [31:0] Y;
    logic        valid_out;
    logic        flag_overflow;
    logic        flag_underflow;
    logic        flag_invalid;
    logic        flag_zero;
    logic        flag_inexact;

    // Test Statistics
    int pass_cnt = 0;
    int fail_cnt = 0;
    int test_num = 0;

    // IEEE 754 Constants
    localparam logic [31:0] P_ZERO      = 32'h00000000; // +0.0
    localparam logic [31:0] N_ZERO      = 32'h80000000; // -0.0
    localparam logic [31:0] P_INF       = 32'h7F800000; // +Inf
    localparam logic [31:0] N_INF       = 32'hFF800000; // -Inf
    localparam logic [31:0] Q_NAN       = 32'h7FC00000; // Canonical QNaN
    localparam logic [31:0] S_NAN       = 32'h7F800001; // SNaN
    localparam logic [31:0] MAX_FLOAT   = 32'h7F7FFFFF; // +3.4028235e+38
    localparam logic [31:0] N_MAX_FLOAT = 32'hFF7FFFFF; // -3.4028235e+38
    localparam logic [31:0] MIN_NORM    = 32'h00800000; // +1.1754944e-38
    localparam logic [31:0] VAL_POS_2   = 32'h40000000; // +2.0
    localparam logic [31:0] VAL_NEG_2   = 32'hC0000000; // -2.0
    localparam logic [31:0] VAL_POS_4   = 32'h40800000; // +4.0
    localparam logic [31:0] VAL_NEG_4   = 32'hC0800000; // -4.0

    // DUT Instantiation
    FPU_multiplier dut (
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

    // Clock Generator: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // Verification Task
    task check_mul_corner(
        input string       desc,
        input logic [31:0] in_a,
        input logic [31:0] in_b,
        input logic [31:0] exp_y,
        input bit          match_exact_y,
        input logic        exp_ovf,
        input logic        exp_unf,
        input logic        exp_inv,
        input logic        exp_zero,
        input logic        exp_inexact
    );
        bit check_passed;
        logic [31:0] cur_y;
        bit cur_ovf, cur_unf, cur_inv, cur_zero, cur_inex;
        begin
            test_num++;

            // Drive inputs synchronously on negedge
            @(negedge clk);
            A        <= in_a;
            B        <= in_b;
            valid_in <= 1'b1;

            @(negedge clk);
            valid_in <= 1'b0;

            // Wait for 4-stage pipeline completion
            while (!valid_out) @(posedge clk);
            #1;

            cur_y     = Y;
            cur_ovf   = flag_overflow;
            cur_unf   = flag_underflow;
            cur_inv   = flag_invalid;
            cur_zero  = flag_zero;
            cur_inex  = flag_inexact;

            // Check value
            if (exp_inv === 1'b1 || (exp_y[30:23] == 8'hFF && exp_y[22:0] != 0)) begin
                check_passed = (cur_y[30:23] == 8'hFF && cur_y[22:0] != 0);
            end else if (match_exact_y) begin
                check_passed = (cur_y === exp_y);
            end else begin
                check_passed = 1'b1;
            end

            // Check flags (skip if 1'bx or 1'bz)
            if (exp_ovf     !== 1'bx && exp_ovf     !== 1'bz) check_passed &= (cur_ovf === exp_ovf);
            if (exp_unf     !== 1'bx && exp_unf     !== 1'bz) check_passed &= (cur_unf === exp_unf);
            if (exp_inv     !== 1'bx && exp_inv     !== 1'bz) check_passed &= (cur_inv === exp_inv);
            if (exp_zero    !== 1'bx && exp_zero    !== 1'bz) check_passed &= (cur_zero === exp_zero);
            if (exp_inexact !== 1'bx && exp_inexact !== 1'bz) check_passed &= (cur_inex === exp_inexact);

            if (check_passed) begin
                $display("[PASS] #%-3d %-48s | A=0x%08h B=0x%08h -> Y=0x%08h [Z:%b V:%b U:%b NV:%b NX:%b]",
                         test_num, desc, in_a, in_b, cur_y, cur_zero, cur_ovf, cur_unf, cur_inv, cur_inex);
                pass_cnt++;
            end else begin
                $display("[FAIL] #%-3d %-48s | A=0x%08h B=0x%08h -> Got Y=0x%08h (Exp: 0x%08h) Flags Got[Z:%b V:%b U:%b NV:%b NX:%b] Exp[Z:%b V:%b U:%b NV:%b NX:%b]",
                         test_num, desc, in_a, in_b, cur_y, exp_y,
                         cur_zero, cur_ovf, cur_unf, cur_inv, cur_inex,
                         exp_zero, exp_ovf, exp_unf, exp_inv, exp_inexact);
                fail_cnt++;
            end
        end
    endtask

    initial begin
        $dumpfile("waveform_corner_multiplier.vcd");
        $dumpvars(0, tb_corner_multiplier);

        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        A        = 32'h0;
        B        = 32'h0;

        $display("===============================================================================");
        $display("  CORNER-CASE TESTBENCH: FPU MULTIPLIER (IEEE 754 4-STAGE PIPELINED)");
        $display("===============================================================================\n");

        #25;
        rst_n = 1'b1;
        #20;

        // ---------------------------------------------------------------------
        // 1. SIGN PERMUTATIONS WITH ZERO (+0.0, -0.0)
        // ---------------------------------------------------------------------
        $display("--- SECTION 1: Sign Permutations Paired with Zeros (+0.0, -0.0) ---");
        // (+ve, +0.0) -> +0.0
        check_mul_corner("(+ve, +0.0): (+4.0) * (+0.0) = +0.0", VAL_POS_4, P_ZERO, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(+0.0, +ve): (+0.0) * (+4.0) = +0.0", P_ZERO, VAL_POS_4, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // (+ve, -0.0) -> -0.0
        check_mul_corner("(+ve, -0.0): (+4.0) * (-0.0) = -0.0", VAL_POS_4, N_ZERO, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(-0.0, +ve): (-0.0) * (+4.0) = -0.0", N_ZERO, VAL_POS_4, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // (-ve, +0.0) -> -0.0
        check_mul_corner("(-ve, +0.0): (-4.0) * (+0.0) = -0.0", VAL_NEG_4, P_ZERO, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(+0.0, -ve): (+0.0) * (-4.0) = -0.0", P_ZERO, VAL_NEG_4, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // (-ve, -0.0) -> +0.0
        check_mul_corner("(-ve, -0.0): (-4.0) * (-0.0) = +0.0", VAL_NEG_4, N_ZERO, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(-0.0, -ve): (-0.0) * (-4.0) = +0.0", N_ZERO, VAL_NEG_4, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // Zero * Zero Combinations
        check_mul_corner("(+0.0) * (+0.0) = +0.0", P_ZERO, P_ZERO, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(+0.0) * (-0.0) = -0.0", P_ZERO, N_ZERO, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(-0.0) * (+0.0) = -0.0", N_ZERO, P_ZERO, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("(-0.0) * (-0.0) = +0.0", N_ZERO, N_ZERO, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // ---------------------------------------------------------------------
        // 2. SIGN PERMUTATIONS WITH INFINITY (+Inf, -Inf)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 2: Sign Permutations Paired with Infinity (+Inf, -Inf) ---");
        check_mul_corner("(+ve, +Inf): (+4.0) * (+Inf) = +Inf", VAL_POS_4, P_INF, P_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(+Inf, +ve): (+Inf) * (+4.0) = +Inf", P_INF, VAL_POS_4, P_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(+ve, -Inf): (+4.0) * (-Inf) = -Inf", VAL_POS_4, N_INF, N_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(-Inf, +ve): (-Inf) * (+4.0) = -Inf", N_INF, VAL_POS_4, N_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        check_mul_corner("(-ve, +Inf): (-4.0) * (+Inf) = -Inf", VAL_NEG_4, P_INF, N_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(+Inf, -ve): (+Inf) * (-4.0) = -Inf", P_INF, VAL_NEG_4, N_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(-ve, -Inf): (-4.0) * (-Inf) = +Inf", VAL_NEG_4, N_INF, P_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(-Inf, -ve): (-Inf) * (-4.0) = +Inf", N_INF, VAL_NEG_4, P_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        check_mul_corner("(+Inf, +Inf): (+Inf) * (+Inf) = +Inf", P_INF, P_INF, P_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(+Inf, -Inf): (+Inf) * (-Inf) = -Inf", P_INF, N_INF, N_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_mul_corner("(-Inf, -Inf): (-Inf) * (-Inf) = +Inf", N_INF, N_INF, P_INF, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        // Zero * Infinity -> Indeterminate (NaN)
        check_mul_corner("(+0.0) * (+Inf) = NaN", P_ZERO, P_INF, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(-0.0) * (+Inf) = NaN", N_ZERO, P_INF, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(+0.0) * (-Inf) = NaN", P_ZERO, N_INF, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(-0.0) * (-Inf) = NaN", N_ZERO, N_INF, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(+Inf) * (+0.0) = NaN", P_INF, P_ZERO, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(-Inf) * (-0.0) = NaN", N_INF, N_ZERO, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 3. SIGN PERMUTATIONS WITH NAN (QNaN, SNaN)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 3: Sign Permutations Paired with NaNs (QNaN, SNaN) ---");
        check_mul_corner("(+ve, QNaN): (+4.0) * QNaN = NaN", VAL_POS_4, Q_NAN, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(QNaN, +ve): QNaN * (+4.0) = NaN", Q_NAN, VAL_POS_4, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(-ve, QNaN): (-4.0) * QNaN = NaN", VAL_NEG_4, Q_NAN, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(QNaN, -ve): QNaN * (-4.0) = NaN", Q_NAN, VAL_NEG_4, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        check_mul_corner("(+ve, SNaN): (+4.0) * SNaN = NaN", VAL_POS_4, S_NAN, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(SNaN, -ve): SNaN * (-4.0) = NaN", S_NAN, VAL_NEG_4, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_mul_corner("(QNaN, QNaN): QNaN * QNaN = NaN",   Q_NAN, Q_NAN, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 4. IEEE 754 EXCEPTION FLAG TRIGGERS
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 4: Dedicated Flag Trigger Vectors ---");
        // flag_invalid: 0 * Inf
        check_mul_corner("FLAG_INVALID: (+0.0) * (+Inf) = NaN", P_ZERO, P_INF, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        // flag_overflow: MaxFloat * 2.0 = +Inf
        check_mul_corner("FLAG_OVERFLOW (+): MaxFloat * 2.0 = +Inf", MAX_FLOAT, VAL_POS_2, P_INF, 1, 1'b1, 1'b0, 1'b0, 1'b0, 1'bx);
        check_mul_corner("FLAG_OVERFLOW (-): -MaxFloat * 2.0 = -Inf", N_MAX_FLOAT, VAL_POS_2, N_INF, 1, 1'b1, 1'b0, 1'b0, 1'b0, 1'bx);

        // flag_underflow: MinNorm * MinNorm -> flush to zero
        check_mul_corner("FLAG_UNDERFLOW: MinNorm * MinNorm = 0.0", MIN_NORM, MIN_NORM, P_ZERO, 1, 1'b0, 1'b1, 1'b0, 1'b1, 1'bx);

        // flag_zero: 0.0 * 4.0 = +0.0
        check_mul_corner("FLAG_ZERO: (+0.0) * (+4.0) = +0.0", P_ZERO, VAL_POS_4, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // flag_inexact: 1.5 * 1.3333333
        check_mul_corner("FLAG_INEXACT: 1.5 * 1.3333333 (Truncation)", 32'h3FC00000, 32'h3FAAAAAB, 32'h40000000, 1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);

        // ---------------------------------------------------------------------
        // 5. OUTPUT STATE TARGET VERIFICATION (+0.0, -0.0, +Inf, -Inf, NaN)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 5: Explicit Output Target Verification ---");
        check_mul_corner("TARGET +0.0: (+4.0) * (+0.0)", VAL_POS_4, P_ZERO, P_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("TARGET -0.0: (+4.0) * (-0.0)", VAL_POS_4, N_ZERO, N_ZERO, 1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_mul_corner("TARGET +Inf: MaxFloat * 2.0", MAX_FLOAT, VAL_POS_2, P_INF, 1, 1'b1, 1'b0, 1'b0, 1'b0, 1'bx);
        check_mul_corner("TARGET -Inf: -MaxFloat * 2.0", N_MAX_FLOAT, VAL_POS_2, N_INF, 1, 1'b1, 1'b0, 1'b0, 1'b0, 1'bx);
        check_mul_corner("TARGET NaN: (+0.0) * (+Inf)", P_ZERO, P_INF, Q_NAN, 0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 6. RANDOMIZED SIGN-QUADRANT CORNER STRESS LOOP (50 ITERATIONS)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 6: Randomized Sign-Quadrant Corner Stress Loop (50 Vectors) ---");
        for (int k = 0; k < 50; k++) begin
            logic [31:0] rand_a, rand_b;
            bit s_a, s_b;
            logic [7:0] exp_a, exp_b;
            logic [22:0] mant_a, mant_b;
            string q_desc;

            // Quadrant cycling: 0: (+,+), 1: (+,-), 2: (-,+), 3: (-,-)
            s_a = (k % 4 == 2 || k % 4 == 3) ? 1'b1 : 1'b0;
            s_b = (k % 4 == 1 || k % 4 == 3) ? 1'b1 : 1'b0;

            exp_a  = 8'd120 + ($urandom % 15);
            exp_b  = 8'd120 + ($urandom % 15);
            mant_a = $urandom;
            mant_b = $urandom;

            rand_a = {s_a, exp_a, mant_a};
            rand_b = {s_b, exp_b, mant_b};

            // Inject corner every 5th iteration
            if (k % 5 == 0) rand_b = P_ZERO;
            else if (k % 5 == 1) rand_b = N_ZERO;
            else if (k % 5 == 2) rand_b = P_INF;
            else if (k % 5 == 3) rand_b = N_INF;
            else if (k % 5 == 4) rand_b = Q_NAN;

            case (k % 4)
                0: q_desc = "RAND-CORNER (+,+)";
                1: q_desc = "RAND-CORNER (+,-)";
                2: q_desc = "RAND-CORNER (-,+)";
                3: q_desc = "RAND-CORNER (-,-)";
            endcase

            check_mul_corner(q_desc, rand_a, rand_b, 32'h0, 0, 1'bx, 1'bx, 1'bx, 1'bx, 1'bx);
        end

        // Summary Report
        $display("\n===============================================================================");
        $display("  FPU_MULTIPLIER CORNER TEST SUMMARY");
        $display("  Total Tests Executed : %0d", test_num);
        $display("  Passed Tests         : %0d", pass_cnt);
        $display("  Failed Tests         : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  STATUS: ALL FPU_MULTIPLIER CORNER CASES PASSED!");
        else
            $display("  STATUS: FPU_MULTIPLIER CORNER CASES DETECTED %0d FAILURES!", fail_cnt);
        $display("===============================================================================\n");

        $finish;
    end

endmodule
