// ============================================================================
// File: axi_lite_slave.v
// Module: axi_lite_slave
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: AXI4-Lite Slave Register Interface mapped at base 0x43C00000.
//              Provides memory-mapped register access for ARM Cortex-A9 host.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module axi_lite_slave #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    // AXI4-Lite Bus Interface
    input  wire                          s_axi_aclk,
    input  wire                          s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]                    s_axi_awprot,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,
    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,
    output reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // Accelerator Control / Status Registers
    output wire                          reg_start,
    output wire                          reg_soft_rst,
    output wire                          reg_perf_enable,
    output reg  [31:0]                   reg_instruction,
    output reg  [31:0]                   reg_rs1_data,
    output reg  [5:0]                    reg_qp,
    output reg  [7:0]                    reg_t_thresh,
    output reg  [7:0]                    reg_r_in,
    output reg  [7:0]                    reg_g_in,
    output reg  [7:0]                    reg_b_in,
    output reg                           reg_pixel_valid,
    output reg  [7:0]                    reg_y_bg,

    // Status Inputs from Accelerator Core
    input  wire                          pe_busy,
    input  wire                          nal_valid,
    input  wire                          inpaint_active,
    input  wire                          foreground_mask,
    input  wire [7:0]                    y_inpainted,
    input  wire [31:0]                   nal_word,
    input  wire [31:0]                   total_cycles,
    input  wire [31:0]                   active_cycles,
    input  wire [31:0]                   stall_cycles,
    input  wire [31:0]                   pixel_count,
    input  wire [31:0]                   inpaint_events,
    input  wire [31:0]                   nal_word_count
);

    // Register Offsets (Byte addresses)
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CR_CONTROL     = 6'h00; // 0x00
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CR_INSTRUCTION = 6'h04; // 0x04
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CR_RS1_DATA    = 6'h08; // 0x08
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CR_CONFIG      = 6'h0C; // 0x0C
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CR_PIXEL_IN    = 6'h10; // 0x10
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CR_Y_BG        = 6'h14; // 0x14
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_STATUS      = 6'h18; // 0x18
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_Y_INPAINTED = 6'h1C; // 0x1C
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_NAL_WORD    = 6'h20; // 0x20
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_TOT_CYCLES  = 6'h24; // 0x24
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_ACT_CYCLES  = 6'h28; // 0x28
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_STL_CYCLES  = 6'h2C; // 0x2C
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_PIXEL_CNT   = 6'h30; // 0x30
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_INP_EVENTS  = 6'h34; // 0x34
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SR_NAL_CNT     = 6'h38; // 0x38

    reg [31:0] cr_control;
    assign reg_start       = cr_control[0];
    assign reg_soft_rst    = cr_control[1];
    assign reg_perf_enable = cr_control[2];

    // AXI Write State Machine
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            axi_awaddr      <= 6'd0;
            cr_control      <= 32'd0;
            reg_instruction <= 32'd0;
            reg_rs1_data    <= 32'd0;
            reg_qp          <= 6'd10;
            reg_t_thresh    <= 8'd30;
            reg_r_in        <= 8'd0;
            reg_g_in        <= 8'd0;
            reg_b_in        <= 8'd0;
            reg_pixel_valid <= 1'b0;
            reg_y_bg        <= 8'd76;
        end else begin
            // Single-cycle self-clearing pixel_valid pulse
            reg_pixel_valid <= 1'b0;

            // Write Address Handshake
            if (!s_axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                axi_awaddr    <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            // Write Response and Register Latch
            if (s_axi_wready && s_axi_wvalid && s_axi_awready && s_axi_awvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
                case (s_axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2] << 2)
                    ADDR_CR_CONTROL:     cr_control      <= s_axi_wdata;
                    ADDR_CR_INSTRUCTION: reg_instruction <= s_axi_wdata;
                    ADDR_CR_RS1_DATA:    reg_rs1_data    <= s_axi_wdata;
                    ADDR_CR_CONFIG: begin
                        reg_qp       <= s_axi_wdata[5:0];
                        reg_t_thresh <= s_axi_wdata[15:8];
                    end
                    ADDR_CR_PIXEL_IN: begin
                        reg_r_in        <= s_axi_wdata[7:0];
                        reg_g_in        <= s_axi_wdata[15:8];
                        reg_b_in        <= s_axi_wdata[23:16];
                        reg_pixel_valid <= s_axi_wdata[31];
                    end
                    ADDR_CR_Y_BG:        reg_y_bg        <= s_axi_wdata[7:0];
                    default: ;
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI Read State Machine
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (!s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00; // OKAY
                case (s_axi_araddr[C_S_AXI_ADDR_WIDTH-1:2] << 2)
                    ADDR_CR_CONTROL:     s_axi_rdata <= cr_control;
                    ADDR_CR_INSTRUCTION: s_axi_rdata <= reg_instruction;
                    ADDR_CR_RS1_DATA:    s_axi_rdata <= reg_rs1_data;
                    ADDR_CR_CONFIG:      s_axi_rdata <= {16'd0, reg_t_thresh, 2'b00, reg_qp};
                    ADDR_CR_PIXEL_IN:    s_axi_rdata <= {reg_pixel_valid, 7'd0, reg_b_in, reg_g_in, reg_r_in};
                    ADDR_CR_Y_BG:        s_axi_rdata <= {24'd0, reg_y_bg};
                    ADDR_SR_STATUS:      s_axi_rdata <= {28'd0, foreground_mask, inpaint_active, nal_valid, pe_busy};
                    ADDR_SR_Y_INPAINTED: s_axi_rdata <= {24'd0, y_inpainted};
                    ADDR_SR_NAL_WORD:    s_axi_rdata <= nal_word;
                    ADDR_SR_TOT_CYCLES:  s_axi_rdata <= total_cycles;
                    ADDR_SR_ACT_CYCLES:  s_axi_rdata <= active_cycles;
                    ADDR_SR_STL_CYCLES:  s_axi_rdata <= stall_cycles;
                    ADDR_SR_PIXEL_CNT:   s_axi_rdata <= pixel_count;
                    ADDR_SR_INP_EVENTS:  s_axi_rdata <= inpaint_events;
                    ADDR_SR_NAL_CNT:     s_axi_rdata <= nal_word_count;
                    default:             s_axi_rdata <= 32'hDEADBEEF;
                endcase
            end else begin
                s_axi_arready <= 1'b0;
                if (s_axi_rvalid && s_axi_rready)
                    s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
