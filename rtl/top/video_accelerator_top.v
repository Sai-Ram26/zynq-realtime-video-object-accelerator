// =============================================================================
// Module: video_accelerator_top.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Complete Hardware-Accelerated Video Processing System-on-Chip Top-Level.
//   Integrates:
//     - Dual Control-Plane:
//         1. AXI4-Lite Slave Interface for ARM Cortex-A9 (Zynq PS)
//         2. Native Coprocessor Interface for PicoRV32 RISC-V (1-cycle access)
//     - Zero-DDR Line-Buffer Inpainting Data-Plane:
//         1. Pipelined Frame-Differencing Background Subtraction
//         2. 8x8 Spatial Windowing & Line-Buffer Inpainting (inpainting_8x8_linebuffer)
//         3. Multiplierless Stochastic Computing S-SAD unit (stochastic_sad.v)
//     - H.264 Video Compression Core:
//         1. 4x4 Raster-to-Block Stream Assembler (block_assembler_4x4.v)
//         2. Sparsity-Aware Macroblock Skipping Protocol (macroblock_skip.v)
//         3. 4x4 Intra-Prediction Engine (intra_pred_4x4.v)
//         4. Multiplierless 2D 4x4 Integer DCT (dct_4x4.v, 0 DSPs)
//         5. 16-Channel Forward Quantization Array (quant.v)
//         6. CAVLC Entropy Coding & NAL Serializer (cavlc.v)
//     - High-Performance AXI4-Stream Video Master / Slave with Flow Control
//     - Real-Time Hardware Performance Profiling Counters
// =============================================================================

