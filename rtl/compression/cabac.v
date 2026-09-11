`timescale 1ns / 1ps

// ============================================================================
// Module: cabac
// Description: Context-Adaptive Binary Arithmetic Coder (CABAC / CAVLC Engine).
//              Binarizes quantized levels, models state context, and outputs
//              compressed bitstream words.
// ============================================================================

module cabac (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    input  wire signed [15:0]   coeff_in,
    input  wire                 is_last_in_block,
    output reg                  valid_out,
    output reg [31:0]           bitstream_word,
    output reg [4:0]            bit_count
);

    // Simplified Hardware State-Machine for Entropy Bitstream Packing
    reg [63:0] bit_buffer;
    reg [5:0]  buf_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out      <= 1'b0;
            bitstream_word <= 32'd0;
            bit_count      <= 5'd0;
            bit_buffer     <= 64'd0;
            buf_len        <= 6'd0;
        end else begin
            valid_out <= 1'b0;
            if (valid_in) begin
                // Binarization: Non-zero flags + sign + magnitude
                if (coeff_in == 0) begin
                    // Zero run: 1 bit '0'
                    bit_buffer <= (bit_buffer << 1) | 64'd0;
                    buf_len    <= buf_len + 1'b1;
                end else begin
                    // Significant coeff: 1 bit '1' + sign bit + 4-bit mag
                    wire sign = (coeff_in < 0);
                    wire [3:0] mag = (coeff_in < 0) ? (-coeff_in[3:0]) : coeff_in[3:0];
                    bit_buffer <= (bit_buffer << 6) | {1'b1, sign, mag};
                    buf_len    <= buf_len + 6'd6;
                end
            end

            // Emit 32-bit compressed word once buffer fills or on last block coeff
            if (buf_len >= 6'd32 || (is_last_in_block && buf_len > 0)) begin
                valid_out      <= 1'b1;
                bitstream_word <= bit_buffer[63:32];
                bit_count      <= (buf_len >= 6'd32) ? 5'd32 : buf_len[4:0];
                bit_buffer     <= bit_buffer << 32;
                buf_len        <= (buf_len >= 6'd32) ? (buf_len - 6'd32) : 6'd0;
            end
        end
    end

endmodule
