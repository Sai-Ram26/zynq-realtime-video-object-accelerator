// =============================================================================
// Module: hybrid_inpainter.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Unified Hybrid Object Removal & Inpainting Sub-System.
//   Integrates:
//     1. Frame-Difference Background Subtraction Core
//     2. Line-Buffered 8x8 Spatial Window Neighborhood-Average Inpainter
//     3. Stochastic Computing Arithmetic (S-SAD) Unit for low-power subtraction
//     4. Programmable Inpainting Arbiter:
//          mode 2'b00: Temporal Inpainting (replace with learned background)
//          mode 2'b01: Spatial 8x8 Inpainting (neighborhood boundary average)
//          mode 2'b10: Hybrid Spatial-Temporal Arbiter (uses temporal if bg valid,
//                      otherwise falls back to spatial 8x8 reconstruction)
// =============================================================================

`timescale 1ns / 1ps

module hybrid_inpainter #(
    parameter integer LINE_WIDTH = 64, // Configurable for testbench (64) or video (480/1280)
    parameter integer DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire [DATA_WIDTH-1:0] curr_pixel,
    input  wire [DATA_WIDTH-1:0] bg_pixel,
    input  wire [DATA_WIDTH-1:0] threshold,
    input  wire [1:0]            mode_sel,    // 00: Temporal, 01: Spatial 8x8, 10: Hybrid
    input  wire                  bg_valid,    // 1 if prior background model exists

    output wire                  valid_out,
    output wire                  mask_out,
    output wire [DATA_WIDTH-1:0] clean_pixel_out,

    // Stochastic monitor outputs
    output wire                  s_mult,
    output wire                  s_add,
    output wire                  s_sad_stream
);

    // -------------------------------------------------------------------------
    // 1. Background Subtraction Difference Detector
    // -------------------------------------------------------------------------
    reg [7:0]  diff_r;
    reg [7:0]  curr_d1, bg_d1, thresh_d1;
    reg        valid_d1;
    reg        raw_mask_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_r     <= 8'd0;
            curr_d1    <= 8'd0;
            bg_d1      <= 8'd0;
            thresh_d1  <= 8'd0;
            valid_d1   <= 1'b0;
            raw_mask_r <= 1'b0;
        end else begin
            valid_d1  <= valid_in;
            curr_d1   <= curr_pixel;
            bg_d1     <= bg_pixel;
            thresh_d1 <= threshold;

            if (curr_pixel >= bg_pixel)
                diff_r <= curr_pixel - bg_pixel;
            else
                diff_r <= bg_pixel - curr_pixel;

            raw_mask_r <= ((curr_pixel >= bg_pixel ? curr_pixel - bg_pixel : bg_pixel - curr_pixel) > threshold);
        end
    end

    // -------------------------------------------------------------------------
    // 2. Stochastic Computing Arithmetic (S-SAD)
    // -------------------------------------------------------------------------
    stochastic_sad u_stoch (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .a_in(curr_pixel),
        .b_in(bg_pixel),
        .s_stream_a(),
        .s_stream_b(),
        .s_mult(s_mult),
        .s_add(s_add),
        .s_sad_stream(s_sad_stream),
        .valid_out(),
        .mult_out(),
        .add_out(),
        .sad_out()
    );

    // -------------------------------------------------------------------------
    // 3. Line-Buffered 8x8 Spatial Inpainter
    // -------------------------------------------------------------------------
    wire                  spatial_valid;
    wire [DATA_WIDTH-1:0] spatial_clean;

    inpainting_8x8_linebuffer #(
        .LINE_WIDTH(LINE_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_spatial_inpaint (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(valid_d1),
        .in_pixel(curr_d1),
        .in_mask(raw_mask_r),
        .out_valid(spatial_valid),
        .out_pixel(spatial_clean)
    );

    // -------------------------------------------------------------------------
    // 4. Temporal Inpaint Pipeline (Matched with spatial delay)
    // -------------------------------------------------------------------------
    // inpainting_8x8_linebuffer has 2 pipeline stages of latency from in_valid
    reg [DATA_WIDTH-1:0] temporal_clean_pipe [0:1];
    reg                  temporal_mask_pipe [0:1];
    reg                  temporal_valid_pipe [0:1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            temporal_clean_pipe[0] <= 8'd0;
            temporal_clean_pipe[1] <= 8'd0;
            temporal_mask_pipe[0]  <= 1'b0;
            temporal_mask_pipe[1]  <= 1'b0;
            temporal_valid_pipe[0] <= 1'b0;
            temporal_valid_pipe[1] <= 1'b0;
        end else begin
            temporal_valid_pipe[0] <= valid_d1;
            temporal_mask_pipe[0]  <= raw_mask_r;
            temporal_clean_pipe[0] <= raw_mask_r ? bg_d1 : curr_d1;

            temporal_valid_pipe[1] <= temporal_valid_pipe[0];
            temporal_mask_pipe[1]  <= temporal_mask_pipe[0];
            temporal_clean_pipe[1] <= temporal_clean_pipe[0];
        end
    end

    // -------------------------------------------------------------------------
    // 5. Output Arbiter
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] final_pixel;
    reg                  final_mask;
    reg                  final_valid;

    always @(*) begin
        final_valid = spatial_valid;
        final_mask  = temporal_mask_pipe[1];

        case (mode_sel)
            2'b00: begin // Pure Temporal
                final_pixel = temporal_clean_pipe[1];
            end
            2'b01: begin // Pure Spatial 8x8
                final_pixel = spatial_clean;
            end
            2'b10: begin // Hybrid: Temporal if bg_valid, else Spatial 8x8
                if (bg_valid)
                    final_pixel = temporal_clean_pipe[1];
                else
                    final_pixel = spatial_clean;
            end
            default: begin
                final_pixel = temporal_clean_pipe[1];
            end
        endcase
    end

    assign valid_out       = final_valid;
    assign mask_out        = final_mask;
    assign clean_pixel_out = final_pixel;

endmodule
