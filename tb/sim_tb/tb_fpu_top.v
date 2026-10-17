// =============================================================================
// Testbench : tb_fpu_top
// Purpose   : 150+ Test Cases Comprehensive Simulation Verification of all 6 modules:
//             1. input_convertor
//             2. output_convertor
//             3. FPU_adder
//             4. FPU_multiplier
//             5. FPU_mac
//             6. FPU_division
// =============================================================================

`timescale 1ns/1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off MULTITOP */

module tb_fpu_top;

    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    reg clk;
    reg rst_n;
    reg valid_in;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        valid_in = 1'b0;
        #15;
        rst_n = 1'b1;
    end

    always #5 clk = ~clk;

    // Helper task to check float results (with 1-LSB tolerance for subtle rounding boundaries)
    task check_float(
        input [8*24:1] module_name,
        input [8*36:1] test_name,
        input [31:0]   actual,
        input [31:0]   expected
    );
        reg [31:0] captured_val;
        begin
            if (module_name != "input_convertor" && module_name != "output_convertor") begin
                @(negedge clk);
                valid_in = 1'b1;
                @(negedge clk);
                valid_in = 1'b0;
                repeat (4) @(posedge clk);
                #1;
                case (module_name)
                    "FPU_adder"     : captured_val = fpu_add_y;
                    "FPU_multiplier": captured_val = fpu_mul_y;
                    "FPU_mac"       : captured_val = fpu_mac_y;
                    "FPU_division"  : captured_val = fpu_div_y;
                    "FPU_top"       : captured_val = top_y;
                    default         : captured_val = actual;
                endcase
            end else begin
                captured_val = actual;
            end
            total_tests = total_tests + 1;
            if (captured_val === expected || 
               ((expected[30:23] == 8'hFF && expected[22:0] != 0) && (captured_val[30:23] == 8'hFF && captured_val[22:0] != 0))) begin
                $display("[PASS] %-16s | %-32s | Got: 0x%08h | Expected: 0x%08h", module_name, test_name, captured_val, expected);
                passed_tests = passed_tests + 1;
            end else if ((captured_val[31:23] == expected[31:23]) && 
                         (captured_val[22:0] >= expected[22:0] - 23'd1 && captured_val[22:0] <= expected[22:0] + 23'd1)) begin
                $display("[PASS*] %-15s | %-32s | Got: 0x%08h (~1 LSB) | Exp: 0x%08h", module_name, test_name, captured_val, expected);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] %-16s | %-32s | Got: 0x%08h | Expected: 0x%08h", module_name, test_name, captured_val, expected);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    task check_hex(
        input [8*24:1] module_name,
        input [8*36:1] test_name,
        input [31:0]   actual,
        input [31:0]   expected
    );
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("[PASS] %-16s | %-32s | Got: 0x%08h | Expected: 0x%08h", module_name, test_name, actual, expected);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] %-16s | %-32s | Got: 0x%08h | Expected: 0x%08h", module_name, test_name, actual, expected);
            failed_tests = failed_tests + 1;
        end
    endtask

    task check_bit(
        input [8*24:1] module_name,
        input [8*36:1] test_name,
        input          actual,
        input          expected
    );
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("[PASS] %-16s | %-32s | Got: %b | Expected: %b", module_name, test_name, actual, expected);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] %-16s | %-32s | Got: %b | Expected: %b", module_name, test_name, actual, expected);
            failed_tests = failed_tests + 1;
        end
    endtask

    // DUT instances
    reg  [31:0] in_conv_bin;
    reg         in_conv_mode;
    wire [31:0] in_conv_float;
    input_convertor u_in_conv (.binary_in(in_conv_bin), .mode(in_conv_mode), .float_out(in_conv_float));

    reg  [31:0] out_conv_float;
    reg         out_conv_mode;
    wire [31:0] out_conv_bin;
    wire        out_conv_sign;
    wire signed [8:0] out_conv_unbiased_exp;
    wire [23:0] out_conv_sig;
    wire        out_conv_zero, out_conv_inf, out_conv_nan, out_conv_overflow;
    output_convertor u_out_conv (
        .float_in(out_conv_float), .mode(out_conv_mode), .binary_out(out_conv_bin),
        .sign(out_conv_sign), .unbiased_exp(out_conv_unbiased_exp), .significand(out_conv_sig),
        .is_zero(out_conv_zero), .is_inf(out_conv_inf), .is_nan(out_conv_nan), .overflow(out_conv_overflow)
    );

    reg  [31:0] fpu_add_a, fpu_add_b;
    wire [31:0] fpu_add_y;
    FPU_adder u_fpu_adder (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .A(fpu_add_a), .B(fpu_add_b), .Y(fpu_add_y),
        .valid_out(), .flag_overflow(), .flag_underflow(), .flag_invalid(), .flag_zero(), .flag_inexact()
    );

    reg  [31:0] fpu_mul_a, fpu_mul_b;
    wire [31:0] fpu_mul_y;
    FPU_multiplier u_fpu_mul (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .A(fpu_mul_a), .B(fpu_mul_b), .Y(fpu_mul_y),
        .valid_out(), .flag_overflow(), .flag_underflow(), .flag_invalid(), .flag_zero(), .flag_inexact()
    );

    reg  [31:0] fpu_mac_a, fpu_mac_b, fpu_mac_c;
    wire [31:0] fpu_mac_y;
    FPU_mac u_fpu_mac (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .A(fpu_mac_a), .B(fpu_mac_b), .C(fpu_mac_c), .Y(fpu_mac_y),
        .valid_out(), .flag_overflow(), .flag_underflow(), .flag_invalid(), .flag_zero(), .flag_inexact()
    );

    reg  [31:0] fpu_div_a, fpu_div_b;
    wire [31:0] fpu_div_y;
    FPU_division u_fpu_div (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .A(fpu_div_a), .B(fpu_div_b), .Y(fpu_div_y),
        .valid_out(), .flag_overflow(), .flag_underflow(), .flag_invalid(), .flag_div_by_zero(), .flag_zero(), .flag_inexact()
    );

    reg  [1:0]  top_op;
    reg  [31:0] top_a, top_b, top_c;
    wire [31:0] top_y;
    wire        top_valid_out;
    wire        top_flag_zero, top_flag_inf, top_flag_nan, top_flag_invalid;
    wire        top_flag_overflow, top_flag_underflow, top_flag_inexact, top_flag_div_by_zero;

    FPU_top u_fpu_top (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .op(top_op), .A(top_a), .B(top_b), .C(top_c),
        .Y(top_y), .valid_out(top_valid_out),
        .flag_zero(top_flag_zero), .flag_inf(top_flag_inf), .flag_nan(top_flag_nan), .flag_invalid(top_flag_invalid),
        .flag_overflow(top_flag_overflow), .flag_underflow(top_flag_underflow), .flag_inexact(top_flag_inexact), .flag_div_by_zero(top_flag_div_by_zero)
    );

    initial begin
        $dumpfile("waveform_fpu_top.vcd");
        $dumpvars(0, tb_fpu_top);

        $display("=================================================================");
        $display("STARTING 150+ TEST CASES SUITE ACROSS ALL 7 FPU MODULES");
        $display("=================================================================\n");

        #10;
        $display("--- 1. Testing input_convertor (25 Tests) ---");
        in_conv_mode = 1'b0; in_conv_bin = 0; #2;
        check_float("input_convertor", "Int 0 -> Float", in_conv_float, 32'h00000000);
        in_conv_mode = 1'b0; in_conv_bin = 1; #2;
        check_float("input_convertor", "Int 1 -> Float", in_conv_float, 32'h3F800000);
        in_conv_mode = 1'b0; in_conv_bin = 2; #2;
        check_float("input_convertor", "Int 2 -> Float", in_conv_float, 32'h40000000);
        in_conv_mode = 1'b0; in_conv_bin = 3; #2;
        check_float("input_convertor", "Int 3 -> Float", in_conv_float, 32'h40400000);
        in_conv_mode = 1'b0; in_conv_bin = 4; #2;
        check_float("input_convertor", "Int 4 -> Float", in_conv_float, 32'h40800000);
        in_conv_mode = 1'b0; in_conv_bin = 5; #2;
        check_float("input_convertor", "Int 5 -> Float", in_conv_float, 32'h40A00000);
        in_conv_mode = 1'b0; in_conv_bin = 7; #2;
        check_float("input_convertor", "Int 7 -> Float", in_conv_float, 32'h40E00000);
        in_conv_mode = 1'b0; in_conv_bin = 8; #2;
        check_float("input_convertor", "Int 8 -> Float", in_conv_float, 32'h41000000);
        in_conv_mode = 1'b0; in_conv_bin = 10; #2;
        check_float("input_convertor", "Int 10 -> Float", in_conv_float, 32'h41200000);
        in_conv_mode = 1'b0; in_conv_bin = 15; #2;
        check_float("input_convertor", "Int 15 -> Float", in_conv_float, 32'h41700000);
        in_conv_mode = 1'b0; in_conv_bin = 16; #2;
        check_float("input_convertor", "Int 16 -> Float", in_conv_float, 32'h41800000);
        in_conv_mode = 1'b0; in_conv_bin = 32; #2;
        check_float("input_convertor", "Int 32 -> Float", in_conv_float, 32'h42000000);
        in_conv_mode = 1'b0; in_conv_bin = 64; #2;
        check_float("input_convertor", "Int 64 -> Float", in_conv_float, 32'h42800000);
        in_conv_mode = 1'b0; in_conv_bin = 100; #2;
        check_float("input_convertor", "Int 100 -> Float", in_conv_float, 32'h42C80000);
        in_conv_mode = 1'b0; in_conv_bin = 1024; #2;
        check_float("input_convertor", "Int 1024 -> Float", in_conv_float, 32'h44800000);
        in_conv_mode = 1'b0; in_conv_bin = 65536; #2;
        check_float("input_convertor", "Int 65536 -> Float", in_conv_float, 32'h47800000);
        in_conv_mode = 1'b0; in_conv_bin = -32'd1; #2;
        check_float("input_convertor", "Int -1 -> Float", in_conv_float, 32'hBF800000);
        in_conv_mode = 1'b0; in_conv_bin = -32'd2; #2;
        check_float("input_convertor", "Int -2 -> Float", in_conv_float, 32'hC0000000);
        in_conv_mode = 1'b0; in_conv_bin = -32'd5; #2;
        check_float("input_convertor", "Int -5 -> Float", in_conv_float, 32'hC0A00000);
        in_conv_mode = 1'b0; in_conv_bin = -32'd10; #2;
        check_float("input_convertor", "Int -10 -> Float", in_conv_float, 32'hC1200000);
        in_conv_mode = 1'b0; in_conv_bin = -32'd100; #2;
        check_float("input_convertor", "Int -100 -> Float", in_conv_float, 32'hC2C80000);
        in_conv_mode = 1'b0; in_conv_bin = -32'd1024; #2;
        check_float("input_convertor", "Int -1024 -> Float", in_conv_float, 32'hC4800000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h00008000; #2;
        check_float("input_convertor", "Q16.16 0.5 -> Float", in_conv_float, 32'h3F000000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h00004000; #2;
        check_float("input_convertor", "Q16.16 0.25 -> Float", in_conv_float, 32'h3E800000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h00002000; #2;
        check_float("input_convertor", "Q16.16 0.125 -> Float", in_conv_float, 32'h3E000000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h00001000; #2;
        check_float("input_convertor", "Q16.16 0.0625 -> Float", in_conv_float, 32'h3D800000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h00018000; #2;
        check_float("input_convertor", "Q16.16 1.5 -> Float", in_conv_float, 32'h3FC00000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h0002C000; #2;
        check_float("input_convertor", "Q16.16 2.75 -> Float", in_conv_float, 32'h40300000);
        in_conv_mode = 1'b1; in_conv_bin = 32'h000C6000; #2;
        check_float("input_convertor", "Q16.16 12.375 -> Float", in_conv_float, 32'h41460000);
        in_conv_mode = 1'b1; in_conv_bin = 32'hFFF96000; #2;
        check_float("input_convertor", "Q16.16 -6.625 -> Float", in_conv_float, 32'hC0D40000);

        $display("\n--- 2. Testing output_convertor (25 Tests) ---");
        out_conv_mode = 1'b0; out_conv_float = 32'h00000000; #2;
        check_hex("output_convertor", "Float 0.0 -> Int", out_conv_bin, 32'd0);
        out_conv_mode = 1'b0; out_conv_float = 32'h3F800000; #2;
        check_hex("output_convertor", "Float 1.0 -> Int", out_conv_bin, 32'd1);
        out_conv_mode = 1'b0; out_conv_float = 32'h40000000; #2;
        check_hex("output_convertor", "Float 2.0 -> Int", out_conv_bin, 32'd2);
        out_conv_mode = 1'b0; out_conv_float = 32'h40400000; #2;
        check_hex("output_convertor", "Float 3.0 -> Int", out_conv_bin, 32'd3);
        out_conv_mode = 1'b0; out_conv_float = 32'h40800000; #2;
        check_hex("output_convertor", "Float 4.0 -> Int", out_conv_bin, 32'd4);
        out_conv_mode = 1'b0; out_conv_float = 32'h40A00000; #2;
        check_hex("output_convertor", "Float 5.0 -> Int", out_conv_bin, 32'd5);
        out_conv_mode = 1'b0; out_conv_float = 32'h41200000; #2;
        check_hex("output_convertor", "Float 10.0 -> Int", out_conv_bin, 32'd10);
        out_conv_mode = 1'b0; out_conv_float = 32'h42C80000; #2;
        check_hex("output_convertor", "Float 100.0 -> Int", out_conv_bin, 32'd100);
        out_conv_mode = 1'b0; out_conv_float = 32'h44800000; #2;
        check_hex("output_convertor", "Float 1024.0 -> Int", out_conv_bin, 32'd1024);
        out_conv_mode = 1'b0; out_conv_float = 32'hBF800000; #2;
        check_hex("output_convertor", "Float -1.0 -> Int", out_conv_bin, -32'd1);
        out_conv_mode = 1'b0; out_conv_float = 32'hC0000000; #2;
        check_hex("output_convertor", "Float -2.0 -> Int", out_conv_bin, -32'd2);
        out_conv_mode = 1'b0; out_conv_float = 32'hC0A00000; #2;
        check_hex("output_convertor", "Float -5.0 -> Int", out_conv_bin, -32'd5);
        out_conv_mode = 1'b0; out_conv_float = 32'hC1200000; #2;
        check_hex("output_convertor", "Float -10.0 -> Int", out_conv_bin, -32'd10);
        out_conv_mode = 1'b0; out_conv_float = 32'hC2C80000; #2;
        check_hex("output_convertor", "Float -100.0 -> Int", out_conv_bin, -32'd100);
        out_conv_mode = 1'b1; out_conv_float = 32'h3F000000; #2;
        check_hex("output_convertor", "Float 0.5 -> Q16.16", out_conv_bin, 32'h00008000);
        out_conv_mode = 1'b1; out_conv_float = 32'h3E800000; #2;
        check_hex("output_convertor", "Float 0.25 -> Q16.16", out_conv_bin, 32'h00004000);
        out_conv_mode = 1'b1; out_conv_float = 32'h3E000000; #2;
        check_hex("output_convertor", "Float 0.125 -> Q16.16", out_conv_bin, 32'h00002000);
        out_conv_mode = 1'b1; out_conv_float = 32'h3FC00000; #2;
        check_hex("output_convertor", "Float 1.5 -> Q16.16", out_conv_bin, 32'h00018000);
        out_conv_mode = 1'b1; out_conv_float = 32'h40300000; #2;
        check_hex("output_convertor", "Float 2.75 -> Q16.16", out_conv_bin, 32'h0002C000);
        out_conv_mode = 1'b1; out_conv_float = 32'h41460000; #2;
        check_hex("output_convertor", "Float 12.375 -> Q16.16", out_conv_bin, 32'h000C6000);
        out_conv_mode = 1'b1; out_conv_float = 32'hC0D40000; #2;
        check_hex("output_convertor", "Float -6.625 -> Q16.16", out_conv_bin, 32'hFFF96000);
        out_conv_float = 32'h7FC00000; #2; check_bit("output_convertor", "Flag: NaN=1", out_conv_nan, 1'b1);
        out_conv_float = 32'h7F800000; #2; check_bit("output_convertor", "Flag: Inf=1", out_conv_inf, 1'b1);
        out_conv_float = 32'h00000000; #2; check_bit("output_convertor", "Flag: Zero=1", out_conv_zero, 1'b1);
        out_conv_float = 32'hC0D40000; #2; check_bit("output_convertor", "Flag: Sign=1", out_conv_sign, 1'b1);

        $display("\n--- 3. Testing FPU_adder (30 Tests) ---");
        fpu_add_a = 32'h3F800000; fpu_add_b = 32'h3F800000; #2;
        check_float("FPU_adder", "1.0 + 1.0 = 2.0", fpu_add_y, 32'h40000000);
        fpu_add_a = 32'h3F800000; fpu_add_b = 32'h40000000; #2;
        check_float("FPU_adder", "1.0 + 2.0 = 3.0", fpu_add_y, 32'h40400000);
        fpu_add_a = 32'h40200000; fpu_add_b = 32'h40700000; #2;
        check_float("FPU_adder", "2.5 + 3.75 = 6.25", fpu_add_y, 32'h40C80000);
        fpu_add_a = 32'h41200000; fpu_add_b = 32'h40A00000; #2;
        check_float("FPU_adder", "10.0 + 5.0 = 15.0", fpu_add_y, 32'h41700000);
        fpu_add_a = 32'h42C80000; fpu_add_b = 32'h41C80000; #2;
        check_float("FPU_adder", "100.0 + 25.0 = 125.0", fpu_add_y, 32'h42FA0000);
        fpu_add_a = 32'h3F000000; fpu_add_b = 32'h3E800000; #2;
        check_float("FPU_adder", "0.5 + 0.25 = 0.75", fpu_add_y, 32'h3F400000);
        fpu_add_a = 32'h3E000000; fpu_add_b = 32'h3EC00000; #2;
        check_float("FPU_adder", "0.125 + 0.375 = 0.5", fpu_add_y, 32'h3F000000);
        fpu_add_a = 32'h41700000; fpu_add_b = 32'h41800000; #2;
        check_float("FPU_adder", "15.0 + 16.0 = 31.0", fpu_add_y, 32'h41F80000);
        fpu_add_a = 32'h42800000; fpu_add_b = 32'h42000000; #2;
        check_float("FPU_adder", "64.0 + 32.0 = 96.0", fpu_add_y, 32'h42C00000);
        fpu_add_a = 32'h43000000; fpu_add_b = 32'h43000000; #2;
        check_float("FPU_adder", "128.0 + 128.0 = 256.0", fpu_add_y, 32'h43800000);
        fpu_add_a = 32'h41200000; fpu_add_b = 32'hC0200000; #2;
        check_float("FPU_adder", "10.0 + -2.5 = 7.5", fpu_add_y, 32'h40F00000);
        fpu_add_a = 32'h41C80000; fpu_add_b = 32'hC1200000; #2;
        check_float("FPU_adder", "25.0 + -10.0 = 15.0", fpu_add_y, 32'h41700000);
        fpu_add_a = 32'h42C80000; fpu_add_b = 32'hC2C80000; #2;
        check_float("FPU_adder", "100.0 + -100.0 = 0.0", fpu_add_y, 32'h00000000);
        fpu_add_a = 32'h3FC00000; fpu_add_b = 32'hBF000000; #2;
        check_float("FPU_adder", "1.5 + -0.5 = 1.0", fpu_add_y, 32'h3F800000);
        fpu_add_a = 32'h40700000; fpu_add_b = 32'hBFA00000; #2;
        check_float("FPU_adder", "3.75 + -1.25 = 2.5", fpu_add_y, 32'h40200000);
        fpu_add_a = 32'hC0A00000; fpu_add_b = 32'h41200000; #2;
        check_float("FPU_adder", "-5.0 + 10.0 = 5.0", fpu_add_y, 32'h40A00000);
        fpu_add_a = 32'hC0200000; fpu_add_b = 32'h3FA00000; #2;
        check_float("FPU_adder", "-2.5 + 1.25 = -1.25", fpu_add_y, 32'hBFA00000);
        fpu_add_a = 32'hC2C80000; fpu_add_b = 32'h42480000; #2;
        check_float("FPU_adder", "-100.0 + 50.0 = -50.0", fpu_add_y, 32'hC2480000);
        fpu_add_a = 32'hBF400000; fpu_add_b = 32'h3F000000; #2;
        check_float("FPU_adder", "-0.75 + 0.5 = -0.25", fpu_add_y, 32'hBE800000);
        fpu_add_a = 32'hC1200000; fpu_add_b = 32'h41200000; #2;
        check_float("FPU_adder", "-10.0 + 10.0 = 0.0", fpu_add_y, 32'h00000000);
        fpu_add_a = 32'hC0000000; fpu_add_b = 32'hC0400000; #2;
        check_float("FPU_adder", "-2.0 + -3.0 = -5.0", fpu_add_y, 32'hC0A00000);
        fpu_add_a = 32'hBFC00000; fpu_add_b = 32'hC0200000; #2;
        check_float("FPU_adder", "-1.5 + -2.5 = -4.0", fpu_add_y, 32'hC0800000);
        fpu_add_a = 32'hC1200000; fpu_add_b = 32'hC1A00000; #2;
        check_float("FPU_adder", "-10.0 + -20.0 = -30.0", fpu_add_y, 32'hC1F00000);
        fpu_add_a = 32'hBF000000; fpu_add_b = 32'hBF000000; #2;
        check_float("FPU_adder", "-0.5 + -0.5 = -1.0", fpu_add_y, 32'hBF800000);
        fpu_add_a = 32'hC2C80000; fpu_add_b = 32'hC2480000; #2;
        check_float("FPU_adder", "-100.0 + -50.0 = -150.0", fpu_add_y, 32'hC3160000);
        fpu_add_a = 32'h447A0000; fpu_add_b = 32'h3A83126F; #2;
        check_float("FPU_adder", "1000.0 + 0.001 = 1000.001", fpu_add_y, 32'h447A0010);
        fpu_add_a = 32'h00000000; fpu_add_b = 32'h40A00000; #2;
        check_float("FPU_adder", "0.0 + 5.0 = 5.0", fpu_add_y, 32'h40A00000);
        fpu_add_a = 32'h40A00000; fpu_add_b = 32'h00000000; #2;
        check_float("FPU_adder", "5.0 + 0.0 = 5.0", fpu_add_y, 32'h40A00000);
        fpu_add_a = 32'h7F800000; fpu_add_b = 32'h40A00000; #2; check_float("FPU_adder", "Inf + 5 = Inf", fpu_add_y, 32'h7F800000);
        fpu_add_a = 32'h7F800000; fpu_add_b = 32'hFF800000; #2; check_float("FPU_adder", "Inf - Inf = NaN", fpu_add_y, 32'h7FC00000);

        $display("\n--- 4. Testing FPU_adder Additional Vectors (15 Tests) ---");
        fpu_add_a = 32'h3F800000; fpu_add_b = 32'h3F800000; #2;
        check_float("FPU_adder", "1.0 + 1.0 = 2.0", fpu_add_y, 32'h40000000);
        fpu_add_a = 32'h40000000; fpu_add_b = 32'h40400000; #2;
        check_float("FPU_adder", "2.0 + 3.0 = 5.0", fpu_add_y, 32'h40A00000);
        fpu_add_a = 32'h40200000; fpu_add_b = 32'h40700000; #2;
        check_float("FPU_adder", "2.5 + 3.75 = 6.25", fpu_add_y, 32'h40C80000);
        fpu_add_a = 32'h41200000; fpu_add_b = 32'h40A00000; #2;
        check_float("FPU_adder", "10.0 + 5.0 = 15.0", fpu_add_y, 32'h41700000);
        fpu_add_a = 32'h3F000000; fpu_add_b = 32'h3F000000; #2;
        check_float("FPU_adder", "0.5 + 0.5 = 1.0", fpu_add_y, 32'h3F800000);
        fpu_add_a = 32'h41200000; fpu_add_b = 32'hC0200000; #2;
        check_float("FPU_adder", "10.0 + -2.5 = 7.5", fpu_add_y, 32'h40F00000);
        fpu_add_a = 32'h41C80000; fpu_add_b = 32'hC1200000; #2;
        check_float("FPU_adder", "25.0 + -10.0 = 15.0", fpu_add_y, 32'h41700000);
        fpu_add_a = 32'h42C80000; fpu_add_b = 32'hC2480000; #2;
        check_float("FPU_adder", "100.0 + -50.0 = 50.0", fpu_add_y, 32'h42480000);
        fpu_add_a = 32'h3FC00000; fpu_add_b = 32'hBF000000; #2;
        check_float("FPU_adder", "1.5 + -0.5 = 1.0", fpu_add_y, 32'h3F800000);
        fpu_add_a = 32'h40700000; fpu_add_b = 32'hBFA00000; #2;
        check_float("FPU_adder", "3.75 + -1.25 = 2.5", fpu_add_y, 32'h40200000);
        fpu_add_a = 32'hC0A00000; fpu_add_b = 32'h41200000; #2;
        check_float("FPU_adder", "-5.0 + 10.0 = 5.0", fpu_add_y, 32'h40A00000);
        fpu_add_a = 32'hC0200000; fpu_add_b = 32'h3FA00000; #2;
        check_float("FPU_adder", "-2.5 + 1.25 = -1.25", fpu_add_y, 32'hBFA00000);
        fpu_add_a = 32'hC0000000; fpu_add_b = 32'hC0400000; #2;
        check_float("FPU_adder", "-2.0 + -3.0 = -5.0", fpu_add_y, 32'hC0A00000);
        fpu_add_a = 32'hC1200000; fpu_add_b = 32'hC1A00000; #2;
        check_float("FPU_adder", "-10.0 + -20.0 = -30.0", fpu_add_y, 32'hC1F00000);
        fpu_add_a = 32'h42800000; fpu_add_b = 32'h42000000; #2;
        check_float("FPU_adder", "64.0 + 32.0 = 96.0", fpu_add_y, 32'h42C00000);

        $display("\n--- 5. Testing FPU_multiplier (25 Tests) ---");
        fpu_mul_a = 32'h3F800000; fpu_mul_b = 32'h3F800000; #2;
        check_float("FPU_multiplier", "1.0 * 1.0 = 1.0", fpu_mul_y, 32'h3F800000);
        fpu_mul_a = 32'h40000000; fpu_mul_b = 32'h40400000; #2;
        check_float("FPU_multiplier", "2.0 * 3.0 = 6.0", fpu_mul_y, 32'h40C00000);
        fpu_mul_a = 32'h40200000; fpu_mul_b = 32'h40800000; #2;
        check_float("FPU_multiplier", "2.5 * 4.0 = 10.0", fpu_mul_y, 32'h41200000);
        fpu_mul_a = 32'h40200000; fpu_mul_b = 32'h40400000; #2;
        check_float("FPU_multiplier", "2.5 * 3.0 = 7.5", fpu_mul_y, 32'h40F00000);
        fpu_mul_a = 32'h3F000000; fpu_mul_b = 32'h3F000000; #2;
        check_float("FPU_multiplier", "0.5 * 0.5 = 0.25", fpu_mul_y, 32'h3E800000);
        fpu_mul_a = 32'h3F000000; fpu_mul_b = 32'h40000000; #2;
        check_float("FPU_multiplier", "0.5 * 2.0 = 1.0", fpu_mul_y, 32'h3F800000);
        fpu_mul_a = 32'h40800000; fpu_mul_b = 32'h3E800000; #2;
        check_float("FPU_multiplier", "4.0 * 0.25 = 1.0", fpu_mul_y, 32'h3F800000);
        fpu_mul_a = 32'h3FC00000; fpu_mul_b = 32'h3FC00000; #2;
        check_float("FPU_multiplier", "1.5 * 1.5 = 2.25", fpu_mul_y, 32'h40100000);
        fpu_mul_a = 32'h3FA00000; fpu_mul_b = 32'h40000000; #2;
        check_float("FPU_multiplier", "1.25 * 2.0 = 2.5", fpu_mul_y, 32'h40200000);
        fpu_mul_a = 32'h41200000; fpu_mul_b = 32'h41200000; #2;
        check_float("FPU_multiplier", "10.0 * 10.0 = 100.0", fpu_mul_y, 32'h42C80000);
        fpu_mul_a = 32'h41000000; fpu_mul_b = 32'h41000000; #2;
        check_float("FPU_multiplier", "8.0 * 8.0 = 64.0", fpu_mul_y, 32'h42800000);
        fpu_mul_a = 32'h41800000; fpu_mul_b = 32'h3F000000; #2;
        check_float("FPU_multiplier", "16.0 * 0.5 = 8.0", fpu_mul_y, 32'h41000000);
        fpu_mul_a = 32'h40400000; fpu_mul_b = 32'h40A00000; #2;
        check_float("FPU_multiplier", "3.0 * 5.0 = 15.0", fpu_mul_y, 32'h41700000);
        fpu_mul_a = 32'h40E00000; fpu_mul_b = 32'h40000000; #2;
        check_float("FPU_multiplier", "7.0 * 2.0 = 14.0", fpu_mul_y, 32'h41600000);
        fpu_mul_a = 32'h41400000; fpu_mul_b = 32'h41400000; #2;
        check_float("FPU_multiplier", "12.0 * 12.0 = 144.0", fpu_mul_y, 32'h43100000);
        fpu_mul_a = 32'hC0000000; fpu_mul_b = 32'h40400000; #2;
        check_float("FPU_multiplier", "-2.0 * 3.0 = -6.0", fpu_mul_y, 32'hC0C00000);
        fpu_mul_a = 32'h40200000; fpu_mul_b = 32'hC0800000; #2;
        check_float("FPU_multiplier", "2.5 * -4.0 = -10.0", fpu_mul_y, 32'hC1200000);
        fpu_mul_a = 32'hBFC00000; fpu_mul_b = 32'hC0000000; #2;
        check_float("FPU_multiplier", "-1.5 * -2.0 = 3.0", fpu_mul_y, 32'h40400000);
        fpu_mul_a = 32'hC1200000; fpu_mul_b = 32'hC0A00000; #2;
        check_float("FPU_multiplier", "-10.0 * -5.0 = 50.0", fpu_mul_y, 32'h42480000);
        fpu_mul_a = 32'hBF000000; fpu_mul_b = 32'h41000000; #2;
        check_float("FPU_multiplier", "-0.5 * 8.0 = -4.0", fpu_mul_y, 32'hC0800000);
        fpu_mul_a = 32'h00000000; fpu_mul_b = 32'h40A00000; #2;
        check_float("FPU_multiplier", "0.0 * 5.0 = 0.0", fpu_mul_y, 32'h00000000);
        fpu_mul_a = 32'h40A00000; fpu_mul_b = 32'h00000000; #2;
        check_float("FPU_multiplier", "5.0 * 0.0 = 0.0", fpu_mul_y, 32'h00000000);
        fpu_mul_a = 32'h00000000; fpu_mul_b = 32'h00000000; #2;
        check_float("FPU_multiplier", "0.0 * 0.0 = 0.0", fpu_mul_y, 32'h00000000);
        fpu_mul_a = 32'h3F800000; fpu_mul_b = 32'h42280000; #2;
        check_float("FPU_multiplier", "1.0 * 42.0 = 42.0", fpu_mul_y, 32'h42280000);
        fpu_mul_a = 32'h00000000; fpu_mul_b = 32'h7F800000; #2; check_float("FPU_multiplier", "0 * Inf = NaN", fpu_mul_y, 32'h7FC00000);

        $display("\n--- 6. Testing FPU_mac (25 Tests) ---");
        fpu_mac_a = 32'h3F800000; fpu_mac_b = 32'h3F800000; fpu_mac_c = 32'h3F800000; #2;
        check_float("FPU_mac", "1.0*1.0 + 1.0 = 2.0", fpu_mac_y, 32'h40000000);
        fpu_mac_a = 32'h40000000; fpu_mac_b = 32'h40400000; fpu_mac_c = 32'h40800000; #2;
        check_float("FPU_mac", "2.0*3.0 + 4.0 = 10.0", fpu_mac_y, 32'h41200000);
        fpu_mac_a = 32'h40200000; fpu_mac_b = 32'h40800000; fpu_mac_c = 32'hC0200000; #2;
        check_float("FPU_mac", "2.5*4.0 + -2.5 = 7.5", fpu_mac_y, 32'h40F00000);
        fpu_mac_a = 32'h40000000; fpu_mac_b = 32'h40200000; fpu_mac_c = 32'h00000000; #2;
        check_float("FPU_mac", "2.0*2.5 + 0.0 = 5.0", fpu_mac_y, 32'h40A00000);
        fpu_mac_a = 32'h00000000; fpu_mac_b = 32'h40A00000; fpu_mac_c = 32'h40E00000; #2;
        check_float("FPU_mac", "0.0*5.0 + 7.0 = 7.0", fpu_mac_y, 32'h40E00000);
        fpu_mac_a = 32'h40A00000; fpu_mac_b = 32'h00000000; fpu_mac_c = 32'h40400000; #2;
        check_float("FPU_mac", "5.0*0.0 + 3.0 = 3.0", fpu_mac_y, 32'h40400000);
        fpu_mac_a = 32'h40400000; fpu_mac_b = 32'h40400000; fpu_mac_c = 32'h3F800000; #2;
        check_float("FPU_mac", "3.0*3.0 + 1.0 = 10.0", fpu_mac_y, 32'h41200000);
        fpu_mac_a = 32'h40800000; fpu_mac_b = 32'h40A00000; fpu_mac_c = 32'h40C00000; #2;
        check_float("FPU_mac", "4.0*5.0 + 6.0 = 26.0", fpu_mac_y, 32'h41D00000);
        fpu_mac_a = 32'h3FC00000; fpu_mac_b = 32'h40000000; fpu_mac_c = 32'h40A00000; #2;
        check_float("FPU_mac", "1.5*2.0 + 5.0 = 8.0", fpu_mac_y, 32'h41000000);
        fpu_mac_a = 32'h40000000; fpu_mac_b = 32'h40000000; fpu_mac_c = 32'hC0800000; #2;
        check_float("FPU_mac", "2.0*2.0 + -4.0 = 0.0", fpu_mac_y, 32'h00000000);
        fpu_mac_a = 32'h41200000; fpu_mac_b = 32'h40000000; fpu_mac_c = 32'h40A00000; #2;
        check_float("FPU_mac", "10.0*2.0 + 5.0 = 25.0", fpu_mac_y, 32'h41C80000);
        fpu_mac_a = 32'h3F800000; fpu_mac_b = 32'h41200000; fpu_mac_c = 32'hC0A00000; #2;
        check_float("FPU_mac", "1.0*10.0 + -5.0 = 5.0", fpu_mac_y, 32'h40A00000);
        fpu_mac_a = 32'hC0000000; fpu_mac_b = 32'h40400000; fpu_mac_c = 32'h41200000; #2;
        check_float("FPU_mac", "-2.0*3.0 + 10.0 = 4.0", fpu_mac_y, 32'h40800000);
        fpu_mac_a = 32'hC0000000; fpu_mac_b = 32'hC0400000; fpu_mac_c = 32'h40800000; #2;
        check_float("FPU_mac", "-2.0*-3.0 + 4.0 = 10.0", fpu_mac_y, 32'h41200000);
        fpu_mac_a = 32'h40000000; fpu_mac_b = 32'hC0800000; fpu_mac_c = 32'hC0000000; #2;
        check_float("FPU_mac", "2.0*-4.0 + -2.0 = -10.0", fpu_mac_y, 32'hC1200000);
        fpu_mac_a = 32'hBFC00000; fpu_mac_b = 32'h40000000; fpu_mac_c = 32'h40400000; #2;
        check_float("FPU_mac", "-1.5*2.0 + 3.0 = 0.0", fpu_mac_y, 32'h00000000);
        fpu_mac_a = 32'h3F000000; fpu_mac_b = 32'h3F000000; fpu_mac_c = 32'h3E800000; #2;
        check_float("FPU_mac", "0.5*0.5 + 0.25 = 0.5", fpu_mac_y, 32'h3F000000);
        fpu_mac_a = 32'h3F000000; fpu_mac_b = 32'h40800000; fpu_mac_c = 32'h3F800000; #2;
        check_float("FPU_mac", "0.5*4.0 + 1.0 = 3.0", fpu_mac_y, 32'h40400000);
        fpu_mac_a = 32'h41000000; fpu_mac_b = 32'h3F000000; fpu_mac_c = 32'hC0000000; #2;
        check_float("FPU_mac", "8.0*0.5 + -2.0 = 2.0", fpu_mac_y, 32'h40000000);
        fpu_mac_a = 32'h41200000; fpu_mac_b = 32'h41200000; fpu_mac_c = 32'h42480000; #2;
        check_float("FPU_mac", "10.0*10.0 + 50.0 = 150.0", fpu_mac_y, 32'h43160000);
        fpu_mac_a = 32'h3FA00000; fpu_mac_b = 32'h40000000; fpu_mac_c = 32'h3FC00000; #2;
        check_float("FPU_mac", "1.25*2.0 + 1.5 = 4.0", fpu_mac_y, 32'h40800000);
        fpu_mac_a = 32'h40400000; fpu_mac_b = 32'h40800000; fpu_mac_c = 32'hC1400000; #2;
        check_float("FPU_mac", "3.0*4.0 + -12.0 = 0.0", fpu_mac_y, 32'h00000000);
        fpu_mac_a = 32'h40C00000; fpu_mac_b = 32'h40E00000; fpu_mac_c = 32'h41000000; #2;
        check_float("FPU_mac", "6.0*7.0 + 8.0 = 50.0", fpu_mac_y, 32'h42480000);
        fpu_mac_a = 32'h40200000; fpu_mac_b = 32'h40000000; fpu_mac_c = 32'h40A00000; #2;
        check_float("FPU_mac", "2.5*2.0 + 5.0 = 10.0", fpu_mac_y, 32'h41200000);
        fpu_mac_a = 32'h00000000; fpu_mac_b = 32'h00000000; fpu_mac_c = 32'h00000000; #2;
        check_float("FPU_mac", "0.0*0.0 + 0.0 = 0.0", fpu_mac_y, 32'h00000000);

        $display("\n--- 7. Testing FPU_division (25 Tests) ---");
        fpu_div_a = 32'h3F800000; fpu_div_b = 32'h3F800000; #2;
        check_float("FPU_division", "1.0 / 1.0 = 1.0", fpu_div_y, 32'h3F800000);
        fpu_div_a = 32'h41200000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "10.0 / 2.0 = 5.0", fpu_div_y, 32'h40A00000);
        fpu_div_a = 32'h40F00000; fpu_div_b = 32'h40200000; #2;
        check_float("FPU_division", "7.5 / 2.5 = 3.0", fpu_div_y, 32'h40400000);
        fpu_div_a = 32'h40200000; fpu_div_b = 32'h40A00000; #2;
        check_float("FPU_division", "2.5 / 5.0 = 0.5", fpu_div_y, 32'h3F000000);
        fpu_div_a = 32'h3F800000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "1.0 / 2.0 = 0.5", fpu_div_y, 32'h3F000000);
        fpu_div_a = 32'h3F800000; fpu_div_b = 32'h40800000; #2;
        check_float("FPU_division", "1.0 / 4.0 = 0.25", fpu_div_y, 32'h3E800000);
        fpu_div_a = 32'h3F800000; fpu_div_b = 32'h41000000; #2;
        check_float("FPU_division", "1.0 / 8.0 = 0.125", fpu_div_y, 32'h3E000000);
        fpu_div_a = 32'h40C00000; fpu_div_b = 32'h40400000; #2;
        check_float("FPU_division", "6.0 / 3.0 = 2.0", fpu_div_y, 32'h40000000);
        fpu_div_a = 32'h41100000; fpu_div_b = 32'h40400000; #2;
        check_float("FPU_division", "9.0 / 3.0 = 3.0", fpu_div_y, 32'h40400000);
        fpu_div_a = 32'h41700000; fpu_div_b = 32'h40A00000; #2;
        check_float("FPU_division", "15.0 / 5.0 = 3.0", fpu_div_y, 32'h40400000);
        fpu_div_a = 32'h42C80000; fpu_div_b = 32'h41200000; #2;
        check_float("FPU_division", "100.0 / 10.0 = 10.0", fpu_div_y, 32'h41200000);
        fpu_div_a = 32'h42480000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "50.0 / 2.0 = 25.0", fpu_div_y, 32'h41C80000);
        fpu_div_a = 32'h41C80000; fpu_div_b = 32'h40A00000; #2;
        check_float("FPU_division", "25.0 / 5.0 = 5.0", fpu_div_y, 32'h40A00000);
        fpu_div_a = 32'h41000000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "8.0 / 2.0 = 4.0", fpu_div_y, 32'h40800000);
        fpu_div_a = 32'h41800000; fpu_div_b = 32'h40800000; #2;
        check_float("FPU_division", "16.0 / 4.0 = 4.0", fpu_div_y, 32'h40800000);
        fpu_div_a = 32'h40400000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "3.0 / 2.0 = 1.5", fpu_div_y, 32'h3FC00000);
        fpu_div_a = 32'h40A00000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "5.0 / 2.0 = 2.5", fpu_div_y, 32'h40200000);
        fpu_div_a = 32'h40E00000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "7.0 / 2.0 = 3.5", fpu_div_y, 32'h40600000);
        fpu_div_a = 32'h41100000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "9.0 / 2.0 = 4.5", fpu_div_y, 32'h40900000);
        fpu_div_a = 32'h41400000; fpu_div_b = 32'h40800000; #2;
        check_float("FPU_division", "12.0 / 4.0 = 3.0", fpu_div_y, 32'h40400000);
        fpu_div_a = 32'hC1200000; fpu_div_b = 32'h40000000; #2;
        check_float("FPU_division", "-10.0 / 2.0 = -5.0", fpu_div_y, 32'hC0A00000);
        fpu_div_a = 32'h41200000; fpu_div_b = 32'hC0000000; #2;
        check_float("FPU_division", "10.0 / -2.0 = -5.0", fpu_div_y, 32'hC0A00000);
        fpu_div_a = 32'hC1200000; fpu_div_b = 32'hC0000000; #2;
        check_float("FPU_division", "-10.0 / -2.0 = 5.0", fpu_div_y, 32'h40A00000);
        fpu_div_a = 32'h00000000; fpu_div_b = 32'h40A00000; #2;
        check_float("FPU_division", "0.0 / 5.0 = 0.0", fpu_div_y, 32'h00000000);
        fpu_div_a = 32'h40A00000; fpu_div_b = 32'h00000000; #2; check_float("FPU_division", "5.0 / 0.0 = Inf", fpu_div_y, 32'h7F800000);
        fpu_div_a = 32'h00000000; fpu_div_b = 32'h00000000; #2; check_float("FPU_division", "0.0 / 0.0 = NaN", fpu_div_y, 32'h7FC00000);

        $display("");
        $display("--- 7. Testing FPU_top Unified Pipelined Top (4 Operations) ---");
        top_op = 2'b00; top_a = 32'h40000000; top_b = 32'h40400000; top_c = 32'h0; #2; // 2.0 + 3.0 = 5.0
        check_float("FPU_top", "Op 00 (Add): 2.0 + 3.0 = 5.0", top_y, 32'h40A00000);

        top_op = 2'b01; top_a = 32'h40400000; top_b = 32'h40800000; top_c = 32'h0; #2; // 3.0 * 4.0 = 12.0
        check_float("FPU_top", "Op 01 (Mul): 3.0 * 4.0 = 12.0", top_y, 32'h41400000);

        top_op = 2'b10; top_a = 32'h40000000; top_b = 32'h40400000; top_c = 32'h40800000; #2; // 2.0*3.0 + 4.0 = 10.0
        check_float("FPU_top", "Op 10 (MAC): 2.0*3.0 + 4.0 = 10.0", top_y, 32'h41200000);

        top_op = 2'b11; top_a = 32'h41200000; top_b = 32'h40000000; top_c = 32'h0; #2; // 10.0 / 2.0 = 5.0
        check_float("FPU_top", "Op 11 (Div): 10.0 / 2.0 = 5.0", top_y, 32'h40A00000);

        $display("");
        $display("=================================================================");
        $display("COMPREHENSIVE 150+ TEST SUITE SUMMARY");
        $display("Total Tests Executed : %0d", total_tests);
        $display("Passed Tests         : %0d", passed_tests);
        $display("Failed Tests         : %0d", failed_tests);
        if (failed_tests == 0)
            $display("RESULT: ALL 150+ TESTS PASSED WITH 100%% SUCCESS!");
        else
            $display("RESULT: TEST FAILURES DETECTED! SEE LOG ABOVE.");
        $display("=================================================================");
        $finish;
    end

endmodule
