// =============================================================================
// Module: axis_fifo
// Description: Synthesizable Synchronous AXI4-Stream Elastic FIFO with backpressure
// =============================================================================

`timescale 1ns / 1ps

module axis_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 6  // 2^6 = 64 words depth
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Slave AXI-Stream Input (Ingress)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Master AXI-Stream Output (Egress)
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tlast,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,

    // Status
    output wire [ADDR_WIDTH:0]    fifo_count,
    output wire                   fifo_empty,
    output wire                   fifo_full
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Dual-port distributed / block RAM memory array
    reg [DATA_WIDTH-1:0] mem_data [0:DEPTH-1];
    reg                  mem_last [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    assign fifo_empty = (count == 0);
    assign fifo_full  = (count == DEPTH);
    assign fifo_count = count;

    assign s_axis_tready = !fifo_full;
    assign m_axis_tvalid = !fifo_empty;
    assign m_axis_tdata  = mem_data[rd_ptr];
    assign m_axis_tlast  = mem_last[rd_ptr];

    wire write_en = s_axis_tvalid && s_axis_tready;
    wire read_en  = m_axis_tvalid && m_axis_tready;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count  <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (write_en) begin
                mem_data[wr_ptr] <= s_axis_tdata;
                mem_last[wr_ptr] <= s_axis_tlast;
                wr_ptr           <= wr_ptr + 1'b1;
            end

            if (read_en) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({write_en, read_en})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
