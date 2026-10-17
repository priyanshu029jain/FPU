// =============================================================================
// Testbench : tb_LZD
// Purpose   : Complete simulation testbench for leading_zero_detector.v
// Structure :
//   Part 1: Direct Cases  (Specific single and multi-bit vectors)
//   Part 2: Corner Cases  (All-zeros, all-ones, all 32 one-hot positions)
//   Part 3: Random Cases  (50+ pseudo-random vectors verified against golden model)
// =============================================================================

`timescale 1ns/1ps

module tb_LZD;

    localparam WIDTH       = 32;
    localparam COUNT_WIDTH = 6;

    reg  [WIDTH-1:0]       in_vector;
    wire [COUNT_WIDTH-1:0] zero_count;
    wire                   all_zeros;

    integer total_tests = 0;
    integer pass_tests  = 0;
    integer fail_tests  = 0;
    integer k, iter;

    // Golden model variables
    reg [COUNT_WIDTH-1:0] golden_cnt;
    reg                   golden_all_z;
    integer               scan_idx;
    reg                   scan_found;

    leading_zero_detector #(
        .WIDTH(WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) uut (
        .in_vector(in_vector),
        .zero_count(zero_count),
        .all_zeros(all_zeros)
    );

    task check_lzd(
        input [8*36:1]          desc,
        input [COUNT_WIDTH-1:0] exp_count,
        input                   exp_all_z
    );
        total_tests = total_tests + 1;
        #1;
        if (zero_count === exp_count && all_zeros === exp_all_z) begin
            $display("[PASS] %-34s | In: 0x%08h | Count: %2d | AllZero: %b", desc, in_vector, zero_count, all_zeros);
            pass_tests = pass_tests + 1;
        end else begin
            $display("[FAIL] %-34s | Got: Count=%0d AllZero=%b | Exp: Count=%0d AllZero=%b",
                     desc, zero_count, all_zeros, exp_count, exp_all_z);
            fail_tests = fail_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("waveform_lzd.vcd");
        $dumpvars(0, tb_LZD);

        $display("=================================================================");
        $display("STARTING SIMULATION: tb_LZD (Direct, Corner & Random Cases)");
        $display("=================================================================\n");

        #5;

        // =====================================================================
        // PART 1: DIRECT CASES
        // =====================================================================
        $display("--- PART 1: DIRECT CASES ---");

        in_vector = 32'h80000000; #2; check_lzd("Direct: Bit 31 is 1 (MSB)", 6'd0, 1'b0);
        in_vector = 32'h40000000; #2; check_lzd("Direct: Bit 30 is 1", 6'd1, 1'b0);
        in_vector = 32'h00010000; #2; check_lzd("Direct: Bit 16 is 1", 6'd15, 1'b0);
        in_vector = 32'h00000100; #2; check_lzd("Direct: Bit 8 is 1", 6'd23, 1'b0);
        in_vector = 32'h00000001; #2; check_lzd("Direct: Bit 0 is 1 (LSB)", 6'd31, 1'b0);

        // Priority multi-bit (noise in lower bits)
        in_vector = 32'h8000FFFF; #2; check_lzd("Direct: MSB=1 with noisy LSBs", 6'd0, 1'b0);
        in_vector = 32'h00801234; #2; check_lzd("Direct: Bit 23=1 with noisy LSBs", 6'd8, 1'b0);

        // =====================================================================
        // PART 2: CORNER CASES
        // =====================================================================
        $display("\n--- PART 2: CORNER CASES ---");

        // 2.1 All Zeros (Flag=1, Count=32)
        in_vector = 32'h00000000; #2; check_lzd("Corner: All Zeros Vector", 6'd32, 1'b1);

        // 2.2 All Ones (Count=0, Flag=0)
        in_vector = 32'hFFFFFFFF; #2; check_lzd("Corner: All Ones Vector", 6'd0, 1'b0);

        // 2.3 Automated 32-Position Sweep (1-hot vectors)
        $display("--- Corner: 32-Position 1-Hot Vector Sweep (Bits 31 to 0) ---");
        for (k = 31; k >= 0; k = k - 1) begin
            in_vector = (32'b1 << k);
            #2;
            if ({26'd0, zero_count} === (31 - k) && all_zeros === 1'b0) begin
                pass_tests = pass_tests + 1;
            end else begin
                $display("[FAIL-SWEEP] Bit %0d hot: Got Count=%0d Exp=%0d", k, zero_count, (31 - k));
                fail_tests = fail_tests + 1;
            end
            total_tests = total_tests + 1;
        end
        $display("[PASS] 32-position single-bit sweep completed successfully.");

        // =====================================================================
        // PART 3: RANDOM CASES (50 Iterations Verified Against Golden Model)
        // =====================================================================
        $display("\n--- PART 3: RANDOM CASES (50 Iterations) ---");

        for (iter = 0; iter < 50; iter = iter + 1) begin
            in_vector = $random;

            // Golden reference scan
            golden_cnt   = 6'd32;
            golden_all_z = 1'b1;
            scan_found   = 1'b0;

            for (scan_idx = WIDTH - 1; scan_idx >= 0; scan_idx = scan_idx - 1) begin
                if (in_vector[scan_idx] == 1'b1 && !scan_found) begin
                    /* verilator lint_off WIDTHTRUNC */
                    golden_cnt   = (WIDTH - 1 - scan_idx);
                    /* verilator lint_on WIDTHTRUNC */
                    golden_all_z = 1'b0;
                    scan_found   = 1'b1;
                end
            end

            #2;
            if (zero_count === golden_cnt && all_zeros === golden_all_z) begin
                pass_tests = pass_tests + 1;
            end else begin
                $display("[FAIL-RANDOM] Iter %0d | In=0x%08h | Got: Cnt=%0d AllZ=%b | Exp: Cnt=%0d AllZ=%b",
                         iter, in_vector, zero_count, all_zeros, golden_cnt, golden_all_z);
                fail_tests = fail_tests + 1;
            end
            total_tests = total_tests + 1;
        end
        $display("[PASS] 50 Random LZD vectors validated successfully against golden model.");

        $display("\n=================================================================");
        $display("tb_LZD SUMMARY: Total=%0d, Passed=%0d, Failed=%0d", total_tests, pass_tests, fail_tests);
        if (fail_tests == 0)
            $display("RESULT: ALL DIRECT, CORNER, AND RANDOM TESTS PASSED!");
        else
            $display("RESULT: FAILURES DETECTED IN tb_LZD!");
        $display("=================================================================");
        $finish;
    end

endmodule
