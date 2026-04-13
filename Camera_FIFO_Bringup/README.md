
# OV7670 FIFO Camera Bring-up (Spartan-6 Mimas V2)

## Status

* FPGA programming via `.bin` works
* FIFO read path functional
* SCCB communication established (camera responds to register writes)
* LED output shows stable but non-dynamic data

## Current Behavior

* LEDs show fixed pattern (e.g., D5, D7, D8 ON)
* No live pixel stream yet

## Hardware Setup

* Camera: OV7670 + AL422B FIFO
* Board: Numato Mimas V2 (Spartan-6)
* Interface: Parallel data (D0–D7), FIFO control, SCCB

<p align="center">
<img src="media/cam_fifo_2.jpg" width="400"/>
</p>

<p align="center">
<img src="media/cam_fifo_3.jpg" width="400"/>
</p>

## Next Steps

* Verify FIFO write/capture behavior
* Check camera clock (XCLK)
* Implement full SCCB initialization sequence
* Move to VGA output

## Notes

This stage confirms:

* Camera is powered
* FIFO responds
* SCCB writes are effective

Remaining issue is likely:

* FIFO write timing or camera capture trigger
=======
# OV7670 FIFO Camera Bring-up (Spartan-6 Mimas V2)

## Status

* FPGA programming via `.bin` works
* FIFO read path functional
* SCCB communication established (camera responds to register writes)
* LED output shows stable but non-dynamic data

## Current Behavior

* LEDs show fixed pattern (e.g., D5, D7, D8 ON)
* No live pixel stream yet

## Hardware Setup

* Camera: OV7670 + AL422B FIFO
* Board: Numato Mimas V2 (Spartan-6)
* Interface: Parallel data (D0–D7), FIFO control, SCCB

<p align="center">
<img src="media/cam_fifo_2.jpg" width="400"/>
</p>

<p align="center">
<img src="media/cam_fifo_3.jpg" width="400"/>
</p>

## Next Steps

* Verify FIFO write/capture behavior
* Check camera clock (XCLK)
* Implement full SCCB initialization sequence
* Move to VGA output

## Notes

This stage confirms:

* Camera is powered
* FIFO responds
* SCCB writes are effective

Remaining issue is likely:

* FIFO write timing or camera capture trigger

