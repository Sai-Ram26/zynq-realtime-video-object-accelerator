`timescale 1ns / 1ps

// ============================================================================
// Module: quant
// Description: H.264 Forward Quantization Core.
// Formula: Z = (|W| * M(QP % 6) + f) >> (qbits + QP / 6)
// Hardware Implementation: Multiplierless LUT scale & arithmetic right shift.
// ============================================================================

module quant #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire [5:0]            qp,        // Quantization Parameter (0 to 51)
    input  wire signed [15:0]    w_in,      // DCT transformed coefficient
    output reg                   valid_out,
    output reg signed [15:0]     z_out      // Quantized Level
);

    wire [2:0] qp_rem = qp % 6;
    wire [3:0] qp_div = qp / 6;

    // Multiplication factor scale LUT M(QP % 6)
    reg [15:0] scale_factor;
    always @(*) begin
        case (qp_rem)
            3'd0: scale_factor = 16'd13107;
            3'd1: scale_factor = 16'd11916;
            3'd2: scale_factor = 16'd10082;
            3'd3: scale_factor = 16'd9362;
            3'd4: scale_factor = 16'd8192;
            3'd5: scale_factor = 16'd7282;
            default: scale_factor = 16'd13107;
        endcase
    end

    wire signed [15:0] abs_w = (w_in < 0) ? -w_in : w_in;
    wire [31:0] scaled_w = abs_w * scale_factor;
    wire [4:0] total_shift = 5'd14 + qp_div; // 14 fractional bits + qp_div
    wire [15:0] quant_mag = scaled_w >> total_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            z_out     <= 16'sd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (w_in < 0)
                    z_out <= -quant_mag;
                else
                    z_out <= quant_mag;
            end
        end
    end

endmodule
