# ==============================================================================
# File: zedboard.xdc
# Target: Avnet ZedBoard (Zynq-7000 XC7Z020-1CLG484C)
# Description: Minimal PL physical constraints for diagnostic LEDs
# Standard: Bank 33 @ 3.3V LVCMOS
# ==============================================================================

# Diagnostic LED 0: System alive / heartbeat (LD0)
set_property PACKAGE_PIN T22 [get_ports {led0}]
set_property IOSTANDARD LVCMOS33 [get_ports {led0}]

# Diagnostic LED 1: Encoder active status (LD1)
set_property PACKAGE_PIN T21 [get_ports {led1}]
set_property IOSTANDARD LVCMOS33 [get_ports {led1}]

# Diagnostic LED 2: Job complete / fault indicator (LD2)
set_property PACKAGE_PIN U22 [get_ports {led2}]
set_property IOSTANDARD LVCMOS33 [get_ports {led2}]

# Configuration Bank Voltage Select
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Timing exceptions: Asynchronous diagnostic LEDs do not require setup/hold checks against clk_fpga_0
set_false_path -to [get_ports {led0 led1 led2}]


