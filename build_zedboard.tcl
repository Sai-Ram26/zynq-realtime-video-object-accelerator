# ==============================================================================
# File: build_zedboard.tcl
# Target: Avnet ZedBoard (AMD/Xilinx Zynq-7000 XC7Z020-1CLG484C)
# Flow: Automated Vivado Build Script (Model 4 Construction Manual)
# Usage:
#   vivado -mode batch -source build_zedboard.tcl -notrace
# ==============================================================================

set env(PATH) "C:/AMDDesignTools/2026.1/Vivado/bin/unwrapped/win64.o;$env(PATH)"
set script_dir [file normalize [file dirname [info script]]]
set repo_root  $script_dir
set proj_name  "zedboard_video_accel"
set proj_dir   [file normalize [file join $repo_root "vivado_build"]]
set part       "xc7z020clg484-1"
# Fix Windows posix-spawn crash — this alone prevents Error 17-180 (not maxThreads)
set_param general.usePosixSpawnForFork 0
set_param general.maxThreads 4
set_param synth.maxThreads   2

puts "========================================================================"
puts "  BUILDING COMPLETE ZEDBOARD H.264 VIDEO ACCELERATOR SYSTEM"
puts "  Device     : $part"
puts "  Repository : $repo_root"
puts "  Project Dir: $proj_dir"
puts "========================================================================"

# -----------------------------------------------------------------------------
# 1. Create Vivado Project
# -----------------------------------------------------------------------------
catch {close_project}
file mkdir $proj_dir
create_project $proj_name $proj_dir -part $part -force

# Configure board preset (ZedBoard)
if {[catch {set_property board_part em.avnet.com:zed:part0:1.4 [current_project]}]} {
    puts "INFO: board_part 1.4 not found - trying 1.3"
    catch {set_property board_part em.avnet.com:zed:part0:1.3 [current_project]}
}

# -----------------------------------------------------------------------------
# 2. Add Synthesizable RTL & Constraints (Single-File Architecture)
# -----------------------------------------------------------------------------
set sv_top  [file join $repo_root "h264_accel_top.sv"]
set scaler_rtl [file join $repo_root "rtl" "video_scaler.sv"]
set yuv_scaler_rtl [file join $repo_root "rtl" "model4_yuv420_scaler.sv"]
set yuv_source_frontend_rtl [file join $repo_root "rtl" "model4_yuv420_source_frontend.sv"]
set macroblock_packer_rtl [file join $repo_root "rtl" "model4_yuv420_macroblock_packer.sv"]
set source_to_tiles_rtl [file join $repo_root "rtl" "model4_source_to_tiles.sv"]
set fmp4_muxer_rtl [file join $repo_root "rtl" "model4_fmp4_muxer.sv"]
set xdc_fil [file join $repo_root "zedboard.xdc"]

if {![file exists $sv_top]} {
    return -code error "Authoritative Model-4 RTL not found: $sv_top"
}

add_files -norecurse $sv_top
set_property USED_IN {synthesis implementation} [get_files $sv_top]
if {![file exists $scaler_rtl]} {
    return -code error "Model-4 scaler RTL not found: $scaler_rtl"
}
add_files -norecurse $scaler_rtl
set_property USED_IN {synthesis implementation simulation} [get_files $scaler_rtl]
if {![file exists $yuv_scaler_rtl]} {
    return -code error "Model-4 YUV420 scaler RTL not found: $yuv_scaler_rtl"
}
add_files -norecurse $yuv_scaler_rtl
set_property USED_IN {synthesis implementation simulation} [get_files $yuv_scaler_rtl]
if {![file exists $yuv_source_frontend_rtl]} {
    return -code error "Model-4 YUV420 source frontend RTL not found: $yuv_source_frontend_rtl"
}
add_files -norecurse $yuv_source_frontend_rtl
set_property USED_IN {synthesis implementation simulation} [get_files $yuv_source_frontend_rtl]
if {![file exists $macroblock_packer_rtl]} {
    return -code error "Model-4 macroblock packer RTL not found: $macroblock_packer_rtl"
}
add_files -norecurse $macroblock_packer_rtl
set_property USED_IN {synthesis implementation simulation} [get_files $macroblock_packer_rtl]
if {![file exists $source_to_tiles_rtl]} {
    return -code error "Model-4 source-to-tiles RTL not found: $source_to_tiles_rtl"
}
add_files -norecurse $source_to_tiles_rtl
set_property USED_IN {synthesis implementation simulation} [get_files $source_to_tiles_rtl]
if {![file exists $fmp4_muxer_rtl]} {
    return -code error "Model-4 fMP4 muxer RTL not found: $fmp4_muxer_rtl"
}
add_files -norecurse $fmp4_muxer_rtl
set_property USED_IN {synthesis implementation simulation} [get_files $fmp4_muxer_rtl]
update_compile_order -fileset sources_1
puts "INFO: Added Model-4 accelerator RTL, streaming scaler, and fMP4 hardware muxer"

