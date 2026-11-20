# ==============================================================================
# program_zedboard.tcl — One-Click ZedBoard FPGA Bitstream Programmer
# ==============================================================================
set script_dir [file normalize [file dirname [info script]]]
set bit_file   [file join $script_dir "RELEASE" "encoder.bit"]

if {![file exists $bit_file]} {
    puts "ERROR: Bitstream not found at $bit_file"
    return -code error "Bitstream not found"
}

puts "Connecting to hardware target..."
open_hw_manager
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    puts "Already connected or notice: $err"
}

open_hw_target
set dev [get_hw_devices xc7z020_1]
if {[llength $dev] == 0} {
    # Fallback to first device
    set dev [lindex [get_hw_devices] 0]
}
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

puts "Programming $bit_file to $dev..."
set_property PROGRAM.FILE $bit_file $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "========================================================================"
puts "  SUCCESS: ZEDBOARD FPGA BITSTREAM PROGRAMMED!"
puts "  LD0 (Heartbeat) and LD1 (Active) are now operational."
puts "========================================================================"
