# ==============================================================================
# File: zedboard_physical.xdc
# Project: High-Efficiency Zynq SoC Video Accelerator Architecture
# Target Board: Avnet ZedBoard (xc7z020clg484-1)
# Description: Physical Pin Constraints & I/O Standards (LVCMOS33)
# ==============================================================================

# ------------------------------------------------------------------------------
# 100 MHz Oscillator Clock Source (GCLK - Pin Y9)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# ------------------------------------------------------------------------------
# Center Pushbutton Reset (BTNC - Pin P16) - Active Low internally inverted
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN P16 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ------------------------------------------------------------------------------
# User On-Board LEDs (LD0 - LD7) for Status Indicators
# ------------------------------------------------------------------------------
# LD0: Heartbeat / Clock alive
set_property PACKAGE_PIN T22 [get_ports {led_status[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[0]}]

# LD1: PE Busy / Accelerator Active
set_property PACKAGE_PIN T21 [get_ports {led_status[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[1]}]

# LD2: Foreground Object Detected
set_property PACKAGE_PIN U22 [get_ports {led_status[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[2]}]

# LD3: Inpainting Engine Active
set_property PACKAGE_PIN U21 [get_ports {led_status[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[3]}]

# LD4: DCT Transform Valid
set_property PACKAGE_PIN V22 [get_ports {led_status[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[4]}]

# LD5: NAL Word Output Valid
set_property PACKAGE_PIN W22 [get_ports {led_status[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[5]}]

# LD6: AXI Bus Transaction Active
set_property PACKAGE_PIN U19 [get_ports {led_status[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[6]}]

# LD7: Error / Overflow Flag
set_property PACKAGE_PIN U14 [get_ports {led_status[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_status[7]}]

# ------------------------------------------------------------------------------
# User DIP Switches (SW0 - SW7) for Hardware Configuration
# ------------------------------------------------------------------------------
# SW0: Performance Monitor Enable
set_property PACKAGE_PIN F22 [get_ports {sw_config[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[0]}]

# SW1: Bypass Inpainting (Debug Mode)
set_property PACKAGE_PIN G22 [get_ports {sw_config[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[1]}]

# SW2-SW7: Hardware Quantization Parameter Selection (QP 0-51)
set_property PACKAGE_PIN H22 [get_ports {sw_config[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[2]}]

set_property PACKAGE_PIN F21 [get_ports {sw_config[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[3]}]

set_property PACKAGE_PIN H19 [get_ports {sw_config[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[4]}]

set_property PACKAGE_PIN H18 [get_ports {sw_config[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[5]}]

set_property PACKAGE_PIN H17 [get_ports {sw_config[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[6]}]

set_property PACKAGE_PIN M15 [get_ports {sw_config[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_config[7]}]
