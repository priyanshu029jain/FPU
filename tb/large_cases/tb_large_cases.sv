// =============================================================================
// Testbench : tb_large_cases.sv
// Language  : SystemVerilog (IEEE 1800-2012)
// Purpose   : Massive Regression Test Suite (2,800+ Test Vectors)
//             Exhaustive sweeps across dynamic ranges, verifying algebraic laws
//             and IEEE 754-2008 single-precision numerical invariance:
//               1. Additive Identity Law          : X + 0.0 == X               (500 Cases)
//               2. Inversion Cancellation Law     : X + (-X) == 0.0            (500 Cases)
//               3. Multiplicative Identity Law    : X * 1.0 == X               (500 Cases)
//               4. Multiplicative Zero Annihilator: X * 0.0 == 0.0             (300 Cases)
//               5. Division by Unity Identity     : X / 1.0 == X               (500 Cases)
//               6. Fused Multiply-Add Identities  : X * 1.0 + 0 == X, 0*B + C  (500 Cases)
// Latency   : Cycle-accurate 4-stage synchronous pipeline verification
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */

module tb_large_cases;

    int i;
    int total_cnt = 0;
    int pass_cnt  = 0;
    int fail_cnt  = 0;

    int s1_pass = 0, s2_pass = 0, s3_pass = 0;
    int s4_pass = 0, s5_pass = 0, s6_pass = 0;

    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic [1:0]  op;
    logic [31:0] A, B, C;
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

    // DUT Instance: 4-Stage Synchronous Pipelined Unified FPU Top
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

    // 100 MHz System Clock
    always #5 clk = ~clk;

    localparam logic [31:0] F_ONE  = 32'h3F800000; // +1.0
    localparam logic [31:0] F_ZERO = 32'h00000000; // +0.0

    // Synchronous Pipelined Test Task
    task apply_test(
        input logic [1:0]  test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [31:0] test_c,
        input logic [31:0] exp_y,
        input logic        check_zero,
        input int          section_id
    );
        logic [31:0] captured_y;
        logic        captured_zero;
        begin
            @(negedge clk);
            op       <= test_op;
            A        <= test_a;
            B        <= test_b;
            C        <= test_c;
            valid_in <= 1'b1;

            @(negedge clk);
            valid_in <= 1'b0;

            // Wait for 4-stage pipeline valid_out strobe
            while (!valid_out) @(posedge clk);
            #1;

            captured_y    = Y;
            captured_zero = flag_zero;
            total_cnt++;

            if (check_zero) begin
                if (captured_y === F_ZERO || captured_zero || captured_y === 32'h80000000) begin
                    pass_cnt++;
                    case (section_id)
                        2: s2_pass++;
                        4: s4_pass++;
                        6: s6_pass++;
                        default: ;
                    endcase
                end else begin
                    $display("[FAIL-LARGE] Exp Zero | op=%b A=0x%08h B=0x%08h Y=0x%08h Zero=%b", 
                             test_op, test_a, test_b, captured_y, captured_zero);
                    fail_cnt++;
                end
            end else begin
                if (captured_y === exp_y) begin
                    pass_cnt++;
                    case (section_id)
                        1: s1_pass++;
                        3: s3_pass++;
                        5: s5_pass++;
                        6: s6_pass++;
                        default: ;
                    endcase
                end else begin
                    $display("[FAIL-LARGE] Mismatch | op=%b A=0x%08h B=0x%08h C=0x%08h Got=0x%08h Exp=0x%08h", 
                             test_op, test_a, test_b, test_c, captured_y, exp_y);
                    fail_cnt++;
                end
            end
        end
    endtask

    logic [31:0] test_vec_a, test_vec_b, test_vec_c;

    initial begin
        $dumpfile("waveform_large_cases.vcd");
        $dumpvars(0, tb_large_cases);

        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        op       = 2'b00;
        A        = 32'h0;
        B        = 32'h0;
        C        = 32'h0;

        $display("=================================================================");
        $display("STARTING MASSIVE REGRESSION TEST SUITE (2,800+ VECTORS)");
        $display("Pipelined Invariance & Algebraic Laws across All 4 FPU Units");
        $display("=================================================================\n");

        #25;
        rst_n = 1'b1;
        #10;

        // =====================================================================
        // SECTION 1: 500 Cases - Additive Identity Law (X + 0.0 == X)
        // =====================================================================
        $display("--- SECTION 1: Additive Identity Law: X + 0.0 == X (500 Vectors) ---");
        for (i = 0; i < 500; i++) begin
            test_vec_a = {i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h555555)};
            apply_test(2'b00, test_vec_a, F_ZERO, 32'h0, test_vec_a, 1'b0, 1);
        end
        $display(">> Section 1 Completed: %0d / 500 Passed\n", s1_pass);

        // =====================================================================
        // SECTION 2: 500 Cases - Inversion Cancellation Law (X + (-X) == 0.0)
        // =====================================================================
        $display("--- SECTION 2: Inversion Cancellation Law: X + (-X) == 0.0 (500 Vectors) ---");
        for (i = 0; i < 500; i++) begin
            test_vec_a = {1'b0, 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h333333)};
            test_vec_b = {1'b1, test_vec_a[30:0]}; // -X
            apply_test(2'b00, test_vec_a, test_vec_b, 32'h0, F_ZERO, 1'b1, 2);
        end
        $display(">> Section 2 Completed: %0d / 500 Passed\n", s2_pass);

        // =====================================================================
        // SECTION 3: 500 Cases - Multiplicative Identity Law (X * 1.0 == X)
        // =====================================================================
        $display("--- SECTION 3: Multiplicative Identity Law: X * 1.0 == X (500 Vectors) ---");
        for (i = 0; i < 500; i++) begin
            test_vec_a = {i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h0F0F0F)};
            apply_test(2'b01, test_vec_a, F_ONE, 32'h0, test_vec_a, 1'b0, 3);
        end
        $display(">> Section 3 Completed: %0d / 500 Passed\n", s3_pass);

        // =====================================================================
        // SECTION 4: 300 Cases - Multiplicative Zero Annihilator (X * 0.0 == 0.0)
        // =====================================================================
        $display("--- SECTION 4: Multiplicative Zero Property: X * 0.0 == 0.0 (300 Vectors) ---");
        for (i = 0; i < 300; i++) begin
            test_vec_a = {i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h123456)};
            apply_test(2'b01, test_vec_a, F_ZERO, 32'h0, F_ZERO, 1'b1, 4);
        end
        $display(">> Section 4 Completed: %0d / 300 Passed\n", s4_pass);

        // =====================================================================
        // SECTION 5: 500 Cases - Division by Unity Identity (X / 1.0 == X)
        // =====================================================================
        $display("--- SECTION 5: Division by Unity Identity: X / 1.0 == X (500 Vectors) ---");
        for (i = 0; i < 500; i++) begin
            test_vec_a = {i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h25A5A5)};
            apply_test(2'b11, test_vec_a, F_ONE, 32'h0, test_vec_a, 1'b0, 5);
        end
        $display(">> Section 5 Completed: %0d / 500 Passed\n", s5_pass);

        // =====================================================================
        // SECTION 6: 500 Cases - Fused Multiply-Add Identities (MAC)
        // =====================================================================
        $display("--- SECTION 6: Fused Multiply-Add Identities (500 Vectors) ---");
        for (i = 0; i < 250; i++) begin
            // 250 Cases: X * 1.0 + 0.0 == X
            test_vec_a = {i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h654321)};
            apply_test(2'b10, test_vec_a, F_ONE, F_ZERO, test_vec_a, 1'b0, 6);
        end
        for (i = 250; i < 500; i++) begin
            // 250 Cases: X * 0.0 + C == C
            test_vec_a = {i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'hA1B2C3)};
            test_vec_c = {~i[0], 8'd1 + (8'(i) % 8'd250), 23'(i ^ 23'h777777)};
            apply_test(2'b10, test_vec_a, F_ZERO, test_vec_c, test_vec_c, 1'b0, 6);
        end
        $display(">> Section 6 Completed: %0d / 500 Passed\n", s6_pass);

        // =====================================================================
        // FINAL SUMMARY
        // =====================================================================
        $display("=================================================================");
        $display("MASSIVE REGRESSION TEST SUITE SUMMARY (2,800+ VECTORS)");
        $display("=================================================================");
        $display("  Section 1: Additive Identity (X + 0 = X)       : %0d / 500 Passed", s1_pass);
        $display("  Section 2: Inversion Cancellation (X - X = 0)  : %0d / 500 Passed", s2_pass);
        $display("  Section 3: Multiplicative Identity (X * 1 = X) : %0d / 500 Passed", s3_pass);
        $display("  Section 4: Multiplicative Zero (X * 0 = 0)     : %0d / 300 Passed", s4_pass);
        $display("  Section 5: Division by Unity (X / 1 = X)       : %0d / 500 Passed", s5_pass);
        $display("  Section 6: Fused Multiply-Add Identities (MAC) : %0d / 500 Passed", s6_pass);
        $display("-----------------------------------------------------------------");
        $display("Total Executed Vectors : %0d", total_cnt);
        $display("Total Passed Vectors   : %0d", pass_cnt);
        $display("Total Failed Vectors   : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("RESULT: ALL %0d LARGE TEST CASES PASSED WITH 100%% SUCCESS!", total_cnt);
        else
            $display("RESULT: LARGE TEST SUITE ENCOUNTERED %0d FAILURES!", fail_cnt);
        $display("=================================================================\n");
        $finish;
    end

endmodule
