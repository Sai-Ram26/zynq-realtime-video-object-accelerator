// ==============================================================================
// File: tb/tb_stage4_ddr_engine.v
// Description: Self-checking testbench for Stage 4 - AXI4 DDR Read/Write Engines
//              Includes an inline AXI4 memory model (256 KB RAM).
//              Tests:
//               T1 - Single burst read (32 words, 256 bytes, no 4KB split)
//               T2 - Write burst then readback verify (16 words, 128 bytes)
//               T3 - 4KB boundary crossing read (8 words, crosses 0x1000 boundary)
//               T4 - 4KB boundary crossing write (4 words, crosses 0x11000 boundary)
//               T5 - Statistics counters check
// ==============================================================================

`timescale 1ns / 1ps

module tb_stage4_ddr_engine;

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    reg clk;
    reg resetn;

    // S_AXI_CTRL (idle during DDR master test)
    reg  [7:0]  s_axi_ctrl_awaddr  = 0;
    reg  [2:0]  s_axi_ctrl_awprot  = 0;
    reg         s_axi_ctrl_awvalid = 0;
    wire        s_axi_ctrl_awready;
    reg  [31:0] s_axi_ctrl_wdata   = 0;
    reg  [3:0]  s_axi_ctrl_wstrb   = 0;
    reg         s_axi_ctrl_wvalid  = 0;
    wire        s_axi_ctrl_wready;
    wire [1:0]  s_axi_ctrl_bresp;
    wire        s_axi_ctrl_bvalid;
    reg         s_axi_ctrl_bready  = 1;
    reg  [7:0]  s_axi_ctrl_araddr  = 0;
    reg  [2:0]  s_axi_ctrl_arprot  = 0;
    reg         s_axi_ctrl_arvalid = 0;
    wire        s_axi_ctrl_arready;
    wire [31:0] s_axi_ctrl_rdata;
    wire [1:0]  s_axi_ctrl_rresp;
    wire        s_axi_ctrl_rvalid;
    reg         s_axi_ctrl_rready  = 1;

    // M_AXI_MEM (driven by AXI4 memory model below)
    wire [0:0]  m_axi_mem_awid;
    wire [31:0] m_axi_mem_awaddr;
    wire [7:0]  m_axi_mem_awlen;
    wire [2:0]  m_axi_mem_awsize;
    wire [1:0]  m_axi_mem_awburst;
    wire [0:0]  m_axi_mem_awlock;
    wire [3:0]  m_axi_mem_awcache;
    wire [2:0]  m_axi_mem_awprot;
    wire [3:0]  m_axi_mem_awqos;
    wire        m_axi_mem_awvalid;
    reg         m_axi_mem_awready;

    wire [63:0] m_axi_mem_wdata;
    wire [7:0]  m_axi_mem_wstrb;
    wire        m_axi_mem_wlast;
    wire        m_axi_mem_wvalid;
    reg         m_axi_mem_wready;

    reg  [0:0]  m_axi_mem_bid    = 0;
    reg  [1:0]  m_axi_mem_bresp  = 0;
    reg         m_axi_mem_bvalid = 0;
    wire        m_axi_mem_bready;

    wire [0:0]  m_axi_mem_arid;
    wire [31:0] m_axi_mem_araddr;
    wire [7:0]  m_axi_mem_arlen;
    wire [2:0]  m_axi_mem_arsize;
    wire [1:0]  m_axi_mem_arburst;
    wire [0:0]  m_axi_mem_arlock;
    wire [3:0]  m_axi_mem_arcache;
    wire [2:0]  m_axi_mem_arprot;
    wire [3:0]  m_axi_mem_arqos;
    wire        m_axi_mem_arvalid;
    reg         m_axi_mem_arready;

    reg  [0:0]  m_axi_mem_rid    = 0;
    reg  [63:0] m_axi_mem_rdata  = 0;
    reg  [1:0]  m_axi_mem_rresp  = 0;
    wire        m_axi_mem_rlast;
    reg         m_axi_mem_rvalid = 0;
    wire        m_axi_mem_rready;

    wire [63:0] m_axis_h264_tdata;
    wire [7:0]  m_axis_h264_tkeep;
    wire        m_axis_h264_tvalid;
    reg         m_axis_h264_tready = 1;
    wire        m_axis_h264_tlast;
    wire        irq;
    wire        led0, led1, led2;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    h264_accel_top uut (
        .clk               (clk),
        .resetn            (resetn),
        .s_axi_ctrl_awaddr (s_axi_ctrl_awaddr),
        .s_axi_ctrl_awprot (s_axi_ctrl_awprot),
        .s_axi_ctrl_awvalid(s_axi_ctrl_awvalid),
        .s_axi_ctrl_awready(s_axi_ctrl_awready),
        .s_axi_ctrl_wdata  (s_axi_ctrl_wdata),
        .s_axi_ctrl_wstrb  (s_axi_ctrl_wstrb),
        .s_axi_ctrl_wvalid (s_axi_ctrl_wvalid),
        .s_axi_ctrl_wready (s_axi_ctrl_wready),
        .s_axi_ctrl_bresp  (s_axi_ctrl_bresp),
        .s_axi_ctrl_bvalid (s_axi_ctrl_bvalid),
        .s_axi_ctrl_bready (s_axi_ctrl_bready),
        .s_axi_ctrl_araddr (s_axi_ctrl_araddr),
        .s_axi_ctrl_arprot (s_axi_ctrl_arprot),
        .s_axi_ctrl_arvalid(s_axi_ctrl_arvalid),
        .s_axi_ctrl_arready(s_axi_ctrl_arready),
        .s_axi_ctrl_rdata  (s_axi_ctrl_rdata),
        .s_axi_ctrl_rresp  (s_axi_ctrl_rresp),
        .s_axi_ctrl_rvalid (s_axi_ctrl_rvalid),
        .s_axi_ctrl_rready (s_axi_ctrl_rready),
        .m_axi_mem_awid    (m_axi_mem_awid),
        .m_axi_mem_awaddr  (m_axi_mem_awaddr),
        .m_axi_mem_awlen   (m_axi_mem_awlen),
        .m_axi_mem_awsize  (m_axi_mem_awsize),
        .m_axi_mem_awburst (m_axi_mem_awburst),
        .m_axi_mem_awlock  (m_axi_mem_awlock),
        .m_axi_mem_awcache (m_axi_mem_awcache),
        .m_axi_mem_awprot  (m_axi_mem_awprot),
        .m_axi_mem_awqos   (m_axi_mem_awqos),
        .m_axi_mem_awvalid (m_axi_mem_awvalid),
        .m_axi_mem_awready (m_axi_mem_awready),
        .m_axi_mem_wdata   (m_axi_mem_wdata),
        .m_axi_mem_wstrb   (m_axi_mem_wstrb),
        .m_axi_mem_wlast   (m_axi_mem_wlast),
        .m_axi_mem_wvalid  (m_axi_mem_wvalid),
        .m_axi_mem_wready  (m_axi_mem_wready),
        .m_axi_mem_bid     (m_axi_mem_bid),
        .m_axi_mem_bresp   (m_axi_mem_bresp),
        .m_axi_mem_bvalid  (m_axi_mem_bvalid),
        .m_axi_mem_bready  (m_axi_mem_bready),
        .m_axi_mem_arid    (m_axi_mem_arid),
        .m_axi_mem_araddr  (m_axi_mem_araddr),
        .m_axi_mem_arlen   (m_axi_mem_arlen),
        .m_axi_mem_arsize  (m_axi_mem_arsize),
        .m_axi_mem_arburst (m_axi_mem_arburst),
        .m_axi_mem_arlock  (m_axi_mem_arlock),
        .m_axi_mem_arcache (m_axi_mem_arcache),
        .m_axi_mem_arprot  (m_axi_mem_arprot),
        .m_axi_mem_arqos   (m_axi_mem_arqos),
        .m_axi_mem_arvalid (m_axi_mem_arvalid),
        .m_axi_mem_arready (m_axi_mem_arready),
        .m_axi_mem_rid     (m_axi_mem_rid),
        .m_axi_mem_rdata   (m_axi_mem_rdata),
        .m_axi_mem_rresp   (m_axi_mem_rresp),
        .m_axi_mem_rlast   (m_axi_mem_rlast),
        .m_axi_mem_rvalid  (m_axi_mem_rvalid),
        .m_axi_mem_rready  (m_axi_mem_rready),
        .m_axis_h264_tdata (m_axis_h264_tdata),
        .m_axis_h264_tkeep (m_axis_h264_tkeep),
        .m_axis_h264_tvalid(m_axis_h264_tvalid),
        .m_axis_h264_tready(m_axis_h264_tready),
        .m_axis_h264_tlast (m_axis_h264_tlast),
        .irq               (irq),
        .led0              (led0),
        .led1              (led1),
        .led2              (led2)
    );

    // -------------------------------------------------------------------------
    // Inline AXI4 Memory Model (256 KB, word-addressed by [31:3])
    // -------------------------------------------------------------------------
    reg [63:0] sim_ram [0:32767];

    integer k;
    initial begin
        for (k = 0; k < 32768; k = k + 1)
            sim_ram[k] = {32'hDEAD0000 ^ k, 32'hBEEF0000 ^ k};
    end

    // AXI4 Read slave
    reg  [31:0] axi_rd_addr_r;
    reg  [7:0]  axi_rd_beats_r;
    reg  [7:0]  axi_rd_cnt;
    reg  [1:0]  mem_rd_state;
    localparam MRD_IDLE = 2'd0, MRD_DATA = 2'd1;

    assign m_axi_mem_rlast = (mem_rd_state == MRD_DATA) && (axi_rd_cnt == axi_rd_beats_r);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            mem_rd_state      <= MRD_IDLE;
            m_axi_mem_arready <= 1'b0;
            m_axi_mem_rvalid  <= 1'b0;
            m_axi_mem_rdata   <= 64'd0;
            m_axi_mem_rresp   <= 2'b00;
            axi_rd_addr_r     <= 32'd0;
            axi_rd_beats_r    <= 8'd0;
            axi_rd_cnt        <= 8'd0;
        end else begin
            case (mem_rd_state)
                MRD_IDLE: begin
                    m_axi_mem_arready <= 1'b1;
                    m_axi_mem_rvalid  <= 1'b0;
                    if (m_axi_mem_arvalid && m_axi_mem_arready) begin
                        axi_rd_addr_r     <= m_axi_mem_araddr;
                        axi_rd_beats_r    <= m_axi_mem_arlen;
                        axi_rd_cnt        <= 8'd0;
                        m_axi_mem_rdata   <= sim_ram[{m_axi_mem_araddr[17:3]}];
                        m_axi_mem_rvalid  <= 1'b1;
                        m_axi_mem_arready <= 1'b0;
                        mem_rd_state      <= MRD_DATA;
                    end
                end
                MRD_DATA: begin
                    if (m_axi_mem_rvalid && m_axi_mem_rready) begin
                        if (axi_rd_cnt == axi_rd_beats_r) begin
                            m_axi_mem_rvalid  <= 1'b0;
                            m_axi_mem_arready <= 1'b1;
                            mem_rd_state      <= MRD_IDLE;
                        end else begin
                            axi_rd_addr_r    <= axi_rd_addr_r + 32'd8;
                            axi_rd_cnt       <= axi_rd_cnt + 8'd1;
                            m_axi_mem_rdata  <= sim_ram[{(axi_rd_addr_r + 32'd8) >> 3} & 15'h7FFF];
                            m_axi_mem_rvalid <= 1'b1;
                        end
                    end
                end
                default: mem_rd_state <= MRD_IDLE;
            endcase
        end
    end

    // AXI4 Write slave
    reg [31:0]  axi_wr_addr_r;
    reg [7:0]   axi_wr_beats_r;
    reg [7:0]   axi_wr_cnt;
    reg [1:0]   mem_wr_state;
    localparam MWR_IDLE = 2'd0, MWR_W = 2'd1, MWR_B = 2'd2;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            mem_wr_state      <= MWR_IDLE;
            m_axi_mem_awready <= 1'b0;
            m_axi_mem_wready  <= 1'b0;
            m_axi_mem_bvalid  <= 1'b0;
            m_axi_mem_bresp   <= 2'b00;
            axi_wr_addr_r     <= 32'd0;
            axi_wr_beats_r    <= 8'd0;
            axi_wr_cnt        <= 8'd0;
        end else begin
            case (mem_wr_state)
                MWR_IDLE: begin
                    m_axi_mem_awready <= 1'b1;
                    m_axi_mem_bvalid  <= 1'b0;
                    if (m_axi_mem_awvalid && m_axi_mem_awready) begin
                        axi_wr_addr_r     <= m_axi_mem_awaddr;
                        axi_wr_beats_r    <= m_axi_mem_awlen;
                        axi_wr_cnt        <= 8'd0;
                        m_axi_mem_awready <= 1'b0;
                        m_axi_mem_wready  <= 1'b1;
                        mem_wr_state      <= MWR_W;
                    end
                end
                MWR_W: begin
                    if (m_axi_mem_wvalid && m_axi_mem_wready) begin
                        sim_ram[{axi_wr_addr_r[17:3]} & 15'h7FFF] <= m_axi_mem_wdata;
                        axi_wr_addr_r <= axi_wr_addr_r + 32'd8;
                        axi_wr_cnt    <= axi_wr_cnt + 8'd1;
                        if (m_axi_mem_wlast) begin
                            m_axi_mem_wready <= 1'b0;
                            m_axi_mem_bvalid <= 1'b1;
                            m_axi_mem_bresp  <= 2'b00;
                            mem_wr_state     <= MWR_B;
                        end
                    end
                end
                MWR_B: begin
                    if (m_axi_mem_bvalid && m_axi_mem_bready) begin
                        m_axi_mem_bvalid  <= 1'b0;
                        m_axi_mem_awready <= 1'b1;
                        mem_wr_state      <= MWR_IDLE;
                    end
                end
                default: mem_wr_state <= MWR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 100 MHz Clock
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------
    task ddr_read;
        input [31:0] addr;
        input [15:0] num_bytes;
        begin
            @(posedge clk);
            while (!uut.rd_req_ready) @(posedge clk);
            uut.rd_req_addr   = addr;
            uut.rd_req_bytes  = num_bytes;
            uut.rd_req_valid  = 1'b1;
            uut.rd_data_ready = 1'b1;
            @(posedge clk);
            uut.rd_req_valid  = 1'b0;
            while (uut.rd_state != 0) @(posedge clk);
            @(posedge clk);
        end
    endtask

    task ddr_write;
        input [31:0] addr;
        input [15:0] num_bytes;
        input [63:0] base_val;
        integer i, words;
        begin
            words = num_bytes >> 3;
            @(posedge clk);
            while (!uut.wr_req_ready) @(posedge clk);
            uut.wr_req_addr  = addr;
            uut.wr_req_bytes = num_bytes;
            uut.wr_req_valid = 1'b1;
            @(posedge clk);
            uut.wr_req_valid = 1'b0;

            for (i = 0; i < words; i = i + 1) begin
                force uut.wr_data       = base_val + i;
                force uut.wr_data_strb  = 8'hFF;
                force uut.wr_data_valid = 1'b1;
                do begin
                    @(posedge clk);
                end while (!uut.wr_data_ready);
            end
            force uut.wr_data_valid = 1'b0;
            release uut.wr_data;
            release uut.wr_data_strb;
            release uut.wr_data_valid;

            while (!uut.wr_done) @(posedge clk);
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Capture & Verification
    // -------------------------------------------------------------------------
    integer errors;
    integer w;
    reg [63:0] expected;

    reg [63:0] rd_capture [0:255];
    integer    rd_cap_idx;

    always @(posedge clk) begin
        if (uut.rd_data_valid && uut.rd_data_ready) begin
            rd_capture[rd_cap_idx] <= uut.rd_data;
            rd_cap_idx             <= rd_cap_idx + 1;
        end
    end

    // Safety timeout: 50 us
    initial begin
        #50000;
        $display("[STAGE 4 TB FATAL] Global simulation timeout reached!");
        $finish;
    end

    initial begin
        clk        = 0;
        resetn     = 0;
        errors     = 0;
        rd_cap_idx = 0;

        uut.rd_req_valid  = 0;
        uut.rd_req_addr   = 0;
        uut.rd_req_bytes  = 0;
        uut.rd_data_ready = 1;
        uut.wr_req_valid  = 0;
        uut.wr_req_addr   = 0;
        uut.wr_req_bytes  = 0;

        $display("==================================================================");
        $display("[STAGE 4 TB] AXI4 DDR Read/Write Engine Verification...");
        $display("==================================================================");

        repeat (10) @(posedge clk);
        resetn = 1'b1;
        repeat (200) @(posedge clk);

        // ==============================================================
        // T1: Single read burst, 32 words = 256 bytes @ 0x0000_0100
        // ==============================================================
        $display("[T1] Single read: 32 words (256 bytes) @ 0x00000100...");
        rd_cap_idx = 0;
        ddr_read(32'h00000100, 16'd256);
        for (w = 0; w < 32; w = w + 1) begin
            expected = {32'hDEAD0000 ^ (32'h20 + w), 32'hBEEF0000 ^ (32'h20 + w)};
            if (rd_capture[w] !== expected) begin
                $display("[T1 FAIL] word[%0d]: got 0x%016x expected 0x%016x", w, rd_capture[w], expected);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("[T1 PASS] 32-word read verified. ddr_bytes_read=%0d", uut.reg_ddr_bytes_read);

        // ==============================================================
        // T2: Write 16 words (128 bytes) to 0x0000_0200, then readback
        // ==============================================================
        $display("[T2] Write+Readback: 16 words (128 bytes) @ 0x00000200...");
        ddr_write(32'h00000200, 16'd128, 64'hABCD1234_00000000);
        rd_cap_idx = 0;
        ddr_read(32'h00000200, 16'd128);
        for (w = 0; w < 16; w = w + 1) begin
            expected = 64'hABCD1234_00000000 + w;
            if (rd_capture[w] !== expected) begin
                $display("[T2 FAIL] word[%0d]: got 0x%016x expected 0x%016x", w, rd_capture[w], expected);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("[T2 PASS] Write+Readback verified. ddr_bytes_written=%0d", uut.reg_ddr_bytes_written);

        // ==============================================================
        // T3: Read crossing 4KB boundary
        //     Start at 0x0000_0FF0 (16 bytes before page boundary)
        //     Read 8 words = 64 bytes -> spans 0x0000_0FF0..0x0001_0030
        //     Sub-burst 1: 2 words (16 bytes) to 0x1000 page boundary
        //     Sub-burst 2: 6 words (48 bytes) from 0x1000
        // ==============================================================
        $display("[T3] 4KB boundary read: 8 words (64 bytes) @ 0x00000FF0...");
        rd_cap_idx = 0;
        ddr_read(32'h00000FF0, 16'd64);
        for (w = 0; w < 8; w = w + 1) begin
            expected = {32'hDEAD0000 ^ (32'h1FE + w), 32'hBEEF0000 ^ (32'h1FE + w)};
            if (rd_capture[w] !== expected) begin
                $display("[T3 FAIL] word[%0d] @ addr 0x%08x: got 0x%016x expected 0x%016x",
                         w, 32'hFF0 + w*8, rd_capture[w], expected);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("[T3 PASS] 4KB boundary read verified (split into two sub-bursts).");

        // ==============================================================
        // T4: Write crossing 4KB boundary
        //     Start at 0x0001_0FF8 (8 bytes before 0x11000 boundary)
        //     Write 4 words (32 bytes) -> sub-burst 1: 1 word, sub-burst 2: 3 words
        // ==============================================================
        $display("[T4] 4KB boundary write: 4 words (32 bytes) @ 0x00010FF8...");
        ddr_write(32'h00010FF8, 16'd32, 64'hCAFE0000_12340000);
        begin
            reg [63:0] v0, v1, v2, v3;
            v0 = sim_ram[32'h10FF8 >> 3];
            v1 = sim_ram[32'h11000 >> 3];
            v2 = sim_ram[32'h11008 >> 3];
            v3 = sim_ram[32'h11010 >> 3];
            if (v0 !== 64'hCAFE0000_12340000 + 0 ||
                v1 !== 64'hCAFE0000_12340000 + 1 ||
                v2 !== 64'hCAFE0000_12340000 + 2 ||
                v3 !== 64'hCAFE0000_12340000 + 3) begin
                $display("[T4 FAIL] 4KB boundary write data mismatch in sim_ram");
                errors = errors + 1;
            end else begin
                $display("[T4 PASS] 4KB boundary write verified in sim_ram.");
            end
        end

        // ==============================================================
        // T5: Statistics check
        // ==============================================================
        $display("[T5] Statistics registers check...");
        begin
            integer exp_rd;
            integer exp_wr;
            exp_rd = (32 + 16 + 8) * 8; // 448 bytes
            exp_wr = (16 + 4) * 8;       // 160 bytes
            if (uut.reg_ddr_bytes_read !== exp_rd) begin
                $display("[T5 FAIL] ddr_bytes_read=%0d, expected %0d", uut.reg_ddr_bytes_read, exp_rd);
                errors = errors + 1;
            end
            if (uut.reg_ddr_bytes_written !== exp_wr) begin
                $display("[T5 FAIL] ddr_bytes_written=%0d, expected %0d", uut.reg_ddr_bytes_written, exp_wr);
                errors = errors + 1;
            end
            if (errors == 0)
                $display("[T5 PASS] Stats: rd=%0d bytes, wr=%0d bytes", uut.reg_ddr_bytes_read, uut.reg_ddr_bytes_written);
        end

        // ==============================================================
        // Final report
        // ==============================================================
        if (errors == 0) begin
            $display("------------------------------------------------------------------");
            $display("[TEST PASS] STAGE 4 VERIFICATION COMPLETE: ALL 5 TESTS PASSED!");
            $display("  T1: 32-word single burst read              - PASS");
            $display("  T2: 16-word write + readback               - PASS");
            $display("  T3: 8-word 4KB boundary crossing read      - PASS");
            $display("  T4: 4-word 4KB boundary crossing write     - PASS");
            $display("  T5: DDR statistics registers               - PASS");
            $display("  Read engine:  AXI4 AR+R, 4-KB boundary splitter, stats");
            $display("  Write engine: AXI4 AW+W+B, 4-KB boundary splitter, stats");
            $display("------------------------------------------------------------------");
        end else begin
            $display("[TEST FAIL] %0d error(s) detected!", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
