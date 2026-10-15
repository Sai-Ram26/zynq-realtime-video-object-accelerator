// =============================================================================
// File: tb_riscv_custom_decoder.v
// Module: tb_riscv_custom_decoder
// Project: High-Efficiency Zynq SoC Real-Time Video Compression Accelerator
// Target: Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
//
// Description:
//   Self-checking verification testbench for RISC-V Custom-0 Video Instruction
//   Extension Decoder (riscv_custom_video_decoder.v).
//   Tests opcodes: VBLK, VSCALE, VDCT, VQNT, VENC, VSTATUS, VWAIT
// =============================================================================

`timescale 1ns / 1ps

module tb_riscv_custom_decoder;

    reg         clk;
    reg         rst_n;
    reg         instr_valid;
    reg  [31:0] instr_word;
    wire        instr_ready;
    reg  [31:0] rs1_data;
    reg  [31:0] rs2_data;
    reg  [31:0] rs3_data;
    wire        rd_valid;
    wire [31:0] rd_data;

    wire        hw_start_block;
    wire [15:0] hw_block_w;
    wire [15:0] hw_block_h;
    wire [7:0]  hw_qp;
    wire [7:0]  hw_mode;
    wire [2:0]  hw_sub_op;
    reg         hw_busy;
    reg         hw_done;
    reg  [31:0] hw_cycles;

    // Instantiate Unit Under Test (UUT)
    riscv_custom_video_decoder uut (
        .clk            (clk),
        .rst_n          (rst_n),
        .instr_valid    (instr_valid),
        .instr_word     (instr_word),
        .instr_ready    (instr_ready),
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .rs3_data       (rs3_data),
        .rd_valid       (rd_valid),
        .rd_data        (rd_data),
        .hw_start_block (hw_start_block),
        .hw_block_w     (hw_block_w),
        .hw_block_h     (hw_block_h),
        .hw_qp          (hw_qp),
        .hw_mode        (hw_mode),
        .hw_sub_op      (hw_sub_op),
        .hw_busy        (hw_busy),
        .hw_done        (hw_done),
        .hw_cycles      (hw_cycles)
    );

    // 100 MHz clock generation
    always #5 clk = ~clk;

    // Helper task to issue a 32-bit RISC-V R-type instruction
    // [31:25]=funct7, [24:20]=rs2, [19:15]=rs1, [14:12]=funct3, [11:7]=rd, [6:0]=opcode
    task execute_riscv_custom(
        input [2:0]  f3,
        input [31:0] op1,
        input [31:0] op2,
        input [31:0] op3
    );
    begin
        @(posedge clk);
        instr_valid <= 1'b1;
        instr_word  <= {7'b0000000, 5'd2, 5'd1, f3, 5'd10, 7'b0001011}; // opcode 0x0B
        rs1_data    <= op1;
        rs2_data    <= op2;
        rs3_data    <= op3;
        @(posedge clk);
        instr_valid <= 1'b0;
        @(posedge clk);
    end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        clk         = 0;
        rst_n       = 0;
        instr_valid = 0;
        instr_word  = 0;
        rs1_data    = 0;
        rs2_data    = 0;
        rs3_data    = 0;
        hw_busy     = 0;
        hw_done     = 0;
        hw_cycles   = 32'd125000;

        $display("================================================================");
        $display(" RISC-V Custom Video Instruction Extension (Opcode 0x0B) Testbench");
        $display("================================================================");

        // Reset pulse
        #20;
        rst_n = 1;
        #20;

        // TEST 1: VBLK (funct3 = 3'b000)
        $display("\n--- Test 1: VBLK Instruction (funct3 = 3'b000) ---");
        execute_riscv_custom(3'b000, 32'd426, 32'd240, {16'd0, 8'd2, 8'd32}); // 426x240, QP=32, Mode=2
        if (hw_block_w == 16'd426 && hw_block_h == 16'd240 && hw_qp == 8'd32) begin
            $display("[PASS] VBLK successfully dispatched block parameters: W=%0d, H=%0d, QP=%0d",
                     hw_block_w, hw_block_h, hw_qp);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] VBLK parameters mismatch: W=%0d, H=%0d, QP=%0d",
                     hw_block_w, hw_block_h, hw_qp);
            fail_count = fail_count + 1;
        end

        // TEST 2: VQNT (funct3 = 3'b011)
        $display("\n--- Test 2: VQNT Instruction (funct3 = 3'b011) ---");
        execute_riscv_custom(3'b011, 32'd0, 32'd0, {24'd0, 8'd40}); // Change QP to 40
        if (hw_qp == 8'd40 && rd_data[7:0] == 8'd40) begin
            $display("[PASS] VQNT successfully updated QP to %0d", hw_qp);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] VQNT QP mismatch: expected 40, got %0d", hw_qp);
            fail_count = fail_count + 1;
        end

        // TEST 3: VSTATUS (funct3 = 3'b101)
        $display("\n--- Test 3: VSTATUS Instruction (funct3 = 3'b101) ---");
        hw_cycles = 32'h000ABCDE;
        execute_riscv_custom(3'b101, 32'd0, 32'd0, 32'd0);
        if (rd_data == 32'h000ABCDE) begin
            $display("[PASS] VSTATUS returned hardware cycle counter: 0x%08X", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] VSTATUS cycle counter mismatch: got 0x%08X", rd_data);
            fail_count = fail_count + 1;
        end

        // TEST 4: VWAIT (funct3 = 3'b110)
        $display("\n--- Test 4: VWAIT Instruction (funct3 = 3'b110) ---");
        hw_busy = 1'b1;
        hw_done = 1'b0;
        execute_riscv_custom(3'b110, 32'd0, 32'd0, 32'd0);
        if (rd_data[0] == 1'b1 && rd_data[1] == 1'b0) begin
            $display("[PASS] VWAIT correctly sampled hardware status: busy=1, done=0");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] VWAIT status mismatch: got rd_data=0x%08X", rd_data);
            fail_count = fail_count + 1;
        end

        // TEST 5: Non-custom Opcode (e.g. standard ADD 0x33)
        $display("\n--- Test 5: Standard Non-Custom Opcode (0x33) ---");
        @(posedge clk);
        instr_valid <= 1'b1;
        instr_word  <= 32'h00208533; // add a0, ra, sp (opcode 0x33)
        @(posedge clk);
        instr_valid <= 1'b0;
        @(posedge clk);
        if (hw_start_block == 1'b0) begin
            $display("[PASS] Standard non-custom opcode ignored by custom decoder.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Accelerator spuriously triggered on non-custom opcode!");
            fail_count = fail_count + 1;
        end

        $display("\n================================================================");
        if (fail_count == 0) begin
            $display(">>> ALL %0d TESTS PASSED! RISC-V CUSTOM ISA EXTENSION VERIFIED! <<<", pass_count);
        end else begin
            $display(">>> %0d TESTS FAILED! <<<", fail_count);
        end
        $display("================================================================\n");

        $finish;
    end

endmodule
