`timescale 1ns / 1ps

module tb_video_scaler;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg [15:0] src_width = 16'd4;
    reg [15:0] src_height = 16'd4;
    reg [15:0] dst_width = 16'd2;
    reg [15:0] dst_height = 16'd2;
    reg frame_start = 1'b0;
    reg [23:0] s_data;
    reg s_valid = 1'b0;
    wire s_ready;
    reg s_last;
    wire [23:0] m_data;
    wire m_valid;
    reg m_ready = 1'b1;
    wire m_last;
    integer output_count = 0;

    video_scaler dut (
        .clk(clk),
        .resetn(resetn),
        .src_width(src_width),
        .src_height(src_height),
        .dst_width(dst_width),
        .dst_height(dst_height),
        .frame_start(frame_start),
        .s_axis_tdata(s_data),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .s_axis_tlast(s_last),
        .m_axis_tdata(m_data),
        .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready),
        .m_axis_tlast(m_last)
    );

    task send_pixel(input [23:0] pixel, input last);
        begin
            @(negedge clk);
            s_data = pixel;
            s_last = last;
            s_valid = 1'b1;
            while (!s_ready)
                @(negedge clk);
            @(negedge clk);
            s_valid = 1'b0;
            s_last = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            output_count <= output_count + 1;
            if (output_count == 0) assert(m_data == 24'h000000);
            if (output_count == 1) assert(m_data == 24'h000002);
            if (output_count == 2) assert(m_data == 24'h000008);
            if (output_count == 3) begin
                assert(m_data == 24'h00000A);
                assert(m_last);
            end
        end
    end

    initial begin
        s_data = 24'd0;
        s_last = 1'b0;
        repeat (2) @(negedge clk);
        resetn = 1'b1;

        send_pixel(24'h000000, 1'b0);
        send_pixel(24'h000001, 1'b0);
        send_pixel(24'h000002, 1'b0);
        send_pixel(24'h000003, 1'b1);
        send_pixel(24'h000004, 1'b0);
        send_pixel(24'h000005, 1'b0);
        send_pixel(24'h000006, 1'b0);
        send_pixel(24'h000007, 1'b1);
        send_pixel(24'h000008, 1'b0);
        send_pixel(24'h000009, 1'b0);
        send_pixel(24'h00000A, 1'b0);
        send_pixel(24'h00000B, 1'b1);
        send_pixel(24'h00000C, 1'b0);
        send_pixel(24'h00000D, 1'b0);
        send_pixel(24'h00000E, 1'b0);
        send_pixel(24'h00000F, 1'b1);

        repeat (4) @(posedge clk);
        assert(output_count == 4);
        $display("tb_video_scaler: PASS");
        $finish;
    end
endmodule
