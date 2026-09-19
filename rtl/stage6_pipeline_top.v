// ============================================================================
// File: stage6_pipeline_top.v
// Module: stage6_pipeline_top
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Stage 6 Top-Level Pipeline Integration with Hardware Performance
//              Monitoring, Status Register Latches, and Diagnostic LEDs.
//              Integrates:
//                - stage3_pipeline_top (RGB2YUV, BgSub, Inpaint, DCT, CAVLC)
//                - custom_vector_decoder (RISC-V Opcode 0x0B)
//                - perf_monitor (Total cycles, active cycles, stall cycles, etc.)
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module stage6_pipeline_top #(
    parameter integer LINE_WIDTH = 64
)(
    input  wire        clk,
    input  wire        rst_n,

    // RISC-V Instruction Dispatch
    input  wire        insn_valid,
    input  wire [31:0] instruction,
    input  wire [31:0] rs1_data,
    output wire        pe_array_start,
    output wire [3:0]  pe_target_op,
    output wire [31:0] pe_mem_addr,
    output wire        pe_busy,

    // Video Stream Input
    input  wire        pixel_valid_in,
    input  wire [7:0]  r_in, g_in, b_in,
    input  wire [7:0]  y_bg_in,
    input  wire [7:0]  t_thresh_in,
    input  wire [5:0]  qp_in,

    // Performance Monitor Control & Counters
    input  wire        perf_enable,
    output wire [31:0] total_cycles,
    output wire [31:0] active_cycles,
    output wire [31:0] stall_cycles,
    output wire [31:0] pixel_count,
    output wire [31:0] inpaint_events,
    output wire [31:0] nal_word_count,

    // Compressed Stream Output
    output wire        nal_valid_out,
    output wire [31:0] nal_word_out,
    output wire [5:0]  nal_bit_count_out,
    output wire [4:0]  total_coeff_out,

    // Status Observation & Physical LEDs
    output wire [7:0]  y_inpainted,
    output wire        foreground_mask,
    output wire        inpaint_active,
    output wire [7:0]  led_status
);

    // Instantiate Stage 3 Pipeline Core
    stage3_pipeline_top #(
        .LINE_WIDTH(LINE_WIDTH)
    ) u_pipeline_core (
        .clk               (clk),
        .rst_n             (rst_n),

        .insn_valid        (insn_valid),
        .instruction       (instruction),
        .rs1_data          (rs1_data),
        .pe_array_start    (pe_array_start),
        .pe_target_op      (pe_target_op),
        .pe_mem_addr       (pe_mem_addr),
        .pe_busy           (pe_busy),

        .pixel_valid_in    (pixel_valid_in),
        .r_in              (r_in),
        .g_in              (g_in),
        .b_in              (b_in),
        .y_bg_in           (y_bg_in),
        .t_thresh_in       (t_thresh_in),
        .qp_in             (qp_in),

        .perf_enable       (perf_enable),
        .total_cycles      (total_cycles),
        .active_cycles     (active_cycles),
        .stall_cycles      (stall_cycles),
        .pixel_count       (pixel_count),
        .inpaint_events    (inpaint_events),
        .nal_word_count    (nal_word_count),

        .nal_valid_out     (nal_valid_out),
        .nal_word_out      (nal_word_out),
        .nal_bit_count_out (nal_bit_count_out),
        .total_coeff_out   (total_coeff_out),

        .y_inpainted       (y_inpainted),
        .foreground_mask   (foreground_mask),
        .inpaint_active    (inpaint_active)
    );

    // Heartbeat divider for LED0
    reg [23:0] heartbeat_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            heartbeat_cnt <= 24'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 24'd1;
    end

    // ZedBoard Status LEDs Mapping
    assign led_status[0] = heartbeat_cnt[23];         // Heartbeat (blinks at ~3 Hz)
    assign led_status[1] = pe_busy;                  // Accelerator active
    assign led_status[2] = foreground_mask;          // Motion detected
    assign led_status[3] = inpaint_active;           // Inpainting active
    assign led_status[4] = (total_coeff_out > 0);    // Non-zero coefficients
    assign led_status[5] = nal_valid_out;            // NAL word emitted
    assign led_status[6] = perf_enable;              // Performance monitor running
    assign led_status[7] = (stall_cycles > 0);       // Pipeline stalled

endmodule
