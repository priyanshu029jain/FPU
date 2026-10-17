# Floating-Point Unit System Architecture & Block Diagrams

These diagrams follow the RTL as it is. Every unit has **4 register stages** and accepts one operation per cycle. Nodes marked ⚠ are where the independent bit-exact audit (2026-10-18) found deviations from IEEE 754; see [`documantation/architecture.md` §4](../documantation/architecture.md#4-deviations-from-ieee-754).

## 1. Top-Level Unified FPU Core (`rtl/FPU_top.v`)

```mermaid
graph TD
    VIN["valid_in"] --> GATE{"valid_in gated<br/>by op[1:0]"}
    OP["op[1:0]"] --> GATE
    OP --> OPP["op_pipe1 → op_pipe4<br/>(4-deep register chain)"]

    A["Operand A [31:0]"] --> ADD["FPU_adder<br/>op = 00"]
    A --> MUL["FPU_multiplier<br/>op = 01"]
    A --> MAC["FPU_mac<br/>op = 10"]
    A --> DIV["FPU_division<br/>op = 11"]

    B["Operand B [31:0]"] --> ADD
    B --> MUL
    B --> MAC
    B --> DIV

    C["Operand C [31:0]"] --> MAC

    GATE --> ADD
    GATE --> MUL
    GATE --> MAC
    GATE --> DIV

    ADD -- "Y, valid_out, flags" --> MUX{"Output Mux<br/>select = op_pipe4"}
    MUL -- "Y, valid_out, flags" --> MUX
    MAC -- "Y, valid_out, flags" --> MUX
    DIV -- "Y, valid_out, flags, div_by_zero" --> MUX
    OPP --> MUX

    MUX --> Y["Y [31:0], valid_out"]
    MUX --> FL["flag_zero, flag_invalid, flag_overflow,<br/>flag_underflow, flag_inexact, flag_div_by_zero"]
    Y --> DEC["Combinational decode of Y<br/>(inside FPU_top)"]
    DEC --> FI["flag_inf"]
    DEC --> FN["flag_nan"]
```

- The four units run in parallel on one clock, so the slowest one (the divider) sets the `FPU_top` clock: **min period 100.506 ns (≈9.95 MHz)** in Sky130 synthesis.
- `input_convertor` / `output_convertor` are **not** part of `FPU_top`. They are standalone components, tested separately in `tb_fpu_top.v`.

---

## 2. FPU Adder Pipeline (`rtl/FPU_adder.v`)

```mermaid
graph LR
    subgraph S1["Stage 1: Unpack & Align"]
        IN1["A, B"] --> SPEC["Special-case detect<br/>(0, ∞, NaN) → bypass value ⚠"]
        IN1 --> EXP_DIFF["Exponent Compare<br/>d = |Ea − Eb| ⚠ subnormal uses E=0"]
        EXP_DIFF --> SHIFT["49-bit Barrel Shifter<br/>Right Shift Smaller Sig by d"]
        SHIFT --> GRS["27-bit operands<br/>{24-bit sig, G, R, S}"]
    end

    subgraph S2["Stage 2: Add/Sub & LZD"]
        GRS --> ADDSUB["27-bit Add/Sub<br/>carry → bit 27"]
        ADDSUB --> LZD["Leading Zero Detector<br/>on sum[26:0]"]
    end

    subgraph S3["Stage 3: Normalization"]
        LZD --> NORM["Barrel Shifter: left by LZD count<br/>or right 1 on carry; exponent adjust"]
    end

    subgraph S4["Stage 4: Round & Pack"]
        NORM --> RND["Round-to-Nearest-Even<br/>(GRS logic)"]
        RND --> PACK["Pack {S, E, M}<br/>E ≥ 255 → ±∞, E = 0 → ±0 ⚠ FTZ"]
    end
```

⚠ Bypass returns `B` when `A` is zero, so `+0 + −0 → −0`. Any NaN operand sets `flag_invalid`.

---

## 3. FPU Multiplier Pipeline (`rtl/FPU_multiplier.v`)

```mermaid
graph TD
    subgraph S1["Stage 1: Unpack & Exponent"]
        A_IN["Operand A"] --> S_XOR["Sign: Sa ⊕ Sb"]
        B_IN["Operand B"] --> S_XOR
        A_IN --> E_ADD["Etemp = Ea + Eb − 127<br/>(10-bit signed)"]
        B_IN --> E_ADD
        A_IN --> SPEC["Special-case detect<br/>0×∞ → NaN, ∞, 0, NaN"]
        B_IN --> SPEC
        A_IN --> SIG_A["{hidden, Ma} (24b)<br/>⚠ subnormal not normalized"]
        B_IN --> SIG_B["{hidden, Mb} (24b)"]
    end

    subgraph S2["Stage 2: Significand Multiply"]
        SIG_A --> MULT["24 × 24 Multiplier<br/>(param_multiplier)"]
        SIG_B --> MULT
        MULT --> P_RAW["48-bit Product"]
    end

    subgraph S3["Stage 3: Normalize & GRS"]
        P_RAW --> NORM_CASE{"Bit 47 == 1?"}
        NORM_CASE -- Yes --> RSHIFT["Shift Right 1<br/>Etemp + 1"]
        NORM_CASE -- No --> PASS["Keep Product"]
        RSHIFT --> GRS_EXT["Extract 24-bit sig + G, R, S"]
        PASS --> GRS_EXT
    end

    subgraph S4["Stage 4: Round & Pack"]
        GRS_EXT --> ROUND["Round-to-Nearest-Even"]
        ROUND --> RES["Pack {S, Efinal, Mfinal}<br/>E ≥ 255 → ±∞, E ≤ 0 → ±0 ⚠ FTZ"]
    end
```

---

## 4. FPU Divider Pipeline (`rtl/FPU_division.v`)

```mermaid
graph TD
    subgraph S1["Stage 1: Unpack & Exponent"]
        IN["A, B"] --> SPEC["Special cases: B=0 → ±∞ (div_by_zero),<br/>0/0, ∞/∞, NaN → QNaN"]
        IN --> EXP["Etemp = Ea − Eb + 127"]
        IN --> SIG["{hidden, M} significands (24b)<br/>⚠ subnormal not normalized"]
    end

    subgraph S2["Stage 2: Restoring Division (single combinational stage)"]
        SIG --> LOOP["26 unrolled compare-and-subtract iterations<br/>in ONE clock cycle (~100 ns, ~243 cells deep)"]
        LOOP --> Q["Q[25:0] + remainder ≠ 0"]
    end

    subgraph S3["Stage 3: Normalize & GRS"]
        Q --> NQ{"Q[25] == 1?"}
        NQ -- Yes --> KEEP["Q in [1, 2)"]
        NQ -- No --> LSH["Shift left 1<br/>Etemp − 1"]
        KEEP --> GRS["sig = Q[25:2], G, R,<br/>S = remainder ≠ 0"]
        LSH --> GRS
    end

    subgraph S4["Stage 4: Round & Pack"]
        GRS --> RND["Round-to-Nearest-Even"]
        RND --> PK["Pack; E ≤ 0 → ±0 ⚠ FTZ"]
    end
```

The Stage 2 loop is the critical path of the whole FPU. Splitting it across pipeline stages, or using SRT / Newton-Raphson, is the main frequency improvement available.

---

## 5. Fused Multiply-Add (FMA) Pipeline (`rtl/FPU_mac.v`)

```mermaid
graph TD
    subgraph S1["Stage 1: Unpack & Product"]
        AB["A, B"] --> MULT["24 × 24 Multiplier → 48-bit P"]
        MULT --> NORM_P["Normalize P (bit 47)"]
        AB --> EXP_P["Ep = Ea + Eb − 127 (+1 if bit 47)"]
        CIN["C"] --> EXP_C["Ec, 24-bit sig of C"]
    end

    subgraph S2["Stage 2: Wide Alignment"]
        EXP_P --> CMP["d = Ep − Ec (10-bit signed)"]
        EXP_C --> CMP
        CMP --> ABS["|d| → s2_abs_diff (8-bit) ⚠<br/>wraps when |d| > 255"]
        ABS -- "Ep ≥ Ec" --> ALIGN_C["C in 100-bit field,<br/>shifted right by |d| (sat. 98)"]
        ABS -- "Ec > Ep" --> ALIGN_P["P in 100-bit field,<br/>shifted right by |d| (sat. 98)"]
        NORM_P --> ALIGN_P
    end

    subgraph S3["Stage 3: Wide Add/Sub & LZD"]
        ALIGN_C --> WIDE_ADD["100-bit Add/Sub<br/>(larger magnitude first)"]
        ALIGN_P --> WIDE_ADD
        WIDE_ADD --> WIDE_LZD["100-bit LZD"]
    end

    subgraph S4["Stage 4: Normalize, Round & Pack"]
        WIDE_LZD --> WIDE_NORM["100-bit Normalize Shift"]
        WIDE_NORM --> SINGLE_RND["Single RNE Rounding Step"]
        SINGLE_RND --> FINAL_Y["Pack Y; E ≤ 0 → ±0 ⚠ FTZ"]
    end
```

⚠ Example of the wrap-around bug: `A=9B4E99D0, B=13D13455, C=7AAC7742` gives `|d| = 279`, which wraps to a shift of 23. The result is `7AAC773F`; the correct answer is `7AAC7742`. The alignment shifters' sticky outputs are unconnected, so bits shifted below bit 0 are dropped.
