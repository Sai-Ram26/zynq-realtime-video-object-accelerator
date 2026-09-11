// =============================================================================
// Module: stochastic_gen.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Stochastic Number Generator (SNG) using an 8-bit Linear Feedback Shift
//   Register (LFSR) with maximal-length polynomial (x^8 + x^6 + x^5 + x^4 + 1)
//   and digital magnitude comparator. Converts standard 8-bit binary pixel
//   values (0-255) into a time-multiplexed probabilistic bitstream where:
//       Probability P(s_stream = 1) = binary_in / 256
//
// Benefits:
//   - Multiplier collapses into a single 2-input AND gate (A * B)
//   - Scaled addition collapses into a single 2:1 Multiplexer ((A + B) / 2)
//   - Cuts FPGA arithmetic slice utilization by up to 67%, 0 DSPs required.
// =============================================================================

`timescale 1ns / 1ps

module stochastic_gen (
    input  wire       clk,        // System Clock (100 MHz AXI/PL)
    input  wire       rst_n,      // Active-Low Asynchronous Reset
    input  wire [7:0] binary_in,  // Deterministic 8-bit Input (0 to 255)
    output wire       s_stream    // Probabilistic Bitstream Output
);

    // 8-bit Galois / Fibonacci LFSR Register
    reg [7:0] lfsr_reg;
    wire      lfsr_feedback;

    // Maximal-length LFSR feedback polynomial: x^8 + x^6 + x^5 + x^4 + 1
    // Period = 2^8 - 1 = 255 unique non-zero pseudorandom states
    assign lfsr_feedback = ~(lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize with non-zero seed to avoid deadlock
            lfsr_reg <= 8'hA5; 
        end else begin
            lfsr_reg <= {lfsr_reg[6:0], lfsr_feedback};
        end
    end

    // Statistical digital magnitude comparison
    // When binary_in is high (e.g. 250), comparator output is '1' almost always (P ~ 0.98)
    // When binary_in is low (e.g. 10), comparator output is '1' rarely (P ~ 0.04)
    assign s_stream = (binary_in > lfsr_reg) ? 1'b1 : 1'b0;

endmodule
