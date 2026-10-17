# Floating-Point Unit System Architecture & Block Diagrams

## 1. Top-Level Unified FPU Core (`rtl/FPU_top.v`)

```mermaid
graph TD
    A["Operand A [31:0]"] --> ADD["FPU_adder"]
    A --> MUL["FPU_multiplier"]
    A --> MAC["FPU_mac"]
    A --> DIV["FPU_division"]

    B["Operand B [31:0]"] --> ADD
    B --> MUL
    B --> MAC
    B --> DIV

    C["Operand C [31:0]"] --> MAC

    ADD --> MUX{"Opcode Mux<br/>(op[1:0])"}
    MUL --> MUX
    MAC --> MUX
    DIV --> MUX

    MUX --> Y["Float Output Y [31:0]"]
    Y --> STAT["output_convertor<br/>Status Decoder"]
    STAT --> FZ["flag_zero"]
    STAT --> FI["flag_inf"]
    STAT --> FN["flag_nan"]
    STAT --> FO["flag_overflow"]
```

---

## 2. FPU Adder Pipeline (`rtl/FPU_adder.v`)

```mermaid
graph LR
    subgraph S1["Stage 1: Alignment"]
        IN1["A, B"] --> EXP_DIFF["Exponent Compare<br/>d = |Ea - Eb|"]
        IN1 --> SHIFT["Right Shift Smaller<br/>Significand by d"]
        SHIFT --> GRS["Form 27-bit Sig<br/>[26:3] Sig, [2:0] GRS"]
    end

    subgraph S2["Stage 2: Add/Sub"]
        GRS --> ADDSUB["27-bit Add/Sub<br/>Carry out into bit 27"]
    end

    subgraph S3["Stage 3: Normalization"]
        ADDSUB --> LZD["Leading Zero Detector<br/>(Cancellation Scan)"]
        LZD --> NORM["Barrel Shifter<br/>Exponent Adjust"]
    end

    subgraph S4["Stage 4: Round & Pack"]
        NORM --> RND["Round-to-Nearest-Even<br/>(GRS Logic)"]
        RND --> PACK["Exception Check &<br/>32-bit Pack {S, E, M}"]
    end
```

---

## 3. FPU Multiplier Datapath (`rtl/FPU_multiplier.v`)

```mermaid
graph TD
    subgraph Phase1["Phase 1 & 2: Unpack & Exp"]
        A_IN["Operand A"] --> S_XOR["Sign: Sa ^ Sb"]
        B_IN["Operand B"] --> S_XOR
        A_IN --> E_ADD["Etemp = Ea + Eb - 127"]
        B_IN --> E_ADD
    end

    subgraph Phase3["Phase 3: Significand Multiply"]
        A_IN --> SIG_A["Extract 1.Ma (24b)"]
        B_IN --> SIG_B["Extract 1.Mb (24b)"]
        SIG_A --> MULT["24 x 24 Multiplier"]
        SIG_B --> MULT
        MULT --> P_RAW["48-bit Raw Product"]
    end

    subgraph Phase4["Phase 4 & 5: Normalization & Rounding"]
        P_RAW --> NORM_CASE{"Bit 47 == 1?<br/>[1.0, 2.0) vs [2.0, 4.0)"}
        NORM_CASE -- Yes --> RSHIFT["Shift Right 1<br/>Etemp + 1"]
        NORM_CASE -- No --> PASS["Keep Product<br/>Etemp unchanged"]
        RSHIFT --> GRS_EXT["Extract G (bit 22), R (bit 21), S (OR bits 20:0)"]
        PASS --> GRS_EXT
        GRS_EXT --> ROUND["Nearest-Even Rounding"]
    end

    subgraph Phase6["Phase 6: Packing"]
        ROUND --> RES["Assemble {S, Efinal, Mfinal}"]
    end
```

---

## 4. Fused Multiply-Accumulate (FMA) Dual-Path Alignment (`rtl/FPU_mac.v`)

```mermaid
graph TD
    P["Product A x B<br/>(48-bit Raw)"] --> NORM_P["Normalize Product<br/>(bit 47 implicit 1)"]
    C["Addend C<br/>(24-bit Sig)"] --> EXP_C["Ec = C_expo"]
    NORM_P --> EXP_P["Ep = Ea + Eb - 127 + carry"]

    EXP_P --> CMP["d = Ep - Ec"]
    EXP_C --> CMP

    CMP -- "Ep >= Ec" --> ALIGN_C["C placed in 100-bit space<br/>Shifted right by d"]
    CMP -- "Ec > Ep" --> ALIGN_P["P placed in 100-bit space<br/>Shifted right by -d"]

    ALIGN_C --> WIDE_ADD["100-bit Wide Adder/Subtractor"]
    ALIGN_P --> WIDE_ADD

    WIDE_ADD --> WIDE_LZD["100-bit LZD Scan"]
    WIDE_LZD --> WIDE_NORM["Normalize 100-bit Result"]
    WIDE_NORM --> SINGLE_RND["Single Unified Rounding Step"]
    SINGLE_RND --> FINAL_Y["Final MAC Output Y"]
```
