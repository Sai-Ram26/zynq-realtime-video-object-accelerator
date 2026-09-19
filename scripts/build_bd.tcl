# ==============================================================================
# File: build_bd.tcl
# Project: High-Efficiency Zynq SoC Video Accelerator Architecture
# Description: Vivado Block Design Automation Script for Zynq-7000 SoC Integration
#              Configures ARM Cortex-A9 Processing System (PS7) with:
#                - AXI GP0 Master for Accelerator Register Programming (0x43C00000)
#                - AXI ACP Slave for Coherent L2 Cache DMA Streaming
# ==============================================================================

set design_name zynq_video_accelerator_bd
create_bd_design $design_name

# Create Processing System 7 (PS7)
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]

# Configure PS7 for ZedBoard
# Enable AXI GP0 (Master)
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_ACP {1} \
    CONFIG.PCW_USE_DEFAULT_ACP_USER_VAL {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_PRESET_BANK1_CHECKSUM {0} \
] $ps7

# Create AXI Interconnect for GP0 (Register Control Bus)
set axi_ic_gp0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_gp0]
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] $axi_ic_gp0

# Create Processor System Reset
set ps_rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]

# Connect Clock and Reset Networks
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
               [get_bd_pins processing_system7_0/S_AXI_ACP_ACLK] \
               [get_bd_pins axi_interconnect_gp0/ACLK] \
               [get_bd_pins axi_interconnect_gp0/S00_ACLK] \
               [get_bd_pins axi_interconnect_gp0/M00_ACLK] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins proc_sys_reset_0/ext_reset_in]

connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
               [get_bd_pins axi_interconnect_gp0/ARESETN] \
               [get_bd_pins axi_interconnect_gp0/S00_ARESETN] \
               [get_bd_pins axi_interconnect_gp0/M00_ARESETN]

# Connect GP0 Master to Interconnect Slave
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                    [get_bd_intf_pins axi_interconnect_gp0/S00_AXI]

# Regenerate Layout and Validate
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "======================================================================"
puts " Vivado Block Design '$design_name' Created and Validated Successfully"
puts "======================================================================"