`timescale 1ns / 1ps

module video_accelerator_top #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_AXIS_DATA_WIDTH  = 32,
    parameter integer LINE_WIDTH         = 64  // Configurable: 64 for TB, 480/1280 for HD
)(
    // Global Clock & Active-Low Reset
    input  wire                              aclk,
    input  wire                              aresetn,

    // -------------------------------------------------------------------------
    // 1. AXI4-Lite Slave Interface (Control & Status from ARM PS)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // 2. Native Coprocessor Interface (PicoRV32 RISC-V 1-Cycle Direct Access)
    // -------------------------------------------------------------------------
    input  wire                              riscv_mem_valid,
    output wire                              riscv_mem_ready,
    input  wire [31:0]                       riscv_mem_addr,
    input  wire [31:0]                       riscv_mem_wdata,
    input  wire [3:0]                        riscv_mem_wstrb,
    output wire [31:0]                       riscv_mem_rdata,

    // -------------------------------------------------------------------------
    // 3. AXI4-Stream Video Slave Interface (From AXI DMA MM2S)
    //    [15:8] = Current Frame Pixel, [7:0] = Background Model Pixel
    // -------------------------------------------------------------------------
    input  wire [C_AXIS_DATA_WIDTH-1:0]      s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,
    input  wire [(C_AXIS_DATA_WIDTH/8)-1:0]  s_axis_tkeep,

    // -------------------------------------------------------------------------
    // 4. AXI4-Stream Video Master Interface (To AXI DMA S2MM)
    // -------------------------------------------------------------------------
    output wire [C_AXIS_DATA_WIDTH-1:0]      m_axis_tdata,
    output wire                              m_axis_tvalid,
    input  wire                              m_axis_tready,
    output wire                              m_axis_tlast,
    output wire [(C_AXIS_DATA_WIDTH/8)-1:0]  m_axis_tkeep,

    // Frame Complete Interrupt
    output reg                               irq
);

    // -------------------------------------------------------------------------
    // Control & Configuration Registers
    // -------------------------------------------------------------------------
    // 0x00: CTRL_REG: [0]=Enable, [1]=SoftReset, [2]=CompressionEn, [3]=SpatialInpaintEn
    reg [31:0] reg_ctrl;
    // 0x04: THRESH_REG: [7:0]=Difference Threshold (default: 30)
    reg [31:0] reg_thresh;
    // 0x08: WIDTH_REG: [15:0]=Frame Width
    reg [31:0] reg_width;
    // 0x0C: HEIGHT_REG: [15:0]=Frame Height
    reg [31:0] reg_height;
    // 0x10: QP_REG: [5:0]=Quantization Parameter (default: 28)
    reg [31:0] reg_qp;
    // 0x14: SKIP_THRESH_REG: [7:0]=Skip Threshold (default: 2)
    reg [31:0] reg_skip_thresh;
    // 0x18: STATUS_REG: [0]=Busy, [1]=Done, [2]=IRQ
    reg [31:0] reg_status;

    // Hardware Instrumentation Performance Counters
    reg [31:0] perf_cycle_cnt;
    reg [31:0] perf_pixel_cnt;
    reg [31:0] perf_fg_cnt;
    reg [31:0] perf_skip_cnt;

    // -------------------------------------------------------------------------
    // AXI-Lite Channel Logic
    // -------------------------------------------------------------------------
    reg axi_awready_reg, axi_wready_reg, axi_bvalid_reg;
    reg axi_arready_reg, axi_rvalid_reg;
    reg [31:0] axi_rdata_reg;

    assign s_axi_awready = axi_awready_reg;
    assign s_axi_wready  = axi_wready_reg;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = axi_bvalid_reg;
    assign s_axi_arready = axi_arready_reg;
    assign s_axi_rdata   = axi_rdata_reg;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = axi_rvalid_reg;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            axi_awready_reg <= 1'b0;
            axi_wready_reg  <= 1'b0;
            axi_bvalid_reg  <= 1'b0;
            reg_ctrl        <= 32'h00000001; // Enable Accel, Clean Pixel Mode
            reg_thresh      <= 32'd30;
            reg_width       <= 32'd64;
            reg_height      <= 32'd64;
            reg_qp          <= 32'd28;
            reg_skip_thresh <= 32'd2;
        end else begin
            if (~axi_awready_reg && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready_reg <= 1'b1;
                axi_wready_reg  <= 1'b1;
                axi_bvalid_reg  <= 1'b1;
                case (s_axi_awaddr[5:2])
                    4'h0: reg_ctrl        <= s_axi_wdata;
                    4'h1: reg_thresh      <= s_axi_wdata;
                    4'h2: reg_width       <= s_axi_wdata;
                    4'h3: reg_height      <= s_axi_wdata;
                    4'h4: reg_qp          <= s_axi_wdata;
                    4'h5: reg_skip_thresh <= s_axi_wdata;
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
                    4'h4: axi_rdata_reg <= reg_qp;
                    4'h5: axi_rdata_reg <= reg_skip_thresh;
                    4'h6: axi_rdata_reg <= reg_status;
                    4'h7: axi_rdata_reg <= perf_cycle_cnt;
                    4'h8: axi_rdata_reg <= perf_pixel_cnt;
                    4'h9: axi_rdata_reg <= perf_fg_cnt;
                    4'hA: axi_rdata_reg <= perf_skip_cnt;
                    default: axi_rdata_reg <= 32'hDEADBEEF;
                endcase
            end else begin
                axi_arready_reg <= 1'b0;
                if (s_axi_rready && axi_rvalid_reg)
                    axi_rvalid_reg <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // PicoRV32 RISC-V Coprocessor Native Bridge
    // -------------------------------------------------------------------------
    wire [31:0] riscv_ctrl_out;
    wire [31:0] riscv_thresh_out;
    wire [31:0] riscv_qp_out;
    wire [31:0] riscv_skip_thresh_out;

    picorv32_accel_bridge u_riscv_bridge (
        .clk(aclk),
        .rst_n(aresetn && !reg_ctrl[1]),
        .mem_valid(riscv_mem_valid),
        .mem_ready(riscv_mem_ready),
        .mem_addr(riscv_mem_addr),
        .mem_wdata(riscv_mem_wdata),
        .mem_wstrb(riscv_mem_wstrb),
        .mem_rdata(riscv_mem_rdata),
        .reg_ctrl_out(riscv_ctrl_out),
        .reg_thresh_out(riscv_thresh_out),
        .reg_qp_out(riscv_qp_out),
        .reg_skip_thresh_out(riscv_skip_thresh_out),
        .reg_status_in(reg_status),
        .reg_perf_cycles_in(perf_cycle_cnt),
        .reg_perf_pixels_in(perf_pixel_cnt),
        .reg_perf_fg_in(perf_fg_cnt),
        .reg_perf_skip_in(perf_skip_cnt)
    );

    // Active Control Signals (AXI-Lite or RISC-V)
    wire [7:0] active_thresh      = riscv_mem_valid ? riscv_thresh_out[7:0]      : reg_thresh[7:0];
    wire [5:0] active_qp          = riscv_mem_valid ? riscv_qp_out[5:0]          : reg_qp[5:0];
    wire [7:0] active_skip_thresh = riscv_mem_valid ? riscv_skip_thresh_out[7:0] : reg_skip_thresh[7:0];
    wire       active_compression = riscv_mem_valid ? riscv_ctrl_out[2]          : reg_ctrl[2];
    wire       active_spatial     = riscv_mem_valid ? riscv_ctrl_out[3]          : reg_ctrl[3];

    // -------------------------------------------------------------------------
    // 5. Video Processing Pipeline Datapath
    // -------------------------------------------------------------------------
    assign s_axis_tready = m_axis_tready;

    wire [7:0] curr_pixel = s_axis_tdata[15:8];
    wire [7:0] bg_pixel   = s_axis_tdata[7:0];

    // Stage A & B: Hybrid Object Removal & Inpainting
    wire       inpaint_valid;
    wire       mask_bit;
    wire [7:0] clean_pixel;
    wire       s_mult_mon, s_add_mon, s_sad_mon;

    hybrid_inpainter #(
        .LINE_WIDTH(LINE_WIDTH),
        .DATA_WIDTH(8)
    ) u_hybrid_inpaint (
        .clk(aclk),
        .rst_n(aresetn && !reg_ctrl[1]),
        .valid_in(s_axis_tvalid && s_axis_tready && reg_ctrl[0]),
        .curr_pixel(curr_pixel),
        .bg_pixel(bg_pixel),
        .threshold(active_thresh),
        .mode_sel(active_spatial ? 2'b01 : 2'b00),
        .bg_valid(1'b1),
        .valid_out(inpaint_valid),
        .mask_out(mask_bit),
        .clean_pixel_out(clean_pixel),
        .s_mult(s_mult_mon),
        .s_add(s_add_mon),
        .s_sad_stream(s_sad_mon)
    );

    // Stage C: 4x4 Raster-to-Block Stream Converter
    wire       blk_valid;
    wire       blk_mask;
    wire [7:0] b_x00, b_x01, b_x02, b_x03;
    wire [7:0] b_x10, b_x11, b_x12, b_x13;
    wire [7:0] b_x20, b_x21, b_x22, b_x23;
    wire [7:0] b_x30, b_x31, b_x32, b_x33;

    block_assembler_4x4 #(
        .LINE_WIDTH(LINE_WIDTH)
    ) u_blk_assembler (
        .clk(aclk),
        .rst_n(aresetn && !reg_ctrl[1]),
        .valid_in(inpaint_valid),
        .pixel_in(clean_pixel),
        .mask_in(mask_bit),
        .frame_start(1'b0),
        .block_valid(blk_valid),
        .block_mask(blk_mask),
        .x00(b_x00), .x01(b_x01), .x02(b_x02), .x03(b_x03),
        .x10(b_x10), .x11(b_x11), .x12(b_x12), .x13(b_x13),
        .x20(b_x20), .x21(b_x21), .x22(b_x22), .x23(b_x23),
        .x30(b_x30), .x31(b_x31), .x32(b_x32), .x33(b_x33)
    );

    // Sparsity-Aware Block Skipping
    wire        skip_decision;
    wire [31:0] skip_token_word;

    macroblock_skip #(.BLOCK_SIZE(16)) u_mb_skip (
        .clk(aclk),
        .rst_n(aresetn && !reg_ctrl[1]),
        .valid_in(inpaint_valid),
        .mask_pixel_in(mask_bit),
        .skip_threshold(active_skip_thresh),
        .is_last_pixel(1'b0),
        .block_valid(),
        .skip_mode(skip_decision),
        .fg_pixel_count(),
        .skip_token(skip_token_word)
    );

    // Stage D: H.264 Encoder Core
    wire        h264_valid;
    wire [31:0] h264_bitstream;
    wire [5:0]  h264_bit_cnt;
    wire [4:0]  h264_total_coeff;
    wire [1:0]  h264_trailing_ones;

    h264_encoder u_h264 (
        .clk(aclk),
        .rst_n(aresetn && !reg_ctrl[1]),
        .valid_in(blk_valid),
        .qp(active_qp),
        .pred_mode(2'b11), // 11: Bypass, 10: DC
        .is_skip_block(skip_decision),
        .x00(b_x00), .x01(b_x01), .x02(b_x02), .x03(b_x03),
        .x10(b_x10), .x11(b_x11), .x12(b_x12), .x13(b_x13),
        .x20(b_x20), .x21(b_x21), .x22(b_x22), .x23(b_x23),
        .x30(b_x30), .x31(b_x31), .x32(b_x32), .x33(b_x33),
        .top0(8'd128), .top1(8'd128), .top2(8'd128), .top3(8'd128),
        .left0(8'd128), .left1(8'd128), .left2(8'd128), .left3(8'd128),
        .valid_out(h264_valid),
        .bitstream_data(h264_bitstream),
        .bit_count(h264_bit_cnt),
        .total_coeff(h264_total_coeff),
        .trailing_ones(h264_trailing_ones)
    );

    // -------------------------------------------------------------------------
    // 6. Output Multiplexing & Stream Generation
    // -------------------------------------------------------------------------
    // Delay tlast to align with inpaint pipeline latency (3 cycles)
    reg [2:0] tlast_pipe;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            tlast_pipe <= 3'b000;
        else if (m_axis_tready)
            tlast_pipe <= {tlast_pipe[1:0], s_axis_tlast};
    end

    // Mux outputs: H.264 compressed words vs Raw Clean Pixels
    assign m_axis_tdata  = active_compression ? h264_bitstream :
                                                {16'h0000, 7'b0, mask_bit, clean_pixel};
    assign m_axis_tvalid = active_compression ? h264_valid : inpaint_valid;
    assign m_axis_tlast  = tlast_pipe[2];
    assign m_axis_tkeep  = 4'b1111;

    // -------------------------------------------------------------------------
    // 7. Hardware Performance Counters & Interrupts
    // -------------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn || reg_ctrl[1]) begin
            perf_cycle_cnt <= 32'd0;
            perf_pixel_cnt <= 32'd0;
            perf_fg_cnt    <= 32'd0;
            perf_skip_cnt  <= 32'd0;
            reg_status     <= 32'd0;
            irq            <= 1'b0;
        end else begin
            // Track busy/idle
            reg_status[0] <= s_axis_tvalid || inpaint_valid;

            if (s_axis_tvalid && s_axis_tready) begin
                perf_cycle_cnt <= perf_cycle_cnt + 32'd1;
                perf_pixel_cnt <= perf_pixel_cnt + 32'd1;
            end

            if (inpaint_valid && mask_bit)
                perf_fg_cnt <= perf_fg_cnt + 32'd1;

            if (blk_valid && skip_decision)
                perf_skip_cnt <= perf_skip_cnt + 32'd1;

            // Frame end trigger
            if (m_axis_tvalid && m_axis_tlast) begin
                reg_status[1] <= 1'b1; // Done
                reg_status[2] <= 1'b1; // IRQ flag
                irq           <= 1'b1;
            end else if (irq && s_axi_arvalid && (s_axi_araddr[5:2] == 4'h6)) begin
                // Clear on status register read
                reg_status[1] <= 1'b0;
                reg_status[2] <= 1'b0;
                irq           <= 1'b0;
            end
        end
    end

endmodule
