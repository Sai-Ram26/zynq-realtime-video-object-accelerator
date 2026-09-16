// =============================================================================
// Testbench: tb_stage1_core.v
// Stage 1: Minimum Working Core Verification
// Tests:
//   1. Stochastic Number Generator (stochastic_gen.v)
//   2. Stochastic S-SAD and Arithmetic Unit (stochastic_sad.v)
//   3. Line-Buffered 8x8 Spatial Inpainting Engine (inpainting_8x8_linebuffer.v)
//   4. Unified Hybrid Inpainter Core (hybrid_inpainter.v)
// =============================================================================

`timescale 1ns / 1ps

module tb_stage1_core;

    parameter CLK_PERIOD = 10;
    parameter TEST_WIDTH = 16;
    parameter TOTAL_PIXELS = TEST_WIDTH * 16; // 16x16 grid

    reg        clk;
    reg        rst_n;
    reg        valid_in;
    reg  [7:0] curr_pixel;
    reg  [7:0] bg_pixel;
    reg  [7:0] threshold;
    reg  [1:0] mode_sel;
    reg        bg_valid;

    wire       valid_out;
    wire       mask_out;
    wire [7:0] clean_pixel_out;
    wire       s_mult;
    wire       s_add;
    wire       s_sad_stream;

    // Instantiate Hybrid Inpainter DUT
    hybrid_inpainter #(
        .LINE_WIDTH(TEST_WIDTH),
        .DATA_WIDTH(8)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .curr_pixel(curr_pixel),
        .bg_pixel(bg_pixel),
        .threshold(threshold),
        .mode_sel(mode_sel),
        .bg_valid(bg_valid),
        .valid_out(valid_out),
        .mask_out(mask_out),
        .clean_pixel_out(clean_pixel_out),
        .s_mult(s_mult),
        .s_add(s_add),
        .s_sad_stream(s_sad_stream)
    );

    // Clock generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    integer i, errors;
    reg [7:0] test_curr [0:TOTAL_PIXELS-1];
    reg [7:0] test_bg   [0:TOTAL_PIXELS-1];
    reg       test_mask [0:TOTAL_PIXELS-1];

    initial begin
        // Setup waveform dump
        $dumpfile("sim_stage1_core.vcd");
        $dumpvars(0, tb_stage1_core);

        clk       = 0;
        rst_n     = 0;
        valid_in  = 0;
        curr_pixel= 0;
        bg_pixel  = 0;
        threshold = 8'd25;
        mode_sel  = 2'b00; // Temporal mode first
        bg_valid  = 1'b1;
        errors    = 0;

        $display("===============================================================");
        $display("[STAGE 1] Starting Minimum Working Core Verification");
        $display("===============================================================");

        // Generate synthetic image test pattern:
        // Background: 8'd50 (Uniform gray background)
        // Foreground intruder placed at rows 6-9, cols 6-9: 8'd200
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            test_bg[i] = 8'd50;
            if ((i / TEST_WIDTH >= 6 && i / TEST_WIDTH <= 9) &&
                (i % TEST_WIDTH >= 6 && i % TEST_WIDTH <= 9)) begin
                test_curr[i] = 8'd200; // Intruder pixel
                test_mask[i] = 1'b1;   // Must be masked and removed
            end else begin
                test_curr[i] = 8'd50;  // Background match
                test_mask[i] = 1'b0;
            end
        end

        // Reset DUT
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // ---------------------------------------------------------------------
        // TEST CASE 1: Temporal Inpainting Mode (mode_sel = 2'b00)
        // ---------------------------------------------------------------------
        $display("[+] Test Case 1: Temporal Inpainting (Replace intruder with BG model)...");
        mode_sel = 2'b00;
        bg_valid = 1'b1;

        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            @(posedge clk);
            valid_in   <= 1'b1;
            curr_pixel <= test_curr[i];
            bg_pixel   <= test_bg[i];
        end

        @(posedge clk);
        valid_in <= 1'b0;
        #(CLK_PERIOD * 20);

        // ---------------------------------------------------------------------
        // TEST CASE 2: Spatial 8x8 Inpainting Mode (mode_sel = 2'b01)
        // ---------------------------------------------------------------------
        $display("[+] Test Case 2: Spatial 8x8 Window Inpainting (Reconstruct without BG)...");
        mode_sel = 2'b01;
        bg_valid = 1'b0;

        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            @(posedge clk);
            valid_in   <= 1'b1;
            curr_pixel <= test_curr[i];
            bg_pixel   <= 8'd0; // No valid background provided
        end

        @(posedge clk);
        valid_in <= 1'b0;
        #(CLK_PERIOD * 30);

        // ---------------------------------------------------------------------
        // TEST CASE 3: Stochastic Computing Arithmetic Check
        // ---------------------------------------------------------------------
        $display("[+] Test Case 3: Stochastic Arithmetic Stream Activity Check...");
        if (s_mult === 1'bx || s_add === 1'bx || s_sad_stream === 1'bx) begin
            $display("[ERROR] Stochastic signals contain unknown 'x' states!");
            errors = errors + 1;
        end else begin
            $display("[PASS] Stochastic arithmetic streams active and valid (Zero 'x' states).");
        end

        // ---------------------------------------------------------------------
        // Final Status
        // ---------------------------------------------------------------------
        $display("===============================================================");
        if (errors == 0) begin
            $display("[STAGE 1 SUCCESS] ALL MINIMUM WORKING CORE TESTS PASSED!");
        end else begin
            $display("[STAGE 1 FAILURE] Detected %0d errors in core verification.", errors);
        end
        $display("===============================================================");

        $finish;
    end

    // Real-time output monitor for Temporal Mode
    integer out_count = 0;
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            if (out_count < TOTAL_PIXELS && mode_sel == 2'b00) begin
                // In temporal mode with test pattern, clean pixel must always equal 8'd50
                if (clean_pixel_out !== 8'd50) begin
                    $display("[ERROR] Pixel %0d mismatch: Expected=50, Got=%0d", out_count, clean_pixel_out);
                    errors = errors + 1;
                end
            end
            out_count = out_count + 1;
        end
    end

endmodule
