# ==============================================================================
# Script: program_fpga.tcl
# Description: Connects to ZedBoard via JTAG and downloads the bitstream.
# Location: D:/mini_project2/scripts/program_fpga.tcl
# ==============================================================================

set origin_dir [file normalize [file join [file dirname [info script]] ".."]]
set bit_file   [file join $origin_dir "RELEASE" "encoder.bit"]

if {![file exists $bit_file]} {
    error "ERROR: Bitstream not found at $bit_file. Run build_zedboard.tcl first."
}

puts "========================================================================"
puts "  PROGRAMMING ZEDBOARD FPGA VIA JTAG"
puts "  Bitstream: $bit_file"
puts "========================================================================"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

# Find Zynq XC7Z020 target
set target_device [lindex [get_hw_devices xc7z020_1] 0]
if {$target_device eq ""} {
    set target_device [lindex [get_hw_devices] 1]
}

current_hw_device $target_device
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices $target_device] 0]

set_property PROGRAM.FILE $bit_file $target_device
program_hw_devices $target_device
refresh_hw_device [lindex [get_hw_devices $target_device] 0]

puts "========================================================================"
puts "  SUCCESS: Bitstream successfully loaded into ZedBoard FPGA!"
puts "========================================================================"
