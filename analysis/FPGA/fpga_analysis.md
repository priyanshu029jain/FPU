# FPGA Resource Utilization (Xilinx 7-Series)

> **Revision note (2026-10-18).** The previous version of this file was hand-estimated: no FPGA tool had been run. It listed 0 flip-flops for every module, which contradicts the 4-stage pipelined RTL, and it gave LUT counts 2–4× lower than real synthesis. It also quoted FPGA delays and f<sub>max</sub> figures (e.g. "> 250 MHz") that were never measured. Those numbers have been replaced with real synthesis results below, and the unmeasured timing claims have been removed.

---

## 1. Resource Utilization (Yosys `synth_xilinx`)

**Flow:** Yosys 0.52, `synth_xilinx -family xc7 -flatten`, RTL as in the repository. This is **logic synthesis only**: no Vivado, no placement or routing. Counts are close to, but not identical to, what Vivado would report.

| Module | LUTs (LUT1–6) | Flip-flops (FDCE) | DSP48E1 | CARRY4 | MUXF7 / MUXF8 | BRAM |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `FPU_adder` | 765 | 287 | 0 | 30 | 93 / 32 | 0 |
| `FPU_multiplier` | 143 | 213 | 2 | 19 | 3 / 0 | 0 |
| `FPU_mac` | 2,032 | 546 | 2 | 59 | 271 / 76 | 0 |
| `FPU_division` | 3,069 | 196 | 0 | 338 | 450 / 217 | 0 |
| `input_convertor` (combinational) | 332 | 0 | 0 | 16 | 37 / 15 | 0 |
| `output_convertor` (combinational) | 306 | 0 | 0 | 19 | 99 / 23 | 0 |
| **`FPU_top`** | **5,945** | **1,196** | **4** | **443** | 534 / 236 | **0** |

`FPU_top` does not instantiate the two converters, so their resources are not included in the `FPU_top` row.

### Fit on an Artix-7 XC7A35T (20,800 LUTs, 41,600 FFs, 90 DSP48E1)

| Resource | `FPU_top` | Utilization |
|---|:---:|:---:|
| LUTs | 5,945 | ~28.6% |
| Flip-flops | 1,196 | ~2.9% |
| DSP48E1 | 4 | ~4.4% |

### Observations
- **Divider is the largest unit** (~52% of `FPU_top` LUTs) because all 26 restoring-division iterations are unrolled combinationally in a single pipeline stage (338 CARRY4 chains).
- **Each 24×24 significand multiply maps to 2 DSP48E1** (the DSP48E1 multiplier is 25×18). `FPU_multiplier` and `FPU_mac` each have their own multiplier, giving 4 DSPs in `FPU_top`. No DSP sharing is performed.
- **No BRAM or LUTRAM** is used; all pipeline state is in FDCE flip-flops (async-clear, matching `rst_n`).

---

## 2. Timing

**FPGA timing has not been measured.** Yosys `synth_xilinx` does not perform timing analysis, and no Vivado / nextpnr-xilinx run exists for this project.

What can be said qualitatively:
- The `FPU_top` clock will be set by the divider's Stage 2, a single-cycle chain of 26 subtract-and-select steps. On Sky130 ASIC synthesis this path is ~100 ns (see [`../asic/asic_analysis.md`](../asic/asic_analysis.md)). On a 7-series FPGA it will also be far slower than the other units.
- The MAC's Stage 4 (100-bit normalize + round) is the next-longest path.
- Pipelining the divider is a prerequisite for running `FPU_top` at a typical FPGA clock (100 MHz+).

To obtain real numbers, synthesize and implement in Vivado with a clock constraint and read `report_timing_summary`.

---

## 3. Reproducing

```bash
yosys -p "read_verilog component/param_adder_sub.v component/param_multiplier.v \
          component/barrel_shifter.v component/leading_zero_detector.v \
          rtl/FPU_adder.v rtl/FPU_multiplier.v rtl/FPU_division.v rtl/FPU_mac.v rtl/FPU_top.v; \
          synth_xilinx -family xc7 -top FPU_top -flatten; stat"
```

Replace `-top FPU_top` (and the file list) to synthesize an individual unit.
