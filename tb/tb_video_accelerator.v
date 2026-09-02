`timescale 1ns / 1ps

// ============================================================================
// Testbench: tb_video_accelerator
// Description: Self-checking automated testbench comparing Verilog RTL against
//              Python Golden Reference hex vectors.
// ============================================================================

module tb_video_accelerator;

    parameter PIXELS = 4096; // 64x64 frame
    parameter CLK_PERIOD = 10; // 100 MHz clock

    reg         aclk;
    reg         aresetn;

    // AXI-Lite
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

    // AXI-Stream Slave (Inputs)
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;
    reg  [3:0]  s_axis_tkeep;

    // AXI-Stream Master (Outputs)
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;
    wire [3:0]  m_axis_tkeep;
    wire        irq;

    // Test Vector Memories
    reg [7:0] mem_curr_gray [0:PIXELS-1];
    reg [7:0] mem_bg_gray   [0:PIXELS-1];
    reg [7:0] mem_exp_mask  [0:PIXELS-1];
    reg [7:0] mem_exp_clean [0:PIXELS-1];

    // DUT Instantiation
    video_accelerator_top u_dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
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
        .s_axis_tkeep(s_axis_tkeep),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tkeep(m_axis_tkeep),
        .irq(irq)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) aclk = ~aclk;

    integer i, errors, match_count;

    initial begin
        // Initialize
        aclk          = 0;
        aresetn       = 0;
        s_axi_awvalid = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 1;
        s_axi_arvalid = 0;
        s_axi_rready  = 1;
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tlast  = 0;
        s_axis_tkeep  = 4'hF;
        m_axis_tready = 1;
        errors        = 0;
        match_count   = 0;

        $display("===============================================================");
        $display("[*] Starting Video Accelerator RTL Verification against Python Model");
        $display("===============================================================");

        // Load test vectors
        $readmemh("d:/mini_project2/tb/test_vectors/curr_gray_in.hex", mem_curr_gray);
        $readmemh("d:/mini_project2/tb/test_vectors/bg_gray_in.hex", mem_bg_gray);
        $readmemh("d:/mini_project2/tb/test_vectors/expected_mask.hex", mem_exp_mask);
        $readmemh("d:/mini_project2/tb/test_vectors/expected_cleaned.hex", mem_exp_clean);

        // Reset Sequence
        #(CLK_PERIOD * 5);
        aresetn = 1;
        #(CLK_PERIOD * 5);

        $display("[+] Reset De-asserted. Feeding AXI-Stream Pixels at 1 pixel/cycle...");

        // Stream in all pixels
        for (i = 0; i < PIXELS; i = i + 1) begin
            @(posedge aclk);
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= {16'h0000, mem_curr_gray[i], mem_bg_gray[i]};
            s_axis_tlast  <= (i == PIXELS - 1);
        end

        @(posedge aclk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;

        // Wait for pipeline drain
        #(CLK_PERIOD * 10);

        $display("===============================================================");
        $display("[+] VERIFICATION COMPLETE:");
        $display("    - Total Pixels Checked: %0d", match_count);
        $display("    - Errors Found:         %0d", errors);
        if (errors == 0 && match_count > 0) begin
            $display("[*] SUCCESS: 100%% BIT-EXACT MATCH WITH PYTHON GOLDEN MODEL!");
        end else begin
            $display("[!] FAILURE: Mismatches detected.");
        end
        $display("===============================================================");
        $finish;
    end

    // Output Checker Monitor
    integer out_idx = 0;
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            if (out_idx < PIXELS) begin
                if ((m_axis_tdata[7:0] !== mem_exp_clean[out_idx]) ||
                    (m_axis_tdata[8] !== mem_exp_mask[out_idx][0])) begin
                    $display("[ERROR] Pixel %0d: Expected Clean=%02X Mask=%01b | Got Clean=%02X Mask=%01b",
                             out_idx, mem_exp_clean[out_idx], mem_exp_mask[out_idx][0],
                             m_axis_tdata[7:0], m_axis_tdata[8]);
                    errors = errors + 1;
                end else begin
                    match_count = match_count + 1;
                end
                out_idx = out_idx + 1;
            end
        end
    end

endmodule
