// =============================================================================
// Module: streaming_scaler
// Description: Synthesizable Streaming Spatial Downscaler for Video Accelerator
// Downscales high-resolution video (720p, 1080p, 4K, 8K) to 240p or 144p
// Matches Section 9, 21, 22, 23 of Master Project Specification
// =============================================================================

`timescale 1ns / 1ps

module streaming_scaler #(
    parameter integer DATA_WIDTH = 24, // 24-bit RGB or 8-bit Y/U/V
    parameter integer MAX_WIDTH  = 8192
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Control Configuration
    input  wire [15:0]            src_width,
    input  wire [15:0]            src_height,
    input  wire [15:0]            tgt_width,
    input  wire [15:0]            tgt_height,
    input  wire [7:0]             scaler_mode, // 0=Bilinear/Interpolate, 1=Decimate

    // AXI4-Stream Input (High Resolution Source)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast, // End of source scanline

    // AXI4-Stream Output (Downscaled Video Stream: 240p / 144p)
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast  // End of target scanline
);

    // Coordinate & Accumulator Counters (16-bit integer, 16-bit fractional)
    reg [15:0] in_x;
    reg [15:0] in_y;
    reg [15:0] out_x;
    reg [15:0] out_y;

    reg [31:0] acc_x;
    reg [31:0] acc_y;
    reg [31:0] step_x;
    reg [31:0] step_y;

    // Previous pixel for horizontal interpolation
    reg [DATA_WIDTH-1:0] prev_pixel;

    assign s_axis_tready = (!m_axis_tvalid) || m_axis_tready;

    // Calculate fixed-point step size: (src << 16) / tgt
    always @(posedge clk) begin
        if (!rst_n) begin
            step_x <= 32'h00010000;
            step_y <= 32'h00010000;
        end else begin
            if (tgt_width > 0 && tgt_height > 0) begin
                step_x <= ((src_width << 16) / tgt_width);
                step_y <= ((src_height << 16) / tgt_height);
            end
        end
    end

    wire sample_h_match = (in_x == (acc_x[31:16]));
    wire sample_v_match = (in_y == (acc_y[31:16]));

    always @(posedge clk) begin
        if (!rst_n) begin
            in_x          <= 16'd0;
            in_y          <= 16'd0;
            out_x         <= 16'd0;
            out_y         <= 16'd0;
            acc_x         <= 32'd0;
            acc_y         <= 32'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tlast  <= 1'b0;
            prev_pixel    <= {DATA_WIDTH{1'b0}};
        end else begin
            // Clear valid on downstream consumption
            if (m_axis_tready && m_axis_tvalid) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end

            // Process incoming streaming pixel
            if (s_axis_tvalid && s_axis_tready) begin
                prev_pixel <= s_axis_tdata;

                // Check if incoming pixel lands on target sampling grid
                if (sample_v_match && sample_h_match && (out_x < tgt_width) && (out_y < tgt_height)) begin
                    m_axis_tvalid <= 1'b1;
                    
                    // Mode 0: 2-tap linear average with neighbor; Mode 1: direct decimate
                    if (scaler_mode == 8'd0 && in_x > 0) begin
                        // 8-bit per channel average: (P0 + P1) >> 1
                        m_axis_tdata[7:0]   <= (s_axis_tdata[7:0]   + prev_pixel[7:0])   >> 1;
                        m_axis_tdata[15:8]  <= (s_axis_tdata[15:8]  + prev_pixel[15:8])  >> 1;
                        m_axis_tdata[23:16] <= (s_axis_tdata[23:16] + prev_pixel[23:16]) >> 1;
                    end else begin
                        m_axis_tdata <= s_axis_tdata;
                    end

                    // Target scanline end flag
                    if (out_x == tgt_width - 1) begin
                        m_axis_tlast <= 1'b1;
                        out_x        <= 16'd0;
                        acc_x        <= 32'd0;
                    end else begin
                        m_axis_tlast <= 1'b0;
                        out_x        <= out_x + 1'b1;
                        acc_x        <= acc_x + step_x;
                    end
                end

                // Horizontal source position update
                if (s_axis_tlast || (in_x == src_width - 1)) begin
                    in_x  <= 16'd0;
                    acc_x <= 32'd0;
                    if (in_y == src_height - 1) begin
                        in_y  <= 16'd0;
                        out_y <= 16'd0;
                        acc_y <= 32'd0;
                    end else begin
                        in_y <= in_y + 1'b1;
                        if (sample_v_match && out_y < tgt_height - 1) begin
                            out_y <= out_y + 1'b1;
                            acc_y <= acc_y + step_y;
                        end
                    end
                end else begin
                    in_x <= in_x + 1'b1;
                end
            end
        end
    end

endmodule
