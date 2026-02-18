# Multiplexers

This folder contains VHDL implementations of multiplexers used in FPGA design.

---

## 4-to-1 Multiplexer (With Enable)

**Location:**
Multiplexers/src/mux4to1_with_select.vhd


### Features
- 4 data inputs: `w0, w1, w2, w3`
- 2-bit select input: `s`
- Active-high enable: `En`
- Output: `f`
- Implemented using `with-select` statement
- Fully verified using testbench

### Behavior

When `En = '1'`:

| Select (s) | Output (f) |
|------------|------------|
| 00         | w0         |
| 01         | w1         |
| 10         | w2         |
| 11         | w3         |

When `En = '0'`:
f = '0'


---

## Testbench

Testbench file: Multiplexers/tb/mux4to1_with_select_tb.vhd


The testbench:
- Sweeps all select combinations
- Tests both enable states
- Verifies correct output behavior in simulation

---

## Tools Used

- VHDL
- Xilinx ISE
- ISim Simulator

---

More multiplexer implementations will be added in future updates.




