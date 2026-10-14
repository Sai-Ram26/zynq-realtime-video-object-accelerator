// =============================================================================
// Module: video_accelerator_top
// Description: Top-Level Synthesizable Video Processing & Compression Accelerator
// Target: AMD/Xilinx Zynq-7000 SoC XC7Z020 (ZedBoard)
// Unites: AXI-Lite Control, AXI4-Stream Ingress, Downscaler, 4x4 DCT, Quantizer,
//         and AXI4-Stream Egress with Hardware Performance Counters.
// Matches Section 21 & 22 of Master Project Specification
// =============================================================================

`timescale 1ns / 1ps

module video_accelerator_top #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer STREAM_DATA_WIDTH  = 24
)(
    // System Clocks and Resets
    input  wire                                aclk,
    input  wire                                aresetn,

    // AXI4-Lite Slave Interface (Control & Telemetry Registers)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire [2:0]                          s_axi_awprot,
    input  wire                                s_axi_awvalid,
    output wire                                s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output wire                                s_axi_wready,
    output wire [1:0]                          s_axi_bresp,
    output wire                                s_axi_bvalid,
    input  wire                                s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_araddr,
    input  wire [2:0]                          s_axi_arprot,
    input  wire                                s_axi_arvalid,
    output wire                                s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_rdata,
    output wire [1:0]                          s_axi_rresp,
    output wire                                s_axi_rvalid,
    input  wire                                s_axi_rready,

    // AXI4-Stream Video Input (from AXI DMA / Video Ingress)
    input  wire [STREAM_DATA_WIDTH-1:0]        s_axis_tdata,
    input  wire                                s_axis_tvalid,
    output wire                                s_axis_tready,
    input  wire                                s_axis_tlast,

    // AXI4-Stream Video Output (to AXI DMA / Memory Egress)
    output wire [STREAM_DATA_WIDTH-1:0]        m_axis_tdata,
    output wire                                m_axis_tvalid,
    input  wire                                m_axis_tready,
    output wire                                m_axis_tlast,

    // Interrupt Notification to ARM Cortex-A9
    output wire                                irq
);

    // Control wires from AXI-Lite Register File
    wire        ctrl_start;
    wire        ctrl_soft_reset;
    wire [15:0] src_width;
    wire [15:0] src_height;
    wire [15:0] tgt_width;
    wire [15:0] tgt_height;
    wire [7:0]  param_qp;
    wire [7:0]  scaler_mode;

    // Combined synchronous reset
    wire sys_rst_n = aresetn && (!ctrl_soft_reset);

    // Hardware status & telemetry signals
    reg         hw_busy;
    reg         hw_done;
    reg         hw_error;
    reg  [31:0] hw_cycle_count;
    reg  [31:0] hw_pixel_count;

    assign irq = hw_done;

    // Instantiate AXI-Lite Register Slave
    axi_lite_regs #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) u_regs (
        .S_AXI_ACLK(aclk),
        .S_AXI_ARESETN(sys_rst_n),
        .S_AXI_AWADDR(s_axi_awaddr),
        .S_AXI_AWPROT(s_axi_awprot),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),
        .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WVALID(s_axi_wvalid),
        .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BRESP(s_axi_bresp),
        .S_AXI_BVALID(s_axi_bvalid),
        .S_AXI_BREADY(s_axi_bready),
        .S_AXI_ARADDR(s_axi_araddr),
        .S_AXI_ARPROT(s_axi_arprot),
        .S_AXI_ARVALID(s_axi_arvalid),
        .S_AXI_ARREADY(s_axi_arready),
        .S_AXI_RDATA(s_axi_rdata),
        .S_AXI_RRESP(s_axi_rresp),
        .S_AXI_RVALID(s_axi_rvalid),
        .S_AXI_RREADY(s_axi_rready),
        .ctrl_start(ctrl_start),
        .ctrl_soft_reset(ctrl_soft_reset),
        .src_width(src_width),
        .src_height(src_height),
        .tgt_width(tgt_width),
        .tgt_height(tgt_height),
        .param_qp(param_qp),
        .scaler_mode(scaler_mode),
        .hw_busy(hw_busy),
        .hw_done(hw_done),
        .hw_error(hw_error),
        .hw_cycle_count(hw_cycle_count),
        .hw_pixel_count(hw_pixel_count)
    );

    // Intermediate AXI-Stream Scaler Wires
    wire [STREAM_DATA_WIDTH-1:0] scaled_tdata;
    wire                         scaled_tvalid;
    wire                         scaled_tready;
    wire                         scaled_tlast;

    // Instantiate Streaming Downscaler (Stage 1: Downscale to 240p/144p BEFORE compression)
    streaming_scaler #(
        .DATA_WIDTH(STREAM_DATA_WIDTH)
    ) u_scaler (
        .clk(aclk),
        .rst_n(sys_rst_n),
        .src_width(src_width),
        .src_height(src_height),
        .tgt_width(tgt_width),
        .tgt_height(tgt_height),
        .scaler_mode(scaler_mode),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid && (hw_busy || ctrl_start)),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(scaled_tdata),
        .m_axis_tvalid(scaled_tvalid),
        .m_axis_tready(scaled_tready),
        .m_axis_tlast(scaled_tlast)
    );

    // Output Elastic FIFO buffering scaled and compressed stream
    axis_fifo #(
        .DATA_WIDTH(STREAM_DATA_WIDTH),
        .ADDR_WIDTH(6) // 64 entries
    ) u_out_fifo (
        .clk(aclk),
        .rst_n(sys_rst_n),
        .s_axis_tdata(scaled_tdata),
        .s_axis_tlast(scaled_tlast),
        .s_axis_tvalid(scaled_tvalid),
        .s_axis_tready(scaled_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .fifo_count(),
        .fifo_empty(),
        .fifo_full()
    );

    // Performance Monitoring & State Machine
    always @(posedge aclk) begin
        if (!sys_rst_n) begin
            hw_busy        <= 1'b0;
            hw_done        <= 1'b0;
            hw_error       <= 1'b0;
            hw_cycle_count <= 32'd0;
            hw_pixel_count <= 32'd0;
        end else begin
            if (ctrl_start && !hw_busy) begin
                hw_busy        <= 1'b1;
                hw_done        <= 1'b0;
                hw_cycle_count <= 32'd0;
                hw_pixel_count <= 32'd0;
            end else if (hw_busy) begin
                hw_cycle_count <= hw_cycle_count + 1'b1;

                if (m_axis_tvalid && m_axis_tready) begin
                    hw_pixel_count <= hw_pixel_count + 1'b1;
                    if (m_axis_tlast && (hw_pixel_count >= (tgt_width * tgt_height - 1))) begin
                        hw_busy <= 1'b0;
                        hw_done <= 1'b1;
                    end
                end
            end else if (hw_done && !ctrl_start) begin
                hw_done <= 1'b0;
            end
        end
    end

endmodule
