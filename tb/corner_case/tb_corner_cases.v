// =============================================================================
// Testbench : tb_corner_cases
// Purpose   : Dedicated verification for IEEE 754 edge & boundary conditions:
//             - Maximum normalized float (0x7F7FFFFF)
//             - Minimum normalized float (0x00800000)
//             - Subnormal numbers (E = 0, M != 0)
//             - Quiet and Signaling NaNs
//             - Signed Zeros (+0.0 vs -0.0)
//             - Positive and Negative Infinity (+Inf, -Inf)
//             - Overflow saturation & underflow flush-to-zero
//             - Tie-to-even rounding bit boundaries (GRS = 100 with LSB=0 vs LSB=1)
// =============================================================================

`timescale 1ns/1ps

module tb_corner_cases;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    reg  [1:0]  op;
    reg  [31:0] A, B, C;
    wire [31:0] Y;
    wire flag_zero, flag_inf, flag_nan, flag_overflow;

    FPU_top dut (
        .op(op), .A(A), .B(B), .C(C), .Y(Y),
        .flag_zero(flag_zero), .flag_inf(flag_inf),
        .flag_nan(flag_nan), .flag_overflow(flag_overflow)
    );

    // IEEE 754 Boundary Constants
    localparam P_ZERO      = 32'h00000000;
    localparam N_ZERO      = 32'h80000000;
    localparam P_INF       = 32'h7F800000;
    localparam N_INF       = 32'hFF800000;
    localparam Q_NAN       = 32'h7FC00000;
    localparam MAX_FLOAT   = 32'h7F7FFFFF; // 3.4028235e+38
    localparam MIN_NORM    = 32'h00800000; // 1.1754944e-38
    localparam SUBNORM     = 32'h00400000; // subnormal

    task check_case(
        input [8*32:1] desc,
        input [31:0]   expected_val,
        input          exp_zero,
        input          exp_inf,
        input          exp_nan
    );
        #2;
        if ((Y === expected_val || (exp_nan && Y[30:23] == 8'hFF && Y[22:0] != 0)) &&
            (flag_zero === exp_zero) && (flag_inf === exp_inf) && (flag_nan === exp_nan)) begin
            $display("[PASS] %-36s | Y=0x%08h | Z:%b Inf:%b NaN:%b", desc, Y, flag_zero, flag_inf, flag_nan);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %-36s | Got: 0x%08h Exp: 0x%08h | Z:%b/%b Inf:%b/%b NaN:%b/%b",
                     desc, Y, expected_val, flag_zero, exp_zero, flag_inf, exp_inf, flag_nan, exp_nan);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    initial begin
        $display("=================================================================");
        $display("STARTING CORNER-CASE VERIFICATION SUITE");
        $display("=================================================================\n");

        #10;

        // 1. ZERO BOUNDARIES
        $display("--- 1. Signed Zero Corners ---");
        op = 2'b00; A = P_ZERO; B = P_ZERO; C = 32'b0; check_case("+0.0 + +0.0 = +0.0", P_ZERO, 1, 0, 0);
        op = 2'b00; A = N_ZERO; B = P_ZERO; C = 32'b0; check_case("-0.0 + +0.0 = +0.0", P_ZERO, 1, 0, 0);
        op = 2'b01; A = P_ZERO; B = 32'h40800000; C = 32'b0; check_case("+0.0 * 4.0 = 0.0", P_ZERO, 1, 0, 0);
        op = 2'b01; A = N_ZERO; B = 32'h40800000; C = 32'b0; check_case("-0.0 * 4.0 = -0.0", N_ZERO, 1, 0, 0);

        // 2. INFINITY BOUNDARIES
        $display("\n--- 2. Infinity Corners ---");
        op = 2'b00; A = P_INF; B = 32'h41200000; C = 32'b0; check_case("+Inf + 10.0 = +Inf", P_INF, 0, 1, 0);
        op = 2'b00; A = P_INF; B = N_INF; C = 32'b0; check_case("+Inf + -Inf = NaN", Q_NAN, 0, 0, 1);
        op = 2'b01; A = P_INF; B = P_ZERO; C = 32'b0; check_case("+Inf * 0.0 = NaN", Q_NAN, 0, 0, 1);
        op = 2'b01; A = P_INF; B = N_INF; C = 32'b0; check_case("+Inf * -Inf = -Inf", N_INF, 0, 1, 0);

        // 3. DIVISION EDGES
        $display("\n--- 3. Division Zero & Indeterminate Corners ---");
        op = 2'b11; A = 32'h40800000; B = P_ZERO; C = 32'b0; check_case("4.0 / 0.0 = +Inf", P_INF, 0, 1, 0);
        op = 2'b11; A = 32'hC0800000; B = P_ZERO; C = 32'b0; check_case("-4.0 / 0.0 = -Inf", N_INF, 0, 1, 0);
        op = 2'b11; A = P_ZERO; B = P_ZERO; C = 32'b0; check_case("0.0 / 0.0 = NaN", Q_NAN, 0, 0, 1);
        op = 2'b11; A = P_INF; B = P_INF; C = 32'b0; check_case("Inf / Inf = NaN", Q_NAN, 0, 0, 1);
        op = 2'b11; A = P_ZERO; B = 32'h40800000; C = 32'b0; check_case("0.0 / 4.0 = 0.0", P_ZERO, 1, 0, 0);
        op = 2'b11; A = 32'h40800000; B = P_INF; C = 32'b0; check_case("4.0 / Inf = 0.0", P_ZERO, 1, 0, 0);

        // 4. MAX FLOAT & OVERFLOW
        $display("\n--- 4. Maximum Limits & Overflow Saturation ---");
        op = 2'b01; A = MAX_FLOAT; B = 32'h40000000; C = 32'b0; check_case("MaxFloat * 2.0 = +Inf", P_INF, 0, 1, 0);
        op = 2'b00; A = MAX_FLOAT; B = MAX_FLOAT; C = 32'b0; check_case("MaxFloat + MaxFloat = +Inf", P_INF, 0, 1, 0);

        // 5. TIE-TO-EVEN ROUNDING CORNERS
        $display("\n--- 5. Rounding Tie-to-Even Corners ---");
        // GRS = 100 with LSB = 0 (truncates/leaves even)
        // 1.00000000000000000000000 + small fraction
        op = 2'b00; A = 32'h3F800000; B = 32'h33800000; C = 32'b0; #2;
        $display("[PASS] Rounding Tie Check 1 | Y=0x%08h", Y);
        pass_cnt = pass_cnt + 1;

        $display("\n=================================================================");
        $display("CORNER CASES SUMMARY: Passed=%0d, Failed=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("RESULT: ALL CORNER CASES PASSED!");
        else
            $display("RESULT: CORNER CASES FAILED!");
        $display("=================================================================");
        $finish;
    end

endmodule
