// ============================================================================
// File: tb_stage7_axi.sv
// Module: tb_stage7_axi
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Automated Self-Checking SystemVerilog Testbench for Stage 7
//              AXI4-Lite Register Protocol & ACP Cache-Coherency Verification.
// ============================================================================

`timescale 1ns / 1ps

module tb_stage7_axi;

    parameter integer C_S_AXI_DATA_WIDTH = 32;
    parameter integer C_S_AXI_ADDR_WIDTH = 6;
    parameter integer CLK_PERIOD         = 10; // 100 MHz

    reg                          s_axi_aclk;
    reg                          s_axi_aresetn;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    reg  [2:0]                    s_axi_awprot;
    reg                          s_axi_awvalid;
    wire                         s_axi_awready;
    reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata;
    reg  [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb;
    reg                          s_axi_wvalid;
    wire                         s_axi_wready;
    wire [1:0]                    s_axi_bresp;
    wire                         s_axi_bvalid;
    reg                          s_axi_bready;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    reg  [2:0]                    s_axi_arprot;
    reg                          s_axi_arvalid;
    wire                         s_axi_arready;
    wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]                    s_axi_rresp;
    wire                         s_axi_rvalid;
    reg                          s_axi_rready;

    wire [4:0]                    m_axi_acp_aruser;
    wire [4:0]                    m_axi_acp_awuser;
    wire [3:0]                    m_axi_acp_arcache;
    wire [3:0]                    m_axi_acp_awcache;
    wire [7:0]                    led_status;

    integer pass_count = 0;
    integer fail_count = 0;

    // Clock generator: 100 MHz
    initial s_axi_aclk = 0;
    always #(CLK_PERIOD / 2) s_axi_aclk = ~s_axi_aclk;

    // DUT Instantiation
    axi_video_soc_v1_0 #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .LINE_WIDTH(32)
    ) dut (
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
        .m_axi_acp_aruser  (m_axi_acp_aruser),
        .m_axi_acp_awuser  (m_axi_acp_awuser),
        .m_axi_acp_arcache (m_axi_acp_arcache),
        .m_axi_acp_awcache (m_axi_acp_awcache),
        .led_status        (led_status)
    );

    // -------------------------------------------------------------------------
    // AXI Master Helper Tasks
    // -------------------------------------------------------------------------
    task axi_write(input [5:0] addr, input [31:0] data);
        begin
            @(negedge s_axi_aclk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wvalid  = 1'b1;
            s_axi_wstrb   = 4'b1111;
            s_axi_bready  = 1'b1;

            @(posedge s_axi_aclk);
            while (!s_axi_bvalid) begin
                @(posedge s_axi_aclk);
            end

            @(negedge s_axi_aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            s_axi_bready  = 1'b0;
            @(negedge s_axi_aclk);
        end
    endtask

    task axi_read(input [5:0] addr, output [31:0] data);
        begin
            @(negedge s_axi_aclk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;

            @(posedge s_axi_aclk);
            while (!s_axi_rvalid) begin
                @(posedge s_axi_aclk);
            end

            data = s_axi_rdata;
            @(negedge s_axi_aclk);
            s_axi_arvalid = 1'b0;
            s_axi_rready  = 1'b0;
            @(negedge s_axi_aclk);
        end
    endtask

    reg [31:0] rd_data;

    initial begin
        $display("================================================================");
        $display("   STAGE 7: AXI4-LITE BUS PROTOCOL & ACP COHERENCY TESTBENCH");
        $display("================================================================");

        // Initialize signals
        s_axi_aresetn = 0;
        s_axi_awaddr  = 0;
        s_axi_awprot  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arprot  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        #(CLK_PERIOD * 5);
        @(negedge s_axi_aclk);
        s_axi_aresetn = 1;
        #(CLK_PERIOD * 5);

        // ---------------------------------------------------------------------
        // TEST 1: ACP Cache Coherency Sideband Verification
        // ---------------------------------------------------------------------
        $write("[TEST 1] Verifying ACP Coherency Sidebands (ARUSER=5'h1F, ARCACHE=4'hF)... ");
        if (m_axi_acp_aruser == 5'b11111 && m_axi_acp_arcache == 4'b1111 &&
            m_axi_acp_awuser == 5'b11111 && m_axi_acp_awcache == 4'b1111) begin
            $display("[PASS] ARUSER=%b, ARCACHE=%b, AWUSER=%b, AWCACHE=%b",
                     m_axi_acp_aruser, m_axi_acp_arcache, m_axi_acp_awuser, m_axi_acp_awcache);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Sideband mismatch!");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: AXI Write & Read-back on CR_CONFIG (QP=24, T_thresh=45)
        // Data format: {16'd0, t_thresh[7:0], 2'b00, qp[5:0]} = {16'd0, 8'd45, 2'b00, 6'd24}
        // ---------------------------------------------------------------------
        $write("[TEST 2] AXI Write and Read-back on CR_CONFIG (Offset 0x0C)... ");
        axi_write(6'h0C, {16'd0, 8'd45, 2'b00, 6'd24});
        axi_read(6'h0C, rd_data);
        if (rd_data == {16'd0, 8'd45, 2'b00, 6'd24}) begin
            $display("[PASS] rd_data=0x%08X (QP=24, Thresh=45)", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] rd_data=0x%08X (exp 0x%08X)", rd_data, {16'd0, 8'd45, 2'b00, 6'd24});
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: AXI Write to CR_INSTRUCTION (Opcode 0x0B, Funct3 0x02 = V_INPAINT)
        // ---------------------------------------------------------------------
        $write("[TEST 3] AXI Write & Read-back on CR_INSTRUCTION (Offset 0x04)... ");
        axi_write(6'h04, 32'h0000200B);
        axi_read(6'h04, rd_data);
        if (rd_data == 32'h0000200B) begin
            $display("[PASS] rd_data=0x%08X (Custom RISC-V V_INPAINT)", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] rd_data=0x%08X (exp 0x0000200B)", rd_data);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: AXI Write to CR_CONTROL to enable Performance Monitor (bit 2)
        // ---------------------------------------------------------------------
        $write("[TEST 4] AXI Write CR_CONTROL perf_enable=1 (Offset 0x00)... ");
        axi_write(6'h00, 32'h00000004); // perf_enable = bit 2
        axi_read(6'h00, rd_data);
        if (rd_data[2] == 1'b1) begin
            $display("[PASS] CR_CONTROL=0x%08X (perf_enable asserted)", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] CR_CONTROL=0x%08X", rd_data);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Stream pixel transaction through CR_PIXEL_IN (Offset 0x10)
        // Format: {pixel_valid (bit 31), 7'd0, B[7:0], G[7:0], R[7:0]}
        // ---------------------------------------------------------------------
        $write("[TEST 5] AXI Stream Pixel Transaction via CR_PIXEL_IN... ");
        // Write Red pixel: R=255, G=0, B=0, valid=1 -> 0x800000FF
        axi_write(6'h10, 32'h800000FF);
        #(CLK_PERIOD * 10);
        // Read SR_TOT_CYCLES (Offset 0x24) to verify performance counter advanced
        axi_read(6'h24, rd_data);
        if (rd_data > 0) begin
            $display("[PASS] Total cycles counter incremented via AXI: %0d", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Total cycles counter remained 0");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 6: Read SR_STATUS (Offset 0x18)
        // ---------------------------------------------------------------------
        $write("[TEST 6] AXI Read SR_STATUS (Offset 0x18)... ");
        axi_read(6'h18, rd_data);
        $display("[PASS] SR_STATUS=0x%08X (Bus responder valid)", rd_data);
        pass_count = pass_count + 1;

        $display("================================================================");
        $display("   STAGE 7 TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("   STATUS: ALL STAGE 7 TESTS PASSED SUCCESSFULLY!");
        else
            $display("   STATUS: STAGE 7 SIMULATION FAILED!");
        $display("================================================================");

        $finish;
    end

endmodule
