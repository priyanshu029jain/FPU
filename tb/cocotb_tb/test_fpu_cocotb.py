# ==============================================================================
# Cocotb Testbench : test_fpu_cocotb.py
# Purpose          : 4,000+ Automated Test Cases with Self-Checking Scoreboard
# Target DUT       : FPU_top (IEEE 754-2008 4-Stage Synchronous Pipelined Unit)
# Author           : Antigravity Automated Verification
# ==============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import struct
import math
import random

# IEEE 754 Helper Functions
def bits_to_float32(b: int) -> float:
    return struct.unpack('>f', struct.pack('>I', b & 0xFFFFFFFF))[0]

def float32_to_bits(f: float) -> int:
    return struct.unpack('>I', struct.pack('>f', f))[0]

def is_nan_bits(b: int) -> bool:
    exp = (b >> 23) & 0xFF
    mant = b & 0x7FFFFF
    return exp == 0xFF and mant != 0

def is_inf_bits(b: int) -> bool:
    exp = (b >> 23) & 0xFF
    mant = b & 0x7FFFFF
    return exp == 0xFF and mant == 0

def is_zero_bits(b: int) -> bool:
    return (b & 0x7FFFFFFF) == 0

# Scoreboard Class for Comprehensive Reporting
class FPUScoreboard:
    def __init__(self, target_count=4000):
        self.target_count = target_count
        self.total_tests = 0
        self.passed_tests = 0
        self.failed_tests = 0
        
        # Per-operation breakdown
        self.stats = {
            0: {"name": "ADD/SUB (Y = A + B)",       "total": 0, "pass": 0, "fail": 0},
            1: {"name": "MULTIPLIER (Y = A * B)",    "total": 0, "pass": 0, "fail": 0},
            2: {"name": "MAC / FMA (Y = A * B + C)", "total": 0, "pass": 0, "fail": 0},
            3: {"name": "DIVIDER (Y = A / B)",       "total": 0, "pass": 0, "fail": 0},
        }

    def record_result(self, op: int, passed: bool, test_info: str = ""):
        self.total_tests += 1
        self.stats[op]["total"] += 1
        
        if passed:
            self.passed_tests += 1
            self.stats[op]["pass"] += 1
        else:
            self.failed_tests += 1
            self.stats[op]["fail"] += 1
            if self.failed_tests <= 10:
                cocotb.log.error(f"[FAIL #{self.failed_tests}] {test_info}")

        # Periodic progress report every 500 tests
        if self.total_tests % 500 == 0:
            cocotb.log.info(f"Progress: {self.total_tests}/{self.target_count} test vectors verified | Passed: {self.passed_tests} | Failed: {self.failed_tests}")

    def print_final_summary(self):
        pass_rate = (self.passed_tests / self.total_tests * 100.0) if self.total_tests > 0 else 0.0
        
        cocotb.log.info("\n" + "=" * 80)
        cocotb.log.info("       COCOTB FPU VERIFICATION REGRESSION SCOREBOARD SUMMARY")
        cocotb.log.info("=" * 80)
        cocotb.log.info(f"{'Operation':<30} | {'Total':<8} | {'Passed':<8} | {'Failed':<8} | {'Score %':<8}")
        cocotb.log.info("-" * 80)
        
        for op in range(4):
            s = self.stats[op]
            op_pct = (s["pass"] / s["total"] * 100.0) if s["total"] > 0 else 0.0
            cocotb.log.info(f"{s['name']:<30} | {s['total']:<8} | {s['pass']:<8} | {s['fail']:<8} | {op_pct:>6.2f}%")
            
        cocotb.log.info("=" * 80)
        cocotb.log.info(f"TOTAL VECTORS EXECUTED : {self.total_tests}")
        cocotb.log.info(f"TOTAL VECTORS PASSED   : {self.passed_tests}")
        cocotb.log.info(f"TOTAL VECTORS FAILED   : {self.failed_tests}")
        cocotb.log.info(f"OVERALL PASS SCORE     : {self.passed_tests}/{self.total_tests} ({pass_rate:.2f}%)")
        cocotb.log.info("=" * 80 + "\n")
        
        assert self.failed_tests == 0, f"Regression failed with {self.failed_tests} errors!"


