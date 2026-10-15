## =============================================================================
## ZedBoard (Avnet) - Zynq-7000 SoC (xc7z020clg484-1)
## Pin Constraints File for Real-Time H.264 Video Compression Accelerator
## Student: G. Sai Ram (1602-24-735-163)
## Institution: Vasavi College of Engineering (Autonomous), Hyderabad
##
## Notes on Zynq Architecture Constraints:
##   1. Clocks (100 MHz FCLK0), DDR3 Memory (512MB), Gigabit Ethernet, and
##      USB-UART (MIO 48/49) are internal hardened peripherals on the Zynq PS.
##      They are automatically assigned by the Vivado Board Preset for ZedBoard
##      (em.avnet.com:zed:part0:1.4) and do NOT require physical PL pin entries.
##   2. This constraints file configures the physical Programmable Logic (PL)
##      peripherals on the ZedBoard:
##        - User Slide Switches SW0-SW7 (Bank 35, 2.5V LVCMOS)
##        - User LEDs LD0-LD7          (Bank 33, 3.3V LVCMOS)
##        - Center Pushbutton BTNC     (Bank 34, 2.5V LVCMOS - Manual Reset)
## =============================================================================

## ============================================================
## 1. Timing Constraints (100 MHz System Processing Clock)
## ============================================================
# Propagated automatically from processing_system7_0/FCLK_CLK0 (10.0 ns period)
# Explicit timing constraint for out-of-context or standalone synthesis:
create_clock -period 10.000 -name clk_100mhz [get_pins -hierarchical *aclk*]

## ============================================================
## 2. User Slide Switches (8 switches - Bank 35 @ 2.5V)
##    SW[5:0] : Real-time Hardware QP override (0 to 51)
##    SW[6]   : Compression Bypass Mode
##    SW[7]   : Manual Diagnostic Hold
## ============================================================
set_property PACKAGE_PIN F22 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[0]}]

set_property PACKAGE_PIN G22 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[1]}]

set_property PACKAGE_PIN H22 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[2]}]

set_property PACKAGE_PIN F21 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[3]}]

set_property PACKAGE_PIN H19 [get_ports {sw[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[4]}]

set_property PACKAGE_PIN H18 [get_ports {sw[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[5]}]

set_property PACKAGE_PIN H17 [get_ports {sw[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[6]}]

set_property PACKAGE_PIN M15 [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {sw[7]}]

## ============================================================
## 3. User LEDs (8 LEDs - Bank 33 @ 3.3V)
##    LD0 : Accelerator Busy (Compression active)
##    LD1 : Block Compression Done pulse
##    LD2 : AXI4-Stream Slave Active (receiving video pixels)
##    LD3 : AXI4-Stream Master Active (transmitting H.264 bitstream)
##    LD4 : Accelerator Core Enabled (AXI-Lite CTRL[0])
##    LD5 : Compression Pipeline Enabled (AXI-Lite CTRL[2])
##    LD6 : Frame Complete IRQ Pending
##    LD7 : 1.5 Hz Clock Heartbeat (Alive indicator)
## ============================================================
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

## ============================================================
## 4. Center Pushbutton BTNC (Bank 34 @ 2.5V - Optional Manual Reset)
## ============================================================
# set_property PACKAGE_PIN P16 [get_ports {btnc}]
# set_property IOSTANDARD LVCMOS25 [get_ports {btnc}]

## ============================================================
## 5. Bitstream Configuration Settings for ZedBoard
## ============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
