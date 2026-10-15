# ==============================================================================
# Vivado TCL Script: ZedBoard H.264 Video Compression Accelerator
# Target: Avnet ZedBoard (xc7z020clg484-1)  –  Vivado 2020.2 or later
#
# USAGE  (from Vivado Tcl Console or Command Line):
#   source ./vivado/bd_zedboard_setup.tcl
#
# What this script does:
#   1. Creates a Vivado project for xc7z020clg484-1
#   2. Adds ALL RTL source files (rtl/compression + rtl/top)
#   3. Instantiates the Zynq PS7 block with board preset
#   4. Instantiates AXI DMA (direct-register mode, no scatter-gather)
#   5. Instantiates our custom video_accelerator_top as an RTL module
#   6. Wires AXI-Lite control and AXI-Stream data paths
#   7. Validates the block design and generates the wrapper
# ==============================================================================

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set proj_name  "zedboard_video_accel"
set proj_dir   [file normalize [file join $repo_root "vivado_project"]]
set part       "xc7z020clg484-1"

puts "========================================================================"
puts "  Building ZedBoard H.264 Video Compression Accelerator Project"
puts "  Device: $part"
puts "  Repo Root: $repo_root"
puts "  Project Dir: $proj_dir"
puts "========================================================================"

# ---------------------------------------------------------------------------
# 1. Create Vivado Project
# ---------------------------------------------------------------------------
create_project $proj_name $proj_dir -part $part -force
catch { set_property board_part em.avnet.com:zed:part0:1.4 [current_project] }

# ---------------------------------------------------------------------------
# 2. Add RTL Source Files
#    Compression pipeline:
#      block_assembler_4x4.v  intra_pred_4x4.v  dct_4x4.v  quant.v
#      cavlc.v  macroblock_skip.v  cabac.v  h264_encoder.v
#    Top-level:
#      video_accelerator_top.v
# ---------------------------------------------------------------------------
add_files -norecurse [glob -nocomplain [file join $repo_root rtl compression *.v]]
add_files -norecurse [glob -nocomplain [file join $repo_root rtl top *.v]]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# 3. Create Block Design
# ---------------------------------------------------------------------------
create_bd_design "system_bd"

# ---------------------------------------------------------------------------
# 4. Zynq-7000 Processing System (PS7)
#    Board preset applies DDR and fixed I/O automatically.
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

# Enable FCLK0 @ 100 MHz (default from board preset)
# Enable High-Performance AXI HP0 slave port for DMA burst transfers
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
] [get_bd_cells processing_system7_0]

# ---------------------------------------------------------------------------
# 5. AXI DMA – Direct Register Mode (no Scatter-Gather)
#    MM2S: DDR -> Stream (pixel data to accelerator)
#    S2MM: Stream -> DDR (bitstream from accelerator back to DDR)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg           {0}  \
    CONFIG.c_sg_include_stscntrl_strm {0}  \
    CONFIG.c_m_axi_mm2s_data_width  {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_burst_size        {16} \
    CONFIG.c_m_axi_s2mm_data_width  {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_s2mm_burst_size        {16} \
] [get_bd_cells axi_dma_0]

# ---------------------------------------------------------------------------
# 6. Instantiate Custom RTL: video_accelerator_top
#    This is our PL-side H.264 encoder core.
# ---------------------------------------------------------------------------
create_bd_cell -type module -reference video_accelerator_top video_accelerator_0

# ---------------------------------------------------------------------------
# 7. AXI Interconnect – Control Path
#    PS M_AXI_GP0 (ARM master) -> AXI DMA S_AXI_LITE + Accelerator S_AXI
# ---------------------------------------------------------------------------
# DMA AXI-Lite control
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} \
    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

# Accelerator AXI-Lite control
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} \
    [get_bd_intf_pins video_accelerator_0/s_axi]

# ---------------------------------------------------------------------------
# 8. AXI High-Performance Path
#    DMA MM2S master -> PS HP0 slave  (read DDR -> pixel stream)
#    DMA S2MM master -> PS HP0 slave  (write bitstream -> DDR)
# ---------------------------------------------------------------------------
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/axi_dma_0/M_AXI_MM2S" Clk "Auto"} \
    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/axi_dma_0/M_AXI_S2MM" Clk "Auto"} \
    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# ---------------------------------------------------------------------------
# 9. AXI-Stream Data Path
#    DMA MM2S -> Accelerator input   (pixels in)
#    Accelerator output -> DMA S2MM  (bitstream out)
# ---------------------------------------------------------------------------
connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins video_accelerator_0/s_axis]

connect_bd_intf_net \
    [get_bd_intf_pins video_accelerator_0/m_axis] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ---------------------------------------------------------------------------
# 10. Connect IRQ from accelerator to PS IRQ[0]
# ---------------------------------------------------------------------------
# (Optional: connect if IRQ is used in SW)
# connect_bd_net [get_bd_pins video_accelerator_0/irq] \
#               [get_bd_pins processing_system7_0/IRQ_F2P]

# ---------------------------------------------------------------------------
# 11. Validate, Save, and Generate Wrapper
# ---------------------------------------------------------------------------
validate_bd_design
save_bd_design

make_wrapper \
    -files [get_files [get_property FILE_NAME [current_bd_design]]] \
    -top

set wrapper_path [glob $proj_dir/${proj_name}.srcs/sources_1/bd/system_bd/hdl/system_bd_wrapper.v]
add_files -norecurse $wrapper_path
update_compile_order -fileset sources_1

# Add constraints file
add_files -fileset constrs_1 -norecurse [file join $repo_root vivado zedboard_constraints.xdc]

puts "========================================================================"
puts "  SUCCESS: Block design created."
puts "  Next steps:"
puts "    1. In Vivado GUI: Run Synthesis (Flow > Run Synthesis)"
puts "    2. Run Implementation (Flow > Run Implementation)"
puts "    3. Generate Bitstream (Flow > Generate Bitstream)"
puts "    4. Export Hardware to Vitis (File > Export > Export Hardware)"
puts "========================================================================"