set mem_fil [file join $repo_root "pico_fw.mem"]
if {![file exists $mem_fil]} {
    return -code error "PicoRV32 firmware image not found: $mem_fil"
}
add_files -norecurse $mem_fil
set_property USED_IN {synthesis simulation} [get_files $mem_fil]
puts "INFO: Added firmware memory file: $mem_fil"

if {![file exists $xdc_fil]} {
    return -code error "ZedBoard constraints not found: $xdc_fil"
}
add_files -fileset constrs_1 -norecurse $xdc_fil
set_property USED_IN {synthesis implementation} [get_files $xdc_fil]
puts "INFO: Added constraints file: $xdc_fil"

# -----------------------------------------------------------------------------
# 3. Create Block Design
# -----------------------------------------------------------------------------
create_bd_design "design_1"
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# 4. Processing System 7 (Zynq-7000 PS)
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7

# Apply ZedBoard preset (configures DDR, Ethernet MIO, UART, Clocks)
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7]

# Configure PS7: 50MHz FCLK0, GP0 Master, HP0 Slave (DMA), HP2 Slave (Memory Master), IRQ_F2P
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.0} \
    CONFIG.PCW_USE_M_AXI_GP0            {1}     \
    CONFIG.PCW_USE_S_AXI_HP0            {1}     \
    CONFIG.PCW_USE_S_AXI_HP2            {1}     \
    CONFIG.PCW_USE_FABRIC_INTERRUPT     {1}     \
    CONFIG.PCW_IRQ_F2P_INTR             {1}     \
] [get_bd_cells ps7]

# -----------------------------------------------------------------------------
# 5. AXI DMA - S2MM Only Scatter/Gather for H.264 Variable-Length Output (HP0)
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0

set_property -dict [list \
    CONFIG.c_include_sg                {0}  \
    CONFIG.c_include_mm2s              {0}  \
    CONFIG.c_include_s2mm              {1}  \
    CONFIG.c_sg_include_stscntrl_strm  {0}  \
    CONFIG.c_sg_length_width           {26} \
    CONFIG.c_m_axi_s2mm_data_width     {64} \
    CONFIG.c_s_axis_s2mm_tdata_width   {64} \
    CONFIG.c_s2mm_burst_size           {16} \
] [get_bd_cells axi_dma_0]

# Source-frame DMA: MM2S reads packed YUV420 from DDR and S2MM stores the
# FPGA-scaled macroblock tiles back to the encoder input buffer.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_scale
set_property -dict [list \
    CONFIG.c_include_sg                {0}  \
    CONFIG.c_include_mm2s              {1}  \
    CONFIG.c_include_s2mm              {1}  \
    CONFIG.c_sg_include_stscntrl_strm  {0}  \
    CONFIG.c_sg_length_width           {26} \
    CONFIG.c_m_axi_mm2s_data_width     {64} \
    CONFIG.c_m_axi_s2mm_data_width     {64} \
    CONFIG.c_m_axis_mm2s_tdata_width   {64} \
    CONFIG.c_s_axis_s2mm_tdata_width   {64} \
    CONFIG.c_mm2s_burst_size           {16} \
    CONFIG.c_s2mm_burst_size           {16} \
] [get_bd_cells axi_dma_scale]

# -----------------------------------------------------------------------------
# 6. Custom RTL Module Reference: h264_accel_top
# -----------------------------------------------------------------------------
create_bd_cell -type module -reference h264_accel_top h264_accel_top_0

# -----------------------------------------------------------------------------
# 7. Control Interconnect (PS M_AXI_GP0 -> Accelerator S_AXI_CTRL & DMA S_AXI_LITE)
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_gp0
set_property CONFIG.NUM_MI {3} [get_bd_cells axi_interconnect_gp0]

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_gp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M00_AXI] [get_bd_intf_pins h264_accel_top_0/s_axi_ctrl]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_gp0/M02_AXI] [get_bd_intf_pins axi_dma_scale/S_AXI_LITE]

