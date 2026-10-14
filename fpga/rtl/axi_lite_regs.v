// =============================================================================
// Module: axi_lite_regs
// Description: Synthesizable AXI4-Lite Slave Register File for Video Accelerator
// Base Address: 0x43C00000 (ZedBoard AXI-GP0 Interconnect)
// Matches docs/hardware.md and docs/protocol.md
// =============================================================================

`timescale 1ns / 1ps

module axi_lite_regs #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    // Global Clock and Reset
    input  wire                                S_AXI_ACLK,
    input  wire                                S_AXI_ARESETN,

    // AXI4-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input  wire [2:0]                          S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output wire                                S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output wire                                S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output wire [1:0]                          S_AXI_BRESP,
    output wire                                S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,

    // AXI4-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_ARADDR,
    input  wire [2:0]                          S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,

    // AXI4-Lite Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_RDATA,
    output wire [1:0]                          S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY,

    // Hardware Accelerator Internal Signals
    output wire                                ctrl_start,
    output wire                                ctrl_soft_reset,
    output wire [15:0]                         src_width,
    output wire [15:0]                         src_height,
    output wire [15:0]                         tgt_width,
    output wire [15:0]                         tgt_height,
    output wire [7:0]                          param_qp,
    output wire [7:0]                          scaler_mode,
    input  wire                                hw_busy,
    input  wire                                hw_done,
    input  wire                                hw_error,
    input  wire [31:0]                         hw_cycle_count,
    input  wire [31:0]                         hw_pixel_count
);

    // Register Offsets
    localparam ADDR_CTRL         = 6'h00; // [0]=start, [1]=soft_reset
    localparam ADDR_STATUS       = 6'h04; // [0]=busy, [1]=done, [2]=error
    localparam ADDR_SRC_RES      = 6'h08; // [31:16]=H, [15:0]=W
    localparam ADDR_TGT_RES      = 6'h0C; // [31:16]=H, [15:0]=W
    localparam ADDR_CONFIG       = 6'h10; // [7:0]=QP, [15:8]=scaler_mode
    localparam ADDR_PERF_CYCLES  = 6'h14; // Hardware execution cycles (RO)
    localparam ADDR_PIXEL_COUNT  = 6'h18; // Processed pixel count (RO)

    // Internal Registers
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg_ctrl;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg_src_res;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg_tgt_res;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg_config;

    // AXI Bus Handshaking Signals
    reg  axi_awready;
    reg  axi_wready;
    reg  axi_bvalid;
    reg  axi_arready;
    reg  [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg  axi_rvalid;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00; // OKAY
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00; // OKAY
    assign S_AXI_RVALID  = axi_rvalid;

    // Output assignments
    assign ctrl_start       = slv_reg_ctrl[0];
    assign ctrl_soft_reset  = slv_reg_ctrl[1];
    assign src_width        = slv_reg_src_res[15:0];
    assign src_height       = slv_reg_src_res[31:16];
    assign tgt_width        = slv_reg_tgt_res[15:0];
    assign tgt_height       = slv_reg_tgt_res[31:16];
    assign param_qp         = slv_reg_config[7:0];
    assign scaler_mode      = slv_reg_config[15:8];

    // Write Address & Data Handling
    wire write_en = S_AXI_AWVALID && S_AXI_WVALID && (!axi_awready);

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready      <= 1'b0;
            axi_wready       <= 1'b0;
            axi_bvalid       <= 1'b0;
            slv_reg_ctrl     <= 32'h0;
            slv_reg_src_res  <= {16'd1080, 16'd1920}; // Default 1080p
            slv_reg_tgt_res  <= {16'd240, 16'd426};    // Default 240p
            slv_reg_config   <= {16'h00, 8'd0, 8'd28}; // Bilinear, QP 28
        end else begin
            // Address / Data ready handshake
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
            end else begin
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end

            // Write response
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end

            // Register write execution
            if (write_en) begin
                case (S_AXI_AWADDR[5:0])
                    ADDR_CTRL: begin
                        slv_reg_ctrl <= S_AXI_WDATA;
                    end
                    ADDR_SRC_RES: begin
                        slv_reg_src_res <= S_AXI_WDATA;
                    end
                    ADDR_TGT_RES: begin
                        slv_reg_tgt_res <= S_AXI_WDATA;
                    end
                    ADDR_CONFIG: begin
                        slv_reg_config <= S_AXI_WDATA;
                    end
                    default: ;
                endcase
            end else if (hw_done) begin
                // Auto-clear start pulse upon completion
                slv_reg_ctrl[0] <= 1'b0;
            end
        end
    end

    // Read Address & Read Data Handling
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'h0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_rvalid  <= 1'b1;
                case (S_AXI_ARADDR[5:0])
                    ADDR_CTRL:        axi_rdata <= slv_reg_ctrl;
                    ADDR_STATUS:      axi_rdata <= {29'h0, hw_error, hw_done, hw_busy};
                    ADDR_SRC_RES:     axi_rdata <= slv_reg_src_res;
                    ADDR_TGT_RES:     axi_rdata <= slv_reg_tgt_res;
                    ADDR_CONFIG:      axi_rdata <= slv_reg_config;
                    ADDR_PERF_CYCLES: axi_rdata <= hw_cycle_count;
                    ADDR_PIXEL_COUNT: axi_rdata <= hw_pixel_count;
                    default:          axi_rdata <= 32'hDEADBEEF;
                endcase
            end else begin
                axi_arready <= 1'b0;
                if (S_AXI_RREADY && axi_rvalid) begin
                    axi_rvalid <= 1'b0;
                end
            end
        end
    end

endmodule
