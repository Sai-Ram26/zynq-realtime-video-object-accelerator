// =============================================================================
// Module: block_assembler_4x4.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Raster-to-Block Stream Converter.
//   Buffers 3 horizontal scanlines using dual-port BRAM line stores and
//   assembles 4x4 pixel blocks from the incoming continuous raster stream.
//   Emits a 4x4 matrix pulse (block_valid) every 4th pixel on every 4th row,
//   feeding the downstream H.264 2D DCT and Quantization engine at full throughput.
// =============================================================================

`timescale 1ns / 1ps

module block_assembler_4x4 #(
    parameter integer LINE_WIDTH = 64 // Configurable: 64 for TB, 480/640/1280 for video
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [7:0]  pixel_in,
    input  wire        mask_in,
    input  wire        frame_start,

    output reg         block_valid,
    output reg         block_mask,     // 1 if block contains foreground/motion
    output reg  [7:0]  x00, x01, x02, x03,
    output reg  [7:0]  x10, x11, x12, x13,
    output reg  [7:0]  x20, x21, x22, x23,
    output reg  [7:0]  x30, x31, x32, x33
);

    // Line Buffers for 3 preceding scan lines
    reg [7:0] lb0 [0:LINE_WIDTH-1];
    reg [7:0] lb1 [0:LINE_WIDTH-1];
    reg [7:0] lb2 [0:LINE_WIDTH-1];

    reg [11:0] col_cnt;
    reg [11:0] row_cnt;

    // Shift registers for current 4 columns
    reg [7:0] w0 [0:3];
    reg [7:0] w1 [0:3];
    reg [7:0] w2 [0:3];
    reg [7:0] w3 [0:3];
    reg [3:0] mask_accum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt     <= 12'd0;
            row_cnt     <= 12'd0;
            block_valid <= 1'b0;
            block_mask  <= 1'b0;
            mask_accum  <= 4'd0;
            x00 <= 8'd0; x01 <= 8'd0; x02 <= 8'd0; x03 <= 8'd0;
            x10 <= 8'd0; x11 <= 8'd0; x12 <= 8'd0; x13 <= 8'd0;
            x20 <= 8'd0; x21 <= 8'd0; x22 <= 8'd0; x23 <= 8'd0;
            x30 <= 8'd0; x31 <= 8'd0; x32 <= 8'd0; x33 <= 8'd0;
        end else if (frame_start) begin
            col_cnt     <= 12'd0;
            row_cnt     <= 12'd0;
            block_valid <= 1'b0;
        end else if (valid_in) begin
            // Read line buffer taps and shift
            w0[3] <= w0[2]; w0[2] <= w0[1]; w0[1] <= w0[0]; w0[0] <= lb2[col_cnt];
            w1[3] <= w1[2]; w1[2] <= w1[1]; w1[1] <= w1[0]; w1[0] <= lb1[col_cnt];
            w2[3] <= w2[2]; w2[2] <= w2[1]; w2[1] <= w2[0]; w2[0] <= lb0[col_cnt];
            w3[3] <= w3[2]; w3[2] <= w3[1]; w3[1] <= w3[0]; w3[0] <= pixel_in;

            // Cascade write through line buffers
            lb0[col_cnt] <= pixel_in;
            lb1[col_cnt] <= lb0[col_cnt];
            lb2[col_cnt] <= lb1[col_cnt];

            if (mask_in)
                mask_accum <= mask_accum + 4'd1;

            // Check if 4x4 block boundary reached
            if ((col_cnt[1:0] == 2'b11) && (row_cnt[1:0] == 2'b11) && (row_cnt >= 12'd3)) begin
                block_valid <= 1'b1;
                block_mask  <= (mask_accum > 4'd0 || mask_in);
                mask_accum  <= 4'd0;

                x00 <= lb2[col_cnt-3]; x01 <= lb2[col_cnt-2]; x02 <= lb2[col_cnt-1]; x03 <= lb2[col_cnt];
                x10 <= lb1[col_cnt-3]; x11 <= lb1[col_cnt-2]; x12 <= lb1[col_cnt-1]; x13 <= lb1[col_cnt];
                x20 <= lb0[col_cnt-3]; x21 <= lb0[col_cnt-2]; x22 <= lb0[col_cnt-1]; x23 <= lb0[col_cnt];
                x30 <= w3[2];          x31 <= w3[1];          x32 <= w3[0];          x33 <= pixel_in;
            end else begin
                block_valid <= 1'b0;
            end

            // Horizontal & Vertical column pointers
            if (col_cnt == LINE_WIDTH - 1) begin
                col_cnt <= 12'd0;
                row_cnt <= row_cnt + 12'd1;
            end else begin
                col_cnt <= col_cnt + 12'd1;
            end
        end else begin
            block_valid <= 1'b0;
        end
    end

endmodule
