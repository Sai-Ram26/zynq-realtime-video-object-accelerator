// =============================================================================
// Module: picorv32_accel_bridge.v
// Project: RISC-V Based Video Accelerator SoC on Avnet ZedBoard (xc7z020clg484-1)
// Student: G. Sai Ram (Roll No: 1602-24-735-163)
// Institution: Vasavi College of Engineering (Autonomous), Hyderabad
// Description:
//   Single-Cycle Native Coprocessor Memory Bus Bridge for PicoRV32 RISC-V.
//   Bypasses AXI4-Lite bus arbitration protocols to deliver 1-clock cycle
//   deterministic register read/write access:
//     - mem_valid / mem_ready zero-wait-state handshake
//     - Direct register address decoding
//     - Eliminates 3 to 5 clock cycles of AXI-Lite bus handshake overhead
// =============================================================================

`timescale 1ns / 1ps

module picorv32_accel_bridge (
    input  wire        clk,
    input  wire        rst_n,

    // PicoRV32 Native Memory Interface
    input  wire        mem_valid,
    output wire        mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata,

    // Accelerator Control Register Ports
    output reg  [31:0] reg_ctrl_out,
    output reg  [31:0] reg_thresh_out,
    output reg  [31:0] reg_qp_out,
    output reg  [31:0] reg_skip_thresh_out,

    // Accelerator Status Inputs
    input  wire [31:0] reg_status_in,
    input  wire [31:0] reg_perf_cycles_in,
    input  wire [31:0] reg_perf_pixels_in,
    input  wire [31:0] reg_perf_fg_in,
    input  wire [31:0] reg_perf_skip_in
);

    // Memory-mapped base offset: 0x4000_0000 (Accelerator Registers)
    wire is_accel_addr = (mem_addr[31:16] == 16'h4000);
    wire [3:0] reg_sel = mem_addr[5:2];

    // Zero-wait-state combinational ready acknowledgement
    assign mem_ready = mem_valid && is_accel_addr;

    // Combinational Read Mux
    always @(*) begin
        case (reg_sel)
            4'h0: mem_rdata = reg_ctrl_out;
            4'h1: mem_rdata = reg_thresh_out;
            4'h2: mem_rdata = reg_qp_out;
            4'h3: mem_rdata = reg_skip_thresh_out;
            4'h4: mem_rdata = reg_status_in;
            4'h5: mem_rdata = reg_perf_cycles_in;
            4'h6: mem_rdata = reg_perf_pixels_in;
            4'h7: mem_rdata = reg_perf_fg_in;
            4'h8: mem_rdata = reg_perf_skip_in;
            default: mem_rdata = 32'hDEADBEEF;
        endcase
    end

    // Synchronous Register Writes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl_out        <= 32'h00000005; // Accel Enable + Compression Enable
            reg_thresh_out      <= 32'd30;
            reg_qp_out          <= 32'd28;
            reg_skip_thresh_out <= 32'd2;
        end else if (mem_valid && is_accel_addr && |mem_wstrb) begin
            case (reg_sel)
                4'h0: reg_ctrl_out        <= mem_wdata;
                4'h1: reg_thresh_out      <= mem_wdata;
                4'h2: reg_qp_out          <= mem_wdata;
                4'h3: reg_skip_thresh_out <= mem_wdata;
                default: ;
            endcase
        end
    end

endmodule
