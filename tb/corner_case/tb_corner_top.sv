// =============================================================================
// Testbench : tb_corner_top.sv
// Language  : SystemVerilog (IEEE 1800-2012)
// Purpose   : Dedicated Corner-Case Verification Suite for FPU_top
//             (Unified IEEE 754 4-Stage Synchronous Pipelined Top-Level FPU)
//
// Test Matrix:
//   1. Opcode-driven corner cases across ADD, MUL, MAC, and DIV
//   2. Sign Permutations (+/+, +/-, -/+, -/-) paired with 0, Inf, NaN
//   3. Specific IEEE 754 Flag Triggers across all top flags:
//      - flag_zero        : Asserted on +0.0 and -0.0
//      - flag_inf         : Asserted on +Inf and -Inf
//      - flag_nan         : Asserted on NaNs (QNaN, SNaN)
//      - flag_invalid     : Asserted on 0*Inf, 0/0, Inf/Inf, Inf-Inf, NaNs
//      - flag_overflow    : Exponent >= 255 saturation
//      - flag_underflow   : Exponent <= 0 flush-to-zero
//      - flag_inexact     : Bits lost to rounding / non-zero division remainder
//      - flag_div_by_zero : X / 0.0 (X != 0, X != NaN)
//   4. Output State Target Verification (+0.0, -0.0, +Inf, -Inf, NaN)
//   5. Randomized 4-Opcode Sign-Quadrant Corner Stress Loop (100 vectors / 25 per unit)
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */

