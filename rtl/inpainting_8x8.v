// ============================================================================
// File: inpainting_8x8.v
// Module: inpainting_8x8
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 3 Spatial 8x8 Line-Buffered Inpainting Engine.
//              Uses a 7-line dual-port Block RAM line-store network to form a
//              real-time 8x8 sliding spatial window. Evaluates foreground masks
//              and reconstructs masked pixels using mathematical spatial averages
//              of clean background neighbors.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module inpainting_8x8 #(
    parameter integer LINE_WIDTH = 16 // Configurable horizontal line width (pixels)
)(
    input  wire        clk,            // System processing clock (100 MHz)
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        valid_in,       // Input pixel valid handshake
    input  wire [7:0]  y_in,           // Incoming luma (Y)
    input  wire        mask_in,        // 1-bit Motion Mask ('1' = Masked/Foreground)
    input  wire [7:0]  u_in,           // Incoming chroma (U)
    input  wire [7:0]  v_in,           // Incoming chroma (V)

    output reg         valid_out,      // Output valid handshake
    output reg  [7:0]  y_inpainted,    // Inpainted/Reconstructed Luma
    output reg  [7:0]  u_out,          // Passed chroma (U)
    output reg  [7:0]  v_out,          // Passed chroma (V)
    output reg         inpaint_active  // High when center pixel was masked and inpainted
);

    localparam integer WORD_WIDTH = 9; // 8 bits Y + 1 bit Mask = 9 bits

    // Line Buffer Arrays for 7 Previous Horizontal Lines
    reg [WORD_WIDTH-1:0] line_buf_0 [0:LINE_WIDTH-1];
    reg [WORD_WIDTH-1:0] line_buf_1 [0:LINE_WIDTH-1];
    reg [WORD_WIDTH-1:0] line_buf_2 [0:LINE_WIDTH-1];
    reg [WORD_WIDTH-1:0] line_buf_3 [0:LINE_WIDTH-1];
    reg [WORD_WIDTH-1:0] line_buf_4 [0:LINE_WIDTH-1];
    reg [WORD_WIDTH-1:0] line_buf_5 [0:LINE_WIDTH-1];
    reg [WORD_WIDTH-1:0] line_buf_6 [0:LINE_WIDTH-1];

    reg [10:0] col_ptr;
    reg [WORD_WIDTH-1:0] tap_matrix [0:7][0:7];
    integer r, c;

    // Stage 1: Line Store BRAM Write & 8x8 Window Shift Array
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_ptr <= 11'd0;
            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 8; c = c + 1) begin
                    tap_matrix[r][c] <= {WORD_WIDTH{1'b0}};
                end
            end
        end else if (valid_in) begin
            line_buf_0[col_ptr] <= {mask_in, y_in};
            line_buf_1[col_ptr] <= line_buf_0[col_ptr];
            line_buf_2[col_ptr] <= line_buf_1[col_ptr];
            line_buf_3[col_ptr] <= line_buf_2[col_ptr];
            line_buf_4[col_ptr] <= line_buf_3[col_ptr];
            line_buf_5[col_ptr] <= line_buf_4[col_ptr];
            line_buf_6[col_ptr] <= line_buf_5[col_ptr];

            if (col_ptr == LINE_WIDTH - 1) begin
                col_ptr <= 11'd0;
            end else begin
                col_ptr <= col_ptr + 1'b1;
            end

            for (r = 0; r < 8; r = r + 1) begin
                for (c = 7; c > 0; c = c - 1) begin
                    tap_matrix[r][c] <= tap_matrix[r][c-1];
                end
            end

            tap_matrix[0][0] <= {mask_in, y_in};
            tap_matrix[1][0] <= line_buf_0[col_ptr];
            tap_matrix[2][0] <= line_buf_1[col_ptr];
            tap_matrix[3][0] <= line_buf_2[col_ptr];
            tap_matrix[4][0] <= line_buf_3[col_ptr];
            tap_matrix[5][0] <= line_buf_4[col_ptr];
            tap_matrix[6][0] <= line_buf_5[col_ptr];
            tap_matrix[7][0] <= line_buf_6[col_ptr];
        end
    end

    // Stage 2 Pipeline Registers: Neighborhood Sum & Count
    reg [13:0] unmasked_sum;
    reg [6:0]  unmasked_count;
    reg [7:0]  center_y_r;
    reg        center_mask_r;
    reg [7:0]  u_pipe_1;
    reg [7:0]  v_pipe_1;
    reg        valid_pipe_1;

    reg [13:0] sum_acc;
    reg [6:0]  cnt_acc;

    always @(*) begin
        sum_acc = 14'd0;
        cnt_acc = 7'd0;
        for (r = 0; r < 8; r = r + 1) begin
            for (c = 0; c < 8; c = c + 1) begin
                if (tap_matrix[r][c][8] == 1'b0) begin
                    sum_acc = sum_acc + tap_matrix[r][c][7:0];
                    cnt_acc = cnt_acc + 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            unmasked_sum   <= 14'd0;
            unmasked_count <= 7'd0;
            center_y_r     <= 8'd0;
            center_mask_r  <= 1'b0;
            u_pipe_1       <= 8'd0;
            v_pipe_1       <= 8'd0;
            valid_pipe_1   <= 1'b0;
        end else begin
            valid_pipe_1   <= valid_in;
            u_pipe_1       <= u_in;
            v_pipe_1       <= v_in;
            center_y_r     <= tap_matrix[3][3][7:0];
            center_mask_r  <= tap_matrix[3][3][8];
            unmasked_sum   <= sum_acc;
            unmasked_count <= cnt_acc;
        end
    end

    // Stage 3 Pipeline Registers: Substitution
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out      <= 1'b0;
            y_inpainted    <= 8'd0;
            u_out          <= 8'd0;
            v_out          <= 8'd0;
            inpaint_active <= 1'b0;
        end else begin
            valid_out <= valid_pipe_1;
            u_out     <= u_pipe_1;
            v_out     <= v_pipe_1;
            if (center_mask_r == 1'b1) begin
                inpaint_active <= 1'b1;
                if (unmasked_count > 7'd0) begin
                    y_inpainted <= unmasked_sum / unmasked_count;
                end else begin
                    y_inpainted <= center_y_r;
                end
            end else begin
                inpaint_active <= 1'b0;
                y_inpainted    <= center_y_r;
            end
        end
    end

endmodule
