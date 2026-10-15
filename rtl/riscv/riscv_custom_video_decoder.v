// =============================================================================
// File: riscv_custom_video_decoder.v
// Module: riscv_custom_video_decoder
// Project: High-Efficiency Zynq SoC Real-Time Video Compression Accelerator
// Target: Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
//
// Description:
//   Academic Research Contribution: Custom RISC-V Video Instruction Extension.
//   Implements a custom opcode decoder for RISC-V pipelines (e.g. PicoRV32 / Rocket)
//   intercepting the standard RISC-V non-allocated Custom-0 Opcode 0x0B (7'b0001011).
//
//   Custom ISA Extensions:
//     - VBLK    (funct3 = 3'b000): Dispatch complete 4x4 block acceleration
//                                  rs1 = width, rs2 = height, rs3 = QP[7:0] | mode[15:8]
//     - VSCALE  (funct3 = 3'b001): Video scaling parameter trigger
//     - VDCT    (funct3 = 3'b010): 4x4 Multiplierless Integer DCT
//     - VQNT    (funct3 = 3'b011): Scalar Quantization trigger with QP
//     - VENC    (funct3 = 3'b100): CAVLC / Entropy encoding trigger
//     - VSTATUS (funct3 = 3'b101): Hardware performance / cycle counter read
//     - VWAIT   (funct3 = 3'b110): Hardware synchronization / wait-until-idle
// =============================================================================

`timescale 1ns / 1ps

module riscv_custom_video_decoder (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction interface from RISC-V CPU pipeline
    input  wire        instr_valid,
    input  wire [31:0] instr_word,
    output wire        instr_ready,

    // Register Operands from RISC-V Register File
    input  wire [31:0] rs1_data, // Parameter 1 (e.g. width / base addr)
    input  wire [31:0] rs2_data, // Parameter 2 (e.g. height / stride)
    input  wire [31:0] rs3_data, // Parameter 3 (e.g. [7:0]=QP, [15:8]=Mode)

    // Writeback Result to RISC-V rd Destination Register
    output reg         rd_valid,
    output reg  [31:0] rd_data,

    // Direct Accelerator Hardware Control Signals
    output reg         hw_start_block,
    output reg  [15:0] hw_block_w,
    output reg  [15:0] hw_block_h,
    output reg  [7:0]  hw_qp,
    output reg  [7:0]  hw_mode,
    output reg  [2:0]  hw_sub_op,     // 0=all, 1=scale, 2=dct, 3=quant, 4=cavlc
    input  wire        hw_busy,
    input  wire        hw_done,
    input  wire [31:0] hw_cycles
);

    // Standard RISC-V Custom-0 Opcode = 7'b0001011 (0x0B)
    localparam [6:0] OPCODE_CUSTOM0 = 7'b0001011;

    wire [6:0] opcode = instr_word[6:0];
    wire [2:0] funct3 = instr_word[14:12];
    wire [6:0] funct7 = instr_word[31:25];

    wire is_custom_video = instr_valid && (opcode == OPCODE_CUSTOM0);
    wire is_status_query = (funct3 == 3'b101) || (funct3 == 3'b110);
    assign instr_ready   = is_status_query ? 1'b1 : !hw_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_valid       <= 1'b0;
            rd_data        <= 32'd0;
            hw_start_block <= 1'b0;
            hw_block_w     <= 16'd640;
            hw_block_h     <= 16'd480;
            hw_qp          <= 8'd28;
            hw_mode        <= 8'd0;
            hw_sub_op      <= 3'd0;
        end else begin
            rd_valid       <= 1'b0;
            hw_start_block <= 1'b0;

            if (is_custom_video && instr_ready) begin
                case (funct3)
                    3'b000: begin // VBLK: Full block acceleration
                        hw_start_block <= 1'b1;
                        hw_sub_op      <= 3'd0;
                        hw_block_w     <= rs1_data[15:0];
                        hw_block_h     <= rs2_data[15:0];
                        hw_qp          <= rs3_data[7:0];
                        hw_mode        <= rs3_data[15:8];
                        rd_valid       <= 1'b1;
                        rd_data        <= 32'h00000001; // Success / Ack
                    end

                    3'b001: begin // VSCALE: Scaling parameter set
                        hw_sub_op      <= 3'd1;
                        hw_block_w     <= rs1_data[15:0];
                        hw_block_h     <= rs2_data[15:0];
                        rd_valid       <= 1'b1;
                        rd_data        <= 32'h00000001;
                    end

                    3'b010: begin // VDCT: Trigger 4x4 integer transform
                        hw_start_block <= 1'b1;
                        hw_sub_op      <= 3'd2;
                        rd_valid       <= 1'b1;
                        rd_data        <= 32'h00000001;
                    end

                    3'b011: begin // VQNT: Trigger quantization
                        hw_sub_op      <= 3'd3;
                        hw_qp          <= rs3_data[7:0];
                        rd_valid       <= 1'b1;
                        rd_data        <= {24'd0, rs3_data[7:0]};
                    end

                    3'b100: begin // VENC: Trigger CAVLC entropy coding
                        hw_sub_op      <= 3'd4;
                        rd_valid       <= 1'b1;
                        rd_data        <= 32'h00000001;
                    end

                    3'b101: begin // VSTATUS: Read hardware performance cycle counter
                        rd_valid <= 1'b1;
                        rd_data  <= hw_cycles;
                    end

                    3'b110: begin // VWAIT: Read busy status
                        rd_valid <= 1'b1;
                        rd_data  <= {30'd0, hw_done, hw_busy};
                    end

                    default: begin
                        rd_valid <= 1'b1;
                        rd_data  <= 32'h00000000;
                    end
                endcase
            end
        end
    end

endmodule
