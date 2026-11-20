`timescale 1ns / 1ps

module tb_model4_yuv420_source_frontend;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg frame_start = 1'b0;
    reg [15:0] src_width = 16'd4;
    reg [15:0] src_height = 16'd4;
    reg [63:0] s_data = 64'd0;
    reg s_valid = 1'b0;
    reg s_last = 1'b0;
    wire s_ready;

    wire [7:0] y_data, u_data, v_data;
    wire y_valid, u_valid, v_valid;
    wire y_last, u_last, v_last;
    reg y_ready = 1'b1, u_ready = 1'b1, v_ready = 1'b1;
    integer y_count = 0, u_count = 0, v_count = 0;

    model4_yuv420_source_frontend dut (
        .clk(clk), .resetn(resetn), .frame_start(frame_start),
        .src_width(src_width), .src_height(src_height),
        .s_axis_tdata(s_data), .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready), .s_axis_tlast(s_last),
        .m_y_tdata(y_data), .m_y_tvalid(y_valid), .m_y_tready(y_ready),
        .m_y_tlast(y_last), .m_u_tdata(u_data), .m_u_tvalid(u_valid),
        .m_u_tready(u_ready), .m_u_tlast(u_last), .m_v_tdata(v_data),
        .m_v_tvalid(v_valid), .m_v_tready(v_ready), .m_v_tlast(v_last)
    );

    task send_word;
        input [63:0] data;
        input last;
        begin
            @(negedge clk);
            s_data = data;
            s_last = last;
            s_valid = 1'b1;
            while (!s_ready) @(negedge clk);
            @(negedge clk);
            s_valid = 1'b0;
            s_last = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (y_valid && y_ready) begin
            assert(y_data == y_count[7:0]);
            assert(y_last == (y_count == 15));
            y_count <= y_count + 1;
        end
        if (u_valid && u_ready) begin
            assert(u_data == 8'd16 + u_count);
            assert(u_last == (u_count == 3));
            u_count <= u_count + 1;
        end
        if (v_valid && v_ready) begin
            assert(v_data == 8'd20 + v_count);
            assert(v_last == (v_count == 3));
            v_count <= v_count + 1;
        end
    end

    initial begin
        repeat (2) @(negedge clk);
        resetn = 1'b1;
        @(negedge clk);
        frame_start = 1'b1;
        @(negedge clk);
        frame_start = 1'b0;

        // Bytes 16..23 contain U and V, exercising a plane boundary in a word.
        send_word(64'h0706050403020100, 1'b0);
        send_word(64'h0F0E0D0C0B0A0908, 1'b0);
        send_word(64'h1716151413121110, 1'b1);

        repeat (20) @(posedge clk);
        assert(y_count == 16);
        assert(u_count == 4);
        assert(v_count == 4);
        $display("tb_model4_yuv420_source_frontend: PASS");
        $finish;
    end
endmodule
