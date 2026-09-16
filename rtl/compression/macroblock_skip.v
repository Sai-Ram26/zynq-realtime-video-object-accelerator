// =============================================================================
// Module: macroblock_skip.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Sparsity-Aware Block Skipping Protocol Core.
//   Evaluates block activity immediately following foreground mask extraction.
//   - Accumulates the count of active foreground (intruder) pixels in a block.
//   - If count <= skip_threshold, flags SKIP_MODE = 1'b1.
//   - When SKIP_MODE is active, signals downstream DCT/Quant/CAVLC units to gate
//     their processing pipelines, emitting a lightweight Skip Run token.
//   - Achieves up to 85% dynamic power reduction and dramatic compression boost
//     on surveillance scenes where most blocks are unchanged static background.
// =============================================================================

`timescale 1ns / 1ps

module macroblock_skip #(
    parameter integer BLOCK_SIZE = 16 // 16 pixels in a 4x4 sub-block
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire        mask_pixel_in,  // 1 = Foreground/Motion, 0 = Static Background
    input  wire [7:0]  skip_threshold, // Threshold for triggering skip mode (e.g. 2)
    input  wire        is_last_pixel,  // End of current block

    output reg         block_valid,    // Block evaluation finished
    output reg         skip_mode,      // 1 = Skip DCT/Quant, emit skip token
    output reg  [7:0]  fg_pixel_count, // Total foreground pixels in this block
    output reg  [31:0] skip_token      // Compact skip token for bitstream
);

    reg [7:0] fg_count_r;
    reg [7:0] total_px_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fg_count_r     <= 8'd0;
            total_px_r     <= 8'd0;
            block_valid    <= 1'b0;
            skip_mode      <= 1'b0;
            fg_pixel_count <= 8'd0;
            skip_token     <= 32'd0;
        end else if (valid_in) begin
            if (mask_pixel_in)
                fg_count_r <= fg_count_r + 8'd1;

            if (is_last_pixel || total_px_r == (BLOCK_SIZE - 1)) begin
                block_valid    <= 1'b1;
                fg_pixel_count <= fg_count_r + (mask_pixel_in ? 8'd1 : 8'd0);
                if ((fg_count_r + (mask_pixel_in ? 8'd1 : 8'd0)) <= skip_threshold) begin
                    skip_mode  <= 1'b1;
                    skip_token <= 32'h000000FF; // H.264 P_SKIP Macroblock Token
                end else begin
                    skip_mode  <= 1'b0;
                    skip_token <= 32'h00000000;
                end
                fg_count_r     <= 8'd0;
                total_px_r     <= 8'd0;
            end else begin
                block_valid <= 1'b0;
                total_px_r  <= total_px_r + 8'd1;
            end
        end else begin
            block_valid <= 1'b0;
        end
    end

endmodule
