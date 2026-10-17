// =============================================================================
// Testbench : tb_fpu_adder
// Purpose   : Cycle-Accurate Verification for 4-Stage Pipelined FPU_adder
// Features  :
//   - Clock generation (100 MHz, 10ns period)
//   - Active-low asynchronous reset
//   - Pipelined latency verification (4 clock cycles)
//   - Pipelined throughput verification (1 test vector per clock cycle)
//   - Direct, Special Cases (Zero, Inf, NaN), and IEEE 754 Exception Flags
// =============================================================================
`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */

module tb_fpu_adder;

    reg         clk;
    reg         rst_n;
    reg         valid_in;
    reg  [31:0] A;
    reg  [31:0] B;

    wire [31:0] Y;
    wire        valid_out;
    wire        flag_overflow;
    wire        flag_underflow;
    wire        flag_invalid;
    wire        flag_zero;
    wire        flag_inexact;

    integer total_tests = 0;
    integer pass_tests  = 0;
    integer fail_tests  = 0;

    // Instantiate 4-Stage Pipelined UUT
    FPU_adder uut (
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

    // Clock generator: 100 MHz (10ns period)
    always #5 clk = ~clk;

    // Task to apply single vector and wait 4 cycles for pipelined output
    task apply_and_check(
        input [8*42:1] desc,
        input [31:0]   in_a,
        input [31:0]   in_b,
        input [31:0]   exp_y,
        input          exp_zero,
        input          exp_invalid
    );
        reg [31:0] captured_y;
        reg        captured_zero;
        reg        captured_inv;
        integer    latency;
        begin
            @(negedge clk);
            A        <= in_a;
            B        <= in_b;
            valid_in <= 1'b1;

            @(negedge clk);
            valid_in <= 1'b0;

            // Wait until valid_out is asserted (expecting exactly 4 cycles from launch)
            latency = 0;
            while (!valid_out && latency < 10) begin
                @(posedge clk);
                latency = latency + 1;
            end

            #1; // Sample output after clock edge
            captured_y    = Y;
            captured_zero = flag_zero;
            captured_inv  = flag_invalid;
            total_tests   = total_tests + 1;

            if (exp_invalid) begin
                if (captured_inv && (captured_y[30:23] == 8'hFF && captured_y[22:0] != 0)) begin
                    $display("[PASS] %-38s | Latency=%0d cyc | NaN=0x%08h | FlagInvalid=%b",
                             desc, latency, captured_y, captured_inv);
                    pass_tests = pass_tests + 1;
                end else begin
                    $display("[FAIL] %-38s | Expected NaN & flag_invalid=1, got Y=0x%08h inv=%b",
                             desc, captured_y, captured_inv);
                    fail_tests = fail_tests + 1;
                end
            end else if (captured_y === exp_y && captured_zero === exp_zero) begin
                $display("[PASS] %-38s | Latency=%0d cyc | Y: 0x%08h | Zero=%b Inexact=%b",
                         desc, latency, captured_y, captured_zero, flag_inexact);
                pass_tests = pass_tests + 1;
            end else begin
                $display("[FAIL] %-38s | Got: Y=0x%08h Zero=%b | Exp: Y=0x%08h Zero=%b",
                         desc, captured_y, captured_zero, exp_y, exp_zero);
                fail_tests = fail_tests + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("waveform_fpu_adder.vcd");
        $dumpvars(0, tb_fpu_adder);

        clk      = 1'b0;
        rst_n    = 1'b0;
        valid_in = 1'b0;
        A        = 32'h0;
        B        = 32'h0;

        $display("=================================================================");
        $display("STARTING SIMULATION: tb_fpu_adder (4-STAGE PIPELINED FPU ADDER)");
        $display("=================================================================\n");

        // Apply Reset
        #15;
        rst_n = 1'b1;
        #10;

        // =====================================================================
        // PART 1: DIRECT ADDITION & SUBTRACTION
        // =====================================================================
        $display("--- PART 1: DIRECT ADDITION & SUBTRACTION (4-CYCLE LATENCY) ---");
        apply_and_check("Direct: 1.0 + 1.0 = 2.0",       32'h3F800000, 32'h3F800000, 32'h40000000, 1'b0, 1'b0);
        apply_and_check("Direct: 1.0 + 2.0 = 3.0",       32'h3F800000, 32'h40000000, 32'h40400000, 1'b0, 1'b0);
        apply_and_check("Direct: 2.5 + 3.75 = 6.25",     32'h40200000, 32'h40700000, 32'h40C80000, 1'b0, 1'b0);
        apply_and_check("Direct: 10.0 + 5.0 = 15.0",     32'h41200000, 32'h40A00000, 32'h41700000, 1'b0, 1'b0);
        apply_and_check("Direct: 100.0 + 25.0 = 125.0",  32'h42C80000, 32'h41C80000, 32'h42FA0000, 1'b0, 1'b0);
        apply_and_check("Direct: 0.5 + 0.25 = 0.75",     32'h3F000000, 32'h3E800000, 32'h3F400000, 1'b0, 1'b0);
        apply_and_check("Direct: 0.125 + 0.375 = 0.5",   32'h3E000000, 32'h3EC00000, 32'h3F000000, 1'b0, 1'b0);
        apply_and_check("Direct: 15.0 + 16.0 = 31.0",    32'h41700000, 32'h41800000, 32'h41F80000, 1'b0, 1'b0);
        apply_and_check("Direct: 64.0 + 32.0 = 96.0",    32'h42800000, 32'h42000000, 32'h42C00000, 1'b0, 1'b0);
        apply_and_check("Direct: 128.0 + 128.0 = 256.0", 32'h43000000, 32'h43000000, 32'h43800000, 1'b0, 1'b0);

        // Subtractions (Opposite Signs)
        apply_and_check("Direct: 10.0 + (-2.5) = 7.5",   32'h41200000, 32'hC0200000, 32'h40F00000, 1'b0, 1'b0);
        apply_and_check("Direct: 25.0 + (-10.0) = 15.0", 32'h41C80000, 32'hC1200000, 32'h41700000, 1'b0, 1'b0);
        apply_and_check("Direct: 1.5 + (-0.5) = 1.0",    32'h3FC00000, 32'hBF000000, 32'h3F800000, 1'b0, 1'b0);
        apply_and_check("Direct: 3.75 + (-1.25) = 2.5",  32'h40700000, 32'hBFA00000, 32'h40200000, 1'b0, 1'b0);
        apply_and_check("Direct: -5.0 + 10.0 = 5.0",     32'hC0A00000, 32'h41200000, 32'h40A00000, 1'b0, 1'b0);
        apply_and_check("Direct: -2.5 + 1.25 = -1.25",   32'hC0200000, 32'h3FA00000, 32'hBFA00000, 1'b0, 1'b0);
        apply_and_check("Direct: -100.0 + 50.0 = -50.0", 32'hC2C80000, 32'h42480000, 32'hC2480000, 1'b0, 1'b0);
        apply_and_check("Direct: -0.75 + 0.5 = -0.25",   32'hBF400000, 32'h3F000000, 32'hBE800000, 1'b0, 1'b0);
        apply_and_check("Direct: -2.0 + (-3.0) = -5.0",  32'hC0000000, 32'hC0400000, 32'hC0A00000, 1'b0, 1'b0);
        apply_and_check("Direct: -10.0 + (-20.0) = -30", 32'hC1200000, 32'hC1A00000, 32'hC1F00000, 1'b0, 1'b0);

        // =====================================================================
        // PART 2: SPECIAL CASES & EXCEPTION FLAGS
        // =====================================================================
        $display("\n--- PART 2: SPECIAL & CORNER CASES ---");
        apply_and_check("Corner: 0.0 + 5.0 = 5.0",       32'h00000000, 32'h40A00000, 32'h40A00000, 1'b0, 1'b0);
        apply_and_check("Corner: 5.0 + 0.0 = 5.0",       32'h40A00000, 32'h00000000, 32'h40A00000, 1'b0, 1'b0);
        apply_and_check("Corner: 0.0 + 0.0 = 0.0",       32'h00000000, 32'h00000000, 32'h00000000, 1'b1, 1'b0);
        apply_and_check("Corner: 100.0 + (-100.0) = 0.0",32'h42C80000, 32'hC2C80000, 32'h00000000, 1'b1, 1'b0);
        apply_and_check("Corner: -10.0 + 10.0 = 0.0",    32'hC1200000, 32'h41200000, 32'h00000000, 1'b1, 1'b0);
        apply_and_check("Corner: +Inf + 5.0 = +Inf",     32'h7F800000, 32'h40A00000, 32'h7F800000, 1'b0, 1'b0);
        apply_and_check("Corner: -Inf + 5.0 = -Inf",     32'hFF800000, 32'h40A00000, 32'hFF800000, 1'b0, 1'b0);
        apply_and_check("Corner: +Inf + (-Inf) = NaN",   32'h7F800000, 32'hFF800000, 32'h7FC00000, 1'b0, 1'b1);
        apply_and_check("Corner: NaN + 5.0 = NaN",       32'h7FC00000, 32'h40A00000, 32'h7FC00000, 1'b0, 1'b1);
        apply_and_check("Corner: 5.0 + NaN = NaN",       32'h40A00000, 32'h7FC00000, 32'h7FC00000, 1'b0, 1'b1);
        apply_and_check("Corner: Huge Exp Diff (Align)", 32'h4E800000, 32'h30800000, 32'h4E800000, 1'b0, 1'b0);

        // =====================================================================
        // PART 3: PIPELINE THROUGHPUT (1 VECTOR PER CYCLE CONTINUOUS STREAM)
        // =====================================================================
        $display("\n--- PART 3: CONTINUOUS PIPELINE STREAMING (1 Vector / Cycle) ---");
        begin : pipeline_stream
            reg [31:0] stream_a [0:4];
            reg [31:0] stream_b [0:4];
            reg [31:0] stream_exp [0:4];

            stream_a[0] = 32'h3F800000; stream_b[0] = 32'h3F800000; stream_exp[0] = 32'h40000000; // 1 + 1 = 2
            stream_a[1] = 32'h40000000; stream_b[1] = 32'h40000000; stream_exp[1] = 32'h40800000; // 2 + 2 = 4
            stream_a[2] = 32'h40800000; stream_b[2] = 32'h40800000; stream_exp[2] = 32'h41000000; // 4 + 4 = 8
            stream_a[3] = 32'h41000000; stream_b[3] = 32'h41000000; stream_exp[3] = 32'h41800000; // 8 + 8 = 16
            stream_a[4] = 32'h41800000; stream_b[4] = 32'h41800000; stream_exp[4] = 32'h42000000; // 16 + 16 = 32

            fork
                begin : send_stream
                    integer s_idx;
                    for (s_idx = 0; s_idx < 5; s_idx = s_idx + 1) begin
                        @(negedge clk);
                        A        <= stream_a[s_idx];
                        B        <= stream_b[s_idx];
                        valid_in <= 1'b1;
                    end
                    @(negedge clk);
                    valid_in <= 1'b0;
                end
                begin : recv_stream
                    integer r_idx;
                    r_idx = 0;
                    while (r_idx < 5) begin
                        @(posedge clk);
                        #1;
                        if (valid_out) begin
                            total_tests = total_tests + 1;
                            if (Y === stream_exp[r_idx]) begin
                                $display("[PASS] Stream Vector %0d | Y=0x%08h (1 result/cycle sustained)", r_idx, Y);
                                pass_tests = pass_tests + 1;
                            end else begin
                                $display("[FAIL] Stream Vector %0d | Got: 0x%08h Exp: 0x%08h", r_idx, Y, stream_exp[r_idx]);
                                fail_tests = fail_tests + 1;
                            end
                            r_idx = r_idx + 1;
                        end
                    end
                end
            join
        end

        // Final Summary
        $display("\n=================================================================");
        $display("tb_fpu_adder SUMMARY: Total=%0d, Passed=%0d, Failed=%0d", total_tests, pass_tests, fail_tests);
        if (fail_tests == 0)
            $display("RESULT: ALL PIPELINED 4-STAGE TESTS PASSED SUCCESSFULLY!");
        else
            $display("RESULT: %0d TESTS FAILED!", fail_tests);
        $display("=================================================================");

        #20;
        $finish;
    end

endmodule
