// ============================================================================
// File: stage2_core_top.v
// Module: stage2_core_top
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 2 Core Integration Top Module. Connects the Custom RISC-V
//              Opcode Vector Decoder, Fixed-Point RGB2YUV Converter,
//              Temporal Background Subtraction Engine, and Spatial 8x8 Inpainting Engine.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module stage2_core_top #(
    parameter integer LINE_WIDTH = 16
)(
    input  wire        clk,             // System processing clock (100 MHz)
    input  wire        rst_n,           // Active-low asynchronous reset

    // RISC-V Control Plane Interface
    input  wire        insn_valid,      // CPU Instruction valid trigger
    input  wire [31:0] instruction,     // 32-bit RISC-V instruction word
    input  wire [31:0] rs1_data,        // Register 1 data (Memory pointer)
    output wire        pe_array_start,  // PE Array launch trigger
    output wire [3:0]  pe_target_op,    // Decoded target operation
    output wire [31:0] pe_mem_addr,     // Decoded memory base address
    output wire        pe_busy,         // Acceleration core busy status

    // Streaming Data Path Interface
    input  wire        pixel_valid_in,  // Streaming pixel input valid
    input  wire [7:0]  r_in,            // Red pixel component
    input  wire [7:0]  g_in,            // Green pixel component
    input  wire [7:0]  b_in,            // Blue pixel component
    input  wire [7:0]  y_bg_in,         // Background reference luma
    input  wire [7:0]  t_thresh_in,     // Motion subtraction threshold

    output wire        pixel_valid_out, // Processed pixel valid
    output wire [7:0]  y_inpainted,     // Reconstructed/Inpainted luma
    output wire [7:0]  u_out,           // Chroma U component
    output wire [7:0]  v_out,           // Chroma V component
    output wire [7:0]  abs_diff_out,    // Absolute pixel difference
    output wire        foreground_mask, // 1-bit Motion Mask ('1'=Foreground)
    output wire        inpaint_active   // High when inpainting substitution is active
);

    // Internal Wires
    wire       rgb2yuv_valid_w;
    wire [7:0] y_converted_w, u_converted_w, v_converted_w;
    wire       bgsub_valid_w;
    wire [7:0] y_sub_w, diff_sub_w;
    wire       mask_sub_w;
    reg        pe_array_ready_reg;

    // 1. Instantiate Custom RISC-V Opcode Decoder
    custom_vector_decoder u_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .insn_valid(insn_valid),
        .instruction(instruction),
        .rs1_data(rs1_data),
        .pe_array_start(pe_array_start),
        .pe_target_op(pe_target_op),
        .pe_mem_addr(pe_mem_addr),
        .pe_array_ready(pe_array_ready_reg),
        .pe_busy(pe_busy)
    );

    // 2. Instantiate Stage 1 RGB to YUV420 Converter
    rgb2yuv u_rgb2yuv (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(pixel_valid_in),
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .valid_out(rgb2yuv_valid_w),
        .y_out(y_converted_w),
        .u_out(u_converted_w),
        .v_out(v_converted_w)
    );

    // 3. Instantiate Stage 2 Temporal Background Subtraction Engine
    bg_sub u_bg_sub (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(rgb2yuv_valid_w),
        .y_curr(y_converted_w),
        .y_bg(y_bg_in),
        .t_thresh(t_thresh_in),
        .valid_out(bgsub_valid_w),
        .y_out(y_sub_w),
        .diff_out(diff_sub_w),
        .foreground_mask(mask_sub_w)
    );

    // 4. Instantiate Stage 3 Spatial 8x8 Inpainting Engine
    inpainting_8x8 #(
        .LINE_WIDTH(LINE_WIDTH)
    ) u_inpainting (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(bgsub_valid_w),
        .y_in(y_sub_w),
        .mask_in(mask_sub_w),
        .u_in(u_converted_w),
        .v_in(v_converted_w),
        .valid_out(pixel_valid_out),
        .y_inpainted(y_inpainted),
        .u_out(u_out),
        .v_out(v_out),
        .inpaint_active(inpaint_active)
    );

    // Pipeline abs_diff and foreground_mask to match inpainting_8x8 output latency (2 cycles)
    reg [7:0] diff_pipe1_r, diff_pipe2_r;
    reg       mask_pipe1_r, mask_pipe2_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_pipe1_r <= 8'd0;
            diff_pipe2_r <= 8'd0;
            mask_pipe1_r <= 1'b0;
            mask_pipe2_r <= 1'b0;
            pe_array_ready_reg <= 1'b0;
        end else begin
            diff_pipe1_r <= diff_sub_w;
            diff_pipe2_r <= diff_pipe1_r;
            mask_pipe1_r <= mask_sub_w;
            mask_pipe2_r <= mask_pipe1_r;
            pe_array_ready_reg <= pixel_valid_out;
        end
    end

    assign abs_diff_out    = diff_pipe2_r;
    assign foreground_mask = mask_pipe2_r;

endmodule
