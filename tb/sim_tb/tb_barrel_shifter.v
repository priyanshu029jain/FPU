// =============================================================================
// Testbench : tb_barrel_shifter
// Purpose   : Complete simulation testbench for barrel_shifter.v
// Structure :
//   Part 1: Direct Cases  (Standard left and right shifts)
//   Part 2: Corner Cases  (Shift by 0, shift by WIDTH-1, overshift, sticky bit drops)
//   Part 3: Random Cases  (50+ pseudo-random vectors verified against golden model)
// =============================================================================

`timescale 1ns/1ps

module tb_barrel_shifter;

    localparam DATA_WIDTH  = 48;
    localparam SHIFT_WIDTH = 6;

    reg  [DATA_WIDTH-1:0]  data_in;
    reg  [SHIFT_WIDTH-1:0] shift_amt;
    reg                    dir;
    reg                    arith;
    wire [DATA_WIDTH-1:0]  data_out;
    wire                   sticky;

    integer total_tests = 0;
    integer pass_tests  = 0;
    integer fail_tests  = 0;
    integer iter, b_idx;

    // Golden model variables
    reg [DATA_WIDTH-1:0] golden_out;
    reg                  golden_sticky;
    reg [DATA_WIDTH-1:0] golden_mask;

    barrel_shifter #(
        .DATA_WIDTH(DATA_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH)
    ) uut (
        .data_in(data_in),
        .shift_amt(shift_amt),
        .dir(dir),
        .arith(arith),
        .data_out(data_out),
        .sticky(sticky)
    );

    task check_shift(
        input [8*36:1]        desc,
        input [DATA_WIDTH-1:0] exp_data,
        input                  exp_sticky
    );
        total_tests = total_tests + 1;
        #1;
        if (data_out === exp_data && sticky === exp_sticky) begin
            $display("[PASS] %-34s | Out: 0x%012h | Sticky: %b", desc, data_out, sticky);
            pass_tests = pass_tests + 1;
        end else begin
            $display("[FAIL] %-34s | Got: Out=0x%012h S=%b | Exp: Out=0x%012h S=%b",
                     desc, data_out, sticky, exp_data, exp_sticky);
            fail_tests = fail_tests + 1;
        end
    endtask

    initial begin
        $dumpfile("waveform_barrel_shifter.vcd");
        $dumpvars(0, tb_barrel_shifter);

        $display("=================================================================");
        $display("STARTING SIMULATION: tb_barrel_shifter (Direct, Corner & Random)");
        $display("=================================================================\n");

        #5;

        // =====================================================================
        // PART 1: DIRECT CASES
        // =====================================================================
        $display("--- PART 1: DIRECT CASES ---");

        // 1.1 Direct Left Shifts
        dir = 1'b0; arith = 1'b0;
        data_in = 48'h000000000001; shift_amt = 6'd4; #2;
        check_shift("Direct: Shift Left by 4", 48'h000000000010, 1'b0);

        data_in = 48'h00000000000F; shift_amt = 6'd8; #2;
        check_shift("Direct: Shift Left by 8", 48'h000000000F00, 1'b0);

        // 1.2 Direct Logical Right Shifts
        dir = 1'b1; arith = 1'b0;
        data_in = 48'h00000000F000; shift_amt = 6'd8; #2;
        check_shift("Direct: Shift Right by 8 (S=0)", 48'h0000000000F0, 1'b0);

        data_in = 48'h0000000000F5; shift_amt = 6'd4; #2;
        check_shift("Direct: Shift Right 0xF5 by 4 (S=1)", 48'h00000000000F, 1'b1);

        // =====================================================================
        // PART 2: CORNER CASES
        // =====================================================================
        $display("\n--- PART 2: CORNER CASES ---");

        // 2.1 Identity (Shift by 0)
        dir = 1'b0; arith = 1'b0;
        data_in = 48'h123456789ABC; shift_amt = 6'd0; #2;
        check_shift("Corner: Shift Left by 0", 48'h123456789ABC, 1'b0);

        dir = 1'b1; arith = 1'b0;
        data_in = 48'h123456789ABC; shift_amt = 6'd0; #2;
        check_shift("Corner: Shift Right by 0", 48'h123456789ABC, 1'b0);

        // 2.2 Maximum in-range shift (by 47 to MSB / LSB)
        dir = 1'b0; arith = 1'b0;
        data_in = 48'h000000000001; shift_amt = 6'd47; #2;
        check_shift("Corner: Shift Left by 47 (to MSB)", 48'h800000000000, 1'b0);

        dir = 1'b1; arith = 1'b0;
        data_in = 48'h800000000000; shift_amt = 6'd47; #2;
        check_shift("Corner: Shift Right by 47 (to LSB)", 48'h000000000001, 1'b0);

        // 2.3 Single-bit dropped into sticky (LSB was 1, shifted right by 1)
        dir = 1'b1; arith = 1'b0;
        data_in = 48'h000000000003; shift_amt = 6'd1; #2;
        check_shift("Corner: 0x3 >> 1 (Drop LSB, S=1)", 48'h000000000001, 1'b1);

        // 2.4 Arithmetic Right Shift with negative sign (MSB=1)
        dir = 1'b1; arith = 1'b1;
        data_in = 48'h800000000000; shift_amt = 6'd4; #2;
        check_shift("Corner: Arith Right 0x80.. >> 4", 48'hF80000000000, 1'b0);

        // 2.5 Overshift boundary (shift_amt >= 48)
        dir = 1'b1; arith = 1'b0;
        data_in = 48'hFFFFFFFFFFFF; shift_amt = 6'd48; #2;
        check_shift("Corner: Overshift 48 (All out, S=1)", 48'h000000000000, 1'b1);

        data_in = 48'h000000000000; shift_amt = 6'd55; #2;
        check_shift("Corner: Overshift 0 by 55 (S=0)", 48'h000000000000, 1'b0);

        // =====================================================================
        // PART 3: RANDOM CASES (50 Iterations Verified Against Golden Model)
        // =====================================================================
        $display("\n--- PART 3: RANDOM CASES (50 Iterations) ---");

        for (iter = 0; iter < 50; iter = iter + 1) begin
            /* verilator lint_off WIDTHTRUNC */
            data_in   = {$random, $random};
            shift_amt = iter % 55; // Covers 0 to 54 (both in-range and overshift)
            /* verilator lint_on WIDTHTRUNC */
            dir       = iter[0];
            arith     = iter[1];

            // Golden model reference
            if (dir == 1'b0) begin
                golden_out    = data_in << shift_amt;
                golden_sticky = 1'b0;
            end else begin
                if (shift_amt >= DATA_WIDTH) begin
                    golden_out    = (arith && data_in[DATA_WIDTH-1]) ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};
                    golden_sticky = |data_in;
                end else begin
                    if (arith && data_in[DATA_WIDTH-1])
                        golden_out = (data_in >> shift_amt) | ({DATA_WIDTH{1'b1}} << (DATA_WIDTH - shift_amt));
                    else
                        golden_out = (data_in >> shift_amt);

                    golden_mask = {DATA_WIDTH{1'b0}};
                    for (b_idx = 0; b_idx < DATA_WIDTH; b_idx = b_idx + 1) begin
                        if (b_idx < shift_amt)
                            golden_mask[b_idx] = 1'b1;
                    end
                    golden_sticky = |(data_in & golden_mask);
                end
            end

            #2;
            if (data_out === golden_out && sticky === golden_sticky) begin
                pass_tests = pass_tests + 1;
            end else begin
                $display("[FAIL-RANDOM] Iter %0d | In=0x%012h amt=%0d dir=%b arith=%b | Got: Out=0x%012h S=%b | Exp: Out=0x%012h S=%b",
                         iter, data_in, shift_amt, dir, arith, data_out, sticky, golden_out, golden_sticky);
                fail_tests = fail_tests + 1;
            end
            total_tests = total_tests + 1;
        end
        $display("[PASS] 50 Random shift vectors validated successfully against golden model.");

        $display("\n=================================================================");
        $display("tb_barrel_shifter SUMMARY: Total=%0d, Passed=%0d, Failed=%0d", total_tests, pass_tests, fail_tests);
        if (fail_tests == 0)
            $display("RESULT: ALL DIRECT, CORNER, AND RANDOM TESTS PASSED!");
        else
            $display("RESULT: FAILURES DETECTED IN tb_barrel_shifter!");
        $display("=================================================================");
        $finish;
    end

endmodule
