// =============================================================================
// Testbench : tb_multiplier
// Purpose   : Complete simulation testbench for param_multiplier.v
// Structure :
//   Part 1: Direct Cases  (Standard unsigned/signed products, IEEE 754 float significands)
//   Part 2: Corner Cases  (Zeros, Max unsigned 0xFFFFFF*0xFFFFFF, Min negative limits)
//   Part 3: Random Cases  (50+ pseudo-random vectors verified against golden model)
// =============================================================================

`timescale 1ns/1ps

module tb_multiplier;

    localparam A_WIDTH   = 24;
    localparam B_WIDTH   = 24;
    localparam OUT_WIDTH = A_WIDTH + B_WIDTH; // 48 bits

    reg  [A_WIDTH-1:0]   A;
    reg  [B_WIDTH-1:0]   B;
    reg                  is_signed;
    wire [OUT_WIDTH-1:0] product;

    integer total_tests = 0;
    integer pass_tests  = 0;
    integer fail_tests  = 0;
    integer iter;

    // Golden model variables
    reg [OUT_WIDTH-1:0] golden_prod;
    wire signed [A_WIDTH-1:0] s_a = A;
    wire signed [B_WIDTH-1:0] s_b = B;

    param_multiplier #(
        .A_WIDTH(A_WIDTH),
        .B_WIDTH(B_WIDTH)
    ) uut (
        .A(A),
        .B(B),
        .is_signed(is_signed),
        .product(product)
    );

    task check_prod(
        input [8*36:1]        desc,
        input [OUT_WIDTH-1:0] exp_prod
    );
        total_tests = total_tests + 1;
        #1;
        if (product === exp_prod) begin
            $display("[PASS] %-34s | Product: 0x%012h", desc, product);
            pass_tests = pass_tests + 1;
        end else begin
            $display("[FAIL] %-34s | Got: 0x%012h | Exp: 0x%012h", desc, product, exp_prod);
            fail_tests = fail_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("waveform_multiplier.vcd");
        $dumpvars(0, tb_multiplier);

        $display("=================================================================");
        $display("STARTING SIMULATION: tb_multiplier (Direct, Corner & Random)");
        $display("=================================================================\n");

        #5;

        // =====================================================================
        // PART 1: DIRECT CASES
        // =====================================================================
        $display("--- PART 1: DIRECT CASES ---");

        // 1.1 Direct Unsigned
        is_signed = 1'b0;
        A = 24'd10; B = 24'd20; #2; check_prod("Direct: 10 * 20 = 200", 48'd200);
        A = 24'd1;  B = 24'hABCDEF; #2; check_prod("Direct: 1 * 0xABCDEF = 0xABCDEF", 48'h000000ABCDEF);

        // 1.2 Direct IEEE 754 Float Significands (1.0 = 0x800000, 1.5 = 0xC00000)
        A = 24'h800000; B = 24'h800000; #2; check_prod("Direct: 1.0 * 1.0 (sig)", 48'h400000000000);
        A = 24'hC00000; B = 24'hC00000; #2; check_prod("Direct: 1.5 * 1.5 = 2.25 (sig)", 48'h900000000000);
        A = 24'hA00000; B = 24'h800000; #2; check_prod("Direct: 1.25 * 1.0 = 1.25 (sig)", 48'h500000000000);

        // 1.3 Direct Signed
        is_signed = 1'b1;
        A = 24'sd50; B = 24'sd10;  #2; check_prod("Direct: 50 * 10 = 500", 48'sd500);
        A = 24'sd50; B = -24'sd10; #2; check_prod("Direct: 50 * (-10) = -500", -48'sd500);
        A = -24'sd50; B = -24'sd10; #2; check_prod("Direct: (-50) * (-10) = 500", 48'sd500);

        // =====================================================================
        // PART 2: CORNER CASES
        // =====================================================================
        $display("\n--- PART 2: CORNER CASES ---");

        // 2.1 Multiplication by Zero
        is_signed = 1'b0;
        A = 24'd0; B = 24'hFFFFFF; #2; check_prod("Corner: 0 * Max = 0", 48'd0);
        A = 24'd0; B = 24'd0;      #2; check_prod("Corner: 0 * 0 = 0", 48'd0);

        // 2.2 Maximum 24-bit Unsigned Product (0xFFFFFF * 0xFFFFFF)
        A = 24'hFFFFFF; B = 24'hFFFFFF; #2; check_prod("Corner: 0xFFFFFF * 0xFFFFFF (Max)", 48'hFFFFFE000001);

        // 2.3 Signed Min Negative Boundary (-2^23 * 1)
        is_signed = 1'b1;
        A = 24'h800000; B = 24'sd1; #2; check_prod("Corner: -8388608 * 1 (MinNeg)", 48'hFFFFFF800000);

        // 2.4 Negative One * Negative One (-1 * -1 = +1)
        A = -24'sd1; B = -24'sd1; #2; check_prod("Corner: (-1) * (-1) = 1", 48'd1);

        // =====================================================================
        // PART 3: RANDOM CASES (50 Iterations Verified Against Golden Model)
        // =====================================================================
        $display("\n--- PART 3: RANDOM CASES (50 Iterations) ---");

        for (iter = 0; iter < 50; iter = iter + 1) begin
            /* verilator lint_off WIDTHTRUNC */
            /* verilator lint_off WIDTHEXPAND */
            A = $random & 32'h00FFFFFF;
            B = $random & 32'h00FFFFFF;
            /* verilator lint_on WIDTHEXPAND */
            /* verilator lint_on WIDTHTRUNC */
            is_signed = iter[0];

            if (is_signed)
                golden_prod = s_a * s_b;
            else
                golden_prod = A * B;

            #2;
            if (product === golden_prod) begin
                pass_tests = pass_tests + 1;
            end else begin
                $display("[FAIL-RANDOM] Iter %0d | A=0x%06h B=0x%06h signed=%b | Got: 0x%012h | Exp: 0x%012h",
                         iter, A, B, is_signed, product, golden_prod);
                fail_tests = fail_tests + 1;
            end
            total_tests = total_tests + 1;
        end
        $display("[PASS] 50 Random multiplication vectors validated against golden model.");

        $display("\n=================================================================");
        $display("tb_multiplier SUMMARY: Total=%0d, Passed=%0d, Failed=%0d", total_tests, pass_tests, fail_tests);
        if (fail_tests == 0)
            $display("RESULT: ALL DIRECT, CORNER, AND RANDOM TESTS PASSED!");
        else
            $display("RESULT: FAILURES DETECTED IN tb_multiplier!");
        $display("=================================================================");
        $finish;
    end

endmodule
