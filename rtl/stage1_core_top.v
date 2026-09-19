// ============================================================================
// File: stage1_core_top.v
// Module: stage1_core_top
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 1 Core Integration Top Module. Connects the Custom RISC-V
//              Opcode Vector Decoder, Fixed-Point RGB2YUV Converter, and
//              Temporal Background Subtraction Engine into a unified core.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module stage1_core_top (
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
    output wire [7:0]  y_out,           // Converted/processed luma
    output wire [7:0]  u_out,           // Chroma U component
    output wire [7:0]  v_out,           // Chroma V component
    output wire [7:0]  abs_diff_out,    // Absolute pixel difference
    output wire        foreground_mask  // 1-bit Motion Mask ('1'=Foreground)
);

    // Internal Signal Wires
    wire       rgb2yuv_valid_w;
    wire [7:0] y_converted_w;
    wire [7:0] u_converted_w;
    wire [7:0] v_converted_w;

    // PE Array Handshake Signal
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
        .valid_out(pixel_valid_out),
        .y_out(y_out),
        .diff_out(abs_diff_out),
        .foreground_mask(foreground_mask)
    );

    // Pass through U/V chroma components synchronized with pipeline delay
    reg [7:0] u_pipe_r;
    reg [7:0] v_pipe_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_pipe_r           <= 8'd0;
            v_pipe_r           <= 8'd0;
            pe_array_ready_reg <= 1'b0;
        end else begin
            u_pipe_r           <= u_converted_w;
            v_pipe_r           <= v_converted_w;
            pe_array_ready_reg <= pixel_valid_out;
        end
    end

    assign u_out = u_pipe_r;
    assign v_out = v_pipe_r;

endmodule
