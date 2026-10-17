# ASIC Synthesis & Timing Analysis (SkyWater 130nm)

This document summarizes logic synthesis and static timing analysis of the FPU using **Yosys 0.52** and **OpenSTA** with the **SkyWater 130nm high-density library (`sky130_fd_sc_hd__tt_025C_1v80`, 1.80 V, 25 °C)** bundled as [`sky130.lib`](../../sky130.lib).

All numbers below were reproduced on 2026-10-18 by deleting the reports and re-running `script/synth_fpu_*.tcl` and `script/sta_fpu_*.tcl`. The regenerated `fpu_*_area.txt`, `fpu_*_timing.txt` and `fpu_*_power.txt` were identical to the committed ones.

> **Scope and caveats.** These are **pre-layout, synthesis-only** results: no floorplan, placement, clock tree, routing or parasitic extraction.
> - The per-unit STA scripts use a plain clock with **0 ns input/output delay** and **do not load [`script/timing.sdc`](../../script/timing.sdc)**, so there is no clock uncertainty or derating.
> - ABC maps without a delay target.
>
> Treat timing as optimistic and power as not meaningful (see §3).

---

## 1. Area

One gate equivalent (GE) is the area of `sky130_fd_sc_hd__nand2_1` in the bundled Liberty file: **3.7536 µm²**. An earlier revision of this document used 3.31 µm², which overstated every GE count by ~13%.

| Module | Cells | Flip-flops | Total area (µm²) | Sequential area (µm²) | Seq. % | ≈ GE | Report |
|---|:---:|:---:|:---:|:---:|:---:|:---:|---|
| `FPU_adder` | 1,693 | 287 | 15,564.93 | 7,181.89 | 46.1% | ~4,150 | [`fpu_adder_area.txt`](fpu_adder_area.txt) |
| `FPU_multiplier` | 3,291 | 213 | 26,536.70 | 5,330.11 | 20.1% | ~7,070 | [`fpu_multiplier_area.txt`](fpu_multiplier_area.txt) |
| `FPU_division` | 12,813 | 196 | 69,484.14 | 4,904.70 | 7.1% | ~18,510 | [`fpu_division_area.txt`](fpu_division_area.txt) |
| `FPU_mac` | 11,171 | 546 | 70,857.96 | 13,663.10 | 19.3% | ~18,880 | [`fpu_mac_area.txt`](fpu_mac_area.txt) |
| **`FPU_top`** | **29,927** | **1,196** | **182,328.62** | **29,928.70** | **16.4%** | **~48,570** | [`fpu_top_area.txt`](fpu_top_area.txt) |

Notes:
- The RTL describes arithmetic behaviourally (`*`, `+`, shifts, priority loops). There are no hand-designed carry-save, CLA, Wallace or tree-LZD structures; the gate structure is whatever Yosys/ABC infers.
- `FPU_top` instantiates the four units in parallel. `input_convertor` / `output_convertor` are read by `synth_fpu_top.tcl` but are not instantiated by `FPU_top`, so they contribute no area.
- Standard-cell area only (0.18 mm² for `FPU_top`). A real die would add utilization margin, power grid, I/O and clock tree. Earlier cross-node die-area projections (65nm / 28nm) were based on the wrong GE factor and have been removed.

---

## 2. Static Timing

### 2.1 Per-unit results at 10 ns (100 MHz)

Setup timing from the committed `fpu_*_timing.txt` (clock group). f<sub>max</sub> ≈ 1 / (10 ns − WNS).

| Module | Data arrival | WNS | Status | ≈ f<sub>max</sub> | Cells on critical path | Report |
|---|:---:|:---:|:---:|:---:|:---:|---|
| `FPU_adder` | 8.83 ns | **+1.04 ns** | MET | ~112 MHz | ~28 | [`fpu_adder_timing.txt`](fpu_adder_timing.txt) |
| `FPU_multiplier` | 10.24 ns | **−0.38 ns** | **VIOLATED** | ~96 MHz | ~37 | [`fpu_multiplier_timing.txt`](fpu_multiplier_timing.txt) |
| `FPU_mac` | 29.27 ns | −19.42 ns | VIOLATED | ~34 MHz | ~30 | [`fpu_mac_timing.txt`](fpu_mac_timing.txt) |
| `FPU_division` | 99.55 ns | −89.69 ns | VIOLATED | ~10 MHz | ~243 | [`fpu_division_timing.txt`](fpu_division_timing.txt) |
| `FPU_top` | 100.37 ns | −90.51 ns | VIOLATED | ~10 MHz | ~245 | [`fpu_top_timing.txt`](fpu_top_timing.txt) |

