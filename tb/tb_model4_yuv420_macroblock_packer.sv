`timescale 1ns / 1ps

module tb_model4_yuv420_macroblock_packer;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0, frame_start = 0;
    reg [15:0] width = 16, height = 16;
    reg [7:0] yd, ud, vd;
    reg yv = 0, uv = 0, vv = 0, yl = 0, ul = 0, vl = 0;
    wire yr, ur, vr;
    wire [63:0] od;
    wire ov, ol, busy, error;
    integer i, words;

    model4_yuv420_macroblock_packer #(.MAX_WIDTH(32), .MAX_HEIGHT(32)) dut (
        .clk(clk), .resetn(resetn), .frame_start(frame_start),
        .target_width(width), .target_height(height),
        .s_y_tdata(yd), .s_y_tvalid(yv), .s_y_tready(yr), .s_y_tlast(yl),
        .s_u_tdata(ud), .s_u_tvalid(uv), .s_u_tready(ur), .s_u_tlast(ul),
        .s_v_tdata(vd), .s_v_tvalid(vv), .s_v_tready(vr), .s_v_tlast(vl),
        .m_axis_tdata(od), .m_axis_tvalid(ov), .m_axis_tready(1'b1),
        .m_axis_tlast(ol), .busy(busy), .error(error)
    );

    task send_y;
        input integer n;
        begin @(negedge clk); yd=n; yv=1; yl=(n==255);
            while (!yr) @(negedge clk); @(negedge clk); yv=0; yl=0; end
    endtask
    task send_c;
        input integer n;
        input integer plane;
        begin @(negedge clk);
            if (plane==0) begin ud=n; uv=1; ul=(n==63); end
            else begin vd=n; vv=1; vl=(n==63); end
            if (plane==0) begin while (!ur) @(negedge clk); end
            else begin while (!vr) @(negedge clk); end
            @(negedge clk); uv=0; vv=0; ul=0; vl=0;
        end
    endtask

    always @(posedge clk) if (ov) begin
        if (words == 0) assert(od == 64'h0706050403020100);
        if (words == 32) assert(od == 64'h0706050403020100);
        if (words == 40) assert(od == 64'h0706050403020100);
        if (words == 47) assert(ol);
        words <= words + 1;
    end

    initial begin
        words = 0;
        repeat (2) @(negedge clk); resetn=1;
        @(negedge clk); frame_start=1;
        @(negedge clk); frame_start=0;
        for (i=0;i<256;i=i+1) send_y(i);
        for (i=0;i<64;i=i+1) send_c(i,0);
        for (i=0;i<64;i=i+1) send_c(i,1);
        wait (!busy);
        assert(words == 48);
        assert(!error);
        $display("tb_model4_yuv420_macroblock_packer: PASS");
        $finish;
    end
endmodule
