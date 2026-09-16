// =============================================================================
// Module: h264_encoder.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Complete Hardware-Accelerated H.264 Baseline Video Encoder Core.
//   Integrates:
//     1. 4x4 Intra-Prediction Engine (Vertical, Horizontal, DC, Bypass)
//     2. Sparsity-Aware Block Skipping Protocol
//     3. Multiplierless 2D 4x4 Integer DCT (H * X * H^T, 0 DSPs)
//     4. 16-Channel Parallel Forward Quantization Array (quant.v)
//     5. CAVLC Entropy Coding Engine & 32-bit NAL/Bitstream Packer (cavlc.v)
// =============================================================================

`timescale 1ns / 1ps

module h264_encoder (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    input  wire [5:0]           qp,            // Quantization Parameter (0 to 51)
    input  wire [1:0]           pred_mode,     // 00: Vert, 01: Horiz, 10: DC, 11: Bypass
    input  wire                 is_skip_block, // 1 if block skipped by Sparsity Protocol

    // 4x4 input pixel matrix (Inpainted Clean Pixels)
    input  wire [7:0]           x00, x01, x02, x03,
    input  wire [7:0]           x10, x11, x12, x13,
    input  wire [7:0]           x20, x21, x22, x23,
    input  wire [7:0]           x30, x31, x32, x33,

    // Neighbor pixels for Intra Prediction
    input  wire [7:0]           top0, top1, top2, top3,
    input  wire [7:0]           left0, left1, left2, left3,

    // Compressed Bitstream Interface (AXI-Stream ready)
    output wire                 valid_out,
    output wire [31:0]          bitstream_data,
    output wire [5:0]           bit_count,
    output wire [4:0]           total_coeff,
    output wire [1:0]           trailing_ones
);

    // -------------------------------------------------------------------------
    // 1. Intra Prediction Engine
    // -------------------------------------------------------------------------
    wire pred_valid;
    wire signed [8:0] res00, res01, res02, res03;
    wire signed [8:0] res10, res11, res12, res13;
    wire signed [8:0] res20, res21, res22, res23;
    wire signed [8:0] res30, res31, res32, res33;

    intra_pred_4x4 u_pred (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in && !is_skip_block),
        .pred_mode(pred_mode),
        .p00(x00), .p01(x01), .p02(x02), .p03(x03),
        .p10(x10), .p11(x11), .p12(x12), .p13(x13),
        .p20(x20), .p21(x21), .p22(x22), .p23(x23),
        .p30(x30), .p31(x31), .p32(x32), .p33(x33),
        .top0(top0), .top1(top1), .top2(top2), .top3(top3),
        .left0(left0), .left1(left1), .left2(left2), .left3(left3),
        .valid_out(pred_valid),
        .res00(res00), .res01(res01), .res02(res02), .res03(res03),
        .res10(res10), .res11(res11), .res12(res12), .res13(res13),
        .res20(res20), .res21(res21), .res22(res22), .res23(res23),
        .res30(res30), .res31(res31), .res32(res32), .res33(res33)
    );

    // -------------------------------------------------------------------------
    // 2. Multiplierless 2D 4x4 Integer DCT
    // -------------------------------------------------------------------------
    wire dct_valid;
    wire signed [15:0] w00, w01, w02, w03;
    wire signed [15:0] w10, w11, w12, w13;
    wire signed [15:0] w20, w21, w22, w23;
    wire signed [15:0] w30, w31, w32, w33;

    // Convert 9-bit signed residuals to 8-bit magnitude for DCT core
    wire [7:0] in_x00 = (pred_mode == 2'b11) ? x00 : res00[7:0];
    wire [7:0] in_x01 = (pred_mode == 2'b11) ? x01 : res01[7:0];
    wire [7:0] in_x02 = (pred_mode == 2'b11) ? x02 : res02[7:0];
    wire [7:0] in_x03 = (pred_mode == 2'b11) ? x03 : res03[7:0];
    wire [7:0] in_x10 = (pred_mode == 2'b11) ? x10 : res10[7:0];
    wire [7:0] in_x11 = (pred_mode == 2'b11) ? x11 : res11[7:0];
    wire [7:0] in_x12 = (pred_mode == 2'b11) ? x12 : res12[7:0];
    wire [7:0] in_x13 = (pred_mode == 2'b11) ? x13 : res13[7:0];
    wire [7:0] in_x20 = (pred_mode == 2'b11) ? x20 : res20[7:0];
    wire [7:0] in_x21 = (pred_mode == 2'b11) ? x21 : res21[7:0];
    wire [7:0] in_x22 = (pred_mode == 2'b11) ? x22 : res22[7:0];
    wire [7:0] in_x23 = (pred_mode == 2'b11) ? x23 : res23[7:0];
    wire [7:0] in_x30 = (pred_mode == 2'b11) ? x30 : res30[7:0];
    wire [7:0] in_x31 = (pred_mode == 2'b11) ? x31 : res31[7:0];
    wire [7:0] in_x32 = (pred_mode == 2'b11) ? x32 : res32[7:0];
    wire [7:0] in_x33 = (pred_mode == 2'b11) ? x33 : res33[7:0];

    dct_4x4 u_dct (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(pred_valid),
        .x00(in_x00), .x01(in_x01), .x02(in_x02), .x03(in_x03),
        .x10(in_x10), .x11(in_x11), .x12(in_x12), .x13(in_x13),
        .x20(in_x20), .x21(in_x21), .x22(in_x22), .x23(in_x23),
        .x30(in_x30), .x31(in_x31), .x32(in_x32), .x33(in_x33),
        .valid_out(dct_valid),
        .w00(w00), .w01(w01), .w02(w02), .w03(w03),
        .w10(w10), .w11(w11), .w12(w12), .w13(w13),
        .w20(w20), .w21(w21), .w22(w22), .w23(w23),
        .w30(w30), .w31(w31), .w32(w32), .w33(w33)
    );

    // -------------------------------------------------------------------------
    // 3. 16-Channel Forward Quantization Array
    // -------------------------------------------------------------------------
    wire quant_valid;
    wire signed [15:0] z00, z01, z02, z03;
    wire signed [15:0] z10, z11, z12, z13;
    wire signed [15:0] z20, z21, z22, z23;
    wire signed [15:0] z30, z31, z32, z33;

    quant u_q00 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w00), .valid_out(quant_valid), .z_out(z00));
    quant u_q01 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w01), .valid_out(), .z_out(z01));
    quant u_q02 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w02), .valid_out(), .z_out(z02));
    quant u_q03 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w03), .valid_out(), .z_out(z03));

    quant u_q10 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w10), .valid_out(), .z_out(z10));
    quant u_q11 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w11), .valid_out(), .z_out(z11));
    quant u_q12 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w12), .valid_out(), .z_out(z12));
    quant u_q13 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w13), .valid_out(), .z_out(z13));

    quant u_q20 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w20), .valid_out(), .z_out(z20));
    quant u_q21 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w21), .valid_out(), .z_out(z21));
    quant u_q22 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w22), .valid_out(), .z_out(z22));
    quant u_q23 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w23), .valid_out(), .z_out(z23));

    quant u_q30 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w30), .valid_out(), .z_out(z30));
    quant u_q31 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w31), .valid_out(), .z_out(z31));
    quant u_q32 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w32), .valid_out(), .z_out(z32));
    quant u_q33 (.clk(clk), .rst_n(rst_n), .valid_in(dct_valid), .qp(qp), .w_in(w33), .valid_out(), .z_out(z33));

    // Delay is_skip_block through pipeline (1 cycle pred + 2 cycles DCT = 3 cycles)
    reg [2:0] skip_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            skip_pipe <= 3'b000;
        else
            skip_pipe <= {skip_pipe[1:0], is_skip_block};
    end

    // -------------------------------------------------------------------------
    // 4. CAVLC Entropy Coder & Bitstream Serializer
    // -------------------------------------------------------------------------
    cavlc u_cavlc (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(quant_valid || (valid_in && is_skip_block)),
        .skip_mode_in(skip_pipe[2]),
        .z00(z00), .z01(z01), .z02(z02), .z03(z03),
        .z10(z10), .z11(z11), .z12(z12), .z13(z13),
        .z20(z20), .z21(z21), .z22(z22), .z23(z23),
        .z30(z30), .z31(z31), .z32(z32), .z33(z33),
        .valid_out(valid_out),
        .bitstream_word(bitstream_data),
        .bit_count(bit_count),
        .total_coeff_out(total_coeff),
        .trailing_ones_out(trailing_ones)
    );

endmodule
