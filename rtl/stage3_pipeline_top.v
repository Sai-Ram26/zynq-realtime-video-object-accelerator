// ============================================================================
// File: stage3_pipeline_top.v
// Module: stage3_pipeline_top
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 3 Complete Hardware Pipeline Top Integration.
//              Connects the complete 5-stage data-plane processing pipeline:
//                Stage 1: RGB2YUV Converter
//                Stage 2: Temporal Background Subtraction
//                Stage 3: Spatial 8x8 Inpainting Engine
//                Stage 4: 4x4 Integer DCT + Quantization
//                Stage 5: CAVLC Entropy Encoder + NAL Serializer
//              Also instantiates the RISC-V custom opcode decoder and
//              hardware performance monitoring engine.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module stage3_pipeline_top #(
    parameter integer LINE_WIDTH = 64 // Horizontal line width (pixels)
)(
    input  wire        clk,             // System clock (100 MHz)
    input  wire        rst_n,           // Active-low asynchronous reset

    // RISC-V Control Plane Interface
    input  wire        insn_valid,
    input  wire [31:0] instruction,
    input  wire [31:0] rs1_data,
    output wire        pe_array_start,
    output wire [3:0]  pe_target_op,
    output wire [31:0] pe_mem_addr,
    output wire        pe_busy,

    // Streaming Pixel Input
    input  wire        pixel_valid_in,
    input  wire [7:0]  r_in, g_in, b_in,
    input  wire [7:0]  y_bg_in,
    input  wire [7:0]  t_thresh_in,
    input  wire [5:0]  qp_in,            // Quantization Parameter

    // Performance Monitor Interface
    input  wire        perf_enable,
    output wire [31:0] total_cycles,
    output wire [31:0] active_cycles,
    output wire [31:0] stall_cycles,
    output wire [31:0] pixel_count,
    output wire [31:0] inpaint_events,
    output wire [31:0] nal_word_count,

    // Compressed Output
    output wire        nal_valid_out,
    output wire [31:0] nal_word_out,
    output wire [5:0]  nal_bit_count_out,
    output wire [4:0]  total_coeff_out,

    // Debug / Observation
    output wire [7:0]  y_inpainted,
    output wire        foreground_mask,
    output wire        inpaint_active
);

    // -------------------------------------------------------------------------
    // Internal Signal Wires
    // -------------------------------------------------------------------------
    wire        s2_valid_out;
    wire [7:0]  s2_y_inpainted_w;
    wire [7:0]  s2_u_out_w, s2_v_out_w;
    wire [7:0]  s2_abs_diff_w;
    wire        s2_foreground_mask_w;
    wire        s2_inpaint_active_w;

    reg         pe_array_ready_reg;

    // -------------------------------------------------------------------------
    // Block Assembly Shift Registers: Pack 4x4 pixel blocks for DCT
    // -------------------------------------------------------------------------
    reg [7:0]  block_row  [0:3][0:3];  // 4x4 block accumulator
    reg [1:0]  bcol;                    // Block column counter (0-3)
    reg [1:0]  brow;                    // Block row counter (0-3)
    reg [5:0]  pixel_col_cnt;           // Global column counter mod LINE_WIDTH
    reg        block_valid;             // 4x4 block complete pulse

    // DCT wires
    wire        dct_valid_out;
    wire        dct_skip_out;
    wire signed [15:0] dz00, dz01, dz02, dz03;
    wire signed [15:0] dz10, dz11, dz12, dz13;
    wire signed [15:0] dz20, dz21, dz22, dz23;
    wire signed [15:0] dz30, dz31, dz32, dz33;
    reg [5:0]   qp_latched;

    // -------------------------------------------------------------------------
    // 1. RISC-V Custom Opcode Decoder
    // -------------------------------------------------------------------------
    custom_vector_decoder u_decoder (
        .clk(clk), .rst_n(rst_n),
        .insn_valid(insn_valid), .instruction(instruction), .rs1_data(rs1_data),
        .pe_array_start(pe_array_start), .pe_target_op(pe_target_op),
        .pe_mem_addr(pe_mem_addr), .pe_array_ready(pe_array_ready_reg), .pe_busy(pe_busy)
    );

    // -------------------------------------------------------------------------
    // 2. Stage 2 Core (RGB2YUV + BgSub + Inpainting 8x8)
    // -------------------------------------------------------------------------
    stage2_core_top #(
        .LINE_WIDTH(LINE_WIDTH)
    ) u_stage2 (
        .clk(clk), .rst_n(rst_n),
        .insn_valid(1'b0), .instruction(32'd0), .rs1_data(32'd0),
        .pe_array_start(), .pe_target_op(), .pe_mem_addr(), .pe_busy(),
        .pixel_valid_in(pixel_valid_in),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .y_bg_in(y_bg_in), .t_thresh_in(t_thresh_in),
        .pixel_valid_out(s2_valid_out),
        .y_inpainted(s2_y_inpainted_w),
        .u_out(s2_u_out_w), .v_out(s2_v_out_w),
        .abs_diff_out(s2_abs_diff_w),
        .foreground_mask(s2_foreground_mask_w),
        .inpaint_active(s2_inpaint_active_w)
    );

    assign y_inpainted    = s2_y_inpainted_w;
    assign foreground_mask = s2_foreground_mask_w;
    assign inpaint_active  = s2_inpaint_active_w;

    // -------------------------------------------------------------------------
    // 3. Block Assembler: Pack inpainted stream into 4x4 blocks for DCT
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcol          <= 2'd0;
            brow          <= 2'd0;
            pixel_col_cnt <= 6'd0;
            block_valid   <= 1'b0;
            qp_latched    <= 6'd0;
        end else begin
            block_valid <= 1'b0;
            if (s2_valid_out) begin
                block_row[brow][bcol] <= s2_y_inpainted_w;
                qp_latched            <= qp_in;

                if (bcol == 2'd3) begin
                    bcol <= 2'd0;
                    if (brow == 2'd3) begin
                        brow        <= 2'd0;
                        block_valid <= 1'b1;
                    end else begin
                        brow <= brow + 2'd1;
                    end
                end else begin
                    bcol <= bcol + 2'd1;
                end

                if (pixel_col_cnt == LINE_WIDTH - 1)
                    pixel_col_cnt <= 6'd0;
                else
                    pixel_col_cnt <= pixel_col_cnt + 6'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Stage 4: 4x4 Integer DCT + Quantization
    // -------------------------------------------------------------------------
    dct_quant_4x4 u_dct (
        .clk(clk), .rst_n(rst_n),
        .valid_in(block_valid), .skip_mode_in(1'b0), .qp_in(qp_latched),
        .x00(block_row[0][0]), .x01(block_row[0][1]),
        .x02(block_row[0][2]), .x03(block_row[0][3]),
        .x10(block_row[1][0]), .x11(block_row[1][1]),
        .x12(block_row[1][2]), .x13(block_row[1][3]),
        .x20(block_row[2][0]), .x21(block_row[2][1]),
        .x22(block_row[2][2]), .x23(block_row[2][3]),
        .x30(block_row[3][0]), .x31(block_row[3][1]),
        .x32(block_row[3][2]), .x33(block_row[3][3]),
        .valid_out(dct_valid_out), .skip_out(dct_skip_out),
        .z00(dz00), .z01(dz01), .z02(dz02), .z03(dz03),
        .z10(dz10), .z11(dz11), .z12(dz12), .z13(dz13),
        .z20(dz20), .z21(dz21), .z22(dz22), .z23(dz23),
        .z30(dz30), .z31(dz31), .z32(dz32), .z33(dz33)
    );

    // -------------------------------------------------------------------------
    // 5. Stage 5: CAVLC Entropy Encoder + NAL Serializer
    // -------------------------------------------------------------------------
    cavlc_encoder u_cavlc (
        .clk(clk), .rst_n(rst_n),
        .valid_in(dct_valid_out), .skip_mode_in(dct_skip_out),
        .z00(dz00), .z01(dz01), .z02(dz02), .z03(dz03),
        .z10(dz10), .z11(dz11), .z12(dz12), .z13(dz13),
        .z20(dz20), .z21(dz21), .z22(dz22), .z23(dz23),
        .z30(dz30), .z31(dz31), .z32(dz32), .z33(dz33),
        .valid_out(nal_valid_out),
        .bitstream_word(nal_word_out),
        .bit_count(nal_bit_count_out),
        .total_coeff_out(total_coeff_out),
        .trailing_ones_out()
    );

    // -------------------------------------------------------------------------
    // 6. Stage 6: Hardware Performance Monitor
    // -------------------------------------------------------------------------
    perf_monitor u_perf (
        .clk(clk), .rst_n(rst_n),
        .enable(perf_enable),
        .pixel_valid_in(s2_valid_out),
        .inpaint_active(s2_inpaint_active_w),
        .nal_valid(nal_valid_out),
        .total_cycles(total_cycles),
        .active_cycles(active_cycles),
        .stall_cycles(stall_cycles),
        .pixel_count(pixel_count),
        .inpaint_events(inpaint_events),
        .nal_word_count(nal_word_count)
    );

    // PE handshake
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pe_array_ready_reg <= 1'b0;
        else        pe_array_ready_reg <= nal_valid_out;
    end

endmodule
