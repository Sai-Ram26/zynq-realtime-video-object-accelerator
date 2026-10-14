// =============================================================================
// Testbench: tb_axis_fifo
// Verifies AXI4-Stream Elastic FIFO with backpressure handling (Phase 3)
// =============================================================================

`timescale 1ns / 1ps

module tb_axis_fifo;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 4; // 16 entries
    localparam DEPTH = 1 << ADDR_WIDTH;

    reg                   clk;
    reg                   rst_n;

    reg  [DATA_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tlast;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;

    wire [DATA_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tlast;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;

    wire [ADDR_WIDTH:0]   fifo_count;
    wire                  fifo_empty;
    wire                  fifo_full;

    axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .fifo_count(fifo_count),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full)
    );

    always #5 clk = ~clk;

    integer i;
    reg [DATA_WIDTH-1:0] test_words [0:DEPTH-1];

    initial begin
        $display("======================================================================");
        $display("  RUNNING TB_AXIS_FIFO (Phase 3 AXI4-Stream Backpressure Test)");
        $display("======================================================================");

        clk = 0;
        rst_n = 0;
        s_axis_tdata = 0;
        s_axis_tlast = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 0;

        #20;
        rst_n = 1;
        #10;

        if (!fifo_empty) begin
            $display("[FAIL] FIFO should be empty after reset!");
            $finish;
        end
        $display("[1/3] Reset state verified: fifo_empty = 1, count = 0.");

        // Fill FIFO to maximum capacity
        $display("[2/3] Writing %0d words to test capacity and backpressure...", DEPTH);
        for (i = 0; i < DEPTH; i = i + 1) begin
            test_words[i] = 32'hA0000000 + i;
            @(posedge clk);
            s_axis_tdata  <= test_words[i];
            s_axis_tlast  <= (i == DEPTH - 1);
            s_axis_tvalid <= 1'b1;
        end

        @(posedge clk);
        s_axis_tvalid <= 1'b0;

        #1;
        if (!fifo_full || s_axis_tready) begin
            $display("[FAIL] FIFO should be full and s_axis_tready should be 0!");
            $finish;
        end
        $display("      -> OK: FIFO full asserted, s_axis_tready deasserted (Backpressure Verified).");

        // Read all items back and verify
        $display("[3/3] Reading back all words and verifying data integrity...");
        m_axis_tready <= 1'b1;

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            while (!m_axis_tvalid) @(posedge clk);
            if (m_axis_tdata !== test_words[i]) begin
                $display("[FAIL] Data mismatch at index %0d: expected %h, got %h", i, test_words[i], m_axis_tdata);
                $finish;
            end
            if (i == DEPTH - 1 && !m_axis_tlast) begin
                $display("[FAIL] m_axis_tlast did not assert on final word!");
                $finish;
            end
        end

        @(posedge clk);
        m_axis_tready <= 1'b0;
        #10;

        if (!fifo_empty) begin
            $display("[FAIL] FIFO should be empty after draining!");
            $finish;
        end
        $display("      -> OK: All data drained accurately; empty flag asserted.");

        $display("\n======================================================================");
        $display("  TB_AXIS_FIFO PASSED 100%%!");
        $display("======================================================================");
        $finish;
    end

endmodule
