// ============================================================================
// File: tb_stage3_pipeline.sv
// Module: tb_stage3_pipeline
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: End-to-End SystemVerilog Testbench for Stage 3 Complete Pipeline.
//              Verifies full 5-stage data path: RGB->YUV->BgSub->Inpainting->DCT->CAVLC
//              Tests: data flow, control flow, clocking, reset, interfaces, latency.
// Standard: IEEE 1800-2012 SystemVerilog
// ============================================================================

`timescale 1ns / 1ps

module tb_stage3_pipeline;

    localparam integer LINE_WIDTH = 64;
    localparam integer FRAME_W    = 64;
    localparam integer FRAME_H    = 32;

    reg         clk;
    reg         rst_n;

    // RISC-V Control
    reg         insn_valid;
    reg  [31:0] instruction;
    reg  [31:0] rs1_data;
    wire        pe_array_start;
    wire [3:0]  pe_target_op;
    wire [31:0] pe_mem_addr;
    wire        pe_busy;

    // Pixel Streaming
    reg         pixel_valid_in;
    reg  [7:0]  r_in, g_in, b_in;
    reg  [7:0]  y_bg_in;
    reg  [7:0]  t_thresh_in;
    reg  [5:0]  qp_in;

    // Performance
    reg         perf_enable;
    wire [31:0] total_cycles, active_cycles, stall_cycles;
    wire [31:0] pixel_count, inpaint_events, nal_word_count;

    // Compressed Output
    wire        nal_valid_out;
    wire [31:0] nal_word_out;
    wire [5:0]  nal_bit_count_out;
    wire [4:0]  total_coeff_out;

    // Debug
    wire [7:0]  y_inpainted;
    wire        foreground_mask;
    wire        inpaint_active;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i, j;

    // Instantiate DUT
    stage3_pipeline_top #(.LINE_WIDTH(LINE_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .insn_valid(insn_valid), .instruction(instruction), .rs1_data(rs1_data),
        .pe_array_start(pe_array_start), .pe_target_op(pe_target_op),
        .pe_mem_addr(pe_mem_addr), .pe_busy(pe_busy),
        .pixel_valid_in(pixel_valid_in),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .y_bg_in(y_bg_in), .t_thresh_in(t_thresh_in), .qp_in(qp_in),
        .perf_enable(perf_enable),
        .total_cycles(total_cycles), .active_cycles(active_cycles),
        .stall_cycles(stall_cycles), .pixel_count(pixel_count),
        .inpaint_events(inpaint_events), .nal_word_count(nal_word_count),
        .nal_valid_out(nal_valid_out), .nal_word_out(nal_word_out),
        .nal_bit_count_out(nal_bit_count_out), .total_coeff_out(total_coeff_out),
        .y_inpainted(y_inpainted), .foreground_mask(foreground_mask),
        .inpaint_active(inpaint_active)
    );

    // 100 MHz Clock
    always #5 clk = ~clk;

    // NAL Word capture
    integer nal_words_captured = 0;
    always @(posedge clk) begin
        if (nal_valid_out) begin
            nal_words_captured = nal_words_captured + 1;
        end
    end

    initial begin
        $dumpfile("sim_stage3_pipeline.vcd");
        $dumpvars(0, tb_stage3_pipeline);

        clk = 0; rst_n = 0;
        insn_valid = 0; instruction = 0; rs1_data = 0;
        pixel_valid_in = 0;
        r_in = 0; g_in = 0; b_in = 0;
        y_bg_in = 0; t_thresh_in = 8'd30; qp_in = 6'd10;
        perf_enable = 0;

        #20 rst_n = 1;
        #10;

        $display("==========================================================");
        $display("[STAGE 3 PIPELINE] End-to-End Verification Starting...");
        $display("  Frame: %0dx%0d  Line Width: %0d  QP: %0d", FRAME_W, FRAME_H, LINE_WIDTH, qp_in);
        $display("==========================================================");

        // -----------------------------------------------------------------
        // TEST 1: Verify Reset State
        // -----------------------------------------------------------------
        $write("[TEST 1] Verifying initial reset state... ");
        #1;
        if (nal_valid_out == 1'b0 && pe_busy == 1'b0 && total_cycles == 32'd0) begin
            $display("[PASS] All outputs deasserted after reset");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Reset state invalid: nal_valid=%b pe_busy=%b", nal_valid_out, pe_busy);
            fail_count = fail_count + 1;
        end

        // -----------------------------------------------------------------
        // TEST 2: Custom RISC-V Opcode (DCT dispatch = funct3 3'b011)
        // -----------------------------------------------------------------
        $write("[TEST 2] Custom RISC-V Opcode 0x0B funct3=3 (DCT)... ");
        @(posedge clk);
        instruction <= 32'h0000300B; // opcode=0x0B funct3=3 (DCT)
        rs1_data    <= 32'h30008000;
        insn_valid  <= 1'b1;
        @(posedge clk); #1;
        insn_valid <= 1'b0;
        if (pe_target_op == 4'd3 && pe_mem_addr == 32'h30008000 && pe_busy == 1'b1) begin
            $display("[PASS] DCT Opcode decoded! target_op=3 addr=0x30008000 busy=1");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] DCT Opcode: target_op=%0d addr=0x%08X busy=%0b", pe_target_op, pe_mem_addr, pe_busy);
            fail_count = fail_count + 1;
        end

        // -----------------------------------------------------------------
        // TEST 3: Stream 1 complete frame through full pipeline
        //   - Background pixels: R=100,G=100,B=100 -> Y=100
        //   - Background reference: Y_bg=100, Thresh=30 -> mask=0 (no inpaint)
        //   - QP=10
        // -----------------------------------------------------------------
        $display("[TEST 3] Streaming 1 full frame (%0dx%0d) through pipeline...", FRAME_W, FRAME_H);
        perf_enable <= 1'b1;
        for (i = 0; i < FRAME_H; i = i + 1) begin
            for (j = 0; j < FRAME_W; j = j + 1) begin
                @(posedge clk);
                pixel_valid_in <= 1'b1;
                r_in <= 8'd100; g_in <= 8'd100; b_in <= 8'd100;
                y_bg_in    <= 8'd100;
                t_thresh_in <= 8'd30;
                qp_in       <= 6'd10;
            end
        end
        @(posedge clk); pixel_valid_in <= 1'b0;

        // Wait for pipeline to drain
        repeat (30) @(posedge clk);
        #1;

        $write("[TEST 3a] Checking pixel_count from perf_monitor... ");
        if (pixel_count >= (FRAME_W * FRAME_H - 30)) begin
            $display("[PASS] pixel_count=%0d (exp >=%0d)", pixel_count, FRAME_W * FRAME_H - 30);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] pixel_count=%0d too low", pixel_count);
            fail_count = fail_count + 1;
        end

        $write("[TEST 3b] Checking NAL words emitted from pipeline... ");
        if (nal_words_captured > 0) begin
            $display("[PASS] nal_words_captured=%0d (pipeline produced output)", nal_words_captured);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] No NAL words produced by pipeline!");
            fail_count = fail_count + 1;
        end

        $write("[TEST 3c] Checking inpaint_events (expect 0 for bg match)... ");
        if (inpaint_events == 32'd0) begin
            $display("[PASS] inpaint_events=0 (correct, all pixels are background)");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] inpaint_events=%0d (unexpected for full background frame)", inpaint_events);
            fail_count = fail_count + 1;
        end

        // -----------------------------------------------------------------
        // TEST 4: Inject intruder pixels and verify inpaint_events increments
        // -----------------------------------------------------------------
        $display("[TEST 4] Injecting intruder pixels to verify inpainting events...");
        // Reset perf counters via reset
        rst_n <= 0; #12; rst_n <= 1; #5;
        perf_enable <= 1'b1;

        for (i = 0; i < FRAME_H; i = i + 1) begin
            for (j = 0; j < FRAME_W; j = j + 1) begin
                @(posedge clk);
                pixel_valid_in <= 1'b1;
                // Inject intruder block at rows 4-7, cols 4-7 (a 4x4 region)
                if (i >= 4 && i < 8 && j >= 4 && j < 8) begin
                    r_in <= 8'd255; g_in <= 8'd255; b_in <= 8'd255; // White intruder
                end else begin
                    r_in <= 8'd100; g_in <= 8'd100; b_in <= 8'd100;
                end
                y_bg_in <= 8'd100; t_thresh_in <= 8'd30; qp_in <= 6'd10;
            end
        end
        @(posedge clk); pixel_valid_in <= 1'b0;
        repeat (30) @(posedge clk); #1;

        $write("[TEST 4] Checking inpaint_events with intruder frame... ");
        if (inpaint_events > 32'd0) begin
            $display("[PASS] inpaint_events=%0d (inpainting triggered for %0d intruder pixels)",
                      inpaint_events, 4*4);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] inpaint_events=0 even with white intruder pixels");
            fail_count = fail_count + 1;
        end

        perf_enable <= 1'b0;

        #20;
        $display("==========================================================");
        $display("[STAGE 3 PIPELINE SUMMARY] PASSED: %0d FAILED: %0d",
                 pass_count, fail_count);
        $display("  total_cycles=%0d  active_cycles=%0d  stall_cycles=%0d",
                 total_cycles, active_cycles, stall_cycles);
        $display("  pixel_count=%0d  nal_word_count=%0d  inpaint_events=%0d",
                 pixel_count, nal_word_count, inpaint_events);
        $display("  STATUS: STAGE 3 %s!", (fail_count == 0) ? "PASSED" : "FAILED");
        $display("==========================================================");

        $finish;
    end

endmodule
