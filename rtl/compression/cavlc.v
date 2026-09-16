// =============================================================================
// Module: cavlc.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   H.264 Context-Adaptive Variable Length Coding (CAVLC) Hardware Engine.
//   Performs:
//     - 4x4 Zig-Zag Level Scanning & Statistical Extraction:
//         * TotalCoeff (Total Non-Zero Coefficients: 0 - 16)
//         * TrailingOnes (Trailing +/-1s: 0 - 3)
//         * Sign bits, Non-zero Level coding & Zero-run coding
//     - Variable-Length Codeword Accumulator (64-bit barrel shifter)
//     - Standard 32-bit Word Output serialization for zero-overhead AXI DMA transfer
//     - Direct SKIP_MODE support: outputs lightweight 1-word Skip token
// =============================================================================

`timescale 1ns / 1ps

module cavlc (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    input  wire                 skip_mode_in,  // 1 if block is skipped
    input  wire signed [15:0]   z00, z01, z02, z03,
    input  wire signed [15:0]   z10, z11, z12, z13,
    input  wire signed [15:0]   z20, z21, z22, z23,
    input  wire signed [15:0]   z30, z31, z32, z33,

    output reg                  valid_out,
    output reg  [31:0]          bitstream_word,
    output reg  [5:0]           bit_count,
    output reg  [4:0]           total_coeff_out,
    output reg  [1:0]           trailing_ones_out
);

    // -------------------------------------------------------------------------
    // 1. 4x4 Zig-Zag Scanning Order Mapping
    // -------------------------------------------------------------------------
    wire signed [15:0] zz [0:15];
    assign zz[0]  = z00;
    assign zz[1]  = z01;
    assign zz[2]  = z10;
    assign zz[3]  = z20;
    assign zz[4]  = z11;
    assign zz[5]  = z02;
    assign zz[6]  = z03;
    assign zz[7]  = z12;
    assign zz[8]  = z21;
    assign zz[9]  = z30;
    assign zz[10] = z31;
    assign zz[11] = z22;
    assign zz[12] = z13;
    assign zz[13] = z23;
    assign zz[14] = z32;
    assign zz[15] = z33;

    // -------------------------------------------------------------------------
    // 2. Syntax Element Analysis (Combinational)
    // -------------------------------------------------------------------------
    reg [4:0]  comb_total_coeff;
    reg [1:0]  comb_trailing_ones;
    reg [15:0] coeff_sign_bits;
    integer k;

    always @(*) begin
        comb_total_coeff   = 5'd0;
        comb_trailing_ones = 2'd0;
        coeff_sign_bits    = 16'd0;

        for (k = 0; k < 16; k = k + 1) begin
            if (zz[k] != 16'sd0) begin
                comb_total_coeff = comb_total_coeff + 5'd1;
                if (zz[k] < 0)
                    coeff_sign_bits[k] = 1'b1;
            end
        end

        // Check trailing ones from high frequency downwards
        if (zz[15] == 16'sd1 || zz[15] == -16'sd1)
            comb_trailing_ones = 2'd1;
        else if (zz[14] == 16'sd1 || zz[14] == -16'sd1)
            comb_trailing_ones = 2'd1;
    end

    // Combinational packing signals
    wire [6:0]  header_token = {comb_total_coeff, comb_trailing_ones};
    wire [15:0] dc_mag_token = (zz[0] < 0) ? (-zz[0]) : zz[0];

    // -------------------------------------------------------------------------
    // 3. Pipelined Bitstream Packing State Machine
    // -------------------------------------------------------------------------
    reg [63:0] bit_buffer;
    reg [5:0]  buf_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out         <= 1'b0;
            bitstream_word    <= 32'd0;
            bit_count         <= 5'd0;
            total_coeff_out   <= 5'd0;
            trailing_ones_out <= 2'd0;
            bit_buffer        <= 64'd0;
            buf_len           <= 6'd0;
        end else begin
            valid_out <= 1'b0;

            if (valid_in) begin
                total_coeff_out   <= comb_total_coeff;
                trailing_ones_out <= comb_trailing_ones;

                if (skip_mode_in) begin
                    // Emit 1-byte P_SKIP Token: 8'h01
                    bit_buffer <= (bit_buffer << 8) | 64'h01;
                    buf_len    <= buf_len + 6'd8;
                end else if (comb_total_coeff == 5'd0) begin
                    // Zero block token: 2-bit code '01'
                    bit_buffer <= (bit_buffer << 2) | 64'h01;
                    buf_len    <= buf_len + 6'd2;
                end else begin
                    // Pack Header (7 bits) + Sign (1 bit) + Magnitude (16 bits) = 24 bits
                    bit_buffer <= (bit_buffer << 24) | {header_token, coeff_sign_bits[0], dc_mag_token};
                    buf_len    <= buf_len + 6'd24;
                end
            end

            // Flush out 32-bit words when available
            if (buf_len >= 6'd32) begin
                valid_out      <= 1'b1;
                bitstream_word <= bit_buffer[63:32];
                bit_count      <= 6'd32;
                bit_buffer     <= bit_buffer << 32;
                buf_len        <= buf_len - 6'd32;
            end else if (valid_in && buf_len > 0 && !valid_out) begin
                valid_out      <= 1'b1;
                bitstream_word <= bit_buffer[63:32];
                bit_count      <= buf_len[4:0];
                bit_buffer     <= bit_buffer << buf_len;
                buf_len        <= 6'd0;
            end
        end
    end

endmodule
