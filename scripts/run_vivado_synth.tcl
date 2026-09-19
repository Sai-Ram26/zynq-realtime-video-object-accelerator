# ==============================================================================
# File: run_vivado_synth.tcl
# Project: High-Efficiency Zynq SoC Video Accelerator Architecture
# Description: Vivado Non-Project Batch Synthesis and Implementation Script
# Target: AMD Xilinx Zynq-7000 xc7z020clg484-1 (Avnet ZedBoard)
# ==============================================================================

set PROJECT_DIR [file normalize [file dirname [info script]]/..]
set OUTPUT_DIR  [file join $PROJECT_DIR vivado_build]
file mkdir $OUTPUT_DIR

puts "======================================================================"
puts " Starting Batch Synthesis for Zynq Video Accelerator Core"
puts " Target Device: xc7z020clg484-1 (ZedBoard)"
puts " Project Root:  $PROJECT_DIR"
puts " Output Dir:    $OUTPUT_DIR"
puts "======================================================================"

# Step 1: Read Verilog RTL Source Files
read_verilog -sv [file join $PROJECT_DIR rtl custom_vector_decoder.v]
read_verilog -sv [file join $PROJECT_DIR rtl rgb2yuv.v]
read_verilog -sv [file join $PROJECT_DIR rtl bg_sub.v]
read_verilog -sv [file join $PROJECT_DIR rtl inpainting_8x8.v]
read_verilog -sv [file join $PROJECT_DIR rtl stage2_core_top.v]
read_verilog -sv [file join $PROJECT_DIR rtl dct_quant_4x4.v]
read_verilog -sv [file join $PROJECT_DIR rtl cavlc_encoder.v]
read_verilog -sv [file join $PROJECT_DIR rtl perf_monitor.v]
read_verilog -sv [file join $PROJECT_DIR rtl stage3_pipeline_top.v]
read_verilog -sv [file join $PROJECT_DIR rtl stage6_pipeline_top.v]
read_verilog -sv [file join $PROJECT_DIR rtl axi_lite_slave.v]
read_verilog -sv [file join $PROJECT_DIR rtl axi_video_soc_v1_0.v]

# Step 2: Read Constraints
read_xdc [file join $PROJECT_DIR constraints stage5_synth_zedboard.xdc]

# Step 3: Run Synthesis
puts "--> Running synth_design on stage3_pipeline_top..."
synth_design -top stage3_pipeline_top -part xc7z020clg484-1 -flatten_hierarchy rebuilt -mode out_of_context

# Write Post-Synth Checkpoint & Reports
write_checkpoint -force [file join $OUTPUT_DIR post_synth.dcp]
report_utilization -file [file join $OUTPUT_DIR post_synth_utilization.rpt] -pb [file join $OUTPUT_DIR post_synth_utilization.pb]
report_timing_summary -file [file join $OUTPUT_DIR post_synth_timing.rpt]

puts "--> Synthesis Complete. Generating summary reports..."
puts "Reports written to $OUTPUT_DIR"
puts "======================================================================"
