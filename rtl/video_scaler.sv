`timescale 1ns / 1ps

// Model 4 streaming nearest-neighbour scaler.
//
// The scaler is intentionally independent of the H.264 block encoder so it
// can be verified at the AXI-Stream boundary before integration. Input pixels
// are packed as RGB888 or YUV444 according to the surrounding pipeline.
module video_scaler #(
    parameter integer PIXEL_WIDTH = 24
) (
    input  wire                   clk,
    input  wire                   resetn,

    input  wire [15:0]            src_width,
    input  wire [15:0]            src_height,
    input  wire [15:0]            dst_width,
    input  wire [15:0]            dst_height,
    input  wire                   frame_start,

    input  wire [PIXEL_WIDTH-1:0] s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,

    output reg  [PIXEL_WIDTH-1:0] m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast
);

    reg [15:0] src_x;
    reg [15:0] src_y;
    reg [15:0] dst_x;
    reg [15:0] dst_y;
    reg [15:0] next_src_x;
    reg [15:0] next_src_y;
    reg [15:0] x_step;
    reg [15:0] y_step;
    reg [15:0] x_remainder_step;
    reg [15:0] y_remainder_step;
    reg [16:0] x_remainder;
    reg [16:0] y_remainder;
    reg config_busy;
    reg [4:0] div_count;
    reg [15:0] div_src_width;
    reg [15:0] div_src_height;
    reg [15:0] div_dst_width;
    reg [15:0] div_dst_height;
    reg [16:0] div_x_rem;
    reg [16:0] div_y_rem;
    reg [15:0] div_x_quot;
    reg [15:0] div_y_quot;

    wire output_stalled = m_axis_tvalid && !m_axis_tready;
    assign s_axis_tready = !output_stalled && !config_busy;

    // Registered phase accumulators implement floor(dst * src / dst)
    // without a multiply/divide datapath in the pixel-rate path.
    wire select_pixel = (src_x == next_src_x) &&
                        (src_y == next_src_y);
    wire [16:0] x_remainder_sum = x_remainder + x_remainder_step;
    wire [16:0] y_remainder_sum = y_remainder + y_remainder_step;
    wire [16:0] x_div_trial =
        {div_x_rem[15:0], div_src_width[div_count - 1'b1]};
    wire [16:0] y_div_trial =
        {div_y_rem[15:0], div_src_height[div_count - 1'b1]};
    wire x_div_ge = (x_div_trial >= {1'b0, div_dst_width});
    wire y_div_ge = (y_div_trial >= {1'b0, div_dst_height});
    wire [16:0] x_div_next_rem =
        x_div_ge ? (x_div_trial - {1'b0, div_dst_width}) : x_div_trial;
    wire [16:0] y_div_next_rem =
        y_div_ge ? (y_div_trial - {1'b0, div_dst_height}) : y_div_trial;
    wire [15:0] x_div_next_quot =
        div_x_quot | (x_div_ge ? (16'd1 << (div_count - 1'b1)) : 16'd0);
    wire [15:0] y_div_next_quot =
        div_y_quot | (y_div_ge ? (16'd1 << (div_count - 1'b1)) : 16'd0);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            src_x         <= 16'd0;
            src_y         <= 16'd0;
            dst_x         <= 16'd0;
            dst_y         <= 16'd0;
            next_src_x    <= 16'd0;
            next_src_y    <= 16'd0;
            x_step        <= 16'd0;
            y_step        <= 16'd0;
            x_remainder_step <= 16'd0;
            y_remainder_step <= 16'd0;
            x_remainder   <= 17'd0;
            y_remainder   <= 17'd0;
            config_busy   <= 1'b0;
            div_count     <= 5'd0;
            div_src_width <= 16'd0;
            div_src_height <= 16'd0;
            div_dst_width <= 16'd1;
            div_dst_height <= 16'd1;
            div_x_rem     <= 17'd0;
            div_y_rem     <= 17'd0;
            div_x_quot    <= 16'd0;
            div_y_quot    <= 16'd0;
            m_axis_tdata  <= {PIXEL_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (frame_start) begin
                src_x         <= 16'd0;
                src_y         <= 16'd0;
                dst_x         <= 16'd0;
                dst_y         <= 16'd0;
                next_src_x    <= 16'd0;
                next_src_y    <= 16'd0;
                x_step        <= 16'd0;
                y_step        <= 16'd0;
                x_remainder_step <= 16'd0;
                y_remainder_step <= 16'd0;
                x_remainder   <= 17'd0;
                y_remainder   <= 17'd0;
                div_src_width <= src_width;
                div_src_height <= src_height;
                div_dst_width <= (dst_width == 0) ? 16'd1 : dst_width;
                div_dst_height <= (dst_height == 0) ? 16'd1 : dst_height;
                div_x_rem <= 17'd0;
                div_y_rem <= 17'd0;
                div_x_quot <= 16'd0;
                div_y_quot <= 16'd0;
                div_count <= 5'd16;
                config_busy <= 1'b1;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end else if (config_busy) begin
                div_x_rem <= x_div_next_rem;
                div_y_rem <= y_div_next_rem;
                div_x_quot <= x_div_next_quot;
                div_y_quot <= y_div_next_quot;
                if (div_count == 5'd1) begin
                    x_step <= x_div_next_quot;
                    y_step <= y_div_next_quot;
                    x_remainder_step <= x_div_next_rem[15:0];
                    y_remainder_step <= y_div_next_rem[15:0];
                    config_busy <= 1'b0;
                    div_count <= 5'd0;
                end else begin
                    div_count <= div_count - 1'b1;
                end
            end else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                if (select_pixel && !m_axis_tvalid) begin
                    m_axis_tdata  <= s_axis_tdata;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= (dst_x + 16'd1 >= dst_width) &&
                                     (dst_y + 16'd1 >= dst_height);

                    if (dst_x + 16'd1 >= dst_width) begin
                        dst_x <= 16'd0;
                        next_src_x <= 16'd0;
                        x_remainder <= 17'd0;
                        if (dst_y + 16'd1 < dst_height)
                            begin
                                dst_y <= dst_y + 16'd1;
                                if (y_remainder_sum >= dst_height) begin
                                    next_src_y <= next_src_y + y_step + 16'd1;
                                    y_remainder <= y_remainder_sum - dst_height;
                                end else begin
                                    next_src_y <= next_src_y + y_step;
                                    y_remainder <= y_remainder_sum;
                                end
                            end
                    end else begin
                        dst_x <= dst_x + 16'd1;
                        if (x_remainder_sum >= dst_width) begin
                            next_src_x <= next_src_x + x_step + 16'd1;
                            x_remainder <= x_remainder_sum - dst_width;
                        end else begin
                            next_src_x <= next_src_x + x_step;
                            x_remainder <= x_remainder_sum;
                        end
                    end
                end

                if (s_axis_tlast || src_x + 16'd1 >= src_width) begin
                    src_x <= 16'd0;
                    if (src_y + 16'd1 < src_height)
                        src_y <= src_y + 16'd1;
                    else
                        src_y <= 16'd0;
                end else begin
                    src_x <= src_x + 16'd1;
                end
            end
        end
    end
endmodule
