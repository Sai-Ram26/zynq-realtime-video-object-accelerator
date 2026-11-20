`timescale 1ns / 1ps

// Packs raster YUV420 planes into the encoder's macroblock memory layout.
//
// The input planes are independent raster streams.  A frame_start pulse
// begins capture; each plane must contain exactly its target-sized plane and
// assert TLAST on its final byte.  The output is little-endian within each
// 64-bit word: 32 Y words, followed by 8 U words and 8 V words per
// macroblock.  Macroblocks are emitted left-to-right, top-to-bottom.
//
// This implementation uses bounded frame storage.  MAX_WIDTH and MAX_HEIGHT
// are synthesis parameters and must be at least the largest configured frame.
module model4_yuv420_macroblock_packer #(
    parameter integer MAX_WIDTH  = 64,
    parameter integer MAX_HEIGHT = 64
) (
    input wire         clk,
    input wire         resetn,
    input wire         frame_start,
    input wire [15:0]  target_width,
    input wire [15:0]  target_height,

    input wire [7:0]   s_y_tdata,
    input wire         s_y_tvalid,
    output wire        s_y_tready,
    input wire         s_y_tlast,
    input wire [7:0]   s_u_tdata,
    input wire         s_u_tvalid,
    output wire        s_u_tready,
    input wire         s_u_tlast,
    input wire [7:0]   s_v_tdata,
    input wire         s_v_tvalid,
    output wire        s_v_tready,
    input wire         s_v_tlast,

    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input wire         m_axis_tready,
    output wire        m_axis_tlast,
    output wire        busy,
    output reg         error
);
    localparam integer MAX_PIXELS = MAX_WIDTH * MAX_HEIGHT;
    localparam integer MAX_CHROMA_PIXELS = (MAX_WIDTH / 2) * (MAX_HEIGHT / 2);
    localparam integer MAX_Y_WORDS = (MAX_PIXELS + 7) / 8;
    localparam integer MAX_C_WORDS = (MAX_CHROMA_PIXELS + 7) / 8;
    localparam [1:0] ST_IDLE = 2'd0, ST_CAPTURE = 2'd1, ST_EMIT = 2'd2;

    reg [1:0] state;
    (* use_dsp = "no" *) reg [15:0] width_r, height_r;
    reg [31:0] y_count, u_count, v_count;
    (* use_dsp = "no" *) reg [31:0] y_limit, c_limit;
    reg y_seen_last, u_seen_last, v_seen_last;
    reg [15:0] mb_x, mb_y;
    reg [5:0] emit_word;
    reg output_valid;
    reg [63:0] output_data;
    reg output_last;
    reg read_pending;
    // Bank by byte lane so each 64-bit output word is a parallel read from
    // eight isolated synchronous RAMs. This keeps large target frames in BRAM.
    wire [7:0] y_mem0, y_mem1, y_mem2, y_mem3;
    wire [7:0] y_mem4, y_mem5, y_mem6, y_mem7;
    wire [7:0] u_mem0, u_mem1, u_mem2, u_mem3;
    wire [7:0] u_mem4, u_mem5, u_mem6, u_mem7;
    wire [7:0] v_mem0, v_mem1, v_mem2, v_mem3;
    wire [7:0] v_mem4, v_mem5, v_mem6, v_mem7;

    wire y_fire = s_y_tvalid && s_y_tready;
    wire u_fire = s_u_tvalid && s_u_tready;
    wire v_fire = s_v_tvalid && s_v_tready;
    wire dimensions_ok = (target_width != 0) && (target_height != 0) &&
                         ((target_width & 16'd15) == 0) &&
                         ((target_height & 16'd15) == 0) &&
                         (target_width <= MAX_WIDTH) &&
                         (target_height <= MAX_HEIGHT);
    wire capture_complete = (y_count >= y_limit) && (u_count >= c_limit) &&
                            (v_count >= c_limit);

    assign busy = (state != ST_IDLE);
    assign s_y_tready = (state == ST_CAPTURE) && (y_count < y_limit);
    assign s_u_tready = (state == ST_CAPTURE) && (u_count < c_limit);
    assign s_v_tready = (state == ST_CAPTURE) && (v_count < c_limit);

    (* use_dsp = "no" *) integer read_word_index;
    integer row_in_mb;
    integer word_in_row;
    (* use_dsp = "no" *) integer base_index;
    wire output_fire = output_valid && m_axis_tready;
    wire [31:0] read_word_addr = read_word_index;

    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram0 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd0)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem0));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram1 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd1)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem1));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram2 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd2)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem2));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram3 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd3)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem3));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram4 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd4)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem4));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram5 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd5)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem5));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram6 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd6)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem6));
    model4_byte_ram #(.DEPTH(MAX_Y_WORDS)) y_ram7 (
        .clk(clk), .we(y_fire && (y_count[2:0] == 3'd7)),
        .waddr(y_count / 8), .wdata(s_y_tdata), .raddr(read_word_addr), .rdata(y_mem7));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram0 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd0)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem0));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram1 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd1)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem1));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram2 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd2)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem2));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram3 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd3)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem3));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram4 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd4)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem4));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram5 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd5)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem5));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram6 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd6)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem6));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) u_ram7 (
        .clk(clk), .we(u_fire && (u_count[2:0] == 3'd7)),
        .waddr(u_count / 8), .wdata(s_u_tdata), .raddr(read_word_addr), .rdata(u_mem7));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram0 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd0)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem0));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram1 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd1)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem1));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram2 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd2)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem2));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram3 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd3)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem3));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram4 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd4)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem4));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram5 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd5)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem5));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram6 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd6)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem6));
    model4_byte_ram #(.DEPTH(MAX_C_WORDS)) v_ram7 (
        .clk(clk), .we(v_fire && (v_count[2:0] == 3'd7)),
        .waddr(v_count / 8), .wdata(s_v_tdata), .raddr(read_word_addr), .rdata(v_mem7));
    always @* begin
        read_word_index = 0;
        row_in_mb = 0;
        word_in_row = 0;
        base_index = 0;
        if (state == ST_EMIT) begin
            if (emit_word < 6'd32) begin
                row_in_mb = emit_word / 2;
                word_in_row = emit_word % 2;
                base_index = ((mb_y * 16 + row_in_mb) * width_r) +
                             (mb_x * 16) + (word_in_row * 8);
                read_word_index = base_index / 8;
            end else if (emit_word < 6'd40) begin
                row_in_mb = emit_word - 6'd32;
                base_index = ((mb_y * 8 + row_in_mb) * (width_r / 2)) +
                             (mb_x * 8);
                read_word_index = base_index / 8;
            end else begin
                row_in_mb = emit_word - 6'd40;
                base_index = ((mb_y * 8 + row_in_mb) * (width_r / 2)) +
                             (mb_x * 8);
                read_word_index = base_index / 8;
            end
        end
    end
    assign m_axis_tdata = output_data;
    assign m_axis_tvalid = output_valid;
    assign m_axis_tlast = output_valid && output_last;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= ST_IDLE;
            width_r <= 0;
            height_r <= 0;
            y_count <= 0;
            u_count <= 0;
            v_count <= 0;
            y_limit <= 0;
            c_limit <= 0;
            y_seen_last <= 0;
            u_seen_last <= 0;
            v_seen_last <= 0;
            mb_x <= 0;
            mb_y <= 0;
            emit_word <= 0;
            output_valid <= 0;
            output_data <= 0;
            output_last <= 0;
            read_pending <= 0;
            error <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (frame_start) begin
                        error <= !dimensions_ok;
                        width_r <= target_width;
                        height_r <= target_height;
                        y_limit <= {16'd0, target_width} *
                                   {16'd0, target_height};
                        c_limit <= {16'd0, (target_width / 2)} *
                                   {16'd0, (target_height / 2)};
                        y_count <= 0;
                        u_count <= 0;
                        v_count <= 0;
                        y_seen_last <= 0;
                        u_seen_last <= 0;
                        v_seen_last <= 0;
                        mb_x <= 0;
                        mb_y <= 0;
                        emit_word <= 0;
                        if (dimensions_ok)
                            state <= ST_CAPTURE;
                    end
                end
                ST_CAPTURE: begin
                    if (y_fire) begin
                        y_count <= y_count + 1;
                        y_seen_last <= y_seen_last || s_y_tlast;
                        if (s_y_tlast && (y_count + 1 != y_limit))
                            error <= 1'b1;
                    end
                    if (u_fire) begin
                        u_count <= u_count + 1;
                        u_seen_last <= u_seen_last || s_u_tlast;
                        if (s_u_tlast && (u_count + 1 != c_limit))
                            error <= 1'b1;
                    end
                    if (v_fire) begin
                        v_count <= v_count + 1;
                        v_seen_last <= v_seen_last || s_v_tlast;
                        if (s_v_tlast && (v_count + 1 != c_limit))
                            error <= 1'b1;
                    end
                    if (capture_complete) begin
                        if (!y_seen_last || !u_seen_last || !v_seen_last)
                            error <= 1'b1;
                        mb_x <= 0;
                        mb_y <= 0;
                        emit_word <= 0;
                        output_valid <= 0;
                        read_pending <= 0;
                        state <= ST_EMIT;
                    end
                end
                ST_EMIT: begin
                    if (!output_valid) begin
                        if (read_pending) begin
                            if (emit_word < 6'd32)
                                output_data <= {y_mem7, y_mem6, y_mem5, y_mem4,
                                                y_mem3, y_mem2, y_mem1, y_mem0};
                            else if (emit_word < 6'd40)
                                output_data <= {u_mem7, u_mem6, u_mem5, u_mem4,
                                                u_mem3, u_mem2, u_mem1, u_mem0};
                            else
                                output_data <= {v_mem7, v_mem6, v_mem5, v_mem4,
                                                v_mem3, v_mem2, v_mem1, v_mem0};
                            output_last <= (mb_x == (width_r / 16 - 1)) &&
                                           (mb_y == (height_r / 16 - 1)) &&
                                           (emit_word == 6'd47);
                            output_valid <= 1;
                            read_pending <= 0;
                        end else begin
                            read_pending <= 1;
                        end
                    end else if (output_fire) begin
                        output_valid <= 0;
                        if (emit_word == 6'd47) begin
                            emit_word <= 0;
                            if (mb_x == (width_r / 16 - 1)) begin
                                mb_x <= 0;
                                if (mb_y == (height_r / 16 - 1))
                                    state <= ST_IDLE;
                                else
                                    mb_y <= mb_y + 1;
                            end else begin
                                mb_x <= mb_x + 1;
                            end
                        end else begin
                            emit_word <= emit_word + 1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

module model4_byte_ram #(
    parameter integer DEPTH = 1024,
    parameter integer ADDR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
    input wire clk,
    input wire we,
    input wire [31:0] waddr,
    input wire [7:0] wdata,
    input wire [31:0] raddr,
    output reg [7:0] rdata
);
    (* ram_style = "block" *) reg [7:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr[ADDR_WIDTH-1:0]] <= wdata;
        rdata <= mem[raddr[ADDR_WIDTH-1:0]];
    end
endmodule
