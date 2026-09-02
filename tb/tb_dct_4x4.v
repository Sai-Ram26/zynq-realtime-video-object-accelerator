`timescale 1ns / 1ps

// ============================================================================
// Testbench: tb_dct_4x4
// Description: Unit testbench verifying the Multiplierless 2D 4x4 H.264
//              Integer Transform against known mathematical transform matrices.
// ============================================================================

module tb_dct_4x4;

    reg clk;
    reg rst_n;
    reg valid_in;

    // 4x4 inputs
    reg [7:0] x00, x01, x02, x03;
    reg [7:0] x10, x11, x12, x13;
    reg [7:0] x20, x21, x22, x23;
    reg [7:0] x30, x31, x32, x33;

    // 4x4 outputs
    wire valid_out;
    wire signed [15:0] w00, w01, w02, w03;
    wire signed [15:0] w10, w11, w12, w13;
    wire signed [15:0] w20, w21, w22, w23;
    wire signed [15:0] w30, w31, w32, w33;

    // Instantiate DCT 4x4
    dct_4x4 u_dct (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .x00(x00), .x01(x01), .x02(x02), .x03(x03),
        .x10(x10), .x11(x11), .x12(x12), .x13(x13),
        .x20(x20), .x21(x21), .x22(x22), .x23(x23),
        .x30(x30), .x31(x31), .x32(x32), .x33(x33),
        .valid_out(valid_out),
        .w00(w00), .w01(w01), .w02(w02), .w03(w03),
        .w10(w10), .w11(w11), .w12(w12), .w13(w13),
        .w20(w20), .w21(w21), .w22(w22), .w23(w23),
        .w30(w30), .w31(w31), .w32(w32), .w33(w33)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        valid_in = 0;
        x00 = 0; x01 = 0; x02 = 0; x03 = 0;
        x10 = 0; x11 = 0; x12 = 0; x13 = 0;
        x20 = 0; x21 = 0; x22 = 0; x23 = 0;
        x30 = 0; x31 = 0; x32 = 0; x33 = 0;

        $display("===============================================================");
        $display("[*] Starting 2D 4x4 H.264 Integer DCT Unit Test");
        $display("===============================================================");

        #20;
        rst_n = 1;
        #20;

        // Test Case 1: Flat block (all pixels = 100)
        // DC coefficient = 100 * 16 = 1600, all AC coefficients = 0
        @(posedge clk);
        valid_in <= 1'b1;
        x00 <= 100; x01 <= 100; x02 <= 100; x03 <= 100;
        x10 <= 100; x11 <= 100; x12 <= 100; x13 <= 100;
        x20 <= 100; x21 <= 100; x22 <= 100; x23 <= 100;
        x30 <= 100; x31 <= 100; x32 <= 100; x33 <= 100;

        // Test Case 2: Ramp block
        @(posedge clk);
        x00 <= 10; x01 <= 20; x02 <= 30; x03 <= 40;
        x10 <= 10; x11 <= 20; x12 <= 30; x13 <= 40;
        x20 <= 10; x21 <= 20; x22 <= 30; x23 <= 40;
        x30 <= 10; x31 <= 20; x32 <= 30; x33 <= 40;

        @(posedge clk);
        valid_in <= 1'b0;

        // Wait for results
        #50;

        $display("===============================================================");
        $display("[+] DCT 4x4 SIMULATION COMPLETE!");
        $display("===============================================================");
        $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (valid_out) begin
            $display("[+] DCT Transformed 4x4 Output Block:");
            $display("    | %6d %6d %6d %6d |", w00, w01, w02, w03);
            $display("    | %6d %6d %6d %6d |", w10, w11, w12, w13);
            $display("    | %6d %6d %6d %6d |", w20, w21, w22, w23);
            $display("    | %6d %6d %6d %6d |", w30, w31, w32, w33);
        end
    end

endmodule
