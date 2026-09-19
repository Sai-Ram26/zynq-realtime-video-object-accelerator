# ==============================================================================
# File: stage5_synth_zedboard.xdc
# Project: High-Efficiency Zynq SoC Video Accelerator Architecture
# Target: AMD Xilinx Zynq-7000 APSoC (xc7z020clg484-1)
# Description: Timing and Synthesis Constraints for 100 MHz Accelerator Core
# ==============================================================================

# Primary 100 MHz System Clock (10.0 ns Period, 50% Duty Cycle)
create_clock -period 10.000 -name clk_100mhz -waveform {0.000 5.000} [get_ports clk]

# Clock Uncertainty and Jitter
set_clock_uncertainty 0.150 [get_clocks clk_100mhz]

# Asynchronous Reset False Path (Ignore timing on rst_n assertion/deassertion recovery)
set_false_path -from [get_ports rst_n]

# Input Delay Constraints (assuming 2.0 ns setup margin from external source / AXI bridge)
set_input_delay -clock [get_clocks clk_100mhz] -max 2.500 [get_ports {pixel_valid_in r_in* g_in* b_in* y_bg_in* t_thresh_in* qp_in*}]
set_input_delay -clock [get_clocks clk_100mhz] -min 0.500 [get_ports {pixel_valid_in r_in* g_in* b_in* y_bg_in* t_thresh_in* qp_in*}]

# Output Delay Constraints (assuming 2.5 ns max delay to downstream DMA / FIFO)
set_output_delay -clock [get_clocks clk_100mhz] -max 3.000 [get_ports {nal_valid_out nal_word_out* nal_bit_count_out* total_coeff_out*}]
set_output_delay -clock [get_clocks clk_100mhz] -min 0.500 [get_ports {nal_valid_out nal_word_out* nal_bit_count_out* total_coeff_out*}]

# Performance / Debug output false paths (non-critical monitoring signals)
set_false_path -to [get_ports {total_cycles* active_cycles* stall_cycles* pixel_count* inpaint_events* nal_word_count*}]
set_false_path -to [get_ports {y_inpainted* foreground_mask inpaint_active}]
