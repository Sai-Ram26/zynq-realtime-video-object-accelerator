// =============================================================================
// Module: intra_pred_4x4.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   H.264 4x4 Intra-Prediction Engine.
//   Supports standard Intra_4x4 modes:
//     - Mode 0: Vertical Prediction (copies above neighbor pixels)
//     - Mode 1: Horizontal Prediction (copies left neighbor pixels)
//     - Mode 2: DC Prediction (average of available top and left neighbors)
//     - Mode 3: Bypass (Prediction = 0, residual = input pixel)
//   Outputs 16 signed 9-bit residual differences for the 4x4 Integer DCT:
//     Residual[r][c] = Input[r][c] - Prediction[r][c]
// =============================================================================

`timescale 1ns / 1ps

module intra_pred_4x4 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [1:0]  pred_mode,      // 00: Vert, 01: Horiz, 10: DC, 11: Bypass

    // 4x4 Input Original / Inpainted Pixels
    input  wire [7:0]  p00, p01, p02, p03,
    input  wire [7:0]  p10, p11, p12, p13,
    input  wire [7:0]  p20, p21, p22, p23,
    input  wire [7:0]  p30, p31, p32, p33,

    // Top Neighbors (4 pixels from block above)
    input  wire [7:0]  top0, top1, top2, top3,
    // Left Neighbors (4 pixels from block to left)
    input  wire [7:0]  left0, left1, left2, left3,

    output reg         valid_out,
    // 4x4 Residual Outputs (signed 9-bit: -255 to +255)
    output reg  signed [8:0] res00, res01, res02, res03,
    output reg  signed [8:0] res10, res11, res12, res13,
    output reg  signed [8:0] res20, res21, res22, res23,
    output reg  signed [8:0] res30, res31, res32, res33
);

    // Compute DC Average: (top0 + top1 + top2 + top3 + left0 + left1 + left2 + left3 + 4) >> 3
    wire [10:0] dc_sum = top0 + top1 + top2 + top3 + left0 + left1 + left2 + left3 + 4;
    wire [7:0]  dc_val = dc_sum[10:3];

    // Combinational prediction matrix
    reg [7:0] pred [0:3][0:3];
    integer r, c;

    always @(*) begin
        case (pred_mode)
            2'b00: begin // Vertical Prediction
                pred[0][0] = top0; pred[0][1] = top1; pred[0][2] = top2; pred[0][3] = top3;
                pred[1][0] = top0; pred[1][1] = top1; pred[1][2] = top2; pred[1][3] = top3;
                pred[2][0] = top0; pred[2][1] = top1; pred[2][2] = top2; pred[2][3] = top3;
                pred[3][0] = top0; pred[3][1] = top1; pred[3][2] = top2; pred[3][3] = top3;
            end
            2'b01: begin // Horizontal Prediction
                pred[0][0] = left0; pred[0][1] = left0; pred[0][2] = left0; pred[0][3] = left0;
                pred[1][0] = left1; pred[1][1] = left1; pred[1][2] = left1; pred[1][3] = left1;
                pred[2][0] = left2; pred[2][1] = left2; pred[2][2] = left2; pred[2][3] = left2;
                pred[3][0] = left3; pred[3][1] = left3; pred[3][2] = left3; pred[3][3] = left3;
            end
            2'b10: begin // DC Prediction
                for (r = 0; r < 4; r = r + 1)
                    for (c = 0; c < 4; c = c + 1)
                        pred[r][c] = dc_val;
            end
            default: begin // Bypass (Prediction = 0)
                for (r = 0; r < 4; r = r + 1)
                    for (c = 0; c < 4; c = c + 1)
                        pred[r][c] = 8'd0;
            end
        endcase
    end

    // Pipeline residual output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            res00 <= 9'sd0; res01 <= 9'sd0; res02 <= 9'sd0; res03 <= 9'sd0;
            res10 <= 9'sd0; res11 <= 9'sd0; res12 <= 9'sd0; res13 <= 9'sd0;
            res20 <= 9'sd0; res21 <= 9'sd0; res22 <= 9'sd0; res23 <= 9'sd0;
            res30 <= 9'sd0; res31 <= 9'sd0; res32 <= 9'sd0; res33 <= 9'sd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                res00 <= $signed({1'b0, p00}) - $signed({1'b0, pred[0][0]});
                res01 <= $signed({1'b0, p01}) - $signed({1'b0, pred[0][1]});
                res02 <= $signed({1'b0, p02}) - $signed({1'b0, pred[0][2]});
                res03 <= $signed({1'b0, p03}) - $signed({1'b0, pred[0][3]});

                res10 <= $signed({1'b0, p10}) - $signed({1'b0, pred[1][0]});
                res11 <= $signed({1'b0, p11}) - $signed({1'b0, pred[1][1]});
                res12 <= $signed({1'b0, p12}) - $signed({1'b0, pred[1][2]});
                res13 <= $signed({1'b0, p13}) - $signed({1'b0, pred[1][3]});

                res20 <= $signed({1'b0, p20}) - $signed({1'b0, pred[2][0]});
                res21 <= $signed({1'b0, p21}) - $signed({1'b0, pred[2][1]});
                res22 <= $signed({1'b0, p22}) - $signed({1'b0, pred[2][2]});
                res23 <= $signed({1'b0, p23}) - $signed({1'b0, pred[2][3]});

                res30 <= $signed({1'b0, p30}) - $signed({1'b0, pred[3][0]});
                res31 <= $signed({1'b0, p31}) - $signed({1'b0, pred[3][1]});
                res32 <= $signed({1'b0, p32}) - $signed({1'b0, pred[3][2]});
                res33 <= $signed({1'b0, p33}) - $signed({1'b0, pred[3][3]});
            end
        end
    end

endmodule
