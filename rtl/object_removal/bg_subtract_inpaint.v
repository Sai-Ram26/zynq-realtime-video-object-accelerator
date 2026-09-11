`timescale 1ns / 1ps

// ============================================================================
// Module: bg_subtract_inpaint
// Description: Frame-differencing, threshold mask generation, and inpainting
//              pixel replacement core.
// Throughput: 1 pixel per clock cycle (Fully Pipelined, 2 clock latency).
// ============================================================================

module bg_subtract_inpaint (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [7:0]  curr_pixel_in,
    input  wire [7:0]  bg_pixel_in,
    input  wire [7:0]  threshold_in,
    output reg         valid_out,
    output reg         mask_out,
    output reg  [7:0]  cleaned_pixel_out
);

    // Stage 1: Pipelined Absolute Difference Calculation
    reg [7:0]  diff_stage1;
    reg [7:0]  curr_stage1;
    reg [7:0]  bg_stage1;
    reg [7:0]  thresh_stage1;
    reg        valid_stage1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_stage1   <= 8'd0;
            curr_stage1   <= 8'd0;
            bg_stage1     <= 8'd0;
            thresh_stage1 <= 8'd0;
            valid_stage1  <= 1'b0;
        end else begin
            valid_stage1  <= valid_in;
            curr_stage1   <= curr_pixel_in;
            bg_stage1     <= bg_pixel_in;
            thresh_stage1 <= threshold_in;
            
            if (curr_pixel_in >= bg_pixel_in)
                diff_stage1 <= curr_pixel_in - bg_pixel_in;
            else
                diff_stage1 <= bg_pixel_in - curr_pixel_in;
        end
    end

    // Stage 2: Threshold Comparison & Inpaint Multiplexer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out         <= 1'b0;
            mask_out          <= 1'b0;
            cleaned_pixel_out <= 8'd0;
        end else begin
            valid_out <= valid_stage1;
            if (valid_stage1) begin
                if (diff_stage1 > thresh_stage1) begin
                    mask_out          <= 1'b1;         // Foreground detected
                    cleaned_pixel_out <= bg_stage1;    // Inpaint with background
                end else begin
                    mask_out          <= 1'b0;         // Background match
                    cleaned_pixel_out <= curr_stage1;  // Pass current pixel
                end
            end
        end
    end

endmodule