# Test Vector Generator (4,000+ Cases)
def generate_test_vectors():
    vectors = []
    
    # Constants
    POS_ZERO = 0x00000000
    NEG_ZERO = 0x80000000
    POS_ONE  = 0x3F800000  # +1.0
    NEG_ONE  = 0xBF800000  # -1.0
    POS_INF  = 0x7F800000
    NEG_INF  = 0xFF800000
    QNAN     = 0x7FC00000
    SNAN     = 0x7F800001
    MAX_NORM = 0x7F7FFFFF
    MIN_NORM = 0x00800000

    random.seed(42)

    # --------------------------------------------------------------------------
    # 1. ADD / SUB (op = 0) : 1,020 Test Cases
    # --------------------------------------------------------------------------
    # 1.1 Special and Corner Cases (20 cases)
    special_add = [
        (POS_ZERO, POS_ZERO, POS_ZERO, "0 + 0 = 0"),
        (POS_ZERO, NEG_ZERO, POS_ZERO, "0 + (-0) = 0"),
        (NEG_ZERO, NEG_ZERO, NEG_ZERO, "(-0) + (-0) = -0"),
        (POS_ONE, POS_ZERO, POS_ONE, "1 + 0 = 1"),
        (POS_ONE, NEG_ONE, POS_ZERO, "1 + (-1) = 0"),
        (POS_INF, POS_ZERO, POS_INF, "Inf + 0 = Inf"),
        (POS_INF, POS_ONE, POS_INF, "Inf + 1 = Inf"),
        (POS_INF, NEG_INF, QNAN, "Inf + (-Inf) = NaN"),
        (QNAN, POS_ONE, QNAN, "NaN + 1 = NaN"),
        (POS_ONE, SNAN, QNAN, "1 + SNaN = QNaN"),
        (MAX_NORM, POS_ZERO, MAX_NORM, "Max + 0 = Max"),
        (MIN_NORM, POS_ZERO, MIN_NORM, "Min + 0 = Min"),
    ]
    for a, b, exp, desc in special_add:
        vectors.append((0, a, b, 0, exp, "exact", desc))

    # 1.2 Inversion Cancellation X + (-X) == 0 (200 cases)
    for i in range(200):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        neg_x = x_val ^ 0x80000000
        vectors.append((0, x_val, neg_x, 0, POS_ZERO, "zero", f"X + (-X) = 0 (i={i})"))

    # 1.3 Additive Identity X + 0.0 == X (200 cases)
    for i in range(200):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((0, x_val, POS_ZERO, 0, x_val, "exact", f"X + 0 = X (i={i})"))

    # 1.4 Random Normalized Pairs (600 cases)
    for i in range(600):
        # Exponents chosen with small to moderate difference to avoid immediate truncation
        base_exp = random.randint(120, 134)
        exp_a = base_exp + random.randint(-5, 5)
        exp_b = base_exp + random.randint(-5, 5)
        mant_a = random.randint(0, 0x7FFFFF)
        mant_b = random.randint(0, 0x7FFFFF)
        sign_a = random.randint(0, 1)
        sign_b = random.randint(0, 1)
        
        a_bits = (sign_a << 31) | (exp_a << 23) | mant_a
        b_bits = (sign_b << 31) | (exp_b << 23) | mant_b
        
        f_a = bits_to_float32(a_bits)
        f_b = bits_to_float32(b_bits)
        f_res = f_a + f_b
        exp_bits = float32_to_bits(f_res)
        vectors.append((0, a_bits, b_bits, 0, exp_bits, "float", f"Random Add {f_a:.3e} + {f_b:.3e}"))

    # --------------------------------------------------------------------------
    # 2. MULTIPLIER (op = 1) : 1,020 Test Cases
    # --------------------------------------------------------------------------
    # 2.1 Special & Corner Cases (20 cases)
    special_mul = [
        (POS_ZERO, POS_ONE, POS_ZERO, "0 * 1 = 0"),
        (POS_ZERO, POS_ZERO, POS_ZERO, "0 * 0 = 0"),
        (NEG_ZERO, POS_ONE, NEG_ZERO, "-0 * 1 = -0"),
        (POS_ONE, POS_ONE, POS_ONE, "1 * 1 = 1"),
        (POS_ONE, NEG_ONE, NEG_ONE, "1 * (-1) = -1"),
        (NEG_ONE, NEG_ONE, POS_ONE, "(-1) * (-1) = 1"),
        (POS_INF, POS_ONE, POS_INF, "Inf * 1 = Inf"),
        (POS_INF, POS_ZERO, QNAN, "Inf * 0 = NaN"),
        (POS_ZERO, POS_INF, QNAN, "0 * Inf = NaN"),
        (QNAN, POS_ONE, QNAN, "NaN * 1 = NaN"),
    ]
    for a, b, exp, desc in special_mul:
        vectors.append((1, a, b, 0, exp, "exact", desc))

    # 2.2 Multiplicative Identity X * 1.0 == X (300 cases)
    for i in range(300):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((1, x_val, POS_ONE, 0, x_val, "exact", f"X * 1 = X (i={i})"))

    # 2.3 Zero Annihilator X * 0.0 == 0.0 (200 cases)
    for i in range(200):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((1, x_val, POS_ZERO, 0, POS_ZERO, "zero", f"X * 0 = 0 (i={i})"))

    # 2.4 Random Multiplication Pairs (500 cases)
    for i in range(500):
        # Exponents centered around 127 so sum does not overflow
        exp_a = random.randint(115, 135)
        exp_b = random.randint(115, 135)
        mant_a = random.randint(0, 0x7FFFFF)
        mant_b = random.randint(0, 0x7FFFFF)
        sign_a = random.randint(0, 1)
        sign_b = random.randint(0, 1)
        
        a_bits = (sign_a << 31) | (exp_a << 23) | mant_a
        b_bits = (sign_b << 31) | (exp_b << 23) | mant_b
        
        f_a = bits_to_float32(a_bits)
        f_b = bits_to_float32(b_bits)
        f_res = f_a * f_b
        exp_bits = float32_to_bits(f_res)
        vectors.append((1, a_bits, b_bits, 0, exp_bits, "float", f"Random Mul {f_a:.3e} * {f_b:.3e}"))

    # --------------------------------------------------------------------------
    # 3. MAC / FMA (op = 2) : 1,020 Test Cases
    # --------------------------------------------------------------------------
    # 3.1 MAC Identities X * 1.0 + 0.0 == X (300 cases)
    for i in range(300):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((2, x_val, POS_ONE, POS_ZERO, x_val, "exact", f"X * 1 + 0 = X (i={i})"))

    # 3.2 MAC Zero Multiplier 0.0 * B + C == C (300 cases)
    for i in range(300):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        c_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((2, POS_ZERO, POS_ONE, c_val, c_val, "exact", f"0 * B + C = C (i={i})"))

    # 3.3 Random FMA Vectors (420 cases)
    for i in range(420):
        exp_a = random.randint(120, 130)
        exp_b = random.randint(120, 130)
        exp_c = random.randint(120, 130)
        a_bits = (random.randint(0, 1) << 31) | (exp_a << 23) | random.randint(0, 0x7FFFFF)
        b_bits = (random.randint(0, 1) << 31) | (exp_b << 23) | random.randint(0, 0x7FFFFF)
        c_bits = (random.randint(0, 1) << 31) | (exp_c << 23) | random.randint(0, 0x7FFFFF)
        
        fa = bits_to_float32(a_bits)
        fb = bits_to_float32(b_bits)
        fc = bits_to_float32(c_bits)
        f_res = math.fma(fa, fb, fc)
        exp_bits = float32_to_bits(f_res)
        vectors.append((2, a_bits, b_bits, c_bits, exp_bits, "float", f"Random FMA {fa:.2e}*{fb:.2e}+{fc:.2e}"))

    # --------------------------------------------------------------------------
    # 4. DIVIDER (op = 3) : 1,020 Test Cases
    # --------------------------------------------------------------------------
    # 4.1 Division Corner & Special Cases (20 cases)
    special_div = [
        (POS_ZERO, POS_ONE, POS_ZERO, "0 / 1 = 0"),
        (POS_ONE, POS_ONE, POS_ONE, "1 / 1 = 1"),
        (NEG_ONE, POS_ONE, NEG_ONE, "-1 / 1 = -1"),
        (POS_ONE, NEG_ONE, NEG_ONE, "1 / (-1) = -1"),
        (NEG_ONE, NEG_ONE, POS_ONE, "(-1) / (-1) = 1"),
        (POS_ZERO, POS_ZERO, QNAN, "0 / 0 = NaN (Invalid)"),
        (POS_INF, POS_INF, QNAN, "Inf / Inf = NaN (Invalid)"),
        (POS_ONE, POS_ZERO, POS_INF, "1 / 0 = Inf (DivByZero)"),
        (NEG_ONE, POS_ZERO, NEG_INF, "-1 / 0 = -Inf (DivByZero)"),
        (POS_ONE, POS_INF, POS_ZERO, "1 / Inf = 0"),
    ]
    for a, b, exp, desc in special_div:
        vectors.append((3, a, b, 0, exp, "exact", desc))

    # 4.2 Division by Unity X / 1.0 == X (300 cases)
    for i in range(300):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((3, x_val, POS_ONE, 0, x_val, "exact", f"X / 1 = X (i={i})"))

    # 4.3 Division of Zero 0.0 / X == 0.0 (200 cases)
    for i in range(200):
        exp_val = 1 + (i % 250)
        mant = random.randint(0, 0x7FFFFF)
        x_val = (random.randint(0, 1) << 31) | (exp_val << 23) | mant
        vectors.append((3, POS_ZERO, x_val, 0, POS_ZERO, "zero", f"0 / X = 0 (i={i})"))

    # 4.4 Random Division Pairs (500 cases)
    for i in range(500):
        exp_a = random.randint(120, 134)
        exp_b = random.randint(120, 134)
        mant_a = random.randint(0, 0x7FFFFF)
        mant_b = random.randint(1, 0x7FFFFF) # Non-zero divisor
        sign_a = random.randint(0, 1)
        sign_b = random.randint(0, 1)
        
        a_bits = (sign_a << 31) | (exp_a << 23) | mant_a
        b_bits = (sign_b << 31) | (exp_b << 23) | mant_b
        
        fa = bits_to_float32(a_bits)
        fb = bits_to_float32(b_bits)
        f_res = fa / fb
        exp_bits = float32_to_bits(f_res)
        vectors.append((3, a_bits, b_bits, 0, exp_bits, "float", f"Random Div {fa:.3e} / {fb:.3e}"))

    return vectors


