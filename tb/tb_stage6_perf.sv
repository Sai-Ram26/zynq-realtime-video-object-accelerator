// ============================================================================
// File: tb_stage6_perf.sv
// Module: tb_stage6_perf
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Automated Self-Checking SystemVerilog Testbench for Stage 6
//              Performance Counter Readout and Throughput Validation.
// ============================================================================

`timescale 1ns / 1ps

module tb_stage6_perf;

    parameter integer LINE_WIDTH = 32;
    parameter integer FRAME_W    = 32;
    parameter integer FRAME_H    = 16;
    parameter integer CLK_PERIOD = 10; // 100 MHz clock

    reg         clk;
    reg         rst_n;
    reg         insn_valid;
    reg  [31:0] instruction;
    reg  [31:0] rs1_data;
    wire        pe_array_start;
    wire [3:0]  pe_target_op;
    wire [31:0] pe_mem_addr;
    wire        pe_busy;

    reg         pixel_valid_in;
    reg  [7:0]  r_in, g_in, b_in;
    reg  [7:0]  y_bg_in;
    reg  [7:0]  t_thresh_in;
    reg  [5:0]  qp_in;

    reg         perf_enable;
    wire [31:0] total_cycles;
    wire [31:0] active_cycles;
    wire [31:0] stall_cycles;
    wire [31:0] pixel_count;
    wire [31:0] inpaint_events;
    wire [31:0] nal_word_count;

    wire        nal_valid_out;
    wire [31:0] nal_word_out;
    wire [5:0]  nal_bit_count_out;
    wire [4:0]  total_coeff_out;

    wire [7:0]  y_inpainted;
    wire        foreground_mask;
    wire        inpaint_active;
    wire [7:0]  led_status;

    integer pass_count = 0;
    integer fail_count = 0;
    integer r, c;

    // Clock generation: 100 MHz (10 ns period)
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // DUT Instantiation
    stage6_pipeline_top #(
        .LINE_WIDTH(LINE_WIDTH)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .insn_valid        (insn_valid),
        .instruction       (instruction),
        .rs1_data          (rs1_data),
        .pe_array_start    (pe_array_start),
        .pe_target_op      (pe_target_op),
        .pe_mem_addr       (pe_mem_addr),
        .pe_busy           (pe_busy),
        .pixel_valid_in    (pixel_valid_in),
        .r_in              (r_in),
        .g_in              (g_in),
        .b_in              (b_in),
        .y_bg_in           (y_bg_in),
        .t_thresh_in       (t_thresh_in),
        .qp_in             (qp_in),
        .perf_enable       (perf_enable),
        .total_cycles      (total_cycles),
        .active_cycles     (active_cycles),
        .stall_cycles      (stall_cycles),
        .pixel_count       (pixel_count),
        .inpaint_events    (inpaint_events),
        .nal_word_count    (nal_word_count),
        .nal_valid_out     (nal_valid_out),
        .nal_word_out      (nal_word_out),
        .nal_bit_count_out (nal_bit_count_out),
        .total_coeff_out   (total_coeff_out),
        .y_inpainted       (y_inpainted),
        .foreground_mask   (foreground_mask),
        .inpaint_active    (inpaint_active),
        .led_status        (led_status)
    );

    initial begin
        $display("================================================================");
        $display("   STAGE 6: PERFORMANCE MONITOR READOUT & AUDIT TESTBENCH");
        $display("================================================================");

        // Reset
        rst_n          = 0;
        insn_valid     = 0;
        instruction    = 32'd0;
        rs1_data       = 32'd0;
        pixel_valid_in = 0;
        r_in = 0; g_in = 0; b_in = 0;
        y_bg_in        = 8'd76;
        t_thresh_in    = 8'd30;
        qp_in          = 6'd10;
        perf_enable    = 0;

        #(CLK_PERIOD * 5);
        @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: Performance counters remain 0 when perf_enable = 0
        // ---------------------------------------------------------------------
        #(CLK_PERIOD * 10);
        $write("[TEST 1] Verifying counters inactive when perf_enable=0... ");
        if (total_cycles == 0 && pixel_count == 0) begin
            $display("[PASS] total_cycles=%0d, pixel_count=%0d", total_cycles, pixel_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] total_cycles=%0d (exp 0)", total_cycles);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Start performance monitoring & stream frame (32x16 = 512 pixels)
        // ---------------------------------------------------------------------
        @(negedge clk);
        perf_enable = 1;
        @(negedge clk);

        for (r = 0; r < FRAME_H; r = r + 1) begin
            for (c = 0; c < FRAME_W; c = c + 1) begin
                pixel_valid_in = 1;
                // Corrupt center 4x4 region with white intruder (r in [6,9], c in [14,17])
                if (r >= 6 && r <= 9 && c >= 14 && c <= 17) begin
                    r_in = 8'd255; g_in = 8'd255; b_in = 8'd255; // White intruder
                end else begin
                    r_in = 8'd255; g_in = 8'd0;   b_in = 8'd0;   // Red background
                end
                @(negedge clk);
            end
        end

        pixel_valid_in = 0;
        #(CLK_PERIOD * 40); // Allow pipeline flush

        $write("[TEST 2] Verifying pixel_count matches streamed pixels... ");
        if (pixel_count == (FRAME_W * FRAME_H)) begin
            $display("[PASS] pixel_count=%0d (exp %0d)", pixel_count, FRAME_W * FRAME_H);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] pixel_count=%0d (exp %0d)", pixel_count, FRAME_W * FRAME_H);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Check inpaint_events detected 16 corrupted pixels
        // ---------------------------------------------------------------------
        $write("[TEST 3] Verifying inpaint_events counter... ");
        if (inpaint_events == 16) begin
            $display("[PASS] inpaint_events=%0d (exp 16)", inpaint_events);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] inpaint_events=%0d (exp 16)", inpaint_events);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Check active_cycles and total_cycles
        // ---------------------------------------------------------------------
        $write("[TEST 4] Verifying total_cycles > active_cycles... ");
        if (total_cycles >= active_cycles && active_cycles >= (FRAME_W * FRAME_H)) begin
            $display("[PASS] total_cycles=%0d, active_cycles=%0d", total_cycles, active_cycles);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] total_cycles=%0d, active_cycles=%0d", total_cycles, active_cycles);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Check nal_word_count > 0
        // ---------------------------------------------------------------------
        $write("[TEST 5] Verifying compressed NAL words emitted... ");
        if (nal_word_count > 0) begin
            $display("[PASS] nal_word_count=%0d (compressed bitstream generated)", nal_word_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] nal_word_count=%0d (exp > 0)", nal_word_count);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 6: Check LED status bits
        // ---------------------------------------------------------------------
        $write("[TEST 6] Checking hardware status LED indicators... ");
        // led_status[6] must be 1 (perf_enable=1)
        if (led_status[6] == 1'b1) begin
            $display("[PASS] led_status[6]=1 (Perf Monitor active)");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] led_status[6]=0");
            fail_count = fail_count + 1;
        end

        $display("================================================================");
        $display("   STAGE 6 TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("   STATUS: ALL STAGE 6 TESTS PASSED SUCCESSFULLY!");
        else
            $display("   STATUS: STAGE 6 SIMULATION FAILED!");
        $display("================================================================");

        $finish;
    end

endmodule
