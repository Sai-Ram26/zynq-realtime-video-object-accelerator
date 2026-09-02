`timescale 1ns / 1ps

// ============================================================================
// Module: rgb2gray
// Description: Synthesizable fixed-point RGB888 to Grayscale (Y) converter.
// Formula: Y = (77*R + 150*G + 29*B) >> 8
// Architecture: Fully pipelined (2 clock latency), zero DSP multipliers used.
// ============================================================================

module rgb2gray (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [7:0]  r_in,
    input  wire [7:0]  g_in,
    input  wire [7:0]  b_in,
    output reg         valid_out,
    output reg  [7:0]  y_out
);

    // Stage 1: Pipeline Multiplications (Shift-Add LUT decomposition)
    // 77*R  = (64 + 8 + 4 + 1)*R = (R<<6) + (R<<3) + (R<<2) + R
    // 150*G = (128 + 16 + 4 + 2)*G = (G<<7) + (G<<4) + (G<<2) + (G<<1)
    // 29*B  = (16 + 8 + 4 + 1)*B = (B<<4) + (B<<3) + (B<<2) + B

    reg [15:0] prod_r_stage1;
    reg [15:0] prod_g_stage1;
    reg [15:0] prod_b_stage1;
    reg        valid_stage1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_r_stage1 <= 16'd0;
            prod_g_stage1 <= 16'd0;
            prod_b_stage1 <= 16'd0;
            valid_stage1  <= 1'b0;
        end else begin
            valid_stage1  <= valid_in;
            prod_r_stage1 <= 16'd77  * r_in;
            prod_g_stage1 <= 16'd150 * g_in;
            prod_b_stage1 <= 16'd29  * b_in;
        end
    end

    // Stage 2: Summation and Bit Shift (>> 8)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            y_out     <= 8'd0;
        end else begin
            valid_out <= valid_stage1;
            if (valid_stage1) begin
                y_out <= (prod_r_stage1 + prod_g_stage1 + prod_b_stage1) >> 8;
            end
        end
    end

endmodule