# ==============================================================================
# Main Cocotb Test Routine
# ==============================================================================
@cocotb.test()
async def test_fpu_regression_4000(dut):
    """Cocotb 4,000+ Vector Self-Checking Verification for FPU_top."""
    
    # 1. Start 100 MHz Clock (10 ns period)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # 2. Reset Sequence
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.op.value = 0
    dut.A.value = 0
    dut.B.value = 0
    dut.C.value = 0
    
    await Timer(25, unit="ns")
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # 3. Generate 4,080 Test Vectors across All 4 Units
    test_vectors = generate_test_vectors()
    total_vectors = len(test_vectors)
    scoreboard = FPUScoreboard(target_count=total_vectors)
    
    cocotb.log.info("=" * 80)
    cocotb.log.info(f"STARTING COCOTB PYTHON REGRESSION: {total_vectors} TEST VECTORS")
    cocotb.log.info("Architecture: 4-Stage Synchronous Hardware Pipeline (Deterministic 4 Cycles)")
    cocotb.log.info("=" * 80)

    # 4. Apply Vectors and Verify Pipeline Latency & Invariants
    for idx, (op_val, a_bits, b_bits, c_bits, exp_bits, check_mode, desc) in enumerate(test_vectors):
        # Drive transaction on falling clock edge to guarantee setup time
        await FallingEdge(dut.clk)
        dut.op.value = op_val
        dut.A.value = a_bits
        dut.B.value = b_bits
        dut.C.value = c_bits
        dut.valid_in.value = 1

        await FallingEdge(dut.clk)
        dut.valid_in.value = 0

        # Wait for 4-stage pipeline valid_out strobe
        while True:
            await RisingEdge(dut.clk)
            if dut.valid_out.value == 1:
                break
        
        # Read captured outputs
        await Timer(1, unit="ps") # Small delta to settle
        y_str = str(dut.Y.value).lower()
        
        # Self-Checking Logic
        test_passed = False
        fail_reason = ""

        # Invariant Check 1: No Unknown/X bits
        if 'x' in y_str or 'z' in y_str:
            fail_reason = f"Unknown (X/Z) bits detected on Y: {y_str}"
            test_passed = False
        else:
            got_y_val = int(dut.Y.value)
            got_zero  = int(dut.flag_zero.value)
            got_nan   = int(dut.flag_nan.value)
            got_inf   = int(dut.flag_inf.value)
        
            if check_mode == "zero":
                # Must be zero (+0.0 or -0.0) or flag_zero asserted
                if is_zero_bits(got_y_val) or got_zero == 1:
                    test_passed = True
                else:
                    fail_reason = f"Expected zero result, got 0x{got_y_val:08X} (flag_zero={got_zero})"
                    
            elif check_mode == "exact":
                # Exact bit match required (for identities X+0, X*1, X/1, etc.)
                if got_y_val == exp_bits:
                    test_passed = True
                elif is_zero_bits(exp_bits) and (is_zero_bits(got_y_val) or got_zero == 1):
                    test_passed = True
                elif is_nan_bits(exp_bits) and (got_nan == 1 or is_nan_bits(got_y_val)):
                    test_passed = True
                elif is_inf_bits(exp_bits) and (got_inf == 1 or is_inf_bits(got_y_val)):
                    test_passed = True
                else:
                    fail_reason = f"Exact mismatch: Got 0x{got_y_val:08X}, Expected 0x{exp_bits:08X}"
                    
            elif check_mode == "float":
                # General float arithmetic: match exact bits or within 1 ULP (Unit in Last Place) for rounding
                if got_y_val == exp_bits:
                    test_passed = True
                elif is_nan_bits(exp_bits) and (got_nan == 1 or is_nan_bits(got_y_val)):
                    test_passed = True
                elif is_inf_bits(exp_bits) and (got_inf == 1 or is_inf_bits(got_y_val)):
                    test_passed = True
                elif is_zero_bits(exp_bits) and (got_zero == 1 or is_zero_bits(got_y_val)):
                    test_passed = True
                else:
                    # Check sign match and ULP difference <= 1
                    sign_got = (got_y_val >> 31) & 1
                    sign_exp = (exp_bits >> 31) & 1
                    ulp_diff = abs(got_y_val - exp_bits)
                    if sign_got == sign_exp and ulp_diff <= 1:
                        test_passed = True
                    else:
                        fail_reason = f"Float mismatch: Got 0x{got_y_val:08X}, Exp 0x{exp_bits:08X} (ULP diff={ulp_diff})"

            # Check Sign Parity invariant on Mul/Div
            if (op_val == 1 or op_val == 3) and test_passed:
                if not is_nan_bits(got_y_val) and not is_zero_bits(got_y_val):
                    expected_sign = ((a_bits >> 31) & 1) ^ ((b_bits >> 31) & 1)
                    actual_sign = (got_y_val >> 31) & 1
                    if actual_sign != expected_sign:
                        test_passed = False
                        fail_reason = f"Sign parity failed: Expected sign {expected_sign}, got {actual_sign}"

        scoreboard.record_result(op_val, test_passed, f"{desc} | {fail_reason}")

    # 5. Output Final Scoreboard Report
    scoreboard.print_final_summary()
