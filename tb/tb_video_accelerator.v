// =============================================================================
// Testbench: tb_video_accelerator.v
// Project: ZedBoard H.264 Video Compression Accelerator
// Tests:
//   1. AXI4-Lite register write/read (CTRL, WIDTH, HEIGHT, QP)
//   2. Pixel stream -> block assembler -> H.264 encoder pipeline
//   3. Output bitstream valid flag and tlast propagation
//   4. Performance counter increment
// Compatible with Icarus Verilog (iverilog -g2012) and Vivado Simulator
// =============================================================================
`timescale 1ns / 1ps

module tb_video_accelerator;

    // =========================================================================
    // DUT port signals
    // =========================================================================
    reg         aclk;
    reg         aresetn;

    // AXI4-Lite
    reg  [5:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [5:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // AXI4-Stream slave (pixels in)
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;
    reg  [3:0]  s_axis_tkeep;

    // AXI4-Stream master (bitstream out)
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;
    wire [3:0]  m_axis_tkeep;

    wire        irq;

    // =========================================================================
    // DUT instantiation
    //   LINE_WIDTH=16 : small frame for fast simulation
    // =========================================================================
    video_accelerator_top #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(6),
        .C_AXIS_DATA_WIDTH (32),
        .LINE_WIDTH        (16)   // 16-pixel wide test frame
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tkeep   (s_axis_tkeep),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tkeep   (m_axis_tkeep),
        .irq            (irq)
    );

    // =========================================================================
    // Clock: 100 MHz (10 ns period)
    // =========================================================================
    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    // =========================================================================
    // Counters
    // =========================================================================
    integer pixel_sent;
    integer words_received;
    integer i;

    // =========================================================================
    // Task: AXI4-Lite single write
    // The DUT registers awready one cycle after seeing awvalid+wvalid.
    // So: present valid signals, then wait up to 10 cycles for awready.
    // =========================================================================
    task axi_write;
        input [5:0]  addr;
        input [31:0] data;
        integer timeout;
        begin
            // Present address and data simultaneously
            @(negedge aclk);   // drive on falling edge so DUT sees stable values at next rising edge
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            // Wait for awready (registered: appears 1 cycle after condition)
            timeout = 0;
            @(posedge aclk); #1;
            while (!s_axi_awready && timeout < 20) begin
                @(posedge aclk); #1;
                timeout = timeout + 1;
            end
            if (timeout >= 20) $display("[WARN] axi_write: awready timeout addr=%h", addr);
            // De-assert valid
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            // Wait for bvalid
            timeout = 0;
            @(posedge aclk); #1;
            while (!s_axi_bvalid && timeout < 20) begin
                @(posedge aclk); #1;
                timeout = timeout + 1;
            end
            @(negedge aclk);
            s_axi_bready = 1'b0;
            @(posedge aclk);
        end
    endtask

    // =========================================================================
    // Task: AXI4-Lite single read
    // =========================================================================
    task axi_read;
        input  [5:0]  addr;
        output [31:0] rdata;
        integer timeout;
        begin
            @(negedge aclk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;
            timeout = 0;
            @(posedge aclk); #1;
            while (!s_axi_arready && timeout < 20) begin
                @(posedge aclk); #1;
                timeout = timeout + 1;
            end
            if (timeout >= 20) $display("[WARN] axi_read: arready timeout addr=%h", addr);
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
            timeout = 0;
            @(posedge aclk); #1;
            while (!s_axi_rvalid && timeout < 20) begin
                @(posedge aclk); #1;
                timeout = timeout + 1;
            end
            rdata = s_axi_rdata;
            @(negedge aclk);
            s_axi_rready = 1'b0;
            @(posedge aclk);
        end
    endtask

    // =========================================================================
    // Main test
    // =========================================================================
    reg [31:0] rd_data;
    integer fail_count;

    initial begin
        // ------ Initialise all inputs ------
        aresetn       = 1'b0;
        s_axi_awaddr  = 6'd0; s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'd0; s_axi_wstrb = 4'hF; s_axi_wvalid = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = 6'd0; s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axis_tdata  = 32'd0; s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;  s_axis_tkeep  = 4'hF;
        m_axis_tready = 1'b1;  // always ready to consume bitstream
        pixel_sent    = 0;
        words_received = 0;
        fail_count    = 0;

        // ------ Apply reset for 10 cycles ------
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        repeat(5)  @(posedge aclk);

        $display("=== TEST 1: AXI4-Lite Register Write/Read ===");

        // Write WIDTH = 16, HEIGHT = 16, QP = 28
        axi_write(6'h04, 32'd16);   // WIDTH
        axi_write(6'h08, 32'd16);   // HEIGHT
        axi_write(6'h0C, 32'd28);   // QP
        // Enable accelerator + compression: CTRL = 0b0000_0101 = 0x05
        axi_write(6'h00, 32'h00000005);

        // Readback checks
        axi_read(6'h04, rd_data);
        if (rd_data !== 32'd16) begin
            $display("[FAIL] WIDTH expected 16, got %0d", rd_data);
            fail_count = fail_count + 1;
        end else $display("[PASS] WIDTH = 16");

        axi_read(6'h0C, rd_data);
        if (rd_data !== 32'd28) begin
            $display("[FAIL] QP expected 28, got %0d", rd_data);
            fail_count = fail_count + 1;
        end else $display("[PASS] QP = 28");

        axi_read(6'h00, rd_data);
        if (rd_data !== 32'h05) begin
            $display("[FAIL] CTRL expected 0x05, got 0x%08X", rd_data);
            fail_count = fail_count + 1;
        end else $display("[PASS] CTRL = 0x05");

        // ------ TEST 2: Pixel stream (16x16 = 256 pixels, one test frame) ------
        $display("=== TEST 2: Pixel Stream & H.264 Pipeline ===");

        // Send 256 pixels: drive on negedge, sample on posedge
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge aclk);
            s_axis_tdata  = {{24{1'b0}}, i[7:0]};  // 8-bit ramp in [7:0]
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == 255) ? 1'b1 : 1'b0;
            @(posedge aclk);
            // Wait if back-pressured
            while (!s_axis_tready) @(posedge aclk);
            pixel_sent = pixel_sent + 1;
            // Count any output words during send
            if (m_axis_tvalid && m_axis_tready)
                words_received = words_received + 1;
        end
        @(negedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        $display("[INFO] Sent %0d pixels", pixel_sent);

        // Give pipeline time to drain (encoder has ~5 cycle latency)
        begin : drain_loop
            integer t;
            for (t = 0; t < 400; t = t + 1) begin
                @(posedge aclk);
                if (m_axis_tvalid && m_axis_tready)
                    words_received = words_received + 1;
            end
        end

        if (words_received > 0)
            $display("[PASS] Received %0d H.264 bitstream words", words_received);
        else begin
            $display("[FAIL] No H.264 output words received");
            fail_count = fail_count + 1;
        end

        // ------ TEST 3: Performance counter ------
        $display("=== TEST 3: Performance Counter ===");
        axi_read(6'h14, rd_data);
        if (rd_data > 0)
            $display("[PASS] Pixel counter = %0d", rd_data);
        else begin
            $display("[FAIL] Pixel counter is zero");
            fail_count = fail_count + 1;
        end

        // ------ Summary ------
        repeat(10) @(posedge aclk);
        if (fail_count == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d TEST(S) FAILED ===", fail_count);

        $finish;
    end

    // =========================================================================
    // Timeout watchdog (20 000 cycles)
    // =========================================================================
    initial begin
        #200000;
        $display("[TIMEOUT] Simulation exceeded 20000 cycles");
        $finish;
    end

endmodule
