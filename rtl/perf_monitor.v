// ============================================================================
// File: perf_monitor.v
// Module: perf_monitor
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 6 Hardware Performance Monitoring Engine.
//              Tracks: total_cycles, active_cycles, stall_cycles,
//              pixel_count, inpaint_events, nal_word_count.
//              All counters are 32-bit, software-readable via AXI4-Lite.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module perf_monitor (
    input  wire        clk,             // System clock (100 MHz)
    input  wire        rst_n,           // Active-low asynchronous reset
    input  wire        enable,          // Overall performance monitoring enable

    // Event Signals
    input  wire        pixel_valid_in,  // High when valid pixel arrives
    input  wire        inpaint_active,  // High when inpainting substitution is active
    input  wire        nal_valid,       // High when a NAL word is emitted

    // Counter Outputs (software-readable)
    output reg [31:0]  total_cycles,    // Total elapsed clock cycles since enable
    output reg [31:0]  active_cycles,   // Cycles where pixel_valid_in was asserted
    output reg [31:0]  stall_cycles,    // Cycles where enable=1 but pixel_valid_in=0
    output reg [31:0]  pixel_count,     // Total valid pixel count
    output reg [31:0]  inpaint_events,  // Total inpainting substitution events
    output reg [31:0]  nal_word_count   // Total NAL 32-bit words emitted
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles   <= 32'd0;
            active_cycles  <= 32'd0;
            stall_cycles   <= 32'd0;
            pixel_count    <= 32'd0;
            inpaint_events <= 32'd0;
            nal_word_count <= 32'd0;
        end else if (enable) begin
            total_cycles <= total_cycles + 32'd1;
            if (pixel_valid_in) begin
                active_cycles <= active_cycles + 32'd1;
                pixel_count   <= pixel_count   + 32'd1;
            end else begin
                stall_cycles <= stall_cycles + 32'd1;
            end
            if (inpaint_active) begin
                inpaint_events <= inpaint_events + 32'd1;
            end
            if (nal_valid) begin
                nal_word_count <= nal_word_count + 32'd1;
            end
        end
    end

endmodule
