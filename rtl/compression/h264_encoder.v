`timescale 1ns / 1ps

// ============================================================================
// Module: h264_encoder
// Description: Top-level H.264 Baseline Hardware Encoder Core.
//              Integrates:
//                1. 2D 4x4 Integer DCT (dct_4x4.v)
//                2. Forward Quantization (quant.v)
//                3. Entropy / CABAC Bitstream Packer (cabac.v)
// ============================================================================

module h264_encoder (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    input  wire [5:0]           qp,
    // 4x4 input block
    input  wire [7:0]           x00, x01, x02, x03,
    input  wire [7:0]           x10, x11, x12, x13,
    input  wire [7:0]           x20, x21, x22, x23,
    input  wire [7:0]           x30, x31, x32, x33,
    // Compressed bitstream output
    output wire                 valid_out,
    output wire [31:0]          bitstream_data,
    output wire [4:0]           bit_count
);

    // 1. DCT 4x4 Core
    wire dct_valid;
    wire signed [15:0] w00, w01, w02, w03;
    wire signed [15:0] w10, w11, w12, w13;
    wire signed [15:0] w20, w21, w22, w23;
    wire signed [15:0] w30, w31, w32, w33;

    dct_4x4 u_dct (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .x00(x00), .x01(x01), .x02(x02), .x03(x03),
        .x10(x10), .x11(x11), .x12(x12), .x13(x13),
        .x20(x20), .x21(x21), .x22(x22), .x23(x23),
        .x30(x30), .x31(x31), .x32(x32), .x33(x33),
        .valid_out(dct_valid),
        .w00(w00), .w01(w01), .w02(w02), .w03(w03),
        .w10(w10), .w11(w11), .w12(w12), .w13(w13),
        .w20(w20), .w21(w21), .w22(w22), .w23(w23),
        .w30(w30), .w31(w31), .w32(w32), .w33(w33)
    );

    // 2. Quantization Core (DC coefficient quantized)
    wire quant_valid;
    wire signed [15:0] z00;

    quant u_quant (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(dct_valid),
        .qp(qp),
        .w_in(w00),
        .valid_out(quant_valid),
        .z_out(z00)
    );

    // 3. CABAC / Entropy Packer
    cabac u_cabac (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(quant_valid),
        .coeff_in(z00),
        .is_last_in_block(1'b1),
        .valid_out(valid_out),
        .bitstream_word(bitstream_data),
        .bit_count(bit_count)
    );

endmodule
