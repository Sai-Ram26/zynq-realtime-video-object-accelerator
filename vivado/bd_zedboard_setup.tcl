# ==============================================================================
# Vivado TCL Script: ZedBoard H.264 Video Compression Accelerator
# Target: Avnet ZedBoard (xc7z020clg484-1) – Vivado 2017.4 and later
#
# USAGE (from Vivado Tcl Console):
#   cd {C:/path/to/repo}
#   source vivado/bd_zedboard_setup.tcl
#
# What this script does:
#   1.  Creates a Vivado project targeting xc7z020clg484-1
#   2.  Adds all RTL sources (compression + top + riscv)
#   3.  Creates Block Design with:
#         - Zynq PS7 (board preset, FCLK0=100 MHz, HP0 enabled)
#         - AXI DMA  (direct-register, 32-bit, MM2S + S2MM)
#         - video_accelerator_top (RTL module reference)
#         - axi_interconnect_gp0  (1 master -> 2 slaves: DMA+Accel)
#         - axi_interconnect_hp0  (2 masters: DMA -> 1 slave: HP0)
#         - proc_sys_reset_0 for synchronous peripheral reset
#   4.  Wires clocks, resets, AXI-Lite, AXI-Stream manually
#       (avoids apply_bd_automation issues in Vivado 2017.4)
#   5.  Ties off unused RISC-V external ports to 0
#   6.  Sets address map, validates, saves, generates wrapper + adds XDC
# ==============================================================================

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set proj_name  "zedboard_video_accel"
set proj_dir   [file normalize [file join $repo_root "vivado_project"]]
set part       "xc7z020clg484-1"

puts "========================================================================"
puts "  Building ZedBoard H.264 Video Compression Accelerator"
puts "  Device  : $part"
puts "  Repo    : $repo_root"
puts "  Project : $proj_dir"
puts "========================================================================"

# ---------------------------------------------------------------------------
# 1.  Create Vivado project
# ---------------------------------------------------------------------------
create_project $proj_name $proj_dir -part $part -force

# Try board part – Vivado 2017.4 ships 1.3; newer versions have 1.4
if {[catch {set_property board_part em.avnet.com:zed:part0:1.4 [current_project]}]} {
    puts "INFO: board_part 1.4 not found – trying 1.3 (Vivado 2017.4 compatible)"
    catch {set_property board_part em.avnet.com:zed:part0:1.3 [current_project]}
}

# ---------------------------------------------------------------------------
# 2.  Add RTL source files
# ---------------------------------------------------------------------------
set comp_files [glob -nocomplain [file join $repo_root rtl compression *.v]]
set top_files  [glob -nocomplain [file join $repo_root rtl top       *.v]]
set rv_files   [glob -nocomplain [file join $repo_root rtl riscv     *.v]]

if {[llength $comp_files] == 0} {
    error "ERROR: No .v files in rtl/compression/ – check repo_root: $repo_root"
}
add_files -norecurse $comp_files
add_files -norecurse $top_files
add_files -norecurse $rv_files
update_compile_order -fileset sources_1
puts "INFO: Added [expr [llength $comp_files]+[llength $top_files]+[llength $rv_files]] RTL files."

# ---------------------------------------------------------------------------
# 3.  Create Block Design
# ---------------------------------------------------------------------------
create_bd_design "system_bd"
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# 4.  Zynq PS7
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0            {1}   \
    CONFIG.PCW_USE_S_AXI_HP0            {1}   \
    CONFIG.PCW_USE_FABRIC_INT           {1}   \
    CONFIG.PCW_IRQ_F2P_INTR             {1}   \
] [get_bd_cells processing_system7_0]

# ---------------------------------------------------------------------------
# 5.  AXI DMA – direct-register mode (no Scatter-Gather)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0

set_property -dict [list \
    CONFIG.c_include_sg                {0}  \
    CONFIG.c_sg_include_stscntrl_strm  {0}  \
    CONFIG.c_m_axi_mm2s_data_width     {32} \
    CONFIG.c_m_axis_mm2s_tdata_width   {32} \
    CONFIG.c_mm2s_burst_size           {16} \
    CONFIG.c_m_axi_s2mm_data_width     {32} \
    CONFIG.c_s2mm_burst_size           {16} \
] [get_bd_cells axi_dma_0]

# ---------------------------------------------------------------------------
# 6.  Custom RTL: video_accelerator_top
# ---------------------------------------------------------------------------
create_bd_cell -type module -reference video_accelerator_top video_accelerator_0

# ---------------------------------------------------------------------------
# 7.  AXI Interconnect – Control path
#     1 master (GP0)  ->  2 slaves (DMA lite + Accelerator)
#     This avoids the [BD 41-1811] error by explicitly wiring all ports.
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_gp0
set_property CONFIG.NUM_MI {2} [get_bd_cells axi_interconnect_gp0]

connect_bd_intf_net \
    [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_interconnect_gp0/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_interconnect_gp0/M00_AXI] \
    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

connect_bd_intf_net \
    [get_bd_intf_pins axi_interconnect_gp0/M01_AXI] \
    [get_bd_intf_pins video_accelerator_0/s_axi]

# ---------------------------------------------------------------------------
# 8.  AXI Interconnect – HP0 data path
#     2 masters (DMA MM2S + S2MM)  ->  1 slave (HP0)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_hp0
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] \
    [get_bd_cells axi_interconnect_hp0]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] \
    [get_bd_intf_pins axi_interconnect_hp0/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
    [get_bd_intf_pins axi_interconnect_hp0/S01_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_interconnect_hp0/M00_AXI] \
    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# ---------------------------------------------------------------------------
# 9.  AXI-Stream data path
# ---------------------------------------------------------------------------
connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins video_accelerator_0/s_axis]

