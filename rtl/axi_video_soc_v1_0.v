// ============================================================================
// File: axi_video_soc_v1_0.v
// Module: axi_video_soc_v1_0
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Top-Level AXI SoC IP Wrapper for Zynq-7000 (ZedBoard).
//              Integrates:
//                - AXI4-Lite Slave Register Interface (0x43C00000)
//                - Stage 6 High-Efficiency Video Processing Pipeline
//                - AXI ACP (Accelerator Coherency Port) Cache-Coherent Sidebands:
//                  ARUSER = 5'b11111, AWUSER = 5'b11111
//                  ARCACHE = 4'b1111 (Write-back, Read and Write Allocate)
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module axi_video_soc_v1_0 #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer LINE_WIDTH         = 64
)(
    // System Clock and Reset
    input  wire                          s_axi_aclk,
    input  wire                          s_axi_aresetn,

    // AXI4-Lite Slave Interface
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]                    s_axi_awprot,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,
    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready,

    // AXI ACP Cache-Coherent Master Sideband Ports (Connecting to PS7 S_AXI_ACP)
    output wire [4:0]                    m_axi_acp_aruser,
    output wire [4:0]                    m_axi_acp_awuser,
    output wire [3:0]                    m_axi_acp_arcache,
    output wire [3:0]                    m_axi_acp_awcache,

    // External Physical ZedBoard Pins
    output wire [7:0]                    led_status
);

    // -------------------------------------------------------------------------
    // ACP Cache Coherency Sideband Assignments
    // -------------------------------------------------------------------------
    // ARUSER/AWUSER[4:0] = 5'b11111: Inner Shareable, Cacheable
    // ARCACHE/AWCACHE[3:0] = 4'b1111: Write-Back, Read & Write Allocate
    assign m_axi_acp_aruser  = 5'b11111;
    assign m_axi_acp_awuser  = 5'b11111;
    assign m_axi_acp_arcache = 4'b1111;
    assign m_axi_acp_awcache = 4'b1111;

    // -------------------------------------------------------------------------
    // Internal Interconnect Wires
    // -------------------------------------------------------------------------
    wire        reg_start;
    wire        reg_soft_rst;
    wire        reg_perf_enable;
    wire [31:0] reg_instruction;
    wire [31:0] reg_rs1_data;
    wire [5:0]  reg_qp;
    wire [7:0]  reg_t_thresh;
    wire [7:0]  reg_r_in, reg_g_in, reg_b_in;
    wire        reg_pixel_valid;
    wire [7:0]  reg_y_bg;

    wire        pe_array_start;
    wire [3:0]  pe_target_op;
    wire [31:0] pe_mem_addr;
    wire        pe_busy;

    wire [31:0] total_cycles;
    wire [31:0] active_cycles;
    wire [31:0] stall_cycles;
    wire [31:0] pixel_count;
    wire [31:0] inpaint_events;
    wire [31:0] nal_word_count;

    wire        nal_valid_out;
    wire [31:0] nal_word_out;
    wire [5:0]  nal_bit_count_out;
    wire [4:0]  total_coeff_out;

    wire [7:0]  y_inpainted;
    wire        foreground_mask;
    wire        inpaint_active;

    wire        effective_rst_n = s_axi_aresetn & (~reg_soft_rst);

    // Instantiate AXI4-Lite Slave Register Interface
    axi_lite_slave #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) u_axi_slave (
        .s_axi_aclk        (s_axi_aclk),
        .s_axi_aresetn     (s_axi_aresetn),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awprot      (s_axi_awprot),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arprot      (s_axi_arprot),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready),

        .reg_start         (reg_start),
        .reg_soft_rst      (reg_soft_rst),
        .reg_perf_enable   (reg_perf_enable),
        .reg_instruction   (reg_instruction),
        .reg_rs1_data      (reg_rs1_data),
        .reg_qp            (reg_qp),
        .reg_t_thresh      (reg_t_thresh),
        .reg_r_in          (reg_r_in),
        .reg_g_in          (reg_g_in),
        .reg_b_in          (reg_b_in),
        .reg_pixel_valid   (reg_pixel_valid),
        .reg_y_bg          (reg_y_bg),

        .pe_busy           (pe_busy),
        .nal_valid         (nal_valid_out),
        .inpaint_active    (inpaint_active),
        .foreground_mask   (foreground_mask),
        .y_inpainted       (y_inpainted),
        .nal_word          (nal_word_out),
        .total_cycles      (total_cycles),
        .active_cycles     (active_cycles),
        .stall_cycles      (stall_cycles),
        .pixel_count       (pixel_count),
        .inpaint_events    (inpaint_events),
        .nal_word_count    (nal_word_count)
    );

    // Instantiate Stage 6 Video Processing Top Core
    stage6_pipeline_top #(
        .LINE_WIDTH(LINE_WIDTH)
    ) u_stage6_core (
        .clk               (s_axi_aclk),
        .rst_n             (effective_rst_n),

        .insn_valid        (reg_start),
        .instruction       (reg_instruction),
        .rs1_data          (reg_rs1_data),
        .pe_array_start    (pe_array_start),
        .pe_target_op      (pe_target_op),
        .pe_mem_addr       (pe_mem_addr),
        .pe_busy           (pe_busy),

        .pixel_valid_in    (reg_pixel_valid),
        .r_in              (reg_r_in),
        .g_in              (reg_g_in),
        .b_in              (reg_b_in),
        .y_bg_in           (reg_y_bg),
        .t_thresh_in       (reg_t_thresh),
        .qp_in             (reg_qp),

        .perf_enable       (reg_perf_enable),
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
        .inpaint_active    (inpaint_active),
        .led_status        (led_status)
    );

endmodule
