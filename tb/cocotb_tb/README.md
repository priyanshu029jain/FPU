# Cocotb Python Verification Environment (4,000+ Vectors)

This directory contains the Python-based **Cocotb (Coroutine Co-simulation Testbench)** regression suite for the unified 4-stage pipelined **`FPU_top`** core.

---

## 🚀 Features

- **Framework**: `cocotb 2.1.0` + `cocotb-tools` with **Icarus Verilog 12.0**
- **Test Volume**: **4,052 automated test vectors** (>1,000 vectors per arithmetic unit)
- **Scoreboard**: Object-oriented `FPUScoreboard` tracking per-operation and total pass/fail rates with periodic progress reporting
- **Self-Checking Oracle**:
  - IEEE 754 reference model using Python `struct` and native `math.fma`
  - Invariant checks: unknown (X/Z) bit rejection, sign parity ($S_Y = S_A \oplus S_B$), zero flag assertion
  - Boundary ULP tolerance on rounding margins and exact bit matching on identities

---

## 📊 Summary of Execution

```
================================================================================
       COCOTB FPU VERIFICATION REGRESSION SCOREBOARD SUMMARY
================================================================================
Operation                      | Total    | Passed   | Failed   | Score % 
--------------------------------------------------------------------------------
ADD/SUB (Y = A + B)            | 1012     | 1012     | 0        | 100.00%
MULTIPLIER (Y = A * B)         | 1010     | 1010     | 0        | 100.00%
MAC / FMA (Y = A * B + C)      | 1020     | 1020     | 0        | 100.00%
DIVIDER (Y = A / B)            | 1010     | 1010     | 0        | 100.00%
================================================================================
TOTAL VECTORS EXECUTED : 4052
TOTAL VECTORS PASSED   : 4052
TOTAL VECTORS FAILED   : 0
OVERALL PASS SCORE     : 4052/4052 (100.00%)
================================================================================
```

---

## 🏃 Running the Cocotb Suite

From the workspace root:

```bash
# Via the unified launcher:
./run cocotb

# Or directly with Python:
python tb/cocotb_tb/run_cocotb.py
```
