// ============================================================================
// File: custom_vector_decoder.v
// Module: custom_vector_decoder
// Project: High-Efficiency Zynq SoC Video Accelerator Architecture
// Description: Custom RISC-V Opcode Interceptor and Asymmetric Processing Element
//              Array Controller. Intercepts non-allocated opcode 0x0B (7'b0001011)
//              and routes funct3 fields to fire PE acceleration slots.
// Standard: IEEE 1364-2001 Verilog (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module custom_vector_decoder (
    input  wire        clk,            // System processing clock (100 MHz)
    input  wire        rst_n,          // Active-low asynchronous reset
    input  wire        insn_valid,     // Driven high by CPU when instruction is valid
    input  wire [31:0] instruction,    // Raw 32-bit machine instruction word
    input  wire [31:0] rs1_data,       // Base physical address pointer from Register 1

    // Asymmetric Processing Array Interface
    output reg         pe_array_start, // Single-cycle trigger pulse to fire PE slots
    output reg  [3:0]  pe_target_op,   // Processing operation index (0=RGB2YUV, 1=BGSub, etc.)
    output reg  [31:0] pe_mem_addr,    // Base data memory address pointer passed to fabric
    input  wire        pe_array_ready, // Handshake signal indicating calculation done
    output reg         pe_busy         // Status flag indicating active hardware processing
);

    // RISC-V Instruction Field Extraction
    // Opcode Custom-0: 7'b0001011 (0x0B)
    localparam [6:0] CUSTOM_0_OPCODE = 7'b0001011;

    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_array_start <= 1'b0;
            pe_target_op   <= 4'd0;
            pe_mem_addr    <= 32'd0;
            pe_busy        <= 1'b0;
        end else begin
            // Default pulse de-assertion for single-cycle trigger
            pe_array_start <= 1'b0;

            if (pe_busy) begin
                // Monitor completion handshake from PE array
                if (pe_array_ready) begin
                    pe_busy <= 1'b0;
                end
            end else if (insn_valid && (opcode == CUSTOM_0_OPCODE)) begin
                pe_mem_addr    <= rs1_data;
                pe_array_start <= 1'b1;
                pe_busy        <= 1'b1;
                case (funct3)
                    3'b000: pe_target_op <= 4'd0; // Stage 1: RGB to YUV420 Conversion
                    3'b001: pe_target_op <= 4'd1; // Stage 2: Temporal Frame Subtraction
                    3'b010: pe_target_op <= 4'd2; // Stage 3: 8x8 Window Inpainting
                    3'b011: pe_target_op <= 4'd3; // Stage 4: 4x4 Butterfly Integer DCT
                    3'b100: pe_target_op <= 4'd4; // Stage 5: CAVLC Bitstream Packaging
                    default: pe_target_op <= 4'd0;
                endcase
            end
        end
    end

endmodule
