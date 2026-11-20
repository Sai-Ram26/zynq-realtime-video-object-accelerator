`timescale 1ns / 1ps

// Unpack a packed planar YUV420 AXI stream into one byte stream per plane.
//
// Input bytes are presented least-significant byte first in each 64-bit word.
// The input TLAST marks the end of the packed frame; plane TLAST is generated
// from the source dimensions, so it remains correct when a plane boundary is
// inside a 64-bit word.
module model4_yuv420_source_frontend (
    input wire         clk,
    input wire         resetn,
    input wire         frame_start,
    input wire [15:0]  src_width,
    input wire [15:0]  src_height,

    input wire [63:0]  s_axis_tdata,
    input wire         s_axis_tvalid,
    output wire        s_axis_tready,
    input wire         s_axis_tlast,

    output wire [7:0]  m_y_tdata,
    output wire        m_y_tvalid,
    input wire         m_y_tready,
    output wire        m_y_tlast,

    output wire [7:0]  m_u_tdata,
    output wire        m_u_tvalid,
    input wire         m_u_tready,
    output wire        m_u_tlast,

    output wire [7:0]  m_v_tdata,
    output wire        m_v_tvalid,
    input wire         m_v_tready,
    output wire        m_v_tlast
);
    localparam [1:0] PLANE_Y = 2'd0;
    localparam [1:0] PLANE_U = 2'd1;
    localparam [1:0] PLANE_V = 2'd2;
    localparam [1:0] PLANE_DONE = 2'd3;

    reg [63:0] word_data;
    reg [2:0] byte_index;
    reg       word_valid;
    reg [1:0] plane;
    reg [31:0] plane_offset;

    (* use_dsp = "no" *) wire [31:0] y_pixel_count = {16'd0, src_width} *
                                                      {16'd0, src_height};
    (* use_dsp = "no" *) wire [31:0] c_pixel_count = {16'd0, (src_width >> 1)} *
                                                      {16'd0, (src_height >> 1)};
    wire [31:0] y_limit = (y_pixel_count == 0) ? 32'd1 : y_pixel_count;
    wire [31:0] c_limit = (c_pixel_count == 0) ? 32'd1 : c_pixel_count;
    wire [31:0] active_limit = (plane == PLANE_Y) ? y_limit : c_limit;
    wire [7:0] current_byte = word_data[(byte_index * 8) +: 8];
    wire output_valid = word_valid && (plane != PLANE_DONE);
    wire output_ready = (plane == PLANE_Y) ? m_y_tready :
                        (plane == PLANE_U) ? m_u_tready : m_v_tready;
    wire output_fire = output_valid && output_ready;
    wire output_last = output_valid && (plane_offset + 32'd1 >= active_limit);

    assign s_axis_tready = !word_valid && (plane != PLANE_DONE);

    assign m_y_tdata  = current_byte;
    assign m_u_tdata  = current_byte;
    assign m_v_tdata  = current_byte;
    assign m_y_tvalid = output_valid && (plane == PLANE_Y);
    assign m_u_tvalid = output_valid && (plane == PLANE_U);
    assign m_v_tvalid = output_valid && (plane == PLANE_V);
    assign m_y_tlast  = output_last && (plane == PLANE_Y);
    assign m_u_tlast  = output_last && (plane == PLANE_U);
    assign m_v_tlast  = output_last && (plane == PLANE_V);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            word_data   <= 64'd0;
            byte_index  <= 3'd0;
            word_valid  <= 1'b0;
            plane       <= PLANE_Y;
            plane_offset <= 32'd0;
        end else if (frame_start) begin
            word_valid   <= 1'b0;
            byte_index   <= 3'd0;
            plane        <= PLANE_Y;
            plane_offset <= 32'd0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                word_data  <= s_axis_tdata;
                byte_index <= 3'd0;
                word_valid <= 1'b1;
            end

            if (output_fire) begin
                plane_offset <= plane_offset + 32'd1;

                if (output_last) begin
                    plane_offset <= 32'd0;
                    if (plane == PLANE_Y)
                        plane <= PLANE_U;
                    else if (plane == PLANE_U)
                        plane <= PLANE_V;
                    else
                        plane <= PLANE_DONE;
                end

                if (byte_index == 3'd7 || (plane == PLANE_V && output_last)) begin
                    word_valid <= 1'b0;
                    byte_index <= 3'd0;
                end else begin
                    byte_index <= byte_index + 3'd1;
                end
            end
        end
    end
endmodule
