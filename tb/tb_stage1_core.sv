// ============================================================================
// File: tb_stage1_core.sv
// Module: tb_stage1_core
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Automated Self-Checking SystemVerilog Testbench for Stage 1.
//              Verifies Custom RISC-V Opcode 0x0B Interceptor, Fixed-Point
//              RGB2YUV Converter, and Temporal Background Subtraction Pipeline.
// Standard: IEEE 1800-2012 SystemVerilog / IEEE 1364-2001 Verilog
// ============================================================================

`timescale 1ns / 1ps

module tb_stage1_core;

    reg         clk;
    reg         rst_n;

    // Control Plane
    reg         insn_valid;
    reg  [31:0] instruction;
    reg  [31:0] rs1_data;
    wire        pe_array_start;
    wire [3:0]  pe_target_op;
    wire [31:0] pe_mem_addr;
    wire        pe_busy;

    // Data Plane
    reg         pixel_valid_in;
    reg  [7:0]  r_in, g_in, b_in;
    reg  [7:0]  y_bg_in;
    reg  [7:0]  t_thresh_in;

    wire        pixel_valid_out;
    wire [7:0]  y_out;
    wire [7:0]  u_out;
    wire [7:0]  v_out;
    wire [7:0]  abs_diff_out;
    wire        foreground_mask;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate Device Under Test
    stage1_core_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .insn_valid(insn_valid),
        .instruction(instruction),
        .rs1_data(rs1_data),
        .pe_array_start(pe_array_start),
        .pe_target_op(pe_target_op),
        .pe_mem_addr(pe_mem_addr),
        .pe_busy(pe_busy),
        .pixel_valid_in(pixel_valid_in),
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .y_bg_in(y_bg_in),
        .t_thresh_in(t_thresh_in),
        .pixel_valid_out(pixel_valid_out),
        .y_out(y_out),
        .u_out(u_out),
        .v_out(v_out),
        .abs_diff_out(abs_diff_out),
        .foreground_mask(foreground_mask)
    );

    // 100 MHz Clock Generation (10 ns period)
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim_stage1_core.vcd");
        $dumpvars(0, tb_stage1_core);

        clk            = 0;
        rst_n          = 0;
        insn_valid     = 0;
        instruction    = 32'd0;
        rs1_data       = 32'd0;
        pixel_valid_in = 0;
        r_in           = 8'd0;
        g_in           = 8'd0;
        b_in           = 8'd0;
        y_bg_in        = 8'd0;
        t_thresh_in    = 8'd30;

        #20 rst_n = 1;
        #10;

        $display("==========================================================");
        $display("[STAGE 1 SIMULATOR] Running Cycle-Exact Verification...");
        $display("==========================================================");

        // ---------------------------------------------------------------------
        // TEST 1: Testing Custom RISC-V Opcode Interceptor (0x0B)
        // ---------------------------------------------------------------------
        $write("[TEST 1] Testing Custom RISC-V Opcode Interceptor (0x0B)... ");
        @(posedge clk);
        instruction <= 32'h0005050B; // opcode=0x0B, funct3=0 (RGB2YUV)
        rs1_data    <= 32'h10008000;
        insn_valid  <= 1'b1;
        @(posedge clk);
        #1;
        insn_valid  <= 1'b0;

        if (pe_target_op == 4'd0 && pe_mem_addr == 32'h10008000 && pe_busy == 1'b1) begin
            $display("[PASS] Custom Opcode 0x0B correctly decoded! target_op=0, mem_addr=0x10008000, busy=1");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Custom Opcode mismatch! target_op=%d, addr=0x%08X, busy=%b", pe_target_op, pe_mem_addr, pe_busy);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Testing RGB888->YUV420 & Temporal Subtraction Pipeline
        // ---------------------------------------------------------------------
        $display("[TEST 2] Testing RGB888->YUV420 & Temporal Subtraction Pipeline...");

        // Test 2A: Pure Red Background Match (R=255, G=0, B=0, Y_bg=77, T=30)
        @(posedge clk);
        pixel_valid_in <= 1'b1;
        r_in <= 8'd255; g_in <= 8'd0; b_in <= 8'd0;
        y_bg_in <= 8'd77; t_thresh_in <= 8'd30;
        @(posedge clk);
        pixel_valid_in <= 1'b0;

        // Pipeline delay is 2 cycles (Stage 1 color conversion + Stage 2 diff)
        @(posedge clk);
        @(posedge clk);
        #1;
        if (y_out == 8'd76 && foreground_mask == 1'b0 && abs_diff_out == 8'd1) begin
            $display("... [PASS] Pure Red Background Pixel: Y_out=%d (exp ~76), Mask=%b (exp 0), Diff=%d", y_out, foreground_mask, abs_diff_out);
            pass_count = pass_count + 1;
        end else begin
            $display("... [FAIL] Pure Red Background Pixel: Y_out=%d, Mask=%b, Diff=%d", y_out, foreground_mask, abs_diff_out);
            fail_count = fail_count + 1;
        end

        // Test 2B: Pure White Intruder Pixel (R=255, G=255, B=255, Y_bg=77, T=30)
        @(posedge clk);
        pixel_valid_in <= 1'b1;
        r_in <= 8'd255; g_in <= 8'd255; b_in <= 8'd255;
        y_bg_in <= 8'd77; t_thresh_in <= 8'd30;
        @(posedge clk);
        pixel_valid_in <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (y_out == 8'd255 && foreground_mask == 1'b1 && abs_diff_out == 8'd178) begin
            $display("[PASS] Pure White Intruder Pixel: Y_out=%d (exp ~255), Mask=%b (exp 1), Diff=%d", y_out, foreground_mask, abs_diff_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Pure White Intruder Pixel: Y_out=%d, Mask=%b, Diff=%d", y_out, foreground_mask, abs_diff_out);
            fail_count = fail_count + 1;
        end

        // Test 2C: Pure Green Background Pixel (R=0, G=255, B=0, Y_bg=150, T=30)
        @(posedge clk);
        pixel_valid_in <= 1'b1;
        r_in <= 8'd0; g_in <= 8'd255; b_in <= 8'd0;
        y_bg_in <= 8'd150; t_thresh_in <= 8'd30;
        @(posedge clk);
        pixel_valid_in <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (y_out == 8'd149 && foreground_mask == 1'b0 && abs_diff_out == 8'd1) begin
            $display("[PASS] Pure Green Background Pixel: Y_out=%d (exp ~149), Mask=%b (exp 0), Diff=%d", y_out, foreground_mask, abs_diff_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Pure Green Background Pixel: Y_out=%d, Mask=%b, Diff=%d", y_out, foreground_mask, abs_diff_out);
            fail_count = fail_count + 1;
        end

        // Test 2D: Shadow Motion Intruder Pixel (R=50, G=50, B=50, Y_bg=200, T=30)
        @(posedge clk);
        pixel_valid_in <= 1'b1;
        r_in <= 8'd50; g_in <= 8'd50; b_in <= 8'd50;
        y_bg_in <= 8'd200; t_thresh_in <= 8'd30;
        @(posedge clk);
        pixel_valid_in <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (y_out == 8'd50 && foreground_mask == 1'b1 && abs_diff_out == 8'd150) begin
            $display("[PASS] Shadow Motion Intruder Pixel: Y_out=%d (exp ~50), Mask=%b (exp 1), Diff=%d", y_out, foreground_mask, abs_diff_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Shadow Motion Intruder Pixel: Y_out=%d, Mask=%b, Diff=%d", y_out, foreground_mask, abs_diff_out);
            fail_count = fail_count + 1;
        end

        #20;
        $display("==========================================================");
        $display("[STAGE 1 VERIFICATION SUMMARY] PASSED: %0d FAILED: %0d STATUS: STAGE 1 MINIMUM WORKING CORE DEMO %s!",
                 pass_count, fail_count, (fail_count == 0) ? "PASSED" : "FAILED");
        $display("==========================================================");

        $finish;
    end

endmodule
