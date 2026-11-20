`timescale 1ns / 1ps

module tb_model4_yuv420_scaler;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg frame_start = 1'b0;
    reg [15:0] src_width = 16'd4;
    reg [15:0] src_height = 16'd4;
    reg [15:0] dst_width = 16'd2;
    reg [15:0] dst_height = 16'd2;

    reg [7:0] y_data = 0, u_data = 0, v_data = 0;
    reg y_valid = 0, u_valid = 0, v_valid = 0;
    reg y_last = 0, u_last = 0, v_last = 0;
    wire y_ready, u_ready, v_ready;
    wire [7:0] y_out, u_out, v_out;
    wire y_out_valid, u_out_valid, v_out_valid;
    wire y_out_last, u_out_last, v_out_last;
    integer y_count = 0;
    integer u_count = 0;
    integer v_count = 0;

    model4_yuv420_scaler dut (
        .clk(clk), .resetn(resetn), .frame_start(frame_start),
        .src_width(src_width), .src_height(src_height),
        .dst_width(dst_width), .dst_height(dst_height),
        .s_y_tdata(y_data), .s_y_tvalid(y_valid), .s_y_tready(y_ready),
        .s_y_tlast(y_last), .m_y_tdata(y_out), .m_y_tvalid(y_out_valid),
        .m_y_tready(1'b1), .m_y_tlast(y_out_last),
        .s_u_tdata(u_data), .s_u_tvalid(u_valid), .s_u_tready(u_ready),
        .s_u_tlast(u_last), .m_u_tdata(u_out), .m_u_tvalid(u_out_valid),
        .m_u_tready(1'b1), .m_u_tlast(u_out_last),
        .s_v_tdata(v_data), .s_v_tvalid(v_valid), .s_v_tready(v_ready),
        .s_v_tlast(v_last), .m_v_tdata(v_out), .m_v_tvalid(v_out_valid),
        .m_v_tready(1'b1), .m_v_tlast(v_out_last)
    );

    task send_plane_pixel;
        input integer plane;
        input [7:0] pixel;
        input last;
        begin
            @(negedge clk);
            if (plane == 0) begin
                y_data = pixel; y_last = last; y_valid = 1'b1;
                while (!y_ready) @(negedge clk);
            end else if (plane == 1) begin
                u_data = pixel; u_last = last; u_valid = 1'b1;
                while (!u_ready) @(negedge clk);
            end else begin
                v_data = pixel; v_last = last; v_valid = 1'b1;
                while (!v_ready) @(negedge clk);
            end
            @(negedge clk);
            y_valid = 1'b0; u_valid = 1'b0; v_valid = 1'b0;
            y_last = 1'b0; u_last = 1'b0; v_last = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (y_out_valid) begin
            if (y_count == 0) assert(y_out == 8'd0);
            if (y_count == 1) assert(y_out == 8'd2);
            if (y_count == 2) assert(y_out == 8'd8);
            if (y_count == 3) begin assert(y_out == 8'd10); assert(y_out_last); end
            y_count <= y_count + 1;
        end
        if (u_out_valid) begin
            if (u_count == 0) assert(u_out == 8'd0);
            if (u_count == 0) assert(u_out_last);
            u_count <= u_count + 1;
        end
        if (v_out_valid) begin
            if (v_count == 0) assert(v_out == 8'd0);
            if (v_count == 0) assert(v_out_last);
            v_count <= v_count + 1;
        end
    end

    integer i;
    initial begin
        repeat (2) @(negedge clk);
        resetn = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            send_plane_pixel(0, i[7:0], (i % 4) == 3);
        end
        for (i = 0; i < 4; i = i + 1) begin
            send_plane_pixel(1, i[7:0], (i % 4) == 3);
        end
        for (i = 0; i < 4; i = i + 1) begin
            send_plane_pixel(2, i[7:0], (i % 4) == 3);
        end
        repeat (4) @(posedge clk);
        assert(y_count == 4);
        assert(u_count == 1);
        assert(v_count == 1);
        $display("tb_model4_yuv420_scaler: PASS");
        $finish;
    end
endmodule
