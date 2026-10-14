// =============================================================================
// Module: riscv_custom_video_decoder
// Track B: Academic Research Contribution (Section 13, 27, 43 of Specification)
// Custom RISC-V Video Instruction Extension Decoder for PicoRV32.
// Decodes custom-0 opcode (0x0B) instructions:
//   - VBLK   (funct3 = 3'b000): Complete hardware block acceleration
//   - VSCALE (funct3 = 3'b001): Scaling trigger
//   - VDCT   (funct3 = 3'b010): 4x4 Integer transform
//   - VQNT   (funct3 = 3'b011): Quantization trigger
//   - VENC   (funct3 = 3'b100): CAVLC entropy encoding
//   - VSTATUS(funct3 = 3'b101): Hardware performance query
// =============================================================================

`timescale 1ns / 1ps

module riscv_custom_video_decoder (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction Word from RISC-V Pipeline
    input  wire        instr_valid,
    input  wire [31:0] instr_word,
    output wire        instr_ready,

    // Register Operands from RISC-V Register File
    input  wire [31:0] rs1_data, // e.g. input buffer address / width
    input  wire [31:0] rs2_data, // e.g. output buffer address / height
    input  wire [31:0] rs3_data, // e.g. QP and mode parameter

    // Writeback Result to RISC-V rd Register
    output reg         rd_valid,
    output reg  [31:0] rd_data,

    // Direct Accelerator Hardware Controls
    output reg         hw_start_block,
    output reg  [15:0] hw_block_w,
    output reg  [15:0] hw_block_h,
    output reg  [7:0]  hw_qp,
    output reg  [7:0]  hw_mode,
    input  wire        hw_busy,
    input  wire        hw_done,
    input  wire [31:0] hw_cycles
);

    // RISC-V Custom-0 Opcode = 7'b0001011 (0x0B)
    localparam OPCODE_CUSTOM0 = 7'b0001011;

    wire [6:0] opcode = instr_word[6:0];
    wire [2:0] funct3 = instr_word[14:12];
    wire [6:0] funct7 = instr_word[31:25];

    wire is_custom_video = instr_valid && (opcode == OPCODE_CUSTOM0);
    assign instr_ready = !hw_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_valid       <= 1'b0;
            rd_data        <= 32'd0;
            hw_start_block <= 1'b0;
            hw_block_w     <= 16'd426;
            hw_block_h     <= 16'd240;
            hw_qp          <= 8'd28;
            hw_mode        <= 8'd0;
        end else begin
            rd_valid       <= 1'b0;
            hw_start_block <= 1'b0;

            if (is_custom_video && instr_ready) begin
                case (funct3)
                    3'b000: begin // VBLK: Initiate entire 4x4 block accelerator
                        hw_start_block <= 1'b1;
                        hw_block_w     <= rs1_data[15:0];
                        hw_block_h     <= rs2_data[15:0];
                        hw_qp          <= rs3_data[7:0];
                        hw_mode        <= rs3_data[15:8];
                        rd_valid       <= 1'b1;
                        rd_data        <= 32'h00000001; // Dispatch Success
                    end

                    3'b101: begin // VSTATUS: Read hardware performance cycle counter
                        rd_valid <= 1'b1;
                        rd_data  <= hw_cycles;
                    end

                    default: begin
                        rd_valid <= 1'b1;
                        rd_data  <= 32'h0;
                    end
                endcase
            end
        end
    end

endmodule
