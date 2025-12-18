# 16-bit Signed Adder (VHDL)

This project implements a 16-bit signed adder using VHDL signed arithmetic (`numeric_std`), targeting Xilinx Spartan-6 devices.

## Features
- Signed arithmetic using `signed` data type
- Synthesizable and portable VHDL
- Clean separation of design and verification
- Verified using ISim simulation

## Files
- `src/adder_16bit_signed.vhd` — 16-bit signed adder implementation
- `tb/adder_16bit_signed_tb.vhd` — Testbench for verification

## Notes
- Overflow behavior follows standard two’s complement arithmetic
- Designed for clarity and correctness rather than vendor-specific IP

## Tools
- Language: VHDL (`numeric_std`)
- Simulator: ISim
- Target FPGA: Xilinx Spartan-6 (ISE)

## Author
**Vasan Iyer**  
FPGA & Digital Design Engineer  
GitHub: https://github.com/Vaiy108
