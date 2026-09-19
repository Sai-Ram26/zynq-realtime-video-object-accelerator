// ============================================================================
// File: bg_sub.v
// Module: bg_sub
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 2 Temporal Frame Subtraction & Motion Mask Generator.
//              Calculates absolute pixel difference |Y_curr - Y_bg| and compares
//              against a dynamic threshold T_thresh to generate a 1-bit motion mask.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module bg_sub (
    input  wire       clk,             // System clock (100 MHz)
    input  wire       rst_n,           // Active-low asynchronous reset
    input  wire       valid_in,        // Incoming pixel valid handshake
    input  wire [7:0] y_curr,          // Current frame luma (Y_current)
    input  wire [7:0] y_bg,            // Cached background reference luma (Y_background)
    input  wire [7:0] t_thresh,        // Software-assigned threshold (T_thresh)

    output reg        valid_out,       // Outgoing valid handshake
    output reg  [7:0] y_out,           // Passed luma value
    output reg  [7:0] diff_out,        // Absolute pixel difference
    output reg        foreground_mask  // 1-bit Motion Mask ('1' = Foreground, '0' = Background)
);

    // Absolute Value Subtractor Pipeline
    wire [7:0] abs_diff = (y_curr >= y_bg) ? (y_curr - y_bg) : (y_bg - y_curr);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out       <= 1'b0;
            y_out           <= 8'd0;
            diff_out        <= 8'd0;
            foreground_mask <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                y_out           <= y_curr;
                diff_out        <= abs_diff;
                foreground_mask <= (abs_diff > t_thresh) ? 1'b1 : 1'b0;
            end
        end
    end

endmodule
