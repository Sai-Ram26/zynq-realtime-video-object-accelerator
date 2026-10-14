// =============================================================================
// Testbench: tb_axi_lite_regs
// Verifies AXI4-Lite Register File for FPGA Video Accelerator (Phase 3)
// =============================================================================

`timescale 1ns / 1ps

module tb_axi_lite_regs;

    reg clk;
    reg rst_n;

    // AXI4-Lite signals
    reg  [5:0]  s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
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
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // Accelerator core signals
    wire        ctrl_start;
    wire        ctrl_soft_reset;
    wire [15:0] src_width;
    wire [15:0] src_height;
    wire [15:0] tgt_width;
    wire [15:0] tgt_height;
    wire [7:0]  param_qp;
    wire [7:0]  scaler_mode;
    reg         hw_busy;
    reg         hw_done;
    reg         hw_error;
    reg  [31:0] hw_cycle_count;
    reg  [31:0] hw_pixel_count;

    // Instantiate UUT
    axi_lite_regs #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(6)
    ) uut (
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rst_n),
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

    // 100 MHz clock generator (10 ns period)
    always #5 clk = ~clk;

    // AXI-Lite Write Task
    task axi_write(input [5:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            @(posedge clk);
            while (!s_axi_awready || !s_axi_wready) @(posedge clk);

            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    // AXI-Lite Read Task
    task axi_read(input [5:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);

            @(posedge clk);
            s_axi_arvalid <= 1'b0;

            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready  <= 1'b0;
        end
    endtask

    reg [31:0] read_val;

    initial begin
        $display("======================================================================");
        $display("  RUNNING TB_AXI_LITE_REGS (Phase 3 AXI-Lite Control Interface)");
        $display("======================================================================");

        // Initialization
        clk = 0;
        rst_n = 0;
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
        hw_busy = 0;
        hw_done = 0;
        hw_error = 0;
        hw_cycle_count = 32'd1050;
        hw_pixel_count = 32'd102400;

        // Apply Reset
        #20;
        rst_n = 1;
        #20;

        // 1. Verify default reset values
        $display("[1/5] Verifying default power-on register configurations...");
        axi_read(6'h08, read_val); // SRC_RES
        if (read_val !== {16'd1080, 16'd1920}) begin
            $display("[FAIL] Expected default 1080p in SRC_RES, got %h", read_val);
            $finish;
        end
        $display("      -> OK: Default SRC_RES is 1920x1080.");

        axi_read(6'h0C, read_val); // TGT_RES
        if (read_val !== {16'd240, 16'd426}) begin
            $display("[FAIL] Expected default 240p in TGT_RES, got %h", read_val);
            $finish;
        end
        $display("      -> OK: Default TGT_RES is 426x240.");

        // 2. Configure 4K -> 144p downscale settings
        $display("[2/5] Programming 4K (3840x2160) -> 144p (256x144), QP=32...");
        axi_write(6'h08, {16'd2160, 16'd3840});
        axi_write(6'h0C, {16'd144,  16'd256});
        axi_write(6'h10, {16'h0, 8'd1, 8'd32}); // Mode 1, QP 32

        if (src_width !== 16'd3840 || src_height !== 16'd2160) begin
            $display("[FAIL] SRC_RES output mismatch: %d x %d", src_width, src_height);
            $finish;
        end
        if (tgt_width !== 16'd256 || tgt_height !== 16'd144) begin
            $display("[FAIL] TGT_RES output mismatch: %d x %d", tgt_width, tgt_height);
            $finish;
        end
        if (param_qp !== 8'd32) begin
            $display("[FAIL] QP mismatch: %d", param_qp);
            $finish;
        end
        $display("      -> OK: Accelerator internal wires reflect programmed registers.");

        // 3. Issue START command
        $display("[3/5] Issuing START pulse (CTRL[0]=1)...");
        axi_write(6'h00, 32'h00000001);
        if (ctrl_start !== 1'b1) begin
            $display("[FAIL] ctrl_start did not assert!");
            $finish;
        end
        $display("      -> OK: ctrl_start asserted.");

        // 4. Simulate core running and completing
        hw_busy = 1;
        #40;
        hw_busy = 0;
        hw_done = 1;
        #10;
        hw_done = 0;

        // Verify start auto-cleared on done
        if (ctrl_start !== 1'b0) begin
            $display("[FAIL] ctrl_start did not auto-clear after done!");
            $finish;
        end
        $display("      -> OK: ctrl_start auto-cleared on completion.");

        // 5. Read performance telemetry registers
        $display("[4/5] Reading execution cycle counter and pixel count registers...");
        axi_read(6'h14, read_val); // PERF_CYCLES
        if (read_val !== 32'd1050) begin
            $display("[FAIL] PERF_CYCLES mismatch: got %d", read_val);
            $finish;
        end
        axi_read(6'h18, read_val); // PIXEL_COUNT
        if (read_val !== 32'd102400) begin
            $display("[FAIL] PIXEL_COUNT mismatch: got %d", read_val);
            $finish;
        end
        $display("      -> OK: Performance telemetry accurately read over AXI-Lite.");

        $display("\n======================================================================");
        $display("  TB_AXI_LITE_REGS PASSED 100%%!");
        $display("======================================================================");
        $finish;
    end

endmodule