# -----------------------------------------------------------------------------
# 8. Output DDR Interconnect (DMA M_AXI_S2MM -> PS S_AXI_HP0)
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_hp0
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {1}] [get_bd_cells axi_interconnect_hp0]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_interconnect_hp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_scale/M_AXI_MM2S] [get_bd_intf_pins axi_interconnect_hp0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_scale/M_AXI_S2MM] [get_bd_intf_pins axi_interconnect_hp0/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_hp0/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]

# -----------------------------------------------------------------------------
# 9. Custom Memory Master Interconnect (Accelerator M_AXI_MEM -> PS S_AXI_HP2)
#    Converts 64-bit AXI4 to Zynq PS native 64-bit AXI3
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_hp2
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_interconnect_hp2]

connect_bd_intf_net [get_bd_intf_pins h264_accel_top_0/m_axi_mem] [get_bd_intf_pins axi_interconnect_hp2/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_hp2/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP2]

# -----------------------------------------------------------------------------
# 10. AXI4-Stream Video Output: Accelerator M_AXIS_H264 -> DMA S_AXIS_S2MM
# -----------------------------------------------------------------------------
connect_bd_intf_net [get_bd_intf_pins h264_accel_top_0/m_axis_h264] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins axi_dma_scale/M_AXIS_MM2S] [get_bd_intf_pins h264_accel_top_0/s_axis_source]
connect_bd_intf_net [get_bd_intf_pins h264_accel_top_0/m_axis_scaled_tiles] [get_bd_intf_pins axi_dma_scale/S_AXIS_S2MM]

# -----------------------------------------------------------------------------
# 11. Clocks and Reset Tree (FCLK_CLK0 = 50 MHz)
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

set fclk [get_bd_pins ps7/FCLK_CLK0]
set frst [get_bd_pins ps7/FCLK_RESET0_N]

