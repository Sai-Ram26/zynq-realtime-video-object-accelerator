// ============================================================================
// File: dct_quant_4x4.v
// Module: dct_quant_4x4
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 4 Multiplierless 4x4 Integer DCT Butterfly Transform Network
//              and Adaptive Frequency Quantization (AFQ) Engine.
//              Implements the H.264/AVC 4x4 integer DCT core transform:
//                Cf = H * C * H^T  (2D separable row-column transform)
//              Followed by QP-based scalar quantization using shift-add approximation.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module dct_quant_4x4 (
    input  wire        clk,                 // System clock (100 MHz)
    input  wire        rst_n,               // Active-low asynchronous reset
    input  wire        valid_in,            // Block input valid
    input  wire        skip_mode_in,        // '1' = Block is spatially skipped (all zeros)
    input  wire [5:0]  qp_in,               // Quantization Parameter (0-51)

    // 4x4 Block Input: 8-bit residual samples row-major [row][col]
    input  wire signed [7:0] x00, x01, x02, x03,
    input  wire signed [7:0] x10, x11, x12, x13,
    input  wire signed [7:0] x20, x21, x22, x23,
    input  wire signed [7:0] x30, x31, x32, x33,

    output reg         valid_out,           // Block output valid
    output reg         skip_out,            // Propagated skip flag

    // 4x4 Quantized DCT Coefficients row-major [row][col]
    output reg signed [15:0] z00, z01, z02, z03,
    output reg signed [15:0] z10, z11, z12, z13,
    output reg signed [15:0] z20, z21, z22, z23,
    output reg signed [15:0] z30, z31, z32, z33
);

    // -------------------------------------------------------------------------
    // H.264 4x4 Integer DCT Core Transform Butterfly
    // H = [ 1  1  1  1]
    //     [ 2  1 -1 -2]
    //     [ 1 -1 -1  1]
    //     [ 1 -2  2 -1]
    // -------------------------------------------------------------------------

    // Stage 1: Row Transform (combinational)
    wire signed [15:0] r00, r01, r02, r03;
    wire signed [15:0] r10, r11, r12, r13;
    wire signed [15:0] r20, r21, r22, r23;
    wire signed [15:0] r30, r31, r32, r33;

    // Row 0: H * [x00 x01 x02 x03]
    assign r00 = $signed({1'b0, x00}) + $signed({1'b0, x01}) + $signed({1'b0, x02}) + $signed({1'b0, x03});
    assign r01 = ($signed({1'b0, x00}) <<< 1) + $signed({1'b0, x01}) - $signed({1'b0, x02}) - ($signed({1'b0, x03}) <<< 1);
    assign r02 = $signed({1'b0, x00}) - $signed({1'b0, x01}) - $signed({1'b0, x02}) + $signed({1'b0, x03});
    assign r03 = $signed({1'b0, x00}) - ($signed({1'b0, x01}) <<< 1) + ($signed({1'b0, x02}) <<< 1) - $signed({1'b0, x03});

    // Row 1: H * [x10 x11 x12 x13]
    assign r10 = $signed({1'b0, x10}) + $signed({1'b0, x11}) + $signed({1'b0, x12}) + $signed({1'b0, x13});
    assign r11 = ($signed({1'b0, x10}) <<< 1) + $signed({1'b0, x11}) - $signed({1'b0, x12}) - ($signed({1'b0, x13}) <<< 1);
    assign r12 = $signed({1'b0, x10}) - $signed({1'b0, x11}) - $signed({1'b0, x12}) + $signed({1'b0, x13});
    assign r13 = $signed({1'b0, x10}) - ($signed({1'b0, x11}) <<< 1) + ($signed({1'b0, x12}) <<< 1) - $signed({1'b0, x13});

    // Row 2: H * [x20 x21 x22 x23]
    assign r20 = $signed({1'b0, x20}) + $signed({1'b0, x21}) + $signed({1'b0, x22}) + $signed({1'b0, x23});
    assign r21 = ($signed({1'b0, x20}) <<< 1) + $signed({1'b0, x21}) - $signed({1'b0, x22}) - ($signed({1'b0, x23}) <<< 1);
    assign r22 = $signed({1'b0, x20}) - $signed({1'b0, x21}) - $signed({1'b0, x22}) + $signed({1'b0, x23});
    assign r23 = $signed({1'b0, x20}) - ($signed({1'b0, x21}) <<< 1) + ($signed({1'b0, x22}) <<< 1) - $signed({1'b0, x23});

    // Row 3: H * [x30 x31 x32 x33]
    assign r30 = $signed({1'b0, x30}) + $signed({1'b0, x31}) + $signed({1'b0, x32}) + $signed({1'b0, x33});
    assign r31 = ($signed({1'b0, x30}) <<< 1) + $signed({1'b0, x31}) - $signed({1'b0, x32}) - ($signed({1'b0, x33}) <<< 1);
    assign r32 = $signed({1'b0, x30}) - $signed({1'b0, x31}) - $signed({1'b0, x32}) + $signed({1'b0, x33});
    assign r33 = $signed({1'b0, x30}) - ($signed({1'b0, x31}) <<< 1) + ($signed({1'b0, x32}) <<< 1) - $signed({1'b0, x33});

    // Stage 1 Pipeline Registers: Row-transformed results
    reg signed [15:0] rr00, rr01, rr02, rr03;
    reg signed [15:0] rr10, rr11, rr12, rr13;
    reg signed [15:0] rr20, rr21, rr22, rr23;
    reg signed [15:0] rr30, rr31, rr32, rr33;
    reg               stage1_valid;
    reg               stage1_skip;
    reg [5:0]         stage1_qp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid <= 1'b0;
            stage1_skip  <= 1'b0;
            stage1_qp    <= 6'd0;
        end else begin
            stage1_valid <= valid_in;
            stage1_skip  <= skip_mode_in;
            stage1_qp    <= qp_in;
            if (valid_in) begin
                rr00 <= r00; rr01 <= r01; rr02 <= r02; rr03 <= r03;
                rr10 <= r10; rr11 <= r11; rr12 <= r12; rr13 <= r13;
                rr20 <= r20; rr21 <= r21; rr22 <= r22; rr23 <= r23;
                rr30 <= r30; rr31 <= r31; rr32 <= r32; rr33 <= r33;
            end
        end
    end

    // Stage 2: Column Transform on Row-Transformed Data (H * R^T)
    wire signed [15:0] c00, c01, c02, c03;
    wire signed [15:0] c10, c11, c12, c13;
    wire signed [15:0] c20, c21, c22, c23;
    wire signed [15:0] c30, c31, c32, c33;

    // Column 0: H * [rr00 rr10 rr20 rr30]
    assign c00 = rr00 + rr10 + rr20 + rr30;
    assign c10 = (rr00 <<< 1) + rr10 - rr20 - (rr30 <<< 1);
    assign c20 = rr00 - rr10 - rr20 + rr30;
    assign c30 = rr00 - (rr10 <<< 1) + (rr20 <<< 1) - rr30;

    // Column 1: H * [rr01 rr11 rr21 rr31]
    assign c01 = rr01 + rr11 + rr21 + rr31;
    assign c11 = (rr01 <<< 1) + rr11 - rr21 - (rr31 <<< 1);
    assign c21 = rr01 - rr11 - rr21 + rr31;
    assign c31 = rr01 - (rr11 <<< 1) + (rr21 <<< 1) - rr31;

    // Column 2: H * [rr02 rr12 rr22 rr32]
    assign c02 = rr02 + rr12 + rr22 + rr32;
    assign c12 = (rr02 <<< 1) + rr12 - rr22 - (rr32 <<< 1);
    assign c22 = rr02 - rr12 - rr22 + rr32;
    assign c32 = rr02 - (rr12 <<< 1) + (rr22 <<< 1) - rr32;

    // Column 3: H * [rr03 rr13 rr23 rr33]
    assign c03 = rr03 + rr13 + rr23 + rr33;
    assign c13 = (rr03 <<< 1) + rr13 - rr23 - (rr33 <<< 1);
    assign c23 = rr03 - rr13 - rr23 + rr33;
    assign c33 = rr03 - (rr13 <<< 1) + (rr23 <<< 1) - rr33;

    // Quantization: Z = round(C / Qstep)
    // Qstep approximation: shift by (qp/6), scale by ~0.625 for low QP
    // Using simple arithmetic right shift by (qp >> 1) + 2 for hardware feasibility
    wire [3:0] qshift = (stage1_qp[5:1]) + 4'd2;

    function automatic signed [15:0] quantize;
        input signed [15:0] coeff;
        input [3:0] qs;
        begin
            if (coeff >= 0)
                quantize = coeff >>> qs;
            else
                quantize = -((-coeff) >>> qs);
        end
    endfunction

    // Stage 2 Pipeline Registers: Full 2D DCT + Quantized Output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            skip_out  <= 1'b0;
            z00 <= 0; z01 <= 0; z02 <= 0; z03 <= 0;
            z10 <= 0; z11 <= 0; z12 <= 0; z13 <= 0;
            z20 <= 0; z21 <= 0; z22 <= 0; z23 <= 0;
            z30 <= 0; z31 <= 0; z32 <= 0; z33 <= 0;
        end else begin
            valid_out <= stage1_valid;
            skip_out  <= stage1_skip;
            if (stage1_valid) begin
                if (stage1_skip) begin
                    z00 <= 0; z01 <= 0; z02 <= 0; z03 <= 0;
                    z10 <= 0; z11 <= 0; z12 <= 0; z13 <= 0;
                    z20 <= 0; z21 <= 0; z22 <= 0; z23 <= 0;
                    z30 <= 0; z31 <= 0; z32 <= 0; z33 <= 0;
                end else begin
                    z00 <= quantize(c00, qshift); z01 <= quantize(c01, qshift);
                    z02 <= quantize(c02, qshift); z03 <= quantize(c03, qshift);
                    z10 <= quantize(c10, qshift); z11 <= quantize(c11, qshift);
                    z12 <= quantize(c12, qshift); z13 <= quantize(c13, qshift);
                    z20 <= quantize(c20, qshift); z21 <= quantize(c21, qshift);
                    z22 <= quantize(c22, qshift); z23 <= quantize(c23, qshift);
                    z30 <= quantize(c30, qshift); z31 <= quantize(c31, qshift);
                    z32 <= quantize(c32, qshift); z33 <= quantize(c33, qshift);
                end
            end
        end
    end

endmodule
