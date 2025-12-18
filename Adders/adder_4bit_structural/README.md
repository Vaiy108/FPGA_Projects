# 4-bit Full Adder (Structural VHDL)

This project implements a 4-bit full adder using four 1-bit full adder modules, demonstrating hierarchical and structural design in VHDL.

## Features
- Structural composition using reusable 1-bit full adder blocks
- Carry propagation across stages
- Fully synthesizable VHDL
- Verified using a dedicated testbench

## Files
- `src/fa_1bit.vhd` — 1-bit full adder module
- `src/adder_4bit.vhd` — 4-bit adder built structurally
- `tb/adder_4bit_tb.vhd` — Testbench for functional verification

## Tools
- Language: VHDL
- Simulator: ISim
- Target FPGA: Xilinx Spartan-6 (ISE)

## Author
**Vasan Iyer**  
FPGA & Digital Design Engineer  
GitHub: https://github.com/Vaiy108