connect_bd_net $fclk [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net $frst [get_bd_pins proc_sys_reset_0/ext_reset_in]

set rst [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

# Clock distributions
connect_bd_net $fclk [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net $fclk [get_bd_pins ps7/S_AXI_HP0_ACLK]
connect_bd_net $fclk [get_bd_pins ps7/S_AXI_HP2_ACLK]

connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/S00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/M00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/M01_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/M02_ACLK]

connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/S00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/S01_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/S02_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/M00_ACLK]

connect_bd_net $fclk [get_bd_pins axi_interconnect_hp2/ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp2/S00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp2/M00_ACLK]

connect_bd_net $fclk [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net $fclk [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net $fclk [get_bd_pins axi_dma_scale/s_axi_lite_aclk]
connect_bd_net $fclk [get_bd_pins axi_dma_scale/m_axi_mm2s_aclk]
connect_bd_net $fclk [get_bd_pins axi_dma_scale/m_axi_s2mm_aclk]

connect_bd_net $fclk [get_bd_pins h264_accel_top_0/clk]

# Reset distributions
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/S00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/M00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/M01_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/M02_ARESETN]

connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/S00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/S01_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/S02_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/M00_ARESETN]

connect_bd_net $rst [get_bd_pins axi_interconnect_hp2/ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp2/S00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp2/M00_ARESETN]

connect_bd_net $rst [get_bd_pins axi_dma_0/axi_resetn]
connect_bd_net $rst [get_bd_pins axi_dma_scale/axi_resetn]
connect_bd_net $rst [get_bd_pins h264_accel_top_0/resetn]

# -----------------------------------------------------------------------------
# 12. Interrupts (xlconcat -> PS IRQ_F2P)
# -----------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property CONFIG.NUM_PORTS {3} [get_bd_cells xlconcat_0]

connect_bd_net [get_bd_pins h264_accel_top_0/irq]        [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut]       [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins axi_dma_scale/s2mm_introut]   [get_bd_pins xlconcat_0/In2]
connect_bd_net [get_bd_pins xlconcat_0/dout]             [get_bd_pins ps7/IRQ_F2P]

# -----------------------------------------------------------------------------
# 13. Diagnostic External LED Ports
# -----------------------------------------------------------------------------
make_bd_pins_external [get_bd_pins h264_accel_top_0/led0]
set_property name led0 [get_bd_ports led0_0]

make_bd_pins_external [get_bd_pins h264_accel_top_0/led1]
set_property name led1 [get_bd_ports led1_0]

make_bd_pins_external [get_bd_pins h264_accel_top_0/led2]
set_property name led2 [get_bd_ports led2_0]

# -----------------------------------------------------------------------------
# 14. Address Assignments
# -----------------------------------------------------------------------------
assign_bd_address
set_property offset 0x43C00000 [get_bd_addr_segs {ps7/Data/SEG_h264_accel_top_0_reg0}]
set_property range  64K        [get_bd_addr_segs {ps7/Data/SEG_h264_accel_top_0_reg0}]

set_property offset 0x40400000 [get_bd_addr_segs {ps7/Data/SEG_axi_dma_0_Reg}]
set_property range  64K        [get_bd_addr_segs {ps7/Data/SEG_axi_dma_0_Reg}]
set_property offset 0x40500000 [get_bd_addr_segs {ps7/Data/SEG_axi_dma_scale_Reg}]
set_property range  64K        [get_bd_addr_segs {ps7/Data/SEG_axi_dma_scale_Reg}]

# -----------------------------------------------------------------------------
# 15. Validate Block Design & Generate Top HDL Wrapper
# -----------------------------------------------------------------------------
regenerate_bd_layout
validate_bd_design
save_bd_design

set bd_file [get_files [get_property FILE_NAME [current_bd_design]]]
set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
if {[llength $wrapper_files] == 0 || ![file exists [lindex $wrapper_files 0]]} {
    set wrapper_files [glob -nocomplain $proj_dir/*.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v]
    if {[llength $wrapper_files] == 0} {
        set wrapper_files [glob -nocomplain $proj_dir/*.srcs/sources_1/bd/design_1/hdl/design_1_wrapper.v]
    }
}
add_files -norecurse $wrapper_files
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "INFO: Top wrapper established: $wrapper_files"

puts "========================================================================"
puts "  BLOCK DESIGN AND SYSTEM INTEGRATION SUCCESSFUL!"
puts "  Accelerator Control Address : 0x43C00000"
puts "  AXI DMA Control Address     : 0x40400000"
puts "========================================================================"

# -----------------------------------------------------------------------------
# 16. Synthesis, Implementation, Bitstream & Hardware Export (Model 4 §14)
# -----------------------------------------------------------------------------
file mkdir [file join $repo_root "RELEASE"]

puts "========================================================================"
puts "  STARTING SYNTHESIS & IMPLEMENTATION FOR ZEDBOARD..."
puts "========================================================================"

# Apply Fast Runtime-Optimized Strategy with Quick placement
set_property strategy "Flow_RuntimeOptimized" [get_runs synth_1]
set_property strategy "Flow_RuntimeOptimized" [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE    Quick            [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE      RuntimeOptimized [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE    RuntimeOptimized [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED     false [get_runs impl_1]
set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED    false [get_runs impl_1]

# Prevent Windows sub-process fork bug
set_param general.usePosixSpawnForFork 0

set hook_file [file normalize [file join $repo_root "vivado_pre_hook.tcl"]]
set_property STEPS.SYNTH_DESIGN.TCL.PRE $hook_file [get_runs synth_1]
set_property STEPS.INIT_DESIGN.TCL.PRE $hook_file [get_runs impl_1]

launch_runs synth_1 -jobs 1
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed! Check synth_1/runme.log"
    return -code error "Synthesis failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation/Bitstream generation failed!"
    return -code error "Implementation failed"
}

# Copy bitstream to RELEASE directory
set bit_file [file join $proj_dir "${proj_name}.runs" "impl_1" "design_1_wrapper.bit"]
if {![file exists $bit_file]} {
    return -code error "Bitstream run completed without producing $bit_file"
}
file copy -force $bit_file [file join $repo_root "RELEASE" "encoder.bit"]
puts "SUCCESS: Generated [file join $repo_root "RELEASE" "encoder.bit"]"

# A bitstream can be generated even when setup timing is violated. Report this
# explicitly so a successful Vivado run is not mistaken for timing closure.
open_run impl_1
set timing_paths [get_timing_paths -slack_lesser_than 0 -max_paths 1]
if {[llength $timing_paths] != 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    puts "WARNING: Timing constraints are not met; worst setup slack is $worst_slack ns."
} else {
    puts "SUCCESS: No failing setup timing paths reported."
}

# Export hardware platform (XSA)
write_hw_platform -fixed -include_bit -force -file [file join $repo_root "RELEASE" "encoder.xsa"]
puts "SUCCESS: Exported hardware platform to RELEASE/encoder.xsa"
puts "========================================================================"
puts "  BUILD PIPELINE COMPLETED SUCCESSFULLY!"
puts "========================================================================"
