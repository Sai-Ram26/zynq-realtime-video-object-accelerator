# ==============================================================================
# Script: build_zedboard_bitstream.tcl
# Target: Avnet ZedBoard (AMD/Xilinx Zynq-7000 XC7Z020-1CLG484C)
# Flow:   Automated Project Creation -> Block Design -> Synthesis ->
#         Implementation -> Bitstream Generation -> Export Hardware XSA
#
# Usage (in Vivado Tcl Console or Command Line):
#   vivado -mode batch -source scripts/build_zedboard_bitstream.tcl
# ==============================================================================

set script_dir [file normalize [file dirname [info script]]]
set proj_dir   [file normalize [file join $script_dir ".." "vivado_project"]]
set rtl_dir    [file normalize [file join $script_dir ".." "fpga" "rtl"]]
set constr_dir [file normalize [file join $script_dir ".." "fpga" "constraints"]]
set vitis_dir  [file normalize [file join $script_dir ".." "vitis"]]

set proj_name  "zedboard_video_accelerator"
set part       "xc7z020clg484-1"

puts "======================================================================"
puts "  STARTING COMPLETE ZEDBOARD HARDWARE IMPLEMENTATION FLOW"
puts "  Device: $part"
puts "  Output Project: $proj_dir"
puts "======================================================================"

# 1. Create Vivado Project
file mkdir $proj_dir
create_project $proj_name $proj_dir -part $part -force

# Set board part if available
catch { set_property board_part em.avnet.com:zed:part0:1.4 [current_project] }

# 2. Add Synthesizable RTL Modules
add_files -norecurse [list \
    [file join $rtl_dir "rgb2yuv.v"] \
    [file join $rtl_dir "streaming_scaler.v"] \
    [file join $rtl_dir "block_assembler_4x4.v"] \
    [file join $rtl_dir "dct_4x4.v"] \
    [file join $rtl_dir "quant.v"] \
    [file join $rtl_dir "cavlc.v"] \
    [file join $rtl_dir "axis_fifo.v"] \
    [file join $rtl_dir "axi_lite_regs.v"] \
    [file join $rtl_dir "riscv_custom_video_decoder.v"] \
    [file join $rtl_dir "video_accelerator_top.v"] \
]
update_compile_order -fileset sources_1

# 3. Add ZedBoard Physical & Timing Constraints
add_files -fileset constrs_1 -norecurse [file join $constr_dir "zedboard_constraints.xdc"]

# 4. Create Block Design
create_bd_design "system_bd"

# Instantiate Zynq-7000 Processing System (PS7)
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
catch { apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} [get_bd_cells $ps7] }

# Configure PS7: 100MHz PL Clock, GP0 Master, HP0 High-Performance Slave
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
] $ps7

# Instantiate AXI DMA (Simple Register Direct Mode for Video Streaming)
set axi_dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
] $axi_dma

# Instantiate Custom Video Accelerator Top Module
set vid_accel [create_bd_cell -type module -reference video_accelerator_top video_accelerator_0]

# Interconnect Automation: AXI-Lite Control (PS GP0 -> Accelerator & DMA)
catch {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins $axi_dma/S_AXI_LITE]
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins $vid_accel/s_axi]
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/axi_dma_0/M_AXI_MM2S" Clk "Auto"} [get_bd_intf_pins $ps7/S_AXI_HP0]
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/axi_dma_0/M_AXI_S2MM" Clk "Auto"} [get_bd_intf_pins $ps7/S_AXI_HP0]
}

# Connect AXI4-Stream Video Pipeline: DMA MM2S -> Accelerator -> DMA S2MM
connect_bd_intf_net [get_bd_intf_pins $axi_dma/M_AXIS_MM2S] [get_bd_intf_pins $vid_accel/s_axis]
connect_bd_intf_net [get_bd_intf_pins $vid_accel/m_axis] [get_bd_intf_pins $axi_dma/S_AXIS_S2MM]

# Validate & Generate HDL Wrapper
regenerate_bd_layout
validate_bd_design
save_bd_design

set bd_file [get_files [get_property FILE_NAME [current_bd_design]]]
make_wrapper -files $bd_file -top
set wrapper_file [glob -nocomplain $proj_dir/${proj_name}.srcs/sources_1/bd/system_bd/hdl/system_bd_wrapper.v]
if {[file exists $wrapper_file]} {
    add_files -norecurse $wrapper_file
    set_property top system_bd_wrapper [current_fileset]
}

puts "--> Block Design validated. Launching Synthesis & Implementation..."

# 5. Launch Synthesis & Implementation to Bitstream
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 6. Export Hardware Platform (XSA) with Bitstream for Vitis
file mkdir $vitis_dir
set xsa_path [file join $vitis_dir "system_bd_wrapper.xsa"]
write_hw_platform -fixed -include_bit -force -file $xsa_path

puts "======================================================================"
puts "  SYNTHESIS & IMPLEMENTATION COMPLETE!"
puts "  Bitstream: [glob -nocomplain $proj_dir/${proj_name}.runs/impl_1/*.bit]"
puts "  Hardware Platform Exported for Vitis: $xsa_path"
puts "======================================================================"
