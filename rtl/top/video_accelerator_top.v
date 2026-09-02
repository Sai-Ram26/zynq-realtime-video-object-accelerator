`timescale 1ns / 1ps

// ============================================================================
// Module: video_accelerator_top
// Description: Top-level AXI4-Lite + AXI4-Stream Hardware Accelerator for
//              ZedBoard Zynq-7000 SoC.
// Interfaces:
//   - AXI4-Lite: Configuration & Control from ARM PS (Address: 0x43C00000)
//   - S_AXIS_VIDEO: AXI4-Stream Input from DMA MM2S (24-bit RGB or 16-bit packed)
//   - M_AXIS_VIDEO: AXI4-Stream Output to DMA S2MM
// ============================================================================

module video_accelerator_top #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_AXIS_DATA_WIDTH  = 32
)(
    // Global Clocks and Resets
    input  wire                              aclk,
    input  wire                              aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Control & Status from ARM PS)
    // ------------------------------------------------------------------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,
    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave Interface (Raw Pixels from DMA MM2S)
    // Format: [15:8] = Curr Pixel (Grayscale), [7:0] = BG Pixel (Grayscale)
    // ------------------------------------------------------------------------
    input  wire [C_AXIS_DATA_WIDTH-1:0]      s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,
    input  wire [(C_AXIS_DATA_WIDTH/8)-1:0]  s_axis_tkeep,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface (Processed Clean Pixels to DMA S2MM)
    // ------------------------------------------------------------------------
    output wire [C_AXIS_DATA_WIDTH-1:0]      m_axis_tdata,
    output wire                              m_axis_tvalid,
    input  wire                              m_axis_tready,
    output wire                              m_axis_tlast,
    output wire [(C_AXIS_DATA_WIDTH/8)-1:0]  m_axis_tkeep,

    // Interrupt signal to ARM PS
    output reg                               irq
);

    // ------------------------------------------------------------------------
    // 1. Control Registers (AXI4-Lite Register Map)
    // 0x00: CTRL_REG      [0] = Enable, [1] = Soft Reset
    // 0x04: THRESH_REG    [7:0] = Difference Threshold (default: 30)
    // 0x08: WIDTH_REG     [15:0] = Frame Width
    // 0x0C: HEIGHT_REG    [15:0] = Frame Height
    // 0x10: STATUS_REG    [0] = Busy, [1] = Done, [31:16] = Frame Count
    // ------------------------------------------------------------------------
    reg [31:0] reg_ctrl;
    reg [31:0] reg_thresh;
    reg [31:0] reg_width;
    reg [31:0] reg_height;
    reg [31:0] reg_status;

    reg axi_awready_reg;
    reg axi_wready_reg;
    reg axi_bvalid_reg;
    reg axi_arready_reg;
    reg [31:0] axi_rdata_reg;
    reg axi_rvalid_reg;

    assign s_axi_awready = axi_awready_reg;
    assign s_axi_wready  = axi_wready_reg;
    assign s_axi_bresp   = 2'b00; // OKAY
    assign s_axi_bvalid  = axi_bvalid_reg;
    assign s_axi_arready = axi_arready_reg;
    assign s_axi_rdata   = axi_rdata_reg;
    assign s_axi_rresp   = 2'b00; // OKAY
    assign s_axi_rvalid  = axi_rvalid_reg;

    // AXI-Lite Write Channels
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            axi_awready_reg <= 1'b0;
            axi_wready_reg  <= 1'b0;
            axi_bvalid_reg  <= 1'b0;
            reg_ctrl        <= 32'h00000001; // Enabled by default
            reg_thresh      <= 32'd30;        // Default threshold = 30
            reg_width       <= 32'd640;
            reg_height      <= 32'd480;
        end else begin
            if (~axi_awready_reg && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready_reg <= 1'b1;
                axi_wready_reg  <= 1'b1;
                axi_bvalid_reg  <= 1'b1;
                case (s_axi_awaddr[5:2])
                    4'h0: reg_ctrl   <= s_axi_wdata;
                    4'h1: reg_thresh <= s_axi_wdata;
                    4'h2: reg_width  <= s_axi_wdata;
                    4'h3: reg_height <= s_axi_wdata;
                    default: ;
                endcase
            end else begin
                axi_awready_reg <= 1'b0;
                axi_wready_reg  <= 1'b0;
                if (s_axi_bready && axi_bvalid_reg)
                    axi_bvalid_reg <= 1'b0;
            end
        end
    end

    // AXI-Lite Read Channels
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            axi_arready_reg <= 1'b0;
            axi_rdata_reg   <= 32'd0;
            axi_rvalid_reg  <= 1'b0;
        end else begin
            if (~axi_arready_reg && s_axi_arvalid) begin
                axi_arready_reg <= 1'b1;
                axi_rvalid_reg  <= 1'b1;
                case (s_axi_araddr[5:2])
                    4'h0: axi_rdata_reg <= reg_ctrl;
                    4'h1: axi_rdata_reg <= reg_thresh;
                    4'h2: axi_rdata_reg <= reg_width;
                    4'h3: axi_rdata_reg <= reg_height;
                    4'h4: axi_rdata_reg <= reg_status;
                    default: axi_rdata_reg <= 32'hDEADBEEF;
                endcase
            end else begin
                axi_arready_reg <= 1'b0;
                if (s_axi_rready && axi_rvalid_reg)
                    axi_rvalid_reg <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 2. Hardware Accelerator Data Processing Sub-Pipeline
    // ------------------------------------------------------------------------
    // Stream Handshake: We process 1 pixel per clock with backpressure handling
    assign s_axis_tready = m_axis_tready;

    wire [7:0] curr_pixel = s_axis_tdata[15:8];
    wire [7:0] bg_pixel   = s_axis_tdata[7:0];

    wire       inpaint_valid;
    wire       mask_bit;
    wire [7:0] cleaned_pixel;

    bg_subtract_inpaint u_inpaint (
        .clk(aclk),
        .rst_n(aresetn && !reg_ctrl[1]),
        .valid_in(s_axis_tvalid && s_axis_tready && reg_ctrl[0]),
        .curr_pixel_in(curr_pixel),
        .bg_pixel_in(bg_pixel),
        .threshold_in(reg_thresh[7:0]),
        .valid_out(inpaint_valid),
        .mask_out(mask_bit),
        .cleaned_pixel_out(cleaned_pixel)
    );

    // Delay tlast to align with inpaint pipeline latency (2 clock cycles)
    reg [1:0] tlast_pipe;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            tlast_pipe <= 2'b00;
        else if (m_axis_tready)
            tlast_pipe <= {tlast_pipe[0], s_axis_tlast};
    end

    // Output Stream Assignment
    // Packed Output: [31:16]=0, [15:8]=mask_bit, [7:0]=cleaned_pixel
    assign m_axis_tdata  = {16'h0000, 7'b0, mask_bit, cleaned_pixel};
    assign m_axis_tvalid = inpaint_valid;
    assign m_axis_tlast  = tlast_pipe[1];
    assign m_axis_tkeep  = 4'b1111;

    // Interrupt on tlast completion
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            irq <= 1'b0;
        else
            irq <= m_axis_tvalid && m_axis_tlast;
    end

endmodule