> **Correction:** an earlier revision listed `FPU_multiplier` as **+0.48 ns / MET / 105 MHz** with 3,467 cells. The committed report it linked to says **−0.3767 ns VIOLATED** with 3,291 cells. The multiplier does **not** close timing at 100 MHz under these scripts.

The netlists are flattened, so register names do not identify the pipeline stage on each critical path. The following is inferred from RTL structure and path depth rather than traced:
- **Divider:** the ~243-cell path matches Stage 2 of [`FPU_division.v`](../../rtl/FPU_division.v), where all 26 restoring-division iterations are a single combinational `for` loop. This, not a pipelined array, is why the divider needs ~100 ns.
- **`FPU_top`:** follows the divider path (period within 1 ns of the divider alone).
- **MAC:** Stage 4 of [`FPU_mac.v`](../../rtl/FPU_mac.v) contains a 100-bit normalization shift, rounding and packing. Stage 1 contains the full 24×24 multiply. Both are plausible long paths.

### 2.2 Full-FPU maximum frequency (`FPU_top`)

OpenSTA clock-period sweep (binary search to 1 ps) on the synthesized `FPU_top` netlist, reporting the smallest period with worst setup slack ≥ 0:

| Constraint set | Min period | f<sub>max</sub> | WNS at 10 ns |
|---|:---:|:---:|:---:|
| As in `sta_fpu_top.tcl` (plain clock, 0 ns I/O delay) | **100.506 ns** | **9.95 MHz** | −90.51 ns |
| `timing.sdc` (250 ps setup uncertainty, 15% I/O delay, ±5% derate)* | **105.789 ns** | **9.45 MHz** | −95.79 ns |

\* `timing.sdc` uses the Synopsys-only command `remove_from_collection`, which OpenSTA rejects. Its input-delay and driving-cell lines raise errors when the file is sourced; the repo's STA scripts never source it, so this went unnoticed. The figures above used a copy with `remove_from_collection` replaced by OpenSTA's `delete_from_list`.

---

## 3. Power

The `fpu_*_power.txt` files are OpenSTA `report_power` output with **no switching-activity annotation** (no VCD/SAIF; default activity), and every report shows **0 internal power**. They are not valid power estimates.

| Module | Reported total | Assessment |
|---|:---:|---|
| `FPU_adder` | 0.632 mW | Default-activity switching power only; rough indication at best |
| `FPU_multiplier` | 1.60 mW | Same |
| `FPU_mac` | 8.78 mW | Same |
| `FPU_division` | 2.92 × 10⁵ W | **Invalid**: physically impossible, ignore |
| `FPU_top` | 2.83 × 10⁵ W | **Invalid**: physically impossible, ignore |

An earlier revision of this document re-labelled the divider/top values with different exponents ("10⁻¹ W", "10² W (equiv.)"). Those numbers do not appear in the reports and have been removed.

To get meaningful power: dump a VCD from a representative simulation, run `read_vcd` (or SAIF) in OpenSTA, and check that the Liberty internal-power tables are being used.

---

## 4. Improvement Opportunities

These are design suggestions, not measured results.

1. **Pipeline the divider.** Spread the 26 restoring iterations across several registered stages, or switch to SRT radix-4 / Newton-Raphson / Goldschmidt. The divider sets the `FPU_top` clock, so this is the single largest frequency lever.
2. **Rebalance the MAC.** Split the 100-bit normalize + round in Stage 4, and move part of the 24×24 multiply out of Stage 1.
3. **Close the multiplier at 100 MHz.** It misses by 0.38 ns. A delay-targeted ABC run (`abc -D 10000`) or moving logic between stages 2 and 3 is likely sufficient.
4. **Operand isolation.** All four units see every `A`/`B`/`C` change, and only `valid_in` is gated per opcode. Gating the operands by opcode should reduce dynamic power, but the saving has not been quantified here.
5. **Share the multiplier.** `FPU_mac` with `C = −0` (the IEEE additive identity; `+0` would turn a `−0` product into `+0`) can replace `FPU_multiplier` (~7,070 GE / 26,537 µm²). Note that the FMA unit currently has a large-exponent-gap alignment bug (see the README) that would have to be fixed first.
6. **Fix the timing flow.** Correct `timing.sdc` for OpenSTA, load it in the STA scripts, and give ABC a delay target so reported timing reflects the intended constraints.
