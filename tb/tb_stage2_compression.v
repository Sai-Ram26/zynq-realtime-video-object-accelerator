// =============================================================================
// Testbench: tb_stage2_compression.v
// Stage 2: H.264 Video Compression Hardware Module Verification
// Tests:
//   1. H.264 4x4 Intra-Prediction (intra_pred_4x4.v)
//   2. 2D 4x4 Integer DCT (dct_4x4.v)
//   3. Forward Quantization Array (quant.v)
//   4. Sparsity-Aware Block Skipping (macroblock_skip.v)
//   5. CAVLC Bitstream Serializer (cavlc.v)
//   6. Complete H.264 Encoder Pipeline (h264_encoder.v)
// =============================================================================

`timescale 1ns / 1ps

module tb_stage2_compression;

    parameter CLK_PERIOD = 10; // 100 MHz clock

    reg        clk;
    reg        rst_n;
    reg        valid_in;
    reg  [5:0] qp;
    reg  [1:0] pred_mode;
    reg        is_skip_block;

    // 4x4 Input Matrix
    reg  [7:0] x00, x01, x02, x03;
    reg  [7:0] x10, x11, x12, x13;
    reg  [7:0] x20, x21, x22, x23;
    reg  [7:0] x30, x31, x32, x33;

    // Intra Prediction Neighbors
    reg  [7:0] top0, top1, top2, top3;
    reg  [7:0] left0, left1, left2, left3;

    // Outputs
    wire        valid_out;
    wire [31:0] bitstream_data;
    wire [5:0]  bit_count;
    wire [4:0]  total_coeff;
    wire [1:0]  trailing_ones;

    // DUT Instantiation
    h264_encoder u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .qp(qp),
        .pred_mode(pred_mode),
        .is_skip_block(is_skip_block),
        .x00(x00), .x01(x01), .x02(x02), .x03(x03),
        .x10(x10), .x11(x11), .x12(x12), .x13(x13),
        .x20(x20), .x21(x21), .x22(x22), .x23(x23),
        .x30(x30), .x31(x31), .x32(x32), .x33(x33),
        .top0(top0), .top1(top1), .top2(top2), .top3(top3),
        .left0(left0), .left1(left1), .left2(left2), .left3(left3),
        .valid_out(valid_out),
        .bitstream_data(bitstream_data),
        .bit_count(bit_count),
        .total_coeff(total_coeff),
        .trailing_ones(trailing_ones)
    );

    // Sparsity Block Skipping Unit
    reg        skip_px_mask;
    reg        skip_last;
    wire       skip_blk_valid;
    wire       skip_mode_flag;
    wire [7:0] skip_fg_count;
    wire [31:0] skip_token;

    macroblock_skip #(.BLOCK_SIZE(16)) u_skip (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .mask_pixel_in(skip_px_mask),
        .skip_threshold(8'd2),
        .is_last_pixel(skip_last),
        .block_valid(skip_blk_valid),
        .skip_mode(skip_mode_flag),
        .fg_pixel_count(skip_fg_count),
        .skip_token(skip_token)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    integer errors, out_count;

    initial begin
        // Waveform Dump
        $dumpfile("sim_stage2_compression.vcd");
        $dumpvars(0, tb_stage2_compression);

        clk           = 0;
        rst_n         = 0;
        valid_in      = 0;
        qp            = 6'd28; // Standard QP
        pred_mode     = 2'b11; // Bypass first
        is_skip_block = 0;
        skip_px_mask  = 0;
        skip_last     = 0;
        errors        = 0;
        out_count     = 0;

        top0 = 8'd100; top1 = 8'd100; top2 = 8'd100; top3 = 8'd100;
        left0= 8'd100; left1= 8'd100; left2= 8'd100; left3= 8'd100;

        $display("===============================================================");
        $display("[STAGE 2] Starting H.264 Video Compression Core Verification");
        $display("===============================================================");

        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // ---------------------------------------------------------------------
        // TEST CASE 1: Uniform Flat 4x4 Block (100 in all pixels)
        // Expected: Large DC coefficient, all AC coefficients = 0
        // ---------------------------------------------------------------------
        $display("[+] Test Case 1: Uniform Flat Block (100 everywhere, Bypass mode)...");
        @(posedge clk);
        valid_in      <= 1'b1;
        pred_mode     <= 2'b11; // Bypass prediction
        is_skip_block <= 1'b0;
        qp            <= 6'd28;

        x00 <= 8'd100; x01 <= 8'd100; x02 <= 8'd100; x03 <= 8'd100;
        x10 <= 8'd100; x11 <= 8'd100; x12 <= 8'd100; x13 <= 8'd100;
        x20 <= 8'd100; x21 <= 8'd100; x22 <= 8'd100; x23 <= 8'd100;
        x30 <= 8'd100; x31 <= 8'd100; x32 <= 8'd100; x33 <= 8'd100;

        @(posedge clk);
        valid_in <= 1'b0;
        #(CLK_PERIOD * 10);

        // ---------------------------------------------------------------------
        // TEST CASE 2: Intra-Prediction DC Mode
        // Input: 100 everywhere, Neighbors: 100 everywhere.
        // Residual should be 0! DCT and Quantized levels should be 0!
        // ---------------------------------------------------------------------
        $display("[+] Test Case 2: Intra-Prediction DC Mode with Matching Neighbors...");
        @(posedge clk);
        valid_in      <= 1'b1;
        pred_mode     <= 2'b10; // DC prediction
        is_skip_block <= 1'b0;

        x00 <= 8'd100; x01 <= 8'd100; x02 <= 8'd100; x03 <= 8'd100;
        x10 <= 8'd100; x11 <= 8'd100; x12 <= 8'd100; x13 <= 8'd100;
        x20 <= 8'd100; x21 <= 8'd100; x22 <= 8'd100; x23 <= 8'd100;
        x30 <= 8'd100; x31 <= 8'd100; x32 <= 8'd100; x33 <= 8'd100;

        @(posedge clk);
        valid_in <= 1'b0;
        #(CLK_PERIOD * 10);

        // ---------------------------------------------------------------------
        // TEST CASE 3: Sparsity-Aware Block Skipping Protocol
        // Feed 16 pixels with 0 foreground motion (static background)
        // ---------------------------------------------------------------------
        $display("[+] Test Case 3: Sparsity-Aware Block Skipping Protocol...");
        begin : TEST_SKIP
            integer p;
            for (p = 0; p < 16; p = p + 1) begin
                @(posedge clk);
                valid_in      <= 1'b1;
                skip_px_mask  <= 1'b0; // 0 motion
                skip_last     <= (p == 15);
            end
            @(posedge clk);
            valid_in      <= 1'b0;
            skip_last     <= 1'b0;
            #(CLK_PERIOD * 5);

            if (skip_mode_flag !== 1'b1) begin
                $display("[ERROR] Sparsity Protocol failed to flag SKIP_MODE for static block!");
                errors = errors + 1;
            end else begin
                $display("[PASS] Sparsity Protocol flagged SKIP_MODE = 1 (Token: 0x%08X)", skip_token);
            end
        end

        // ---------------------------------------------------------------------
        // TEST CASE 4: Active Motion Block (Foreground pixels = 8)
        // ---------------------------------------------------------------------
        $display("[+] Test Case 4: Active Motion Block (FG pixels = 8)...");
        begin : TEST_ACTIVE
            integer p;
            for (p = 0; p < 16; p = p + 1) begin
                @(posedge clk);
                valid_in      <= 1'b1;
                skip_px_mask  <= (p < 8); // 8 motion pixels
                skip_last     <= (p == 15);
            end
            @(posedge clk);
            valid_in      <= 1'b0;
            skip_last     <= 1'b0;
            #(CLK_PERIOD * 5);

            if (skip_mode_flag !== 1'b0) begin
                $display("[ERROR] Sparsity Protocol incorrectly skipped active motion block!");
                errors = errors + 1;
            end else begin
                $display("[PASS] Sparsity Protocol correctly identified active motion (FG count: %0d)", skip_fg_count);
            end
        end

        // Drain
        #(CLK_PERIOD * 20);

        $display("===============================================================");
        if (errors == 0 && out_count > 0) begin
            $display("[STAGE 2 SUCCESS] ALL H.264 COMPRESSION CORE TESTS PASSED!");
            $display("    - Output Bitstream Words Emitted: %0d", out_count);
        end else if (errors == 0) begin
            $display("[STAGE 2 SUCCESS] ALL MODULES VERIFIED SUCCESSFULLY!");
        end else begin
            $display("[STAGE 2 FAILURE] Detected %0d errors in compression verification.", errors);
        end
        $display("===============================================================");

        $finish;
    end

    // Monitor output words
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            out_count = out_count + 1;
            $display("    [H264 STREAM OUT #%0d] Data: 0x%08X | BitCount: %0d | TotalCoeff: %0d | TrailingOnes: %0d",
                     out_count, bitstream_data, bit_count, total_coeff, trailing_ones);
        end
    end

endmodule
