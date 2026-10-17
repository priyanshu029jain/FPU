// =============================================================================
// Testbench : tb_adder
// Purpose   : Complete simulation testbench for param_adder_sub.v
// Structure :
//   Part 1: Direct Cases  (Sanity & standard arithmetic)
//   Part 2: Corner Cases  (Max/Min limits, carry, signed overflow, borrow)
//   Part 3: Random Cases  (50+ pseudo-random vectors verified against golden model)
// =============================================================================

`timescale 1ns/1ps

module tb_adder;

    localparam WIDTH = 32;

    reg  [WIDTH-1:0] A;
    reg  [WIDTH-1:0] B;
    reg              sub;
    reg              is_signed;
    wire [WIDTH-1:0] result;
    wire             carry_out;
    wire             overflow;

    integer total_tests = 0;
    integer pass_tests  = 0;
    integer fail_tests  = 0;
    integer iter;

    // Golden model variables
    reg [WIDTH:0]   golden_ext;
    reg [WIDTH-1:0] golden_res;
    reg             golden_co;
    reg             golden_ovf;
    reg             sa, sb, sr;

    // Instantiate UUT
    param_adder_sub #(
        .WIDTH(WIDTH)
    ) uut (
        .A(A),
        .B(B),
        .sub(sub),
        .is_signed(is_signed),
        .result(result),
        .carry_out(carry_out),
        .overflow(overflow)
    );

    task check_res(
        input [8*36:1]    desc,
        input [WIDTH-1:0] exp_res,
        input             exp_co,
        input             exp_ovf
    );
        total_tests = total_tests + 1;
        #1;
        if (result === exp_res && carry_out === exp_co && overflow === exp_ovf) begin
            $display("[PASS] %-34s | Res: 0x%08h | CO: %b | OVF: %b", desc, result, carry_out, overflow);
            pass_tests = pass_tests + 1;
        end else begin
            $display("[FAIL] %-34s | Got: Res=0x%08h CO=%b OVF=%b | Exp: Res=0x%08h CO=%b OVF=%b",
                     desc, result, carry_out, overflow, exp_res, exp_co, exp_ovf);
            fail_tests = fail_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("waveform_adder.vcd");
        $dumpvars(0, tb_adder);

        $display("=================================================================");
        $display("STARTING SIMULATION: tb_adder (Direct, Corner & Random Cases)");
        $display("=================================================================\n");

        #5;

        // =====================================================================
        // PART 1: DIRECT CASES
        // =====================================================================
        $display("--- PART 1: DIRECT CASES ---");

        // 1.1 Direct Unsigned Add
        sub = 1'b0; is_signed = 1'b0;
        A = 32'd10; B = 32'd25; #2; check_res("Direct Add: 10 + 25 = 35", 32'd35, 1'b0, 1'b0);
        A = 32'd1000; B = 32'd2345; #2; check_res("Direct Add: 1000 + 2345 = 3345", 32'd3345, 1'b0, 1'b0);

        // 1.2 Direct Unsigned Sub
        sub = 1'b1; is_signed = 1'b0;
        A = 32'd50; B = 32'd20; #2; check_res("Direct Sub: 50 - 20 = 30", 32'd30, 1'b1, 1'b1);
        A = 32'd100; B = 32'd1; #2; check_res("Direct Sub: 100 - 1 = 99", 32'd99, 1'b1, 1'b1);

        // 1.3 Direct Signed Add
        sub = 1'b0; is_signed = 1'b1;
        A = 32'sd50; B = -32'sd20; #2; check_res("Direct Signed: 50 + (-20) = 30", 32'sd30, 1'b1, 1'b0);

        // 1.4 Direct Signed Sub
        sub = 1'b1; is_signed = 1'b1;
        A = 32'sd50; B = -32'sd20; #2; check_res("Direct Signed: 50 - (-20) = 70", 32'sd70, 1'b0, 1'b0);

        // =====================================================================
        // PART 2: CORNER CASES
        // =====================================================================
        $display("\n--- PART 2: CORNER CASES ---");

        // 2.1 All Zeros
        sub = 1'b0; is_signed = 1'b0;
        A = 32'd0; B = 32'd0; #2; check_res("Corner: 0 + 0 = 0", 32'd0, 1'b0, 1'b0);

        // 2.2 Unsigned Carry-Out (Max + 1)
        A = 32'hFFFFFFFF; B = 32'd1; #2; check_res("Corner: MaxUnsigned + 1 (Carry)", 32'd0, 1'b1, 1'b1);

        // 2.3 Unsigned Underflow / Borrow (0 - 1)
        sub = 1'b1; is_signed = 1'b0;
        A = 32'd0; B = 32'd1; #2; check_res("Corner: 0 - 1 = 0xFFFFFFFF (Borrow)", 32'hFFFFFFFF, 1'b0, 1'b0);

        // 2.4 Cancellation to exact zero (A - A = 0)
        A = 32'h12345678; B = 32'h12345678; #2; check_res("Corner: A - A = 0", 32'd0, 1'b1, 1'b1);

        // 2.5 Signed Positive Overflow (+Max + 1)
        sub = 1'b0; is_signed = 1'b1;
        A = 32'h7FFFFFFF; B = 32'd1; #2; check_res("Corner: +MaxSigned + 1 (OVF)", 32'h80000000, 1'b0, 1'b1);

        // 2.6 Signed Negative Overflow (-Max + (-1))
        A = 32'h80000000; B = -32'd1; #2; check_res("Corner: -MaxSigned + (-1) (OVF)", 32'h7FFFFFFF, 1'b1, 1'b1);

        // 2.7 Signed Subtraction Overflow (+Max - (-1))
        sub = 1'b1; is_signed = 1'b1;
        A = 32'h7FFFFFFF; B = -32'd1; #2; check_res("Corner: +MaxSigned - (-1) (OVF)", 32'h80000000, 1'b0, 1'b1);

        // 2.8 Both Negative Add (-1 + -1 = -2)
        sub = 1'b0; is_signed = 1'b1;
        A = -32'd1; B = -32'd1; #2; check_res("Corner: (-1) + (-1) = -2", -32'd2, 1'b1, 1'b0);

        // =====================================================================
        // PART 3: RANDOM CASES (50 Iterations Verified Against Golden Model)
        // =====================================================================
        $display("\n--- PART 3: RANDOM CASES (50 Iterations) ---");

        for (iter = 0; iter < 50; iter = iter + 1) begin
            A = $random;
            B = $random;
            sub = iter[0];
            is_signed = iter[1];

            // Golden reference calculation
            if (sub) begin
                golden_ext = {1'b0, A} + {1'b0, ~B} + 1'b1;
            end else begin
                golden_ext = {1'b0, A} + {1'b0, B};
            end
            golden_res = golden_ext[WIDTH-1:0];
            golden_co  = golden_ext[WIDTH];

            sa = A[WIDTH-1];
            sb = sub ? ~B[WIDTH-1] : B[WIDTH-1];
            sr = golden_res[WIDTH-1];
            golden_ovf = is_signed ? ((sa == sb) && (sr != sa)) : golden_co;

            #2;
            if (result === golden_res && carry_out === golden_co && overflow === golden_ovf) begin
                pass_tests = pass_tests + 1;
            end else begin
                $display("[FAIL-RANDOM] Iter %0d | A=0x%08h B=0x%08h sub=%b signed=%b | Got: R=0x%08h CO=%b OVF=%b | Exp: R=0x%08h CO=%b OVF=%b",
                         iter, A, B, sub, is_signed, result, carry_out, overflow, golden_res, golden_co, golden_ovf);
                fail_tests = fail_tests + 1;
            end
            total_tests = total_tests + 1;
        end
        $display("[PASS] 50 Random vectors validated successfully against golden model.");

        $display("\n=================================================================");
        $display("tb_adder SUMMARY: Total=%0d, Passed=%0d, Failed=%0d", total_tests, pass_tests, fail_tests);
        if (fail_tests == 0)
            $display("RESULT: ALL DIRECT, CORNER, AND RANDOM TESTS PASSED!");
        else
            $display("RESULT: FAILURES DETECTED IN tb_adder!");
        $display("=================================================================");
        $finish;
    end

endmodule
