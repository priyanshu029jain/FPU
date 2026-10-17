# 32-Bit IEEE 754 Pipelined Floating-Point Unit (FPU)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Verilator](https://img.shields.io/badge/Linter-Verilator_5.032-orange.svg)](https://www.veripool.org/verilator/)
[![Icarus Verilog](https://img.shields.io/badge/Simulator-Icarus_Verilog_12.0-blueviolet.svg)](http://iverilog.icarus.com/)
[![Synthesis](https://img.shields.io/badge/Synthesis-Yosys_0.52-yellow.svg)](https://yosyshq.net/yosys/)
[![STA](https://img.shields.io/badge/STA-OpenSTA-brightgreen.svg)](https://github.com/The-OpenROAD-Project/OpenSTA)
[![PDK](https://img.shields.io/badge/PDK-SkyWater_130nm-red.svg)](https://github.com/google/skywater-pdk)

A pipelined **32-bit single-precision floating-point unit** in synthesizable Verilog, supporting add/subtract, multiply, divide and fused multiply-add (FMA) with Round-to-Nearest-Even rounding and IEEE-style status flags. The project also contains a multi-tier verification suite and an open-source ASIC flow (Yosys + OpenSTA on SkyWater 130nm).

This is a learning / portfolio project, not a fully IEEE 754-compliant production core. The [Known Limitations](#-known-limitations) and [Verification Status](#-verification-status-claimed-vs-measured) sections below document exactly where the design deviates from the standard, based on a re-run of every test and synthesis script plus an independent bit-exact audit (2026-10-18).

---

## 📑 Table of Contents
1. [At a Glance](#-at-a-glance)
2. [Architecture](#-architecture)
3. [Module Directory](#-module-directory)
4. [Verification Status (Claimed vs. Measured)](#-verification-status-claimed-vs-measured)
5. [Known Limitations](#-known-limitations)
6. [ASIC Synthesis Results (SkyWater 130nm)](#-asic-synthesis-results-skywater-130nm)
7. [Getting Started](#-getting-started)
8. [Documentation](#-documentation)
9. [License](#-license)

---

## ✅ At a Glance

| Aspect | Status |
|---|---|
| Operations | ADD/SUB, MUL, DIV, FMA (`Y = A*B + C`, single rounding) selected by a 2-bit opcode |
| Pipeline | 4 register stages for every op: `valid_out` rises on the 4th rising edge counting the edge that captures the input. **1 op/cycle** throughput, including back-to-back mixed opcodes (verified) |
| Rounding | Round-to-Nearest-Even only (no other IEEE rounding modes) |
| Normal inputs → normal results | **Bit-exact** for ADD, MUL, DIV in independent audit; FMA has a large-exponent-gap bug (see limitations) |
| Subnormals | **Not supported.** Subnormal results are flushed to zero; subnormal inputs can produce wrong results |
| Special values | ±0, ±∞, NaN handled; canonical qNaN `0x7FC00000` output |
| Flags | zero, inf, nan, invalid, overflow, underflow, inexact, div-by-zero |
| Timing @ 100 MHz (Sky130, pre-layout) | Adder **meets**; multiplier misses by 0.38 ns; MAC and divider miss by a wide margin |
| Full `FPU_top` f<sub>max</sub> | **~9.95 MHz** (min period 100.5 ns; 9.45 MHz with `timing.sdc`), limited by the divider |
| Formal verification | **None.** Assertions are checked in simulation only (no `.sby` / SymbiYosys files) |

---

## 🏗️ Architecture

### Number format
IEEE 754 binary32: 1 sign bit, 8-bit biased exponent (bias 127), 23-bit fraction, implicit leading 1 for normal numbers:

$$V = (-1)^S \times 2^{E - 127} \times (1.M)$$

Rounding uses Guard/Round/Sticky bits with the RNE increment rule $G \land (L \lor R \lor S)$, where $L$ is the result LSB.

### Top level: [`FPU_top`](rtl/FPU_top.v)

| `op` | Operation | Unit |
|:---:|---|---|
| `00` | `Y = A + B` (subtraction via operand sign) | [`FPU_adder`](rtl/FPU_adder.v) |
| `01` | `Y = A * B` | [`FPU_multiplier`](rtl/FPU_multiplier.v) |
| `10` | `Y = A * B + C` (fused, single rounding) | [`FPU_mac`](rtl/FPU_mac.v) |
| `11` | `Y = A / B` | [`FPU_division`](rtl/FPU_division.v) |

All four units are instantiated in parallel. `valid_in` is gated by the opcode, the opcode is delayed through a 4-deep shift register, and a combinational multiplexer selects the matching unit's result and flags. `flag_inf` / `flag_nan` are derived from the final `Y`. Note that because the units run in parallel, the slowest unit (the divider) sets the clock period of `FPU_top`.

### 4-stage pipeline (common structure)

```
          STAGE 1                 STAGE 2                 STAGE 3                 STAGE 4
     +---------------+       +---------------+       +---------------+       +---------------+
     | Unpack, detect|       | Core mantissa |       | Normalize     |       | RNE round,    |
A,B->| specials,     |==r1==>| operation     |==r2==>| (LZD + shift),|==r3==>| pack, flags   |==> Y, flags
(C)  | align / exp   |       |               |       | exponent adj. |       | (registered)  |
     +---------------+       +---------------+       +---------------+       +---------------+
```

| Unit | Stage 1 | Stage 2 | Stage 3 | Stage 4 |
|---|---|---|---|---|
| Adder | Unpack, exponent compare, 49-bit alignment shift + sticky | 27-bit add/sub, LZD | Normalization shift, exponent adjust | RNE round, pack, flags |
| Multiplier | Unpack, specials, exponent add | 24×24 multiply | 1-bit normalize, GRS extraction | RNE round, pack, flags |
| Divider | Unpack, exponent subtract | **All 26 restoring-division iterations (combinational loop)** | Normalize, GRS | RNE round, pack, flags |
| FMA | Unpack, 24×24 multiply, product exponent | 100-bit alignment of product / addend | 100-bit add/sub, LZD | 100-bit normalize, round, pack |

Special operands (NaN, ∞, 0) are detected in Stage 1 and carried down the pipeline as a bypass value that replaces the computed result in Stage 4.

**Implementation note:** arithmetic is written behaviourally (`*`, `+`, `>>`, priority loops). There are no hand-built carry-save, CLA, Wallace or tree-LZD structures; the gate-level structure is whatever Yosys/ABC infers.

---

## 📂 Module Directory

```
floating_point_unit/
├── rtl/                      # 4-stage arithmetic units + top level
│   ├── FPU_top.v             # Opcode router / output mux
│   ├── FPU_adder.v           # Adder / subtractor
│   ├── FPU_multiplier.v      # Multiplier
│   ├── FPU_division.v        # Divider (restoring, single-stage iteration loop)
│   └── FPU_mac.v             # Fused multiply-add
├── component/                # Parameterized building blocks
│   ├── param_adder_sub.v     # N-bit add/sub with carry and signed overflow
│   ├── param_multiplier.v    # Signed/unsigned multiplier
│   ├── barrel_shifter.v      # Left/right, logical/arithmetic shifter with sticky output
│   ├── leading_zero_detector.v
│   ├── input_convertor.v     # Int32 / Q16.16 -> float  (standalone, NOT instantiated in FPU_top)
│   └── output_convertor.v    # float -> Int32 / Q16.16  (standalone, NOT instantiated in FPU_top)
├── tb/
│   ├── sim_tb/               # Tier 1: unit/component directed tests
│   ├── CRV_tb/               # Tier 2: random stimulus with property checks
│   ├── large_cases/          # Tier 3: identity-law regression (2,800 vectors)
│   ├── corner_case/          # Tier 4: per-unit corner cases
│   ├── SVA/                  # Tier 5: simulation-time SystemVerilog assertions (Verilator)
│   └── cocotb_tb/            # Tier 6: Python cocotb regression (4,052 vectors)
├── script/                   # Yosys synthesis + OpenSTA timing/power scripts, SDC
├── analysis/
│   ├── asic/                 # Generated area / timing / power reports
│   ├── test/                 # Saved test logs
│   └── FPGA/                 # Xilinx 7-series resource counts (Yosys synth_xilinx)
├── documantation/            # Per-module specifications
├── history.md                # Engineering log and bug post-mortems
├── notes.pdf                 # Handwritten derivations
├── run.sh / run              # Simulation / synthesis launcher
└── sky130.lib                # Sky130 HD Liberty (tt_025C_1v80)
```

---

## 🧪 Verification Status (Claimed vs. Measured)

Everything below was re-run on 2026-10-18 (Icarus Verilog 12.0, Verilator 5.032, cocotb 2.1, Yosys 0.52, OpenSTA).

### 1. Project test suites: all pass, all lint clean

| Tier | Testbench | Result |
|---|---|---|
| 1 | `tb_adder` / `tb_multiplier` / `tb_barrel_shifter` / `tb_LZD` | 64/64, 63/63, 62/62, 91/91 |
| 1 | `tb_fpu_adder` / `_multiplier` / `_division` / `_mac` | 36/36, 25/25, 24/24, 19/19 |
| 1 | `tb_fpu_top` (incl. converters) | 180/180 |
| 2 | `tb_crv_fpu` | 1,000/1,000 |
| 3 | `tb_large_cases` | 2,800/2,800 |
| 4 | `tb_corner_{adder,multiplier,division,mac,top}` | 93, 97, 92, 87, 128, all passing |
| 5 | `sva_{adder,multiplier,division,mac}` | 48 assertions (11/12/14/11), no assertion failures |
| 6 | `test_fpu_cocotb` | 4,052/4,052 |

Verilator `--lint-only -Wall` is clean on every testbench configuration.

### 2. What those suites actually check

A 100% pass rate is only as strong as the checks behind it:

| Tier | What it really verifies | Gap |
|---|---|---|
| 1 & 4 | Directed vectors with exact expected values (zeros, ∞, NaN, flags, random sign quadrants) | Corner suites contain **no subnormal cases**; `tb_corner_adder` test #14 expects `+0 + −0 = −0`, encoding the sign-of-zero bug |
| 2 CRV | Random operands (exponents 120-134) checked **only** for: no X on `Y`, sign of MUL/DIV, `flag_zero` consistent with `Y` | **No golden model: numerical correctness is not checked.** Uses `$urandom`, not the SV constraint solver |
| 3 Large | X+0=X, X+(−X)=0, X·1=X, X·0=0, X/1=X, FMA identities | Mostly exercises the special-case bypass path. No commutativity test (despite earlier claims) |
| 5 SVA | Concurrent assertions on latency, valid, flags, special cases; ~10 stimulus vectors per unit | Simulation only, **not formal verification** (no SymbiYosys/formal tool is run) |
| 6 cocotb | Random operands (exponents ~115-135) vs Python float reference | Accepts **±1 ULP**, accepts **any zero for any sign**, checks only zero/nan/inf flags, fixed seed, one op every ~5 cycles (no back-to-back streaming) |

### 3. Independent bit-exact audit

To test the claims the suites cannot, an extra cocotb bench was run against `FPU_top` using an **exact rational reference** (Python `Fraction`, correct RNE + subnormals; itself cross-checked against 597k host-float results). It requires **bit-exact** results (any NaN accepted for NaN), streams **one operation every cycle with random mixed opcodes**, and covers the full exponent range.

**Pipeline depth and throughput:**

| Check | Result |
|---|---|
| Latency, single op (ADD / MUL / FMA / DIV) | Identical for all four: `valid_out` rises **3 rising edges after the edge that samples `valid_in`** (4 register stages) ✅ |
| 32 same-op issues on consecutive cycles, for each op | 32 results on 32 consecutive cycles (`valid_out` never drops), identical to one-at-a-time issue ✅ |
| Repeating ADD→MUL→FMA→DIV, one per cycle | 16/16 results in order, identical to one-at-a-time issue ✅ |
| 20,000 random mixed-opcode ops, one per cycle | All returned in order with constant latency ✅ |

**Normal inputs only, full exponent range (12,000 ops):**

| Op | Bit-exact | Failures |
|---|:---:|---|
| ADD | **3000/3000 (100%)** | none |
| MUL | 2890/3000 | 110: result should be subnormal, got 0 |
| DIV | 2860/3000 | 140: result should be subnormal, got 0 |
| FMA | 2981/3000 | 19: **wrong value** when product exponent is far (> ~48) below C's |

**Mixed stimulus (20,000 ops: normal, full-range, tiny, huge, cancellation, raw bit patterns):** 93.2% bit-exact, 5.2% subnormal-flushed-to-zero, 1.6% wrong value (subnormal operands and the FMA bug). Overflow and div-by-zero flags were correct on every correctly computed result; the inexact flag was correct on all normal-only cases.

**Directed IEEE checks:**

| Case | Expected | Got |
|---|---|---|
| `+0 + −0` | `+0` (`00000000`) | `−0` (`80000000`) ❌ |
| `−0 + +0`, `−0 + −0`, `1 + −1`, `fma(+0,1,−0)` | per IEEE | correct ✅ |
| `0x00000001 + 0x00000001` | `0x00000002` | `0x00000000`, `flag_underflow=1` (flush-to-zero) ❌ |
| `0x00800000 * 0x3F000000` (min normal × 0.5) | `0x00400000` | `0x00000000`, `flag_underflow=1` (flush-to-zero) ❌ |
| `0x00800000 / 2.0`, `fma(0x00800000, 0.5, +0)`, `0x00000001 * 1.0` | subnormal | `0x00000000` (flush-to-zero) ❌ |
| `0x00400000 * 2.0` (subnormal in, normal out) | `0x00800000` | `0x00C00000`: **wrong value** ❌ |
| `qNaN + 1` | `invalid = 0` | `invalid = 1` ❌ |

**Formal verification:** the repository contains no `.sby` files and no SymbiYosys or other formal-tool setup. The SVA properties are only evaluated during simulation (`verilator --binary --assert`), so they cover only the stimulus the SVA testbenches drive.

---

## ⚠️ Known Limitations

1. **No subnormal results (flush-to-zero).** Any result with biased exponent 0 is output as ±0 and `flag_underflow` is raised. This affects all four units.
2. **Subnormal inputs are not handled correctly.** The units treat a subnormal's exponent field as 0 rather than the effective exponent 1 and do not normalize the significand, so `subnormal ⊕ normal` can return a wrong value (e.g. ADD `00540245 + 01A4B37C` → `01AF33C5`, expected `01B9B40D`).
3. **FMA alignment bug for large exponent gaps.** In [`FPU_mac.v`](rtl/FPU_mac.v) the absolute exponent difference `s2_abs_diff` is only 8 bits wide while the signed difference can exceed ±255, so it wraps. Example: `A=9B4E99D0, B=13D13455, C=7AAC7742` should return `C` exactly but returns `7AAC773F`.
4. **`+0 + −0` returns `−0`.** The adder's zero bypass returns `B` when `A` is zero; IEEE RNE requires `+0`.
5. **`flag_invalid` is raised for quiet NaN inputs.** IEEE only signals invalid for signaling NaNs and invalid operations (∞−∞, 0·∞, 0/0, ∞/∞).
6. **Round-to-Nearest-Even only.** No RTZ / RUP / RDN modes.
7. **Divider is not truly pipelined.** All 26 restoring iterations sit in one combinational stage (a ~100 ns path in Sky130), which limits `FPU_top` to ~10 MHz. MAC similarly concentrates a 100-bit normalize + round in one stage.
8. **Converters are standalone and do not round.** `input_convertor` / `output_convertor` are tested in `tb_fpu_top.v` but are not connected to `FPU_top`'s datapath.
   - `input_convertor` truncates integers wider than 24 bits (`0x7FFFFFFF` → `0x4EFFFFFF`; RNE gives `0x4F000000`).
   - `output_convertor` truncates toward zero and saturates negative overflow to `0x80000001` rather than INT_MIN. It also flags the exactly representable −2³¹ as overflow.

---

## ⚡ ASIC Synthesis Results (SkyWater 130nm)

Flow: Yosys 0.52 (`synth_fpu_*.tcl`) → OpenSTA (`sta_fpu_*.tcl`) using `sky130_fd_sc_hd__tt_025C_1v80`. All numbers below were reproduced exactly by re-running the scripts.

**Caveats:** these are **pre-layout, synthesis-only** results (no placement, routing or wire parasitics). The per-unit STA scripts use a plain 10 ns clock with zero I/O delay and **do not load [`timing.sdc`](script/timing.sdc)** (no clock uncertainty or derating), and ABC is run without a delay target, so timing is optimistic. `timing.sdc` itself is not OpenSTA-compatible as written: it uses the Synopsys-only command `remove_from_collection`, so its input-delay and driving-cell lines fail. OpenSTA's equivalent is `delete_from_list`.

### Area
Gate equivalents use the Sky130 `nand2_1` area from the bundled Liberty file, **3.7536 µm²**.

| Module | Cells | Flip-flops | Area (µm²) | Sequential area | ≈ GE |
|---|:---:|:---:|:---:|:---:|:---:|
| `FPU_adder` | 1,693 | 287 | 15,564.9 | 46.1% | ~4,150 |
| `FPU_multiplier` | 3,291 | 213 | 26,536.7 | 20.1% | ~7,070 |
| `FPU_division` | 12,813 | 196 | 69,484.1 | 7.1% | ~18,510 |
| `FPU_mac` | 11,171 | 546 | 70,858.0 | 19.3% | ~18,880 |
| **`FPU_top`** | **29,927** | **1,196** | **182,328.6** | 16.4% | **~48,570** |

### Timing (10 ns target, 100 MHz)

| Module | Data arrival | Worst setup slack | Status | ≈ f<sub>max</sub> |
|---|:---:|:---:|:---:|:---:|
| `FPU_adder` | 8.83 ns | **+1.04 ns** | MET | ~112 MHz |
| `FPU_multiplier` | 10.24 ns | **−0.38 ns** | VIOLATED | ~96 MHz |
| `FPU_mac` | 29.27 ns | −19.42 ns | VIOLATED | ~34 MHz |
| `FPU_division` | 99.55 ns | −89.69 ns | VIOLATED | ~10 MHz |
| `FPU_top` | 100.37 ns | −90.51 ns | VIOLATED | ~10 MHz |

### Full-FPU maximum frequency
OpenSTA clock-period sweep (binary search to 1 ps) on the synthesized **`FPU_top`** netlist, reporting the smallest period with worst setup slack ≥ 0:

| Constraints | Min period | f<sub>max</sub> | WNS at 10 ns |
|---|:---:|:---:|:---:|
| As in `sta_fpu_top.tcl` (plain clock, 0 ns I/O delay) | **100.506 ns** | **9.95 MHz** | −90.51 ns |
| `timing.sdc` (with `delete_from_list` fix: 250 ps uncertainty, 15% I/O delay, ±5% derate) | **105.789 ns** | **9.45 MHz** | −95.79 ns |

The top level is limited by the divider's single-stage iteration loop (the divider alone needs ~99.7 ns). The adder alone could run at ~112 MHz.

### Power
[`analysis/asic/fpu_*_power.txt`](analysis/asic/) are OpenSTA `report_power` outputs with **default switching activity** (no VCD/SAIF) and **zero internal power** reported. They are not meaningful power estimates. The adder (0.63 mW), multiplier (1.6 mW) and MAC (8.8 mW) figures are at best rough switching-power indications. The divider and top-level reports (~2.9×10⁵ W) are clearly invalid and should be ignored.

### FPGA
Yosys `synth_xilinx -family xc7` (logic synthesis only; no Vivado place-and-route, so **no FPGA timing**). Details are in [`analysis/FPGA/fpga_analysis.md`](analysis/FPGA/fpga_analysis.md), which replaces earlier hand estimates.

| Module | LUTs | FFs | DSP48E1 | CARRY4 |
|---|:---:|:---:|:---:|:---:|
| `FPU_adder` | 765 | 287 | 0 | 30 |
| `FPU_multiplier` | 143 | 213 | 2 | 19 |
| `FPU_mac` | 2,032 | 546 | 2 | 59 |
| `FPU_division` | 3,069 | 196 | 0 | 338 |
| **`FPU_top`** | **5,945** | **1,196** | **4** | **443** |

`FPU_top` uses ~29% of the LUTs on an Artix-7 XC7A35T.

---

## 🛠️ Getting Started

### Prerequisites
- [Icarus Verilog](http://iverilog.icarus.com/) ≥ 12 (`iverilog`, `vvp`)
- [Verilator](https://www.veripool.org/verilator/) ≥ 5 (lint + SVA runs)
- [cocotb](https://www.cocotb.org/) 2.x + Python 3 (Tier 6)
- [Yosys](https://yosyshq.net/yosys/) + [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA) (synthesis/STA)
- [GTKWave](http://gtkwave.sourceforge.net/) (optional; `run.sh` opens it after each simulation)

### Simulation

```bash
# Tier 1: components and units
./run adder | multiplier | barrel_shifter | LZD
./run fpu_adder | fpu_multiplier | fpu_division | fpu_mac
./run top                # 180-test FPU_top + converter regression

# Tiers 2-4
./run crv                # 1,000 random transactions (property checks only)
./run large              # 2,800 identity-law vectors
./run corner_adder | corner_multiplier | corner_division | corner_mac | corner_top

# Tier 5: simulation-time SVA (Verilator --assert)
./run sva_adder | sva_multiplier | sva_division | sva_mac

# Tier 6: cocotb
./run cocotb
```

### Synthesis + STA

```bash
./run synth top              # FPU_top @ 10 ns
./run synth adder 5.0        # FPU_adder @ 5 ns
./run synth multiplier       # also: division, mac
```

The unit-specific scripts can also be run directly, e.g. `yosys -s script/synth_fpu_adder.tcl && sta script/sta_fpu_adder.tcl`. These write the reports in `analysis/asic/`.

---

## 🗺️ Suggested Next Steps
- Implement gradual underflow (subnormal results) and normalize subnormal inputs (effective exponent 1 + LZD pre-shift).
- Widen `s2_abs_diff` in `FPU_mac.v` and saturate the shift amount from the full 10-bit difference.
- Fix the `+0 + −0` sign rule and restrict `flag_invalid` to sNaN / invalid operations.
- Pipeline the divider across multiple stages (or use SRT radix-4 / Newton-Raphson) and rebalance the MAC stages.
- Add a bit-exact golden model (e.g. Berkeley SoftFloat or exact rational arithmetic) to the CRV and cocotb tiers, and remove the ±1 ULP tolerance.
- Replace `remove_from_collection` with `delete_from_list` in `timing.sdc`, load it in the STA scripts, and generate power from simulation activity (VCD/SAIF).
- Add a SymbiYosys (`.sby`) setup if the SVA properties are meant to be formally proven.

---

## 📖 Documentation
- [`history.md`](history.md): engineering log and bug post-mortems (signed overflow vs carry, LZD/carry race, testbench races, Icarus parser issues, …).
- [`analysis/asic/asic_analysis.md`](analysis/asic/asic_analysis.md): Sky130 area, timing (including the full-FPU f<sub>max</sub> sweep) and power-report assessment.
- [`analysis/FPGA/fpga_analysis.md`](analysis/FPGA/fpga_analysis.md): Xilinx 7-series resource counts.
- [`analysis/test/`](analysis/test/): per-unit verification reports, each with an independent bit-exact audit section.
- [`documantation/`](documantation/): per-module specifications.
- [`notes.pdf`](notes.pdf): handwritten derivations referenced by the RTL comments.

---

## 📄 License
[MIT](LICENSE)
