// =============================================================================
// Module: video_accelerator_top.v
// Project: FPGA-Based Real-Time H.264 Video Compression Accelerator
//          Target: Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
//
// Description:
//   Top-level AXI4-Stream video compression SoC for Zynq-7000 (ZedBoard).
//   The ARM Cortex-A9 PS controls via AXI4-Lite; raw grayscale pixels arrive
//   on the AXI4-Stream slave interface (from AXI DMA MM2S), and H.264
//   baseline bitstream words leave on the master interface (to AXI DMA S2MM).
//
//   Pipeline stages (all in PL / FPGA fabric):
//     1. block_assembler_4x4  – raster-scan pixels -> 4x4 luminance blocks
//     2. h264_encoder         – intra-prediction + DCT + quant + CAVLC
//        (internally uses: intra_pred_4x4, macroblock_skip,
//                          dct_4x4, quant, cavlc)
//     3. AXI-Lite register bank – ARM PS control & status interface
//
//   AXI4-Lite register map (word-aligned, 32-bit):
//     0x00  CTRL   [0]=Enable  [1]=SoftReset  [2]=CompressionEnable
//     0x04  WIDTH  [15:0]=Frame width  (pixels)
//     0x08  HEIGHT [15:0]=Frame height (pixels)
//     0x0C  QP     [5:0]=H.264 QP (0–51, default 28)
//     0x10  STATUS [0]=Busy  [1]=Done  [2]=IRQ pending  (read-only)
//     0x14  PERF0  Pixel counter   (read-only)
//     0x18  PERF1  Skip counter    (read-only)
//
//   Synthesis targets for xc7z020clg484-1:
//     - 0 DSP48 slices (multiplierless DCT & quantization)
//     - < 5 000 LUTs
//     - 100 MHz PL clock from PS FCLK0
// =============================================================================
`timescale 1ns / 1ps

module video_accelerator_top #(
    // AXI4-Lite parameters
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    // AXI4-Stream pixel width (8-bit grayscale packed in 32-bit word [7:0])
    parameter integer C_AXIS_DATA_WIDTH  = 32,
    // Line width used by block assembler (set to actual frame width at runtime
    // via register; this parameter sets the MAXIMUM supported width)
    parameter integer LINE_WIDTH         = 640
)(
    // =========================================================================
    // Global signals (active-low reset from PS)
    // =========================================================================
    input  wire                              aclk,
    input  wire                              aresetn,

    // =========================================================================
    // AXI4-Lite Slave – control interface from ARM Cortex-A9
    // =========================================================================
    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,
    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,
    // Write response channel
    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,
    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,
    // Read data channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready,

    // =========================================================================
    // AXI4-Stream Slave – raw pixel input (from AXI DMA MM2S)
    //   tdata[7:0] = 8-bit grayscale pixel (Y-channel)
    // =========================================================================
    input  wire [C_AXIS_DATA_WIDTH-1:0]     s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,
    input  wire [(C_AXIS_DATA_WIDTH/8)-1:0]  s_axis_tkeep,

    // =========================================================================
    // AXI4-Stream Master – compressed bitstream output (to AXI DMA S2MM)
    //   tdata[31:0] = packed H.264 CAVLC bitstream word
    // =========================================================================
    output wire [C_AXIS_DATA_WIDTH-1:0]     m_axis_tdata,
    output wire                              m_axis_tvalid,
    input  wire                              m_axis_tready,
    output wire                              m_axis_tlast,
    output wire [(C_AXIS_DATA_WIDTH/8)-1:0]  m_axis_tkeep,

    // Frame-complete interrupt to PS
    output reg                               irq,

    // ZedBoard Physical I/O (switches and LEDs for hardware testing)
    input  wire [7:0]                        sw,
    output wire [7:0]                        led
);

    // =========================================================================
    // AXI4-Lite Register Bank
    // =========================================================================
    // Internal register storage
    reg [31:0] reg_ctrl;    // 0x00
    reg [31:0] reg_width;   // 0x04
    reg [31:0] reg_height;  // 0x08
    reg [31:0] reg_qp;      // 0x0C
    reg [31:0] reg_status;  // 0x10  (read-only)
    reg [31:0] perf_pixel;  // 0x14  (read-only)
    reg [31:0] perf_skip;   // 0x18  (read-only)

    // Convenience signals decoded from CTRL register
    wire accel_en   = reg_ctrl[0];
    wire soft_rst   = reg_ctrl[1];
    wire comp_en    = reg_ctrl[2];

    // AXI-Lite handshake registers
    reg  axi_awready_r, axi_wready_r, axi_bvalid_r;
    reg  axi_arready_r, axi_rvalid_r;
    reg [31:0] axi_rdata_r;

    assign s_axi_awready = axi_awready_r;
    assign s_axi_wready  = axi_wready_r;
    assign s_axi_bresp   = 2'b00;   // OKAY
    assign s_axi_bvalid  = axi_bvalid_r;
    assign s_axi_arready = axi_arready_r;
    assign s_axi_rdata   = axi_rdata_r;
    assign s_axi_rresp   = 2'b00;   // OKAY
    assign s_axi_rvalid  = axi_rvalid_r;

    // ---------- Write path ----------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            axi_awready_r <= 1'b0;
            axi_wready_r  <= 1'b0;
            axi_bvalid_r  <= 1'b0;
            reg_ctrl      <= 32'h00000001; // accel enabled, compress enabled
            reg_width     <= 32'd320;
            reg_height    <= 32'd240;
            reg_qp        <= 32'd28;
        end else begin
            if (~axi_awready_r && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready_r <= 1'b1;
                axi_wready_r  <= 1'b1;
                axi_bvalid_r  <= 1'b1;
                // Decode write address (word-indexed on bits [5:2])
                case (s_axi_awaddr[5:2])
                    4'h0: reg_ctrl   <= s_axi_wdata;
                    4'h1: reg_width  <= s_axi_wdata;
                    4'h2: reg_height <= s_axi_wdata;
                    4'h3: reg_qp     <= s_axi_wdata;
                    default: ;
                endcase
            end else begin
                axi_awready_r <= 1'b0;
                axi_wready_r  <= 1'b0;
                if (s_axi_bready && axi_bvalid_r)
                    axi_bvalid_r <= 1'b0;
            end
        end
    end

    // ---------- Read path ----------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            axi_arready_r <= 1'b0;
            axi_rvalid_r  <= 1'b0;
            axi_rdata_r   <= 32'd0;
        end else begin
            if (~axi_arready_r && s_axi_arvalid) begin
                axi_arready_r <= 1'b1;
                axi_rvalid_r  <= 1'b1;
                case (s_axi_araddr[5:2])
                    4'h0: axi_rdata_r <= reg_ctrl;
                    4'h1: axi_rdata_r <= reg_width;
                    4'h2: axi_rdata_r <= reg_height;
                    4'h3: axi_rdata_r <= reg_qp;
                    4'h4: axi_rdata_r <= reg_status;
                    4'h5: axi_rdata_r <= perf_pixel;
                    4'h6: axi_rdata_r <= perf_skip;
                    default: axi_rdata_r <= 32'hDEAD_BEEF;
                endcase
            end else begin
                axi_arready_r <= 1'b0;
                if (s_axi_rready && axi_rvalid_r)
                    axi_rvalid_r <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Video Datapath
    // =========================================================================
    // Internal reset: either external aresetn de-asserted or soft-reset bit set
    wire internal_rst_n = aresetn && ~soft_rst;

    // AXI-Stream slave back-pressure: accept pixels when accelerator is enabled
    assign s_axis_tready = m_axis_tready && accel_en;

    wire pixel_accepted = s_axis_tvalid && s_axis_tready;
    wire [7:0] pixel_in = s_axis_tdata[7:0]; // grayscale Y byte

    // -------------------------------------------------------------------------
    // Stage 1: 4x4 Block Assembler
    //   Accumulates pixels from raster scan into 4x4 blocks.
    //   LINE_WIDTH parameter should match frame width set in reg_width.
    //   NOTE: Parameterise with max supported width; actual width passed as port.
    // -------------------------------------------------------------------------
    wire        blk_valid;
    wire [7:0]  b_x00, b_x01, b_x02, b_x03;
    wire [7:0]  b_x10, b_x11, b_x12, b_x13;
    wire [7:0]  b_x20, b_x21, b_x22, b_x23;
    wire [7:0]  b_x30, b_x31, b_x32, b_x33;

    block_assembler_4x4 #(
        .LINE_WIDTH(LINE_WIDTH)
    ) u_blk_assembler (
        .clk        (aclk),
        .rst_n      (internal_rst_n),
        .valid_in   (pixel_accepted),
        .pixel_in   (pixel_in),
        .mask_in    (1'b0),         // no masking – pass all pixels
        .frame_start(1'b0),
        .block_valid(blk_valid),
        .block_mask (),             // unused output
        .x00(b_x00), .x01(b_x01), .x02(b_x02), .x03(b_x03),
        .x10(b_x10), .x11(b_x11), .x12(b_x12), .x13(b_x13),
        .x20(b_x20), .x21(b_x21), .x22(b_x22), .x23(b_x23),
        .x30(b_x30), .x31(b_x31), .x32(b_x32), .x33(b_x33)
    );

    // -------------------------------------------------------------------------
    // Stage 2: H.264 Baseline Encoder Core
    //   Intra-prediction -> residuals -> 4x4 integer DCT ->
    //   quantization -> CAVLC entropy coding
    // -------------------------------------------------------------------------
    wire        h264_valid;
    wire [31:0] h264_bitstream;
    wire [5:0]  h264_bit_cnt;
    wire [4:0]  h264_total_coeff;
    wire [1:0]  h264_trailing_ones;

    // Hardware switch QP override: if SW[5:0] != 0, switches set QP directly!
    wire [5:0] active_qp = (sw[5:0] != 6'd0) ? sw[5:0] : reg_qp[5:0];

    h264_encoder u_h264 (
        .clk            (aclk),
        .rst_n          (internal_rst_n),
        .valid_in       (blk_valid && comp_en),
        .qp             (active_qp),
        .pred_mode      (2'b11),    // Bypass intra (DC subtraction only)
        .is_skip_block  (1'b0),     // No explicit skip in this mode
        // 4x4 pixel block
        .x00(b_x00), .x01(b_x01), .x02(b_x02), .x03(b_x03),
        .x10(b_x10), .x11(b_x11), .x12(b_x12), .x13(b_x13),
        .x20(b_x20), .x21(b_x21), .x22(b_x22), .x23(b_x23),
        .x30(b_x30), .x31(b_x31), .x32(b_x32), .x33(b_x33),
        // Neighbor prediction context (set to DC 128 when not available)
        .top0 (8'd128), .top1 (8'd128), .top2 (8'd128), .top3 (8'd128),
        .left0(8'd128), .left1(8'd128), .left2(8'd128), .left3(8'd128),
        // Compressed output
        .valid_out      (h264_valid),
        .bitstream_data (h264_bitstream),
        .bit_count      (h264_bit_cnt),
        .total_coeff    (h264_total_coeff),
        .trailing_ones  (h264_trailing_ones)
    );

    // =========================================================================
    // Output Multiplexer
    //   comp_en=1 -> H.264 bitstream words
    //   comp_en=0 -> raw pixels (passthrough, useful for debug)
    // =========================================================================
    // Pipeline tlast through the block assembler latency (3 cycles)
    reg [3:0] tlast_pipe;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            tlast_pipe <= 4'b0;
        else if (s_axis_tready)
            tlast_pipe <= {tlast_pipe[2:0], s_axis_tlast};
    end

    assign m_axis_tdata  = comp_en ? h264_bitstream : {24'h0, pixel_in};
    assign m_axis_tvalid = comp_en ? h264_valid     : pixel_accepted;
    assign m_axis_tlast  = tlast_pipe[3];
    assign m_axis_tkeep  = 4'b1111;

    // =========================================================================
    // Performance Counters & IRQ
    // =========================================================================
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_rst) begin
            perf_pixel  <= 32'd0;
            perf_skip   <= 32'd0;
            reg_status  <= 32'd0;
            irq         <= 1'b0;
        end else begin
            // Busy flag
            reg_status[0] <= pixel_accepted | h264_valid;

            // Count accepted pixels
            if (pixel_accepted)
                perf_pixel <= perf_pixel + 32'd1;

            // Frame-complete detection (tlast on output)
            if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                reg_status[1] <= 1'b1;  // Done
                reg_status[2] <= 1'b1;  // IRQ pending
                irq           <= 1'b1;
            end

            // Clear interrupt on STATUS register read
            if (s_axi_arvalid && (s_axi_araddr[5:2] == 4'h4)) begin
                reg_status[1] <= 1'b0;
                reg_status[2] <= 1'b0;
                irq           <= 1'b0;
            end
        end
    end

    // =========================================================================
    // ZedBoard Physical LED Status Diagnostics
    // =========================================================================
    // Heartbeat counter (toggles LED 7 at ~1.5 Hz @ 100MHz clock)
    reg [25:0] heartbeat_cnt;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) heartbeat_cnt <= 26'd0;
        else heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    assign led[0] = reg_status[0];                // LD0: Accelerator busy
    assign led[1] = h264_valid;                   // LD1: Block encoded
    assign led[2] = s_axis_tvalid & s_axis_tready;// LD2: Receiving pixel stream
    assign led[3] = m_axis_tvalid & m_axis_tready;// LD3: Transmitting H.264 stream
    assign led[4] = accel_en;                     // LD4: Core enabled
    assign led[5] = comp_en;                      // LD5: Compression enabled
    assign led[6] = irq;                          // LD6: Frame IRQ pending
    assign led[7] = heartbeat_cnt[25];            // LD7: Heartbeat (blinks at ~1.5Hz)

endmodule
