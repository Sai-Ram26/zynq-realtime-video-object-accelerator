# ==============================================================================
# Vivado TCL Script: Automated Block Design Setup for ZedBoard (xc7z020clg484-1)
# Project: Real-Time Hardware Video Compression Accelerator with Object Removal
# ==============================================================================

set proj_name "zedboard_video_accelerator"
set proj_dir  "./vivado_project"
set part      "xc7z020clg484-1"

puts "======================================================================"
puts "  BUILDING ZEDBOARD ZYNQ-7000 VIDEO ACCELERATOR HARDWARE PROJECT"
puts "======================================================================"

# 1. Create Project
create_project $proj_name $proj_dir -part $part -force
set_property board_part em.avnet.com:zed:part0:1.4 [current_project]

# 2. Add RTL Source Files
add_files -norecurse [glob ../rtl/object_removal/*.v]
add_files -norecurse [glob ../rtl/compression/*.v]
add_files -norecurse [glob ../rtl/top/*.v]
update_compile_order -fileset sources_1

# 3. Create Block Design
create_bd_design "system_bd"

# 4. Instantiate Zynq-7000 Processing System (PS7)
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" }  [get_bd_cells processing_system7_0]

# Enable High-Performance AXI HP0 Slave port (for AXI DMA high-bandwidth transfers)
set_property -dict [list CONFIG::PCW_USE_S_AXI_HP0 {1}] [get_bd_cells processing_system7_0]

# 5. Instantiate AXI DMA (Direct Memory Access Engine)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
] [get_bd_cells axi_dma_0]

# 6. Instantiate Custom Video Accelerator Top Module (RTL Module in BD)
create_bd_cell -type module -reference video_accelerator_top video_accelerator_0

# 7. Interconnect Automation (AXI SmartConnect & Peripheral Interconnect)
# Connect AXI-Lite Control (PS Master -> Accelerator & DMA Slaves)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Master "/processing_system7_0/M_AXI_GP0" \
    Clk "Auto" } [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Master "/processing_system7_0/M_AXI_GP0" \
    Clk "Auto" } [get_bd_intf_pins video_accelerator_0/s_axi]

# Connect AXI High-Performance Memory Bus (DMA Master -> PS HP0 Slave)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Master "/axi_dma_0/M_AXI_MM2S" \
    Clk "Auto" } [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Master "/axi_dma_0/M_AXI_S2MM" \
    Clk "Auto" } [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# 8. Connect AXI-Stream Video Pipeline (DMA MM2S -> Accelerator -> DMA S2MM)
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins video_accelerator_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins video_accelerator_0/m_axis] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# 9. Validate & Generate Wrapper
validate_bd_design
save_bd_design
make_wrapper -files [get_files [get_property FILE_NAME [current_bd_design]]] -top
add_files -norecurse [glob $proj_dir/${proj_name}.srcs/sources_1/bd/system_bd/hdl/system_bd_wrapper.v]

puts "======================================================================"
puts "  SUCCESS: Vivado Block Design for ZedBoard created and validated!"
puts "======================================================================"
