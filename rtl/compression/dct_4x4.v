`timescale 1ns / 1ps

// ============================================================================
// Module: dct_4x4
// Description: Multiplierless 2D 4x4 H.264 Integer Transform Core.
// Math: W = H * X * H^T
// Implementation: Separable 1D Row Transform -> Transpose Matrix -> 1D Col Transform.
// Latency: 2 clock cycles.
// ============================================================================

module dct_4x4 (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    // 4x4 input pixels (8-bit unsigned)
    input  wire [7:0]           x00, x01, x02, x03,
    input  wire [7:0]           x10, x11, x12, x13,
    input  wire [7:0]           x20, x21, x22, x23,
    input  wire [7:0]           x30, x31, x32, x33,
    // 4x4 transformed coefficients (16-bit signed)
    output reg                  valid_out,
    output reg signed [15:0]    w00, w01, w02, w03,
    output reg signed [15:0]    w10, w11, w12, w13,
    output reg signed [15:0]    w20, w21, w22, w23,
    output reg signed [15:0]    w30, w31, w32, w33
);

    // 1D Row Transform Intermediate Signals
    // row0
    wire signed [15:0] r0_p0 = $signed({8'b0, x00}) + $signed({8'b0, x03});
    wire signed [15:0] r0_p1 = $signed({8'b0, x01}) + $signed({8'b0, x02});
    wire signed [15:0] r0_p2 = $signed({8'b0, x01}) - $signed({8'b0, x02});
    wire signed [15:0] r0_p3 = $signed({8'b0, x00}) - $signed({8'b0, x03});

    wire signed [15:0] t00 = r0_p0 + r0_p1;
    wire signed [15:0] t01 = (r0_p3 <<< 1) + r0_p2;
    wire signed [15:0] t02 = r0_p0 - r0_p1;
    wire signed [15:0] t03 = r0_p3 - (r0_p2 <<< 1);

    // row1
    wire signed [15:0] r1_p0 = $signed({8'b0, x10}) + $signed({8'b0, x13});
    wire signed [15:0] r1_p1 = $signed({8'b0, x11}) + $signed({8'b0, x12});
    wire signed [15:0] r1_p2 = $signed({8'b0, x11}) - $signed({8'b0, x12});
    wire signed [15:0] r1_p3 = $signed({8'b0, x10}) - $signed({8'b0, x13});

    wire signed [15:0] t10 = r1_p0 + r1_p1;
    wire signed [15:0] t11 = (r1_p3 <<< 1) + r1_p2;
    wire signed [15:0] t12 = r1_p0 - r1_p1;
    wire signed [15:0] t13 = r1_p3 - (r1_p2 <<< 1);

    // row2
    wire signed [15:0] r2_p0 = $signed({8'b0, x20}) + $signed({8'b0, x23});
    wire signed [15:0] r2_p1 = $signed({8'b0, x21}) + $signed({8'b0, x22});
    wire signed [15:0] r2_p2 = $signed({8'b0, x21}) - $signed({8'b0, x22});
    wire signed [15:0] r2_p3 = $signed({8'b0, x20}) - $signed({8'b0, x23});

    wire signed [15:0] t20 = r2_p0 + r2_p1;
    wire signed [15:0] t21 = (r2_p3 <<< 1) + r2_p2;
    wire signed [15:0] t22 = r2_p0 - r2_p1;
    wire signed [15:0] t23 = r2_p3 - (r2_p2 <<< 1);

    // row3
    wire signed [15:0] r3_p0 = $signed({8'b0, x30}) + $signed({8'b0, x33});
    wire signed [15:0] r3_p1 = $signed({8'b0, x31}) + $signed({8'b0, x32});
    wire signed [15:0] r3_p2 = $signed({8'b0, x31}) - $signed({8'b0, x32});
    wire signed [15:0] r3_p3 = $signed({8'b0, x30}) - $signed({8'b0, x33});

    wire signed [15:0] t30 = r3_p0 + r3_p1;
    wire signed [15:0] t31 = (r3_p3 <<< 1) + r3_p2;
    wire signed [15:0] t32 = r3_p0 - r3_p1;
    wire signed [15:0] t33 = r3_p3 - (r3_p2 <<< 1);

    // Stage 1 Pipeline Registers (Transposed matrix T)
    reg signed [15:0] reg_t00, reg_t10, reg_t20, reg_t30;
    reg signed [15:0] reg_t01, reg_t11, reg_t21, reg_t31;
    reg signed [15:0] reg_t02, reg_t12, reg_t22, reg_t32;
    reg signed [15:0] reg_t03, reg_t13, reg_t23, reg_t33;
    reg               valid_stage1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_stage1 <= 1'b0;
            reg_t00 <= 16'sd0; reg_t10 <= 16'sd0; reg_t20 <= 16'sd0; reg_t30 <= 16'sd0;
            reg_t01 <= 16'sd0; reg_t11 <= 16'sd0; reg_t21 <= 16'sd0; reg_t31 <= 16'sd0;
            reg_t02 <= 16'sd0; reg_t12 <= 16'sd0; reg_t22 <= 16'sd0; reg_t32 <= 16'sd0;
            reg_t03 <= 16'sd0; reg_t13 <= 16'sd0; reg_t23 <= 16'sd0; reg_t33 <= 16'sd0;
        end else begin
            valid_stage1 <= valid_in;
            // Transposed assignment: T[col][row]
            reg_t00 <= t00; reg_t01 <= t10; reg_t02 <= t20; reg_t03 <= t30;
            reg_t10 <= t01; reg_t11 <= t11; reg_t12 <= t21; reg_t13 <= t31;
            reg_t20 <= t02; reg_t21 <= t12; reg_t22 <= t22; reg_t23 <= t32;
            reg_t30 <= t03; reg_t31 <= t13; reg_t32 <= t23; reg_t33 <= t33;
        end
    end

    // Stage 2: 1D Column Transform (Applied to Transposed Matrix)
    // col0
    wire signed [15:0] c0_p0 = reg_t00 + reg_t03;
    wire signed [15:0] c0_p1 = reg_t01 + reg_t02;
    wire signed [15:0] c0_p2 = reg_t01 - reg_t02;
    wire signed [15:0] c0_p3 = reg_t00 - reg_t03;

    // col1
    wire signed [15:0] c1_p0 = reg_t10 + reg_t13;
    wire signed [15:0] c1_p1 = reg_t11 + reg_t12;
    wire signed [15:0] c1_p2 = reg_t11 - reg_t12;
    wire signed [15:0] c1_p3 = reg_t10 - reg_t13;

    // col2
    wire signed [15:0] c2_p0 = reg_t20 + reg_t23;
    wire signed [15:0] c2_p1 = reg_t21 + reg_t22;
    wire signed [15:0] c2_p2 = reg_t21 - reg_t22;
    wire signed [15:0] c2_p3 = reg_t20 - reg_t23;

    // col3
    wire signed [15:0] c3_p0 = reg_t30 + reg_t33;
    wire signed [15:0] c3_p1 = reg_t31 + reg_t32;
    wire signed [15:0] c3_p2 = reg_t31 - reg_t32;
    wire signed [15:0] c3_p3 = reg_t30 - reg_t33;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            w00 <= 16'sd0; w01 <= 16'sd0; w02 <= 16'sd0; w03 <= 16'sd0;
            w10 <= 16'sd0; w11 <= 16'sd0; w12 <= 16'sd0; w13 <= 16'sd0;
            w20 <= 16'sd0; w21 <= 16'sd0; w22 <= 16'sd0; w23 <= 16'sd0;
            w30 <= 16'sd0; w31 <= 16'sd0; w32 <= 16'sd0; w33 <= 16'sd0;
        end else begin
            valid_out <= valid_stage1;
            if (valid_stage1) begin
                w00 <= c0_p0 + c0_p1;
                w10 <= (c0_p3 <<< 1) + c0_p2;
                w20 <= c0_p0 - c0_p1;
                w30 <= c0_p3 - (c0_p2 <<< 1);

                w01 <= c1_p0 + c1_p1;
                w11 <= (c1_p3 <<< 1) + c1_p2;
                w21 <= c1_p0 - c1_p1;
                w31 <= c1_p3 - (c1_p2 <<< 1);

                w02 <= c2_p0 + c2_p1;
                w12 <= (c2_p3 <<< 1) + c2_p2;
                w22 <= c2_p0 - c2_p1;
                w32 <= c2_p3 - (c2_p2 <<< 1);

                w03 <= c3_p0 + c3_p1;
                w13 <= (c3_p3 <<< 1) + c3_p2;
                w23 <= c3_p0 - c3_p1;
                w33 <= c3_p3 - (c3_p2 <<< 1);
            end
        end
    end

endmodule
