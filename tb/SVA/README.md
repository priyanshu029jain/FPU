# SystemVerilog Assertions (SVA) Verification Suite

This directory contains formal and simulation-based **SystemVerilog Assertions (SVA)** for the IEEE 754 4-Stage Synchronous Pipelined Floating-Point Unit (FPU).

## Overview
SystemVerilog Assertions provide cycle-accurate protocol and property checking:
- **Interface Protocol Assertions**:
  - Reset behavior (`!rst_n |-> ##1 (valid_out == 0 && Y == 0)`).
  - 4-cycle pipeline latency invariant (`valid_in |-> ##4 valid_out`).
  - Throughput / back-to-back streaming validity.
- **Data & Arithmetic Invariants**:
  - Unknown state (`$isunknown`) prevention on output buses.
  - Sign parity property for multiplier and divider ($S_y = S_a \oplus S_b$).
  - IEEE 754 special values and decomposed exception flag consistency (`flag_zero`, `flag_inf`, `flag_nan`, `flag_invalid`, `flag_overflow`, `flag_underflow`, `flag_inexact`, `flag_div_by_zero`).
