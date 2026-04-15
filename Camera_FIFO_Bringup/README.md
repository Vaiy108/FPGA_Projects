# OV7670 FIFO Camera Bring-up (Spartan-6 Mimas V2)

## Overview

This project implements a full hardware pipeline to interface an **OV7670 camera with AL422B FIFO** to a **Spartan-6 FPGA (Numato Mimas V2)** and display the output via **VGA**.

The goal is to build a real-time image acquisition and display system entirely in **VHDL**, covering:

- Camera configuration (SCCB)
- FIFO-based buffering
- VGA signal generation
- End-to-end data flow from sensor → display

---

## Current Status

✔ FPGA programming via `.bin` (Numato config tool)  
✔ SCCB communication established (camera registers configured)  
✔ FIFO read path functional  
✔ VGA output working (640×480 @ 60Hz)  
✔ End-to-end pipeline achieved:  
**Camera → FIFO → FPGA → VGA**

---

## Hardware Setup

- **Camera:** OV7670 with AL422B FIFO  
- **FPGA Board:** Numato Mimas V2 (Spartan-6)  
- **Interface:**
  - Parallel data: `D0–D7`
  - FIFO control: `RCLK`, `RRST`, `OE`, `WR`, `WRST`
  - SCCB: `SIOC`, `SIOD`
  - Sync signals: `VSY`, `HREF`

<p align="center">
<img src="media/cam_fifo_2.jpg" width="400"/>
</p>

<p align="center">
<img src="media/cam_fifo_3.jpg" width="400"/>
</p>

---

## VGA Output Test (640×480 @ 60Hz)

A stable VGA signal was first verified using a test pattern:

- Resolution: **640×480 @ 60Hz**
- Output: RGB color bars

<p align="center">
<img src="media/vga_color_bars.jpg" width="400"/>
</p>

This confirmed:
- Correct timing generation
- Proper monitor synchronization

---

## Camera Bring-up Progress

### 1. FIFO + LED Validation

- FIFO read path verified using LEDs  
- Stable (but static) data observed on LED outputs  

---

### 2. First Camera-to-VGA Output

Initial live pipeline achieved:

<p align="center">
<img src="media/cam_to_vga_first.gif" width="400"/>
</p>

- Camera data successfully reaches VGA  
- Output appears unstable due to lack of synchronization  

---

### Fullscreen Camera Output (FIFO-driven)

Implemented continuous FIFO read mapped to VGA raster:

<p align="center">
<img src="media/cam_to_vga_fullscreen.gif" width="400"/>
</p>

---

### Unsynchronized Camera Output

Current output stage:

<p align="center">
<img src="media/cam_to_vga_unsync.gif" width="400"/>
</p>

#### Observed behavior:
- Fullscreen dynamic pixel activity  
- Coarse/noisy patterns  
- Visible motion when scene changes  

#### Interpretation:
This confirms the complete pipeline is operational:

✔ Camera is producing pixel data  
✔ FIFO buffering is working  
✔ FPGA is reading data correctly  
✔ VGA pipeline is functional  

---

## ⚠ Current Limitation

The displayed image is **not yet stable** due to lack of proper frame synchronization.

### Root Cause:
- VGA timing is independent of camera timing  
- FIFO is read continuously without:
  - frame alignment (`VSY`)  
  - line alignment (`HREF`)  
- No controlled frame capture (FIFO keeps updating while being read)  

---

## 🔧 Technical Summary

| Component | Status |
|----------|--------|
| SCCB (Camera Config) | ✅ Working |
| FIFO Write (Camera side) | ⚠ Not fully controlled |
| FIFO Read (FPGA side) | ✅ Working |
| VGA Timing | ✅ Stable |
| Frame Synchronization | ❌ Not implemented |

---

## Next Steps

- Implement **frame-synchronous capture**
  - Use `VSY` for frame start  
  - Use `HREF` for line alignment  
- Control FIFO write/read phases  
- Freeze a single frame before VGA readout  
- Improve image stability  

---

## Key Learnings

- Interfacing image sensors requires strict timing alignment  
- FIFO buffers simplify data capture but require careful control  
- VGA output is independent and must be synchronized manually  
- Hardware debugging (LEDs, partial pipelines) is critical  

---

## Current Achievement

A full hardware pipeline has been demonstrated:

> **OV7670 Camera → AL422B FIFO → Spartan-6 FPGA → VGA Display**

Even though the image is not yet stable, this stage proves:
- Real camera data acquisition  
- Successful FPGA-based video output  
- Working end-to-end system  

---

## Planned Improvements

- Frame-stable image capture  
- Basic image processing (threshold / grayscale)  
- Optional BRAM-based image processing demo  

---

## Summary

This project successfully demonstrates **low-level camera interfacing and video output using FPGA**, with the remaining challenge focused on **frame synchronization and stabilization**.

