`timescale 1ns / 1ps

// Model 4 source-to-tile FPGA path:
// packed planar YUV420 input -> plane streams -> hardware scaler ->
// encoder-compatible 384-byte macroblock words.
module model4_source_to_tiles #(
    parameter integer MAX_WIDTH  = 64,
    parameter integer MAX_HEIGHT = 64
) (
    input wire         clk,
    input wire         resetn,
    input wire         frame_start,
    input wire [15:0]  src_width,
    input wire [15:0]  src_height,
    input wire [15:0]  target_width,
    input wire [15:0]  target_height,

    input wire [63:0]  s_axis_tdata,
    input wire         s_axis_tvalid,
    output wire        s_axis_tready,
    input wire         s_axis_tlast,

    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input wire         m_axis_tready,
    output wire        m_axis_tlast,
    output wire        busy,
    output wire        error
);
    wire [7:0] source_y_data, source_u_data, source_v_data;
    wire source_y_valid, source_u_valid, source_v_valid;
    wire source_y_ready, source_u_ready, source_v_ready;
    wire source_y_last, source_u_last, source_v_last;
    wire [7:0] scaled_y_data, scaled_u_data, scaled_v_data;
    wire scaled_y_valid, scaled_u_valid, scaled_v_valid;
    wire scaled_y_ready, scaled_u_ready, scaled_v_ready;
    wire scaled_y_last, scaled_u_last, scaled_v_last;
    wire pack_busy;
    wire pack_error;

    model4_yuv420_source_frontend source_frontend (
        .clk(clk),
        .resetn(resetn),
        .frame_start(frame_start),
        .src_width(src_width),
        .src_height(src_height),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_y_tdata(source_y_data),
        .m_y_tvalid(source_y_valid),
        .m_y_tready(source_y_ready),
        .m_y_tlast(source_y_last),
        .m_u_tdata(source_u_data),
        .m_u_tvalid(source_u_valid),
        .m_u_tready(source_u_ready),
        .m_u_tlast(source_u_last),
        .m_v_tdata(source_v_data),
        .m_v_tvalid(source_v_valid),
        .m_v_tready(source_v_ready),
        .m_v_tlast(source_v_last)
    );

    model4_yuv420_scaler scaler (
        .clk(clk),
        .resetn(resetn),
        .frame_start(frame_start),
        .src_width(src_width),
        .src_height(src_height),
        .dst_width(target_width),
        .dst_height(target_height),
        .s_y_tdata(source_y_data),
        .s_y_tvalid(source_y_valid),
        .s_y_tready(source_y_ready),
        .s_y_tlast(source_y_last),
        .m_y_tdata(scaled_y_data),
        .m_y_tvalid(scaled_y_valid),
        .m_y_tready(scaled_y_ready),
        .m_y_tlast(scaled_y_last),
        .s_u_tdata(source_u_data),
        .s_u_tvalid(source_u_valid),
        .s_u_tready(source_u_ready),
        .s_u_tlast(source_u_last),
        .m_u_tdata(scaled_u_data),
        .m_u_tvalid(scaled_u_valid),
        .m_u_tready(scaled_u_ready),
        .m_u_tlast(scaled_u_last),
        .s_v_tdata(source_v_data),
        .s_v_tvalid(source_v_valid),
        .s_v_tready(source_v_ready),
        .s_v_tlast(source_v_last),
        .m_v_tdata(scaled_v_data),
        .m_v_tvalid(scaled_v_valid),
        .m_v_tready(scaled_v_ready),
        .m_v_tlast(scaled_v_last)
    );

    model4_yuv420_macroblock_packer #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_HEIGHT(MAX_HEIGHT)
    ) packer (
        .clk(clk),
        .resetn(resetn),
        .frame_start(frame_start),
        .target_width(target_width),
        .target_height(target_height),
        .s_y_tdata(scaled_y_data),
        .s_y_tvalid(scaled_y_valid),
        .s_y_tready(scaled_y_ready),
        .s_y_tlast(scaled_y_last),
        .s_u_tdata(scaled_u_data),
        .s_u_tvalid(scaled_u_valid),
        .s_u_tready(scaled_u_ready),
        .s_u_tlast(scaled_u_last),
        .s_v_tdata(scaled_v_data),
        .s_v_tvalid(scaled_v_valid),
        .s_v_tready(scaled_v_ready),
        .s_v_tlast(scaled_v_last),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .busy(pack_busy),
        .error(pack_error)
    );

    assign busy = pack_busy;
    assign error = pack_error;
endmodule