connect_bd_intf_net \
    [get_bd_intf_pins video_accelerator_0/m_axis] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ---------------------------------------------------------------------------
# 10. Clock connections (all from FCLK_CLK0 = 100 MHz)
# ---------------------------------------------------------------------------
set fclk [get_bd_pins processing_system7_0/FCLK_CLK0]

# PS AXI clock ports
connect_bd_net $fclk [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net $fclk [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

# GP0 interconnect clocks
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/S00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/M00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_gp0/M01_ACLK]

# HP0 interconnect clocks
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/S00_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/S01_ACLK]
connect_bd_net $fclk [get_bd_pins axi_interconnect_hp0/M00_ACLK]

# DMA clocks
connect_bd_net $fclk [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net $fclk [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
connect_bd_net $fclk [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]

# Accelerator clock
connect_bd_net $fclk [get_bd_pins video_accelerator_0/aclk]

# ---------------------------------------------------------------------------
# 11. Reset tree (PS FCLK_RESET0_N -> proc_sys_reset -> peripheral_aresetn)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0

connect_bd_net \
    [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

connect_bd_net \
    [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

set rst [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

# GP0 interconnect resets
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/S00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/M00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_gp0/M01_ARESETN]

# HP0 interconnect resets
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/S00_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/S01_ARESETN]
connect_bd_net $rst [get_bd_pins axi_interconnect_hp0/M00_ARESETN]

# DMA and accelerator resets
connect_bd_net $rst [get_bd_pins axi_dma_0/axi_resetn]
connect_bd_net $rst [get_bd_pins video_accelerator_0/aresetn]

# ---------------------------------------------------------------------------
# 12. IRQ: accelerator irq -> PS IRQ_F2P[0]
# ---------------------------------------------------------------------------
connect_bd_net \
    [get_bd_pins video_accelerator_0/irq] \
    [get_bd_pins processing_system7_0/IRQ_F2P]

# ---------------------------------------------------------------------------
# 13. Physical board I/O – LEDs and Switches
# ---------------------------------------------------------------------------
catch {
    make_bd_pins_external [get_bd_pins video_accelerator_0/led]
    set_property name led [get_bd_ports led_0]
}
catch {
    make_bd_pins_external [get_bd_pins video_accelerator_0/sw]
    set_property name sw  [get_bd_ports sw_0]
}

# ---------------------------------------------------------------------------
# 14. Tie off unused RISC-V external ports (not driven in this BD)
# ---------------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] \
    [get_bd_cells const_zero]
connect_bd_net \
    [get_bd_pins const_zero/dout] \
    [get_bd_pins video_accelerator_0/ext_riscv_valid]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero32
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {32}] \
    [get_bd_cells const_zero32]
connect_bd_net [get_bd_pins const_zero32/dout] \
    [get_bd_pins video_accelerator_0/ext_riscv_instr]
connect_bd_net [get_bd_pins const_zero32/dout] \
    [get_bd_pins video_accelerator_0/ext_riscv_rs1]
connect_bd_net [get_bd_pins const_zero32/dout] \
    [get_bd_pins video_accelerator_0/ext_riscv_rs2]
connect_bd_net [get_bd_pins const_zero32/dout] \
    [get_bd_pins video_accelerator_0/ext_riscv_rs3]

# ---------------------------------------------------------------------------
# 15. Address map
# ---------------------------------------------------------------------------
set_property offset 0x40400000 [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg]
set_property range  64K        [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg]

set_property offset 0x43C00000 [get_bd_addr_segs video_accelerator_0/s_axi/reg0]
set_property range  64K        [get_bd_addr_segs video_accelerator_0/s_axi/reg0]

set_property offset 0x00000000 \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM]
set_property range  1G \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM]

# ---------------------------------------------------------------------------
# 16. Validate, save, generate wrapper
# ---------------------------------------------------------------------------
validate_bd_design
save_bd_design

make_wrapper \
    -files [get_files [get_property FILE_NAME [current_bd_design]]] \
    -top

# Locate and add wrapper
set wrapper_path [glob -nocomplain \
    [file join $proj_dir ${proj_name}.srcs sources_1 bd system_bd hdl system_bd_wrapper.v]]
if {[llength $wrapper_path] == 0} {
    set wrapper_path [glob -nocomplain \
        [file join $proj_dir ${proj_name}.srcs sources_1 bd system_bd hdl *.v]]
}
if {[llength $wrapper_path] > 0} {
    add_files -norecurse [lindex $wrapper_path 0]
    set_property top system_bd_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    puts "INFO: Wrapper: [lindex $wrapper_path 0]"
} else {
    puts "WARNING: Wrapper not found – add manually from:"
    puts "  $proj_dir/${proj_name}.srcs/sources_1/bd/system_bd/hdl/"
}

# ---------------------------------------------------------------------------
# 17. Add XDC constraints
# ---------------------------------------------------------------------------
set xdc [file join $repo_root vivado zedboard_constraints.xdc]
if {[file exists $xdc]} {
    add_files -fileset constrs_1 -norecurse $xdc
    puts "INFO: Constraints: $xdc"
} else {
    puts "WARNING: Constraints file not found: $xdc"
}

puts "========================================================================"
puts "  SUCCESS: Block design 'system_bd' created and validated."
puts ""
puts "  Memory Map:"
puts "    AXI DMA      : 0x40400000  (64 KB)"
puts "    Accelerator  : 0x43C00000  (64 KB)"
puts ""
puts "  Next steps in Vivado GUI:"
puts "    1. Flow > Run Synthesis"
puts "    2. Flow > Run Implementation"
puts "    3. Flow > Generate Bitstream"
puts "    4. File > Export > Export Hardware (include bitstream)"
puts "    5. Open Vitis – create Application Project from the .xsa"
puts "========================================================================"
