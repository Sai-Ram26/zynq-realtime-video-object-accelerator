`timescale 1ns / 1ps

module tb_model4_source_to_tiles;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg resetn = 1'b0;
    reg frame_start = 1'b0;
    reg [63:0] in_data = 0;
    reg in_valid = 0;
    reg in_last = 0;
    wire in_ready;
    wire [63:0] out_data;
    wire out_valid, out_last, busy, error;
    integer word_count = 0;

    model4_source_to_tiles #(.MAX_WIDTH(32), .MAX_HEIGHT(32)) dut (
        .clk(clk), .resetn(resetn), .frame_start(frame_start),
        .src_width(16'd32), .src_height(16'd32),
        .target_width(16'd16), .target_height(16'd16),
        .s_axis_tdata(in_data), .s_axis_tvalid(in_valid),
        .s_axis_tready(in_ready), .s_axis_tlast(in_last),
        .m_axis_tdata(out_data), .m_axis_tvalid(out_valid),
        .m_axis_tready(1'b1), .m_axis_tlast(out_last),
        .busy(busy), .error(error)
    );

    task send_word;
        input [63:0] data;
        input last;
        begin
            @(negedge clk);
            in_data = data;
            in_last = last;
            in_valid = 1'b1;
            while (!in_ready) @(negedge clk);
            @(negedge clk);
            in_valid = 1'b0;
            in_last = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (out_valid) begin
            if (word_count == 47) assert(out_last);
            word_count <= word_count + 1;
        end
    end

    integer i;
    initial begin
        repeat (2) @(negedge clk);
        resetn = 1'b1;
        @(negedge clk);
        frame_start = 1'b1;
        @(negedge clk);
        frame_start = 1'b0;

        // 32x32 Y plus 16x16 U and V, packed little-endian by byte.
        for (i = 0; i < 192; i = i + 1)
            send_word({8'(i + 7), 8'(i + 6), 8'(i + 5), 8'(i + 4),
                       8'(i + 3), 8'(i + 2), 8'(i + 1), 8'(i)},
                      (i == 191));

        wait (!busy);
        assert(word_count == 48);
        assert(!error);
        $display("tb_model4_source_to_tiles: PASS");
        $finish;
    end
endmodule
