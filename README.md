# 32-Bit IEEE 754 Floating-Point Unit (FPU)

## 📌 Project Overview
This project focuses on the architectural design, implementation, and verification of a **32-Bit Single-Precision Floating-Point Unit (FPU)** compliant with the **IEEE 754 standard**, designed in Verilog HDL.

Floating-point hardware acceleration is essential in modern computing systems—such as digital signal processors (DSPs), graphics processing units (GPUs), and AI/ML accelerators—where high-dynamic-range arithmetic must be executed with low latency and high precision.

---

## 🔬 IEEE 754 Single-Precision Basics

A standard 32-bit floating-point number is partitioned into three key fields:

$$\text{Value} = (-1)^S \times (1.M) \times 2^{E - 127}$$

- **Sign ($S$) — 1 bit (`[31]`)**: Determines the sign of the number ($0$ for positive, $1$ for negative).
- **Exponent ($E$) — 8 bits (`[30:23]`)**: Biased exponent using a bias of $127$.
- **Mantissa ($M$) — 23 bits (`[22:0]`)**: Represents the fractional component of the significand. An implicit leading $1$ is restored ($1.M$) for normalized numbers.

---

## 🎯 Target Functional Modules
1. **FPU Adder / Subtractor**: Equalizes exponents, adds or subtracts aligned significands, performs Leading Zero Detection (LZD) for normalization, and executes Round-to-Nearest-Even using Guard, Round, and Sticky (GRS) bits.
2. **FPU Multiplier**: Computes $24 \times 24$ significand multiplication, adds biased exponents, normalizes the product, and performs rounding.
3. **FPU Fused Multiply-Accumulate (FMA)**: Computes $Y = A \times B + C$ with high precision using wide dual-path alignment and a single final rounding stage.
4. **FPU Divider**: Computes significand division using restoring long division and extracts remainder sticky bits without infinite division loops.
5. **Format Converters**: Converts between standard signed integers, Q16.16 fixed-point numbers, and IEEE 754 floats for rapid verification.

---

## 📑 Design Notes & References
Handwritten architectural derivations, bit-level allocation diagrams, and phase-by-phase design notes are documented in [`notes.pdf`](notes.pdf).

---

## 📄 License
This project is licensed under the [MIT License](LICENSE).
