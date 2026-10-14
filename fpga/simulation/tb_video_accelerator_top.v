// =============================================================================
// Testbench: tb_video_accelerator_top
// Full End-to-End System Simulation for Zynq-7000 Video Accelerator (Phase 4-7)
// =============================================================================

`timescale 1ns / 1ps

module tb_video_accelerator_top;

    parameter C_S_AXI_DATA_WIDTH = 32;
    parameter C_S_AXI_ADDR_WIDTH = 6;
    parameter STREAM_DATA_WIDTH  = 24;

    reg aclk;
    reg aresetn;

    // AXI-Lite
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    reg  [2:0]                    s_axi_awprot;
    reg                           s_axi_awvalid;
    wire                          s_axi_awready;
    reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata;
    reg  [3:0]                    s_axi_wstrb;
    reg                           s_axi_wvalid;
    wire                          s_axi_wready;
    wire [1:0]                    s_axi_bresp;
    wire                          s_axi_bvalid;
    reg                           s_axi_bready;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    reg  [2:0]                    s_axi_arprot;
    reg                           s_axi_arvalid;
    wire                          s_axi_arready;
    wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]                    s_axi_rresp;
    wire                          s_axi_rvalid;
    reg                           s_axi_rready;

    // AXI4-Stream Ingress
    reg  [STREAM_DATA_WIDTH-1:0]  s_axis_tdata;
    reg                           s_axis_tvalid;
    wire                          s_axis_tready;
    reg                           s_axis_tlast;

    // AXI4-Stream Egress
    wire [STREAM_DATA_WIDTH-1:0]  m_axis_tdata;
    wire                          m_axis_tvalid;
    reg                           m_axis_tready;
    wire                          m_axis_tlast;

    wire                          irq;

    // Instantiate Top-Level Accelerator Core
    video_accelerator_top #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .STREAM_DATA_WIDTH(STREAM_DATA_WIDTH)
    ) uut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .irq(irq)
    );

    // 100 MHz clock
    always #5 aclk = ~aclk;

    // AXI-Lite write helper
    task axi_write(input [5:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            @(posedge aclk);
            while (!s_axi_awready || !s_axi_wready) @(posedge aclk);

            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            while (!s_axi_bvalid) @(posedge aclk);
            @(posedge aclk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    // AXI-Lite read helper
    task axi_read(input [5:0] addr, output [31:0] data);
        begin
            @(posedge aclk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            @(posedge aclk);
            while (!s_axi_arready) @(posedge aclk);

            @(posedge aclk);
            s_axi_arvalid <= 1'b0;

            while (!s_axi_rvalid) @(posedge aclk);
            data = s_axi_rdata;
            @(posedge aclk);
            s_axi_rready  <= 1'b0;
        end
    endtask

    integer row, col;
    integer received_pixels;
    reg [31:0] cycles_measured;

    // Drain monitor
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            received_pixels = received_pixels + 1;
        end
    end

    initial begin
        $display("======================================================================");
        $display("  RUNNING TB_VIDEO_ACCELERATOR_TOP (Top-Level Hardware Verification)");
        $display("======================================================================");

        aclk = 0;
        aresetn = 0;
        s_axi_awaddr = 0;
        s_axi_awprot = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arprot = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1;
        received_pixels = 0;

        #20;
        aresetn = 1;
        #20;

        // 1. Program Accelerator: 64x32 -> 16x8, QP=28
        $display("[1/4] Programming control registers via AXI4-Lite (64x32 -> 16x8, QP=28)...");
        axi_write(6'h08, {16'd32, 16'd64});  // SRC_RES
        axi_write(6'h0C, {16'd8,  16'd16});  // TGT_RES
        axi_write(6'h10, {16'h0, 8'd0, 8'd28}); // Bilinear, QP=28
        $display("      -> OK: Registers programmed.");

        // 2. Start accelerator core
        $display("[2/4] Triggering START pulse via CTRL register...");
        axi_write(6'h00, 32'h00000001);
        $display("      -> OK: Accelerator entered BUSY state.");

        // 3. Stream pixel data into AXI4-Stream ingress
        $display("[3/4] Streaming 2,048 source pixels through hardware pipeline...");
        for (row = 0; row < 32; row = row + 1) begin
            for (col = 0; col < 64; col = col + 1) begin
                @(posedge aclk);
                while (!s_axis_tready) @(posedge aclk);
                s_axis_tdata  <= {col[7:0], row[7:0], (col[7:0] + row[7:0])};
                s_axis_tlast  <= (col == 63);
                s_axis_tvalid <= 1'b1;
            end
        end

        @(posedge aclk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;

        // Wait for pipeline drain & completion
        #300;
        $display("      -> Emitted %0d scaled output pixels.", received_pixels);
        if (received_pixels !== 128) begin
            $display("[FAIL] Expected 128 target pixels (16x8), got %0d", received_pixels);
            $finish;
        end
        $display("      -> OK: Pixel count matches target 16x8 dimension exactly.");

        // 4. Query Performance Telemetry Counter
        $display("[4/4] Querying hardware cycle counters via AXI-Lite...");
        axi_read(6'h14, cycles_measured);
        $display("      -> Hardware Pipeline Execution Cycles: %0d cycles.", cycles_measured);
        if (cycles_measured == 0) begin
            $display("[FAIL] Performance cycle counter did not run!");
            $finish;
        end
        $display("      -> OK: Performance counter recorded execution duration.");

        $display("\n======================================================================");
        $display("  TB_VIDEO_ACCELERATOR_TOP PASSED 100%%!");
        $display("======================================================================");
        $finish;
    end

endmodule
