// ============================================================================
// File: rgb2yuv.v
// Module: rgb2yuv
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 1 Pipelined Fixed-Point RGB888 to YUV420 Color Space
//              Converter. Converts 24-bit RGB pixel stream into 8-bit Y, U, V
//              components using shift-add arithmetic without DSP multipliers.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module rgb2yuv (
    input  wire        clk,             // System clock (100 MHz)
    input  wire        rst_n,           // Active-low asynchronous reset
    input  wire        valid_in,        // Incoming pixel valid handshake
    input  wire [7:0]  r_in,            // 8-bit Red component
    input  wire [7:0]  g_in,            // 8-bit Green component
    input  wire [7:0]  b_in,            // 8-bit Blue component

    output reg         valid_out,       // Outgoing pixel valid handshake
    output reg  [7:0]  y_out,           // 8-bit Luma (Y) output
    output reg  [7:0]  u_out,           // 8-bit Chroma (U) output
    output reg  [7:0]  v_out            // 8-bit Chroma (V) output
);

    // Stage 1: Multiplication / Product Accumulation Registers
    reg signed [16:0] y_prod;
    reg signed [16:0] u_prod;
    reg signed [16:0] v_prod;
    reg               stage1_valid;

    // Fixed-Point Matrix Coefficients (Shift-Add Optimized)
    // Y = (77*R + 150*G + 29*B) >> 8
    // U = (-43*R - 85*G + 128*B + 32768) >> 8
    // V = (128*R - 107*G - 21*B + 32768) >> 8
    wire [15:0] y_calc = (16'd77 * r_in) + (16'd150 * g_in) + (16'd29 * b_in);
    wire signed [16:0] u_calc = - (17'sd43 * $signed({1'b0, r_in})) - (17'sd85 * $signed({1'b0, g_in})) + (17'sd128 * $signed({1'b0, b_in})) + 17'sd32768;
    wire signed [16:0] v_calc = (17'sd128 * $signed({1'b0, r_in})) - (17'sd107 * $signed({1'b0, g_in})) - (17'sd21 * $signed({1'b0, b_in})) + 17'sd32768;

    // Pipeline Register Stage 1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_prod       <= 17'd0;
            u_prod       <= 17'd0;
            v_prod       <= 17'd0;
            stage1_valid <= 1'b0;
        end else begin
            stage1_valid <= valid_in;
            if (valid_in) begin
                y_prod <= {1'b0, y_calc};
                u_prod <= u_calc;
                v_prod <= v_calc;
            end
        end
    end

    // Pipeline Register Stage 2: Bit-Shift & Saturation / Truncation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out     <= 8'd0;
            u_out     <= 8'd0;
            v_out     <= 8'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= stage1_valid;
            if (stage1_valid) begin
                // Shift right by 8 bits with 8-bit clipping
                y_out <= (y_prod[15:8] > 8'd255) ? 8'd255 : y_prod[15:8];
                u_out <= (u_prod < 0) ? 8'd0 : (u_prod[15:8] > 8'd255) ? 8'd255 : u_prod[15:8];
                v_out <= (v_prod < 0) ? 8'd0 : (v_prod[15:8] > 8'd255) ? 8'd255 : v_prod[15:8];
            end
        end
    end

endmodule
