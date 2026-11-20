`timescale 1ns / 1ps

// Model 4 planar YUV420 scaler.
//
// The three planes are streamed independently so the source reader can
// schedule luma and chroma bursts from DDR without converting the video back
// to RGB. Each plane uses the same nearest-neighbour coordinate selection and
// AXI-Stream backpressure rules.
module model4_yuv420_scaler (
    input wire         clk,
    input wire         resetn,
    input wire         frame_start,
    input wire [15:0]  src_width,
    input wire [15:0]  src_height,
    input wire [15:0]  dst_width,
    input wire [15:0]  dst_height,

    input wire [7:0]   s_y_tdata,
    input wire         s_y_tvalid,
    output wire        s_y_tready,
    input wire         s_y_tlast,
    output wire [7:0]  m_y_tdata,
    output wire        m_y_tvalid,
    input wire         m_y_tready,
    output wire        m_y_tlast,

    input wire [7:0]   s_u_tdata,
    input wire         s_u_tvalid,
    output wire        s_u_tready,
    input wire         s_u_tlast,
    output wire [7:0]  m_u_tdata,
    output wire        m_u_tvalid,
    input wire         m_u_tready,
    output wire        m_u_tlast,

    input wire [7:0]   s_v_tdata,
    input wire         s_v_tvalid,
    output wire        s_v_tready,
    input wire         s_v_tlast,
    output wire [7:0]  m_v_tdata,
    output wire        m_v_tvalid,
    input wire         m_v_tready,
    output wire        m_v_tlast
);
    video_scaler #(.PIXEL_WIDTH(8)) y_scaler (
        .clk(clk),
        .resetn(resetn),
        .src_width(src_width),
        .src_height(src_height),
        .dst_width(dst_width),
        .dst_height(dst_height),
        .frame_start(frame_start),
        .s_axis_tdata(s_y_tdata),
        .s_axis_tvalid(s_y_tvalid),
        .s_axis_tready(s_y_tready),
        .s_axis_tlast(s_y_tlast),
        .m_axis_tdata(m_y_tdata),
        .m_axis_tvalid(m_y_tvalid),
        .m_axis_tready(m_y_tready),
        .m_axis_tlast(m_y_tlast)
    );

    video_scaler #(.PIXEL_WIDTH(8)) u_scaler (
        .clk(clk),
        .resetn(resetn),
        .src_width(src_width >> 1),
        .src_height(src_height >> 1),
        .dst_width(dst_width >> 1),
        .dst_height(dst_height >> 1),
        .frame_start(frame_start),
        .s_axis_tdata(s_u_tdata),
        .s_axis_tvalid(s_u_tvalid),
        .s_axis_tready(s_u_tready),
        .s_axis_tlast(s_u_tlast),
        .m_axis_tdata(m_u_tdata),
        .m_axis_tvalid(m_u_tvalid),
        .m_axis_tready(m_u_tready),
        .m_axis_tlast(m_u_tlast)
    );

    video_scaler #(.PIXEL_WIDTH(8)) v_scaler (
        .clk(clk),
        .resetn(resetn),
        .src_width(src_width >> 1),
        .src_height(src_height >> 1),
        .dst_width(dst_width >> 1),
        .dst_height(dst_height >> 1),
        .frame_start(frame_start),
        .s_axis_tdata(s_v_tdata),
        .s_axis_tvalid(s_v_tvalid),
        .s_axis_tready(s_v_tready),
        .s_axis_tlast(s_v_tlast),
        .m_axis_tdata(m_v_tdata),
        .m_axis_tvalid(m_v_tvalid),
        .m_axis_tready(m_v_tready),
        .m_axis_tlast(m_v_tlast)
    );
endmodule