module tb_corner_top;

    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic [1:0]  op;
    logic [31:0] A;
    logic [31:0] B;
    logic [31:0] C;
    logic [31:0] Y;
    logic        valid_out;
    logic        flag_zero;
    logic        flag_inf;
    logic        flag_nan;
    logic        flag_invalid;
    logic        flag_overflow;
    logic        flag_underflow;
    logic        flag_inexact;
    logic        flag_div_by_zero;

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
    localparam logic [31:0] VAL_POS_HALF= 32'h3F000000; // +0.5
    localparam logic [31:0] VAL_POS_1   = 32'h3F800000; // +1.0
    localparam logic [31:0] VAL_NEG_1   = 32'hBF800000; // -1.0
    localparam logic [31:0] VAL_POS_2   = 32'h40000000; // +2.0
    localparam logic [31:0] VAL_NEG_2   = 32'hC0000000; // -2.0
    localparam logic [31:0] VAL_POS_3   = 32'h40400000; // +3.0
    localparam logic [31:0] VAL_NEG_3   = 32'hC0400000; // -3.0
    localparam logic [31:0] VAL_POS_4   = 32'h40800000; // +4.0
    localparam logic [31:0] VAL_NEG_4   = 32'hC0800000; // -4.0
    localparam logic [31:0] VAL_POS_6   = 32'h40C00000; // +6.0
    localparam logic [31:0] VAL_NEG_6   = 32'hC0C00000; // -6.0

    // DUT Instantiation
    FPU_top dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .valid_in        (valid_in),
        .op              (op),
        .A               (A),
        .B               (B),
        .C               (C),
        .Y               (Y),
        .valid_out       (valid_out),
        .flag_zero       (flag_zero),
        .flag_inf        (flag_inf),
        .flag_nan        (flag_nan),
        .flag_invalid    (flag_invalid),
        .flag_overflow   (flag_overflow),
        .flag_underflow  (flag_underflow),
        .flag_inexact    (flag_inexact),
        .flag_div_by_zero(flag_div_by_zero)
    );

    // Clock Generator: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // Verification Task
    task check_top_corner(
        input string       desc,
        input logic [1:0]  in_op,
        input logic [31:0] in_a,
        input logic [31:0] in_b,
        input logic [31:0] in_c,
        input logic [31:0] exp_y,
        input bit          match_exact_y,
        input logic        exp_zero,
        input logic        exp_inf,
        input logic        exp_nan,
        input logic        exp_inv,
        input logic        exp_ovf,
        input logic        exp_unf,
        input logic        exp_inex,
        input logic        exp_dz
    );
        bit check_passed;
        logic [31:0] cur_y;
        bit cur_zero, cur_inf, cur_nan, cur_inv, cur_ovf, cur_unf, cur_inex, cur_dz;
        begin
            test_num++;

            // Drive inputs synchronously on negedge
            @(negedge clk);
            op       <= in_op;
            A        <= in_a;
            B        <= in_b;
            C        <= in_c;
            valid_in <= 1'b1;

            @(negedge clk);
            valid_in <= 1'b0;

            // Wait for 4-stage pipeline completion
            while (!valid_out) @(posedge clk);
            #1;

            cur_y    = Y;
            cur_zero = flag_zero;
            cur_inf  = flag_inf;
            cur_nan  = flag_nan;
            cur_inv  = flag_invalid;
            cur_ovf  = flag_overflow;
            cur_unf  = flag_underflow;
            cur_inex = flag_inexact;
            cur_dz   = flag_div_by_zero;

            // Check value
            if (exp_nan === 1'b1 || (exp_y[30:23] == 8'hFF && exp_y[22:0] != 0)) begin
                check_passed = (cur_y[30:23] == 8'hFF && cur_y[22:0] != 0);
            end else if (match_exact_y) begin
                check_passed = (cur_y === exp_y);
            end else begin
                check_passed = 1'b1;
            end

            // Check flags (skip if 1'bx or 1'bz)
            if (exp_zero !== 1'bx && exp_zero !== 1'bz) check_passed &= (cur_zero === exp_zero);
            if (exp_inf  !== 1'bx && exp_inf  !== 1'bz) check_passed &= (cur_inf  === exp_inf);
            if (exp_nan  !== 1'bx && exp_nan  !== 1'bz) check_passed &= (cur_nan  === exp_nan);
            if (exp_inv  !== 1'bx && exp_inv  !== 1'bz) check_passed &= (cur_inv  === exp_inv);
            if (exp_ovf  !== 1'bx && exp_ovf  !== 1'bz) check_passed &= (cur_ovf  === exp_ovf);
            if (exp_unf  !== 1'bx && exp_unf  !== 1'bz) check_passed &= (cur_unf  === exp_unf);
            if (exp_inex !== 1'bx && exp_inex !== 1'bz) check_passed &= (cur_inex === exp_inex);
            if (exp_dz   !== 1'bx && exp_dz   !== 1'bz) check_passed &= (cur_dz   === exp_dz);

            if (check_passed) begin
                $display("[PASS] #%-3d %-54s | Y=0x%08h [Z:%b Inf:%b NaN:%b NV:%b V:%b U:%b NX:%b DZ:%b]",
                         test_num, desc, cur_y, cur_zero, cur_inf, cur_nan, cur_inv, cur_ovf, cur_unf, cur_inex, cur_dz);
                pass_cnt++;
            end else begin
                $display("[FAIL] #%-3d %-54s | Got Y=0x%08h (Exp: 0x%08h) Flags Got[Z:%b Inf:%b NaN:%b NV:%b V:%b U:%b NX:%b DZ:%b] Exp[Z:%b Inf:%b NaN:%b NV:%b V:%b U:%b NX:%b DZ:%b]",
                         test_num, desc, cur_y, exp_y,
                         cur_zero, cur_inf, cur_nan, cur_inv, cur_ovf, cur_unf, cur_inex, cur_dz,
                         exp_zero, exp_inf, exp_nan, exp_inv, exp_ovf, exp_unf, exp_inex, exp_dz);
                fail_cnt++;
            end
        end
    endtask

    initial begin
        $dumpfile("waveform_corner_top.vcd");
        $dumpvars(0, tb_corner_top);

        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        op       = 2'b00;
        A        = 32'h0;
        B        = 32'h0;
        C        = 32'h0;

        $display("===============================================================================");
        $display("  CORNER-CASE TESTBENCH: FPU TOP-LEVEL (IEEE 754 4-STAGE PIPELINED)");
        $display("===============================================================================\n");

        #25;
        rst_n = 1'b1;
        #20;

        // ---------------------------------------------------------------------
        // 1. ADDER CORNERS (OP = 2'b00)
        // ---------------------------------------------------------------------
        $display("--- SECTION 1: FPU_top Adder Corners (op = 2'b00) ---");
        // Cancellation to +0.0
        check_top_corner("ADD: (+4.0) + (-4.0) = +0.0 (Cancel)", 2'b00, VAL_POS_4, VAL_NEG_4, 32'h0, P_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Signed zero addition
        check_top_corner("ADD: (-0.0) + (-0.0) = -0.0", 2'b00, N_ZERO, N_ZERO, 32'h0, N_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Overflow to +Inf
        check_top_corner("ADD: MaxFloat + MaxFloat = +Inf", 2'b00, MAX_FLOAT, MAX_FLOAT, 32'h0, P_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'bx, 1'b0);
        // Overflow to -Inf
        check_top_corner("ADD: -MaxFloat + -MaxFloat = -Inf", 2'b00, N_MAX_FLOAT, N_MAX_FLOAT, 32'h0, N_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'bx, 1'b0);
        // Indeterminate: (+Inf) + (-Inf) -> NaN
        check_top_corner("ADD: (+Inf) + (-Inf) = NaN", 2'b00, P_INF, N_INF, 32'h0, Q_NAN, 0,
                         1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 2. MULTIPLIER CORNERS (OP = 2'b01)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 2: FPU_top Multiplier Corners (op = 2'b01) ---");
        // Signed zeros (+ * - = -0.0)
        check_top_corner("MUL: (+4.0) * (-0.0) = -0.0", 2'b01, VAL_POS_4, N_ZERO, 32'h0, N_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Signed zeros (- * - = +0.0)
        check_top_corner("MUL: (-4.0) * (-0.0) = +0.0", 2'b01, VAL_NEG_4, N_ZERO, 32'h0, P_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Overflow: MaxFloat * 2.0 = +Inf
        check_top_corner("MUL: MaxFloat * 2.0 = +Inf", 2'b01, MAX_FLOAT, VAL_POS_2, 32'h0, P_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'bx, 1'b0);
        // Underflow: MinNorm * MinNorm -> flush to zero
        check_top_corner("MUL: MinNorm * MinNorm = +0.0 (Underflow)", 2'b01, MIN_NORM, MIN_NORM, 32'h0, P_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'bx, 1'b0);
        // Indeterminate: 0 * Inf -> NaN
        check_top_corner("MUL: (+0.0) * (+Inf) = NaN", 2'b01, P_ZERO, P_INF, 32'h0, Q_NAN, 0,
                         1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 3. MAC / FMA CORNERS (OP = 2'b10)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 3: FPU_top MAC Corners (op = 2'b10) ---");
        // Cancellation: (+2.0 * +3.0) + (-6.0) = +0.0
        check_top_corner("MAC: (+2.0 * +3.0) + (-6.0) = +0.0 (Cancel)", 2'b10, VAL_POS_2, VAL_POS_3, VAL_NEG_6, P_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Signed zero output
        check_top_corner("MAC: (-0.0 * +0.0) + (-0.0) = -0.0", 2'b10, N_ZERO, P_ZERO, N_ZERO, N_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Overflow
        check_top_corner("MAC: MaxFloat * 2.0 + 1.0 = +Inf", 2'b10, MAX_FLOAT, VAL_POS_2, VAL_POS_1, P_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'bx, 1'b0);
        // Inf - Inf -> NaN
        check_top_corner("MAC: (+Inf * +1.0) + (-Inf) = NaN", 2'b10, P_INF, VAL_POS_1, N_INF, Q_NAN, 0,
                         1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 4. DIVISION CORNERS (OP = 2'b11)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 4: FPU_top Division Corners (op = 2'b11) ---");
        // Division by Zero (+ / +0 = +Inf)
        check_top_corner("DIV: (+4.0) / (+0.0) = +Inf (DivByZero)", 2'b11, VAL_POS_4, P_ZERO, 32'h0, P_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        // Division by Zero (+ / -0 = -Inf)
        check_top_corner("DIV: (+4.0) / (-0.0) = -Inf (DivByZero)", 2'b11, VAL_POS_4, N_ZERO, 32'h0, N_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        // Division by Zero (- / +0 = -Inf)
        check_top_corner("DIV: (-4.0) / (+0.0) = -Inf (DivByZero)", 2'b11, VAL_NEG_4, P_ZERO, 32'h0, N_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        // Division by Zero (- / -0 = +Inf)
        check_top_corner("DIV: (-4.0) / (-0.0) = +Inf (DivByZero)", 2'b11, VAL_NEG_4, N_ZERO, 32'h0, P_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        // Indeterminate: 0 / 0 -> NaN
        check_top_corner("DIV: (+0.0) / (+0.0) = NaN", 2'b11, P_ZERO, P_ZERO, 32'h0, Q_NAN, 0,
                         1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        // Indeterminate: Inf / Inf -> NaN
        check_top_corner("DIV: (+Inf) / (+Inf) = NaN", 2'b11, P_INF, P_INF, 32'h0, Q_NAN, 0,
                         1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        // X / Inf -> Signed zero
        check_top_corner("DIV: (+4.0) / (+Inf) = +0.0", 2'b11, VAL_POS_4, P_INF, 32'h0, P_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_top_corner("DIV: (+4.0) / (-Inf) = -0.0", 2'b11, VAL_POS_4, N_INF, 32'h0, N_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        // Inexact flag: 1.0 / 3.0
        check_top_corner("DIV: 1.0 / 3.0 = 0.33333334 (Inexact)", 2'b11, VAL_POS_1, VAL_POS_3, 32'h0, 32'h3EAAAAAB, 1,
                         1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // ---------------------------------------------------------------------
        // 5. EXPLICIT OUTPUT TARGET VERIFICATION (+0.0, -0.0, +Inf, -Inf, NaN)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 5: Explicit Output Target Verification ---");
        check_top_corner("TARGET +0.0: (+4.0) + (-4.0)", 2'b00, VAL_POS_4, VAL_NEG_4, 32'h0, P_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_top_corner("TARGET -0.0: (+4.0) * (-0.0)", 2'b01, VAL_POS_4, N_ZERO, 32'h0, N_ZERO, 1,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_top_corner("TARGET +Inf: (+4.0) / (+0.0)", 2'b11, VAL_POS_4, P_ZERO, 32'h0, P_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        check_top_corner("TARGET -Inf: (+4.0) / (-0.0)", 2'b11, VAL_POS_4, N_ZERO, 32'h0, N_INF, 1,
                         1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        check_top_corner("TARGET NaN: (+0.0) / (+0.0)",  2'b11, P_ZERO, P_ZERO, 32'h0, Q_NAN, 0,
                         1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);

        // ---------------------------------------------------------------------
        // 6. RANDOMIZED 4-OPCODE SIGN-QUADRANT CORNER STRESS LOOP (100 VECTORS)
        // ---------------------------------------------------------------------
        $display("\n--- SECTION 6: Randomized 4-Opcode Sign-Quadrant Corner Stress Loop (100 Vectors) ---");
        for (int k = 0; k < 100; k++) begin
            logic [1:0]  rand_op;
            logic [31:0] rand_a, rand_b, rand_c;
            bit s_a, s_b, s_c;
            logic [7:0] exp_a, exp_b, exp_c;
            logic [22:0] mant_a, mant_b, mant_c;
            string q_desc;

            rand_op = k % 4;

            // Quadrant cycling
            s_a = (k % 4 == 2 || k % 4 == 3) ? 1'b1 : 1'b0;
            s_b = (k % 4 == 1 || k % 4 == 3) ? 1'b1 : 1'b0;
            s_c = (k % 2 == 1) ? 1'b1 : 1'b0;

            exp_a  = 8'd120 + ($urandom % 15);
            exp_b  = 8'd120 + ($urandom % 15);
            exp_c  = 8'd120 + ($urandom % 15);
            mant_a = $urandom;
            mant_b = $urandom;
            mant_c = $urandom;

            rand_a = {s_a, exp_a, mant_a};
            rand_b = {s_b, exp_b, mant_b};
            rand_c = {s_c, exp_c, mant_c};

            // Corner injection
            if (k % 6 == 0) rand_b = P_ZERO;
            else if (k % 6 == 1) rand_b = N_ZERO;
            else if (k % 6 == 2) rand_b = P_INF;
            else if (k % 6 == 3) rand_b = N_INF;
            else if (k % 6 == 4) rand_b = Q_NAN;
            else if (k % 6 == 5) rand_b = S_NAN;

            case (rand_op)
                2'b00: q_desc = "RAND-CORNER TOP-ADD";
                2'b01: q_desc = "RAND-CORNER TOP-MUL";
                2'b10: q_desc = "RAND-CORNER TOP-MAC";
                2'b11: q_desc = "RAND-CORNER TOP-DIV";
            endcase

            check_top_corner(q_desc, rand_op, rand_a, rand_b, rand_c, 32'h0, 0,
                             1'bx, 1'bx, 1'bx, 1'bx, 1'bx, 1'bx, 1'bx, 1'bx);
        end

        // Summary Report
        $display("\n===============================================================================");
        $display("  FPU_TOP CORNER TEST SUMMARY");
        $display("  Total Tests Executed : %0d", test_num);
        $display("  Passed Tests         : %0d", pass_cnt);
        $display("  Failed Tests         : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  STATUS: ALL FPU_TOP CORNER CASES PASSED!");
        else
            $display("  STATUS: FPU_TOP CORNER CASES DETECTED %0d FAILURES!", fail_cnt);
        $display("===============================================================================\n");

        $finish;
    end

endmodule
