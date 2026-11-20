// =============================================================================
// model4_fmp4_muxer.sv
// Hardware fragmented-MP4 (fMP4) muxer — Model-4 ZedBoard H.264 pipeline
// Vivado 2026.1, XC7Z020 (SystemVerilog-2012)
//
// Output layout (per job):
//   [init segment]  ftyp(16) + moov(variable)  → one DMA packet (tlast)
//   [per frame]     moof(96) + mdat(12+au_sz)  → one DMA packet per frame
//
// Fixed moof size = 8(moof) + 16(mfhd) + 72(traf) = 96
//   where traf = 8 + tfhd(16) + tfdt(20) + trun(28) = 72
// trun flags = 0x000301 (data_offset | sample_duration | sample_size)
// trun data_offset = 96 + 8 = 104
//
// moov size (dynamic, depends on sps/pps lengths):
//   8 + mvhd(108) + trak(8+92+mdia) + mvex(40)
//   where mdia = 8 + mdhd(32) + hdlr(45) + minf
//         minf = 8 + vmhd(20) + dinf(36) + 8 + stbl
//         stbl = 8 + stsd(16+avc1) + stts(24) + stsc(28) + stsz(20) + stco(24)
//         avc1 = 86 + avcC(16+sps_len+pps_len)
// =============================================================================
`timescale 1ns / 1ps

module model4_fmp4_muxer #(
    parameter integer AU_BUF_BYTES  = 16384,
    parameter integer OUTPUT_WIDTH  = 256,
    parameter integer OUTPUT_HEIGHT = 144
) (
    input  wire        clk,
    input  wire        resetn,

    // -------------------------------------------------------------------------
    // Access-unit byte stream from encoder (one byte per handshake)
    // -------------------------------------------------------------------------
    input  wire        au_valid,
    input  wire [7:0]  au_data,
    input  wire        au_last,
    input  wire        au_is_idr,
    input  wire [31:0] au_pts,
    input  wire [31:0] au_duration,
    input  wire [31:0] frame_id,
    input  wire        job_active,

    // -------------------------------------------------------------------------
    // SPS / PPS config bus (sps_buf / pps_buf pre-loaded externally)
    // -------------------------------------------------------------------------
    input  wire [7:0]  sps_data,
    input  wire [15:0] sps_len,
    input  wire [7:0]  pps_data,
    input  wire [15:0] pps_len,
    input  wire        config_valid,

    // -------------------------------------------------------------------------
    // AXI4-Stream output (to AXI DMA S2MM)
    // -------------------------------------------------------------------------
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg  [7:0]  m_axis_tkeep,
    output reg         m_axis_tlast
);

// =============================================================================
// Address width
// =============================================================================
localparam integer AU_ADDR_W  = $clog2(AU_BUF_BYTES);

// =============================================================================
// FSM states
// =============================================================================
localparam [3:0]
    S_IDLE       = 4'd0,
    S_BUILD_INIT = 4'd1,
    S_EMIT_INIT  = 4'd2,
    S_WAIT_AU    = 4'd3,
    S_STAGE_AU   = 4'd4,
    S_BUILD_MOOF = 4'd5,
    S_EMIT_MOOF  = 4'd6,
    S_EMIT_MDAT  = 4'd7,
    S_DONE       = 4'd8;

reg [3:0] state;

// =============================================================================
// SPS / PPS storage (up to 128 bytes each; write-once at startup)
// =============================================================================
localparam integer MAX_SPS_PPS = 128;
reg [7:0]  sps_buf [0:MAX_SPS_PPS-1];
reg [7:0]  pps_buf [0:MAX_SPS_PPS-1];
reg [15:0] sps_len_r, pps_len_r;
reg        cfg_valid_r;

// Config capture: external logic must write sps_buf/pps_buf then strobe config_valid
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        sps_len_r   <= 16'd0;
        pps_len_r   <= 16'd0;
        cfg_valid_r <= 1'b0;
    end else if (config_valid) begin
        sps_len_r   <= sps_len;
        pps_len_r   <= pps_len;
        cfg_valid_r <= 1'b1;
    end
end

// =============================================================================
// 16 KB AU staging BRAM (inferred)
// =============================================================================
(* ram_style = "block" *)
reg [7:0] au_buf [0:AU_BUF_BYTES-1];
reg [AU_ADDR_W-1:0] au_wr_ptr;
reg [AU_ADDR_W-1:0] au_rd_ptr;
reg [31:0]           au_byte_count;

// BRAM write (AU ingestion)
always @(posedge clk) begin
    if (au_valid && (state == S_STAGE_AU || state == S_WAIT_AU)) begin
        au_buf[au_wr_ptr] <= au_data;
    end
end

// BRAM read (registered output — 1-cycle latency)
reg [7:0] bram_rd_data;
always @(posedge clk) begin
    bram_rd_data <= au_buf[au_rd_ptr];
end

// =============================================================================
// Fragment tracking
// =============================================================================
reg [31:0] frag_seq;
reg [63:0] base_dts;
reg [31:0] cur_duration;
reg        cur_is_idr;

// =============================================================================
// Emit buffer (1 KB for moof/init-seg templates)
// =============================================================================
localparam integer EMIT_DEPTH = 1024;
reg [7:0]  emit_buf [0:EMIT_DEPTH-1];
reg [15:0] emit_wr_idx;
reg [15:0] emit_rd_idx;
reg [15:0] emit_len;
wire [7:0] emit_rd_data = emit_buf[emit_rd_idx];

// =============================================================================
// Dynamic size wires
// =============================================================================
wire [15:0] avcc_sz  = 16'd16  + sps_len_r + pps_len_r;
wire [15:0] avc1_sz  = 16'd86  + avcc_sz;
wire [15:0] stsd_sz  = 16'd16  + avc1_sz;
wire [15:0] stbl_sz  = 16'd8   + stsd_sz + 16'd24 + 16'd28 + 16'd20 + 16'd24;
wire [15:0] minf_sz  = 16'd8   + 16'd20  + 16'd36  + 16'd8  + stbl_sz;
wire [15:0] mdia_sz  = 16'd8   + 16'd32  + 16'd45  + minf_sz;
wire [15:0] trak_sz  = 16'd8   + 16'd92  + mdia_sz;
wire [15:0] moov_sz  = 16'd8   + 16'd108 + trak_sz + 16'd40;

// =============================================================================
// Build sub-state
// =============================================================================
localparam [4:0]
    BOX_FTYP     = 5'd0,
    BOX_MOOV_HDR = 5'd1,
    BOX_MVHD     = 5'd2,
    BOX_TRAK_HDR = 5'd3,
    BOX_TKHD     = 5'd4,
    BOX_MDIA_HDR = 5'd5,
    BOX_MDHD     = 5'd6,
    BOX_HDLR     = 5'd7,
    BOX_MINF_HDR = 5'd8,
    BOX_VMHD     = 5'd9,
    BOX_DINF     = 5'd10,
    BOX_STBL_HDR = 5'd11,
    BOX_STSD     = 5'd12,
    BOX_AVC1     = 5'd13,
    BOX_AVCC     = 5'd14,
    BOX_SPS_DATA = 5'd15,
    BOX_PPS_HDR  = 5'd16,
    BOX_PPS_DATA = 5'd17,
    BOX_STTS     = 5'd18,
    BOX_STSC     = 5'd19,
    BOX_STSZ     = 5'd20,
    BOX_STCO     = 5'd21,
    BOX_MVEX_HDR = 5'd22,
    BOX_TREX     = 5'd23,
    // moof
    BOX_MOOF_HDR = 5'd24,
    BOX_MFHD     = 5'd25,
    BOX_TRAF_HDR = 5'd26,
    BOX_TFHD     = 5'd27,
    BOX_TFDT     = 5'd28,
    BOX_TRUN     = 5'd29;

reg [4:0] box_st;
reg [15:0] bsub;

// =============================================================================
// 64-bit packer
// =============================================================================
reg [55:0] pack_shift; // accumulated bytes (bits 0..55 = bytes 0..6)
reg [2:0]  pack_cnt;   // bytes in pack_shift (0–7)

reg        pck_valid;
reg [7:0]  pck_byte;
reg        pck_last;

wire axis_fire = m_axis_tvalid && m_axis_tready;

// =============================================================================
// Helper: write one byte to emit_buf
// =============================================================================
task automatic emit_byte;
    input [7:0] b;
    begin
        emit_buf[emit_wr_idx] <= b;
        emit_wr_idx <= emit_wr_idx + 16'd1;
    end
endtask

// =============================================================================
// Main FSM
// =============================================================================
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        state          <= S_IDLE;
        frag_seq       <= 32'd1;
        base_dts       <= 64'd0;
        cur_duration   <= 32'd0;
        cur_is_idr     <= 1'b0;
        au_wr_ptr      <= {AU_ADDR_W{1'b0}};
        au_rd_ptr      <= {AU_ADDR_W{1'b0}};
        au_byte_count  <= 32'd0;
        emit_wr_idx    <= 16'd0;
        emit_rd_idx    <= 16'd0;
        emit_len       <= 16'd0;
        bsub           <= 16'd0;
        box_st         <= BOX_FTYP;
        pack_shift     <= 56'd0;
        pack_cnt       <= 3'd0;
        pck_valid      <= 1'b0;
        pck_byte       <= 8'd0;
        pck_last       <= 1'b0;
        m_axis_tdata   <= 64'd0;
        m_axis_tvalid  <= 1'b0;
        m_axis_tkeep   <= 8'd0;
        m_axis_tlast   <= 1'b0;
    end else begin
        // ------------------------------------------------------------------
        // Default: de-assert pck_valid; AXI handshake cleanup
        // ------------------------------------------------------------------
        pck_valid <= 1'b0;
        pck_last  <= 1'b0;

        if (axis_fire) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end

        // ==================================================================
        // Packer — runs every cycle (before FSM so FSM can override valid)
        // ==================================================================
        // (see end of block)

        // ==================================================================
        // FSM
        // ==================================================================
        case (state)

        // ----------------------------------------------------------------
        S_IDLE: begin
            frag_seq      <= 32'd1;
            base_dts      <= 64'd0;
            au_byte_count <= 32'd0;
            au_wr_ptr     <= {AU_ADDR_W{1'b0}};
            au_rd_ptr     <= {AU_ADDR_W{1'b0}};
            pack_cnt      <= 3'd0;
            m_axis_tvalid <= 1'b0;
            if (job_active && cfg_valid_r) begin
                state       <= S_BUILD_INIT;
                box_st      <= BOX_FTYP;
                bsub        <= 16'd0;
                emit_wr_idx <= 16'd0;
                emit_rd_idx <= 16'd0;
            end
        end

        // ----------------------------------------------------------------
        // S_BUILD_INIT: fill emit_buf with ftyp+moov (one byte per cycle)
        // ----------------------------------------------------------------
        S_BUILD_INIT: begin
            case (box_st)

            //  ftyp (16 bytes)
            BOX_FTYP: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h10; // size=16
                16'd4:  emit_buf[emit_wr_idx] <= 8'h66; // 'ftyp'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h74;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h79;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h70;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h69; // major='isom'
                16'd9:  emit_buf[emit_wr_idx] <= 8'h73;
                16'd10: emit_buf[emit_wr_idx] <= 8'h6F;
                16'd11: emit_buf[emit_wr_idx] <= 8'h6D;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // minor=0
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h00;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd15) begin box_st <= BOX_MOOV_HDR; bsub <= 16'd0; end
            end

            // moov header (8 bytes)
            BOX_MOOV_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= moov_sz[15:8];
                16'd3: emit_buf[emit_wr_idx] <= moov_sz[7:0];
                16'd4: emit_buf[emit_wr_idx] <= 8'h6D; // 'moov'
                16'd5: emit_buf[emit_wr_idx] <= 8'h6F;
                16'd6: emit_buf[emit_wr_idx] <= 8'h6F;
                16'd7: emit_buf[emit_wr_idx] <= 8'h76;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_MVHD; bsub <= 16'd0; end
            end

            // mvhd (108 bytes, version=0)
            // Layout v0: hdr(8)+ver+flags(4)+create(4)+modify(4)+timescale(4)+
            //            duration(4)+rate(4)+volume(2)+reserved(10)+matrix(36)+
            //            predefined(24)+next_track_id(4) = 108
            BOX_MVHD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h6C; // 108
                16'd4:  emit_buf[emit_wr_idx] <= 8'h6D; // 'mvhd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h76;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h68;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                // version=0, flags=0
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                // creation_time=0 (4 bytes v0)
                16'd12: emit_buf[emit_wr_idx] <= 8'h00;
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h00;
                // modification_time=0
                16'd16: emit_buf[emit_wr_idx] <= 8'h00;
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h00;
                // timescale=90000=0x00015F90
                16'd20: emit_buf[emit_wr_idx] <= 8'h00;
                16'd21: emit_buf[emit_wr_idx] <= 8'h01;
                16'd22: emit_buf[emit_wr_idx] <= 8'h5F;
                16'd23: emit_buf[emit_wr_idx] <= 8'h90;
                // duration=0
                16'd24: emit_buf[emit_wr_idx] <= 8'h00;
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h00;
                // rate=1.0 = 0x00010000
                16'd28: emit_buf[emit_wr_idx] <= 8'h00;
                16'd29: emit_buf[emit_wr_idx] <= 8'h01;
                16'd30: emit_buf[emit_wr_idx] <= 8'h00;
                16'd31: emit_buf[emit_wr_idx] <= 8'h00;
                // volume=1.0=0x0100
                16'd32: emit_buf[emit_wr_idx] <= 8'h01;
                16'd33: emit_buf[emit_wr_idx] <= 8'h00;
                // reserved (10 bytes)
                16'd34: emit_buf[emit_wr_idx] <= 8'h00;
                16'd35: emit_buf[emit_wr_idx] <= 8'h00;
                16'd36: emit_buf[emit_wr_idx] <= 8'h00;
                16'd37: emit_buf[emit_wr_idx] <= 8'h00;
                16'd38: emit_buf[emit_wr_idx] <= 8'h00;
                16'd39: emit_buf[emit_wr_idx] <= 8'h00;
                16'd40: emit_buf[emit_wr_idx] <= 8'h00;
                16'd41: emit_buf[emit_wr_idx] <= 8'h00;
                16'd42: emit_buf[emit_wr_idx] <= 8'h00;
                16'd43: emit_buf[emit_wr_idx] <= 8'h00;
                // matrix[9] = unity = {0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000}
                16'd44: emit_buf[emit_wr_idx] <= 8'h00;
                16'd45: emit_buf[emit_wr_idx] <= 8'h01;
                16'd46: emit_buf[emit_wr_idx] <= 8'h00;
                16'd47: emit_buf[emit_wr_idx] <= 8'h00; // a=1.0
                16'd48: emit_buf[emit_wr_idx] <= 8'h00;
                16'd49: emit_buf[emit_wr_idx] <= 8'h00;
                16'd50: emit_buf[emit_wr_idx] <= 8'h00;
                16'd51: emit_buf[emit_wr_idx] <= 8'h00; // b=0
                16'd52: emit_buf[emit_wr_idx] <= 8'h00;
                16'd53: emit_buf[emit_wr_idx] <= 8'h00;
                16'd54: emit_buf[emit_wr_idx] <= 8'h00;
                16'd55: emit_buf[emit_wr_idx] <= 8'h00; // u=0
                16'd56: emit_buf[emit_wr_idx] <= 8'h00;
                16'd57: emit_buf[emit_wr_idx] <= 8'h00;
                16'd58: emit_buf[emit_wr_idx] <= 8'h00;
                16'd59: emit_buf[emit_wr_idx] <= 8'h00; // c=0
                16'd60: emit_buf[emit_wr_idx] <= 8'h00;
                16'd61: emit_buf[emit_wr_idx] <= 8'h01;
                16'd62: emit_buf[emit_wr_idx] <= 8'h00;
                16'd63: emit_buf[emit_wr_idx] <= 8'h00; // d=1.0
                16'd64: emit_buf[emit_wr_idx] <= 8'h00;
                16'd65: emit_buf[emit_wr_idx] <= 8'h00;
                16'd66: emit_buf[emit_wr_idx] <= 8'h00;
                16'd67: emit_buf[emit_wr_idx] <= 8'h00; // v=0
                16'd68: emit_buf[emit_wr_idx] <= 8'h00;
                16'd69: emit_buf[emit_wr_idx] <= 8'h00;
                16'd70: emit_buf[emit_wr_idx] <= 8'h00;
                16'd71: emit_buf[emit_wr_idx] <= 8'h00; // tx=0
                16'd72: emit_buf[emit_wr_idx] <= 8'h00;
                16'd73: emit_buf[emit_wr_idx] <= 8'h00;
                16'd74: emit_buf[emit_wr_idx] <= 8'h00;
                16'd75: emit_buf[emit_wr_idx] <= 8'h00; // ty=0
                16'd76: emit_buf[emit_wr_idx] <= 8'h40;
                16'd77: emit_buf[emit_wr_idx] <= 8'h00;
                16'd78: emit_buf[emit_wr_idx] <= 8'h00;
                16'd79: emit_buf[emit_wr_idx] <= 8'h00; // w=1.0
                // pre_defined (24 bytes) = 0
                16'd80: emit_buf[emit_wr_idx] <= 8'h00;
                16'd81: emit_buf[emit_wr_idx] <= 8'h00;
                16'd82: emit_buf[emit_wr_idx] <= 8'h00;
                16'd83: emit_buf[emit_wr_idx] <= 8'h00;
                16'd84: emit_buf[emit_wr_idx] <= 8'h00;
                16'd85: emit_buf[emit_wr_idx] <= 8'h00;
                16'd86: emit_buf[emit_wr_idx] <= 8'h00;
                16'd87: emit_buf[emit_wr_idx] <= 8'h00;
                16'd88: emit_buf[emit_wr_idx] <= 8'h00;
                16'd89: emit_buf[emit_wr_idx] <= 8'h00;
                16'd90: emit_buf[emit_wr_idx] <= 8'h00;
                16'd91: emit_buf[emit_wr_idx] <= 8'h00;
                16'd92: emit_buf[emit_wr_idx] <= 8'h00;
                16'd93: emit_buf[emit_wr_idx] <= 8'h00;
                16'd94: emit_buf[emit_wr_idx] <= 8'h00;
                16'd95: emit_buf[emit_wr_idx] <= 8'h00;
                16'd96: emit_buf[emit_wr_idx] <= 8'h00;
                16'd97: emit_buf[emit_wr_idx] <= 8'h00;
                16'd98: emit_buf[emit_wr_idx] <= 8'h00;
                16'd99: emit_buf[emit_wr_idx] <= 8'h00;
                16'd100: emit_buf[emit_wr_idx] <= 8'h00;
                16'd101: emit_buf[emit_wr_idx] <= 8'h00;
                16'd102: emit_buf[emit_wr_idx] <= 8'h00;
                16'd103: emit_buf[emit_wr_idx] <= 8'h00;
                // next_track_id = 2
                16'd104: emit_buf[emit_wr_idx] <= 8'h00;
                16'd105: emit_buf[emit_wr_idx] <= 8'h00;
                16'd106: emit_buf[emit_wr_idx] <= 8'h00;
                16'd107: emit_buf[emit_wr_idx] <= 8'h02;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd107) begin box_st <= BOX_TRAK_HDR; bsub <= 16'd0; end
            end

            // trak header (8 bytes)
            BOX_TRAK_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= trak_sz[15:8];
                16'd3: emit_buf[emit_wr_idx] <= trak_sz[7:0];
                16'd4: emit_buf[emit_wr_idx] <= 8'h74; // 'trak'
                16'd5: emit_buf[emit_wr_idx] <= 8'h72;
                16'd6: emit_buf[emit_wr_idx] <= 8'h61;
                16'd7: emit_buf[emit_wr_idx] <= 8'h6B;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_TKHD; bsub <= 16'd0; end
            end

            // tkhd (92 bytes, version=0)
            // 8+4+4+4+4+4+4+8+2+2+2+2+36+4+4 = 92
            BOX_TKHD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h5C; // 92
                16'd4:  emit_buf[emit_wr_idx] <= 8'h74; // 'tkhd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h6B;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h68;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // version=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h03; // flags=enabled+in_movie
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // creation_time=0
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h00;
                16'd16: emit_buf[emit_wr_idx] <= 8'h00; // modification_time=0
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h00;
                16'd20: emit_buf[emit_wr_idx] <= 8'h00; // track_id=1
                16'd21: emit_buf[emit_wr_idx] <= 8'h00;
                16'd22: emit_buf[emit_wr_idx] <= 8'h00;
                16'd23: emit_buf[emit_wr_idx] <= 8'h01;
                16'd24: emit_buf[emit_wr_idx] <= 8'h00; // reserved=0
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h00;
                16'd28: emit_buf[emit_wr_idx] <= 8'h00; // duration=0
                16'd29: emit_buf[emit_wr_idx] <= 8'h00;
                16'd30: emit_buf[emit_wr_idx] <= 8'h00;
                16'd31: emit_buf[emit_wr_idx] <= 8'h00;
                16'd32: emit_buf[emit_wr_idx] <= 8'h00; // reserved2 (8 bytes)
                16'd33: emit_buf[emit_wr_idx] <= 8'h00;
                16'd34: emit_buf[emit_wr_idx] <= 8'h00;
                16'd35: emit_buf[emit_wr_idx] <= 8'h00;
                16'd36: emit_buf[emit_wr_idx] <= 8'h00;
                16'd37: emit_buf[emit_wr_idx] <= 8'h00;
                16'd38: emit_buf[emit_wr_idx] <= 8'h00;
                16'd39: emit_buf[emit_wr_idx] <= 8'h00;
                16'd40: emit_buf[emit_wr_idx] <= 8'h00; // layer=0
                16'd41: emit_buf[emit_wr_idx] <= 8'h00;
                16'd42: emit_buf[emit_wr_idx] <= 8'h00; // alternate_group=0
                16'd43: emit_buf[emit_wr_idx] <= 8'h00;
                16'd44: emit_buf[emit_wr_idx] <= 8'h00; // volume=0 (video)
                16'd45: emit_buf[emit_wr_idx] <= 8'h00;
                16'd46: emit_buf[emit_wr_idx] <= 8'h00; // reserved
                16'd47: emit_buf[emit_wr_idx] <= 8'h00;
                // matrix (36 bytes) unity
                16'd48: emit_buf[emit_wr_idx] <= 8'h00;
                16'd49: emit_buf[emit_wr_idx] <= 8'h01;
                16'd50: emit_buf[emit_wr_idx] <= 8'h00;
                16'd51: emit_buf[emit_wr_idx] <= 8'h00; // a=1
                16'd52: emit_buf[emit_wr_idx] <= 8'h00;
                16'd53: emit_buf[emit_wr_idx] <= 8'h00;
                16'd54: emit_buf[emit_wr_idx] <= 8'h00;
                16'd55: emit_buf[emit_wr_idx] <= 8'h00; // b=0
                16'd56: emit_buf[emit_wr_idx] <= 8'h00;
                16'd57: emit_buf[emit_wr_idx] <= 8'h00;
                16'd58: emit_buf[emit_wr_idx] <= 8'h00;
                16'd59: emit_buf[emit_wr_idx] <= 8'h00; // u=0
                16'd60: emit_buf[emit_wr_idx] <= 8'h00;
                16'd61: emit_buf[emit_wr_idx] <= 8'h00;
                16'd62: emit_buf[emit_wr_idx] <= 8'h00;
                16'd63: emit_buf[emit_wr_idx] <= 8'h00; // c=0
                16'd64: emit_buf[emit_wr_idx] <= 8'h00;
                16'd65: emit_buf[emit_wr_idx] <= 8'h01;
                16'd66: emit_buf[emit_wr_idx] <= 8'h00;
                16'd67: emit_buf[emit_wr_idx] <= 8'h00; // d=1
                16'd68: emit_buf[emit_wr_idx] <= 8'h00;
                16'd69: emit_buf[emit_wr_idx] <= 8'h00;
                16'd70: emit_buf[emit_wr_idx] <= 8'h00;
                16'd71: emit_buf[emit_wr_idx] <= 8'h00; // v=0
                16'd72: emit_buf[emit_wr_idx] <= 8'h00;
                16'd73: emit_buf[emit_wr_idx] <= 8'h00;
                16'd74: emit_buf[emit_wr_idx] <= 8'h00;
                16'd75: emit_buf[emit_wr_idx] <= 8'h00; // tx=0
                16'd76: emit_buf[emit_wr_idx] <= 8'h00;
                16'd77: emit_buf[emit_wr_idx] <= 8'h00;
                16'd78: emit_buf[emit_wr_idx] <= 8'h00;
                16'd79: emit_buf[emit_wr_idx] <= 8'h00; // ty=0
                16'd80: emit_buf[emit_wr_idx] <= 8'h40;
                16'd81: emit_buf[emit_wr_idx] <= 8'h00;
                16'd82: emit_buf[emit_wr_idx] <= 8'h00;
                16'd83: emit_buf[emit_wr_idx] <= 8'h00; // w=1
                // width (16.16) = OUTPUT_WIDTH
                16'd84: emit_buf[emit_wr_idx] <= OUTPUT_WIDTH[15:8];
                16'd85: emit_buf[emit_wr_idx] <= OUTPUT_WIDTH[7:0];
                16'd86: emit_buf[emit_wr_idx] <= 8'h00;
                16'd87: emit_buf[emit_wr_idx] <= 8'h00;
                // height (16.16) = OUTPUT_HEIGHT
                16'd88: emit_buf[emit_wr_idx] <= OUTPUT_HEIGHT[15:8];
                16'd89: emit_buf[emit_wr_idx] <= OUTPUT_HEIGHT[7:0];
                16'd90: emit_buf[emit_wr_idx] <= 8'h00;
                16'd91: emit_buf[emit_wr_idx] <= 8'h00;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd91) begin box_st <= BOX_MDIA_HDR; bsub <= 16'd0; end
            end

            // mdia header (8)
            BOX_MDIA_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= mdia_sz[15:8];
                16'd3: emit_buf[emit_wr_idx] <= mdia_sz[7:0];
                16'd4: emit_buf[emit_wr_idx] <= 8'h6D; // 'mdia'
                16'd5: emit_buf[emit_wr_idx] <= 8'h64;
                16'd6: emit_buf[emit_wr_idx] <= 8'h69;
                16'd7: emit_buf[emit_wr_idx] <= 8'h61;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_MDHD; bsub <= 16'd0; end
            end

            // mdhd (32 bytes, version=0)
            BOX_MDHD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h20; // 32
                16'd4:  emit_buf[emit_wr_idx] <= 8'h6D; // 'mdhd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h68;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // v=0,flags=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // creation=0
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h00;
                16'd16: emit_buf[emit_wr_idx] <= 8'h00; // modification=0
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h00;
                16'd20: emit_buf[emit_wr_idx] <= 8'h00; // timescale=90000
                16'd21: emit_buf[emit_wr_idx] <= 8'h01;
                16'd22: emit_buf[emit_wr_idx] <= 8'h5F;
                16'd23: emit_buf[emit_wr_idx] <= 8'h90;
                16'd24: emit_buf[emit_wr_idx] <= 8'h00; // duration=0
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h00;
                16'd28: emit_buf[emit_wr_idx] <= 8'h55; // language='und'
                16'd29: emit_buf[emit_wr_idx] <= 8'hC4;
                16'd30: emit_buf[emit_wr_idx] <= 8'h00; // pre_defined=0
                16'd31: emit_buf[emit_wr_idx] <= 8'h00;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd31) begin box_st <= BOX_HDLR; bsub <= 16'd0; end
            end

            // hdlr (45 bytes)
            BOX_HDLR: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h2D; // 45
                16'd4:  emit_buf[emit_wr_idx] <= 8'h68; // 'hdlr'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h6C;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h72;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // v=0,flags=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // pre_defined=0
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h00;
                16'd16: emit_buf[emit_wr_idx] <= 8'h76; // handler='vide'
                16'd17: emit_buf[emit_wr_idx] <= 8'h69;
                16'd18: emit_buf[emit_wr_idx] <= 8'h64;
                16'd19: emit_buf[emit_wr_idx] <= 8'h65;
                16'd20: emit_buf[emit_wr_idx] <= 8'h00; // reserved (12 bytes)
                16'd21: emit_buf[emit_wr_idx] <= 8'h00;
                16'd22: emit_buf[emit_wr_idx] <= 8'h00;
                16'd23: emit_buf[emit_wr_idx] <= 8'h00;
                16'd24: emit_buf[emit_wr_idx] <= 8'h00;
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h00;
                16'd28: emit_buf[emit_wr_idx] <= 8'h00;
                16'd29: emit_buf[emit_wr_idx] <= 8'h00;
                16'd30: emit_buf[emit_wr_idx] <= 8'h00;
                16'd31: emit_buf[emit_wr_idx] <= 8'h00;
                16'd32: emit_buf[emit_wr_idx] <= 8'h56; // "VideoHandler\0"
                16'd33: emit_buf[emit_wr_idx] <= 8'h69;
                16'd34: emit_buf[emit_wr_idx] <= 8'h64;
                16'd35: emit_buf[emit_wr_idx] <= 8'h65;
                16'd36: emit_buf[emit_wr_idx] <= 8'h6F;
                16'd37: emit_buf[emit_wr_idx] <= 8'h48;
                16'd38: emit_buf[emit_wr_idx] <= 8'h61;
                16'd39: emit_buf[emit_wr_idx] <= 8'h6E;
                16'd40: emit_buf[emit_wr_idx] <= 8'h64;
                16'd41: emit_buf[emit_wr_idx] <= 8'h6C;
                16'd42: emit_buf[emit_wr_idx] <= 8'h65;
                16'd43: emit_buf[emit_wr_idx] <= 8'h72;
                16'd44: emit_buf[emit_wr_idx] <= 8'h00; // null
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd44) begin box_st <= BOX_MINF_HDR; bsub <= 16'd0; end
            end

            // minf header (8 bytes)
            BOX_MINF_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= minf_sz[15:8];
                16'd3: emit_buf[emit_wr_idx] <= minf_sz[7:0];
                16'd4: emit_buf[emit_wr_idx] <= 8'h6D; // 'minf'
                16'd5: emit_buf[emit_wr_idx] <= 8'h69;
                16'd6: emit_buf[emit_wr_idx] <= 8'h6E;
                16'd7: emit_buf[emit_wr_idx] <= 8'h66;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_VMHD; bsub <= 16'd0; end
            end

            // vmhd (20 bytes)
            BOX_VMHD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h14; // 20
                16'd4:  emit_buf[emit_wr_idx] <= 8'h76; // 'vmhd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h6D;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h68;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h01; // flags=1
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // graphicsMode=0
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00; // opcolor
                16'd15: emit_buf[emit_wr_idx] <= 8'h00;
                16'd16: emit_buf[emit_wr_idx] <= 8'h00;
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h00;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd19) begin box_st <= BOX_DINF; bsub <= 16'd0; end
            end

            // dinf (36 bytes): dinf_hdr(8) + dref(28, containing url(12))
            BOX_DINF: begin
                case (bsub)
                // dinf hdr
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h24; // 36
                16'd4:  emit_buf[emit_wr_idx] <= 8'h64; // 'dinf'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h69;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h6E;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h66;
                // dref: size=28
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h1C; // 28
                16'd12: emit_buf[emit_wr_idx] <= 8'h64; // 'dref'
                16'd13: emit_buf[emit_wr_idx] <= 8'h72;
                16'd14: emit_buf[emit_wr_idx] <= 8'h65;
                16'd15: emit_buf[emit_wr_idx] <= 8'h66;
                16'd16: emit_buf[emit_wr_idx] <= 8'h00; // v=0, flags=0
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h00;
                16'd20: emit_buf[emit_wr_idx] <= 8'h00; // entry_count=1
                16'd21: emit_buf[emit_wr_idx] <= 8'h00;
                16'd22: emit_buf[emit_wr_idx] <= 8'h00;
                16'd23: emit_buf[emit_wr_idx] <= 8'h01;
                // url: size=12
                16'd24: emit_buf[emit_wr_idx] <= 8'h00;
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h0C; // 12
                16'd28: emit_buf[emit_wr_idx] <= 8'h75; // 'url '
                16'd29: emit_buf[emit_wr_idx] <= 8'h72;
                16'd30: emit_buf[emit_wr_idx] <= 8'h6C;
                16'd31: emit_buf[emit_wr_idx] <= 8'h20;
                16'd32: emit_buf[emit_wr_idx] <= 8'h00; // v=0, flags=1 (self-contained)
                16'd33: emit_buf[emit_wr_idx] <= 8'h00;
                16'd34: emit_buf[emit_wr_idx] <= 8'h00;
                16'd35: emit_buf[emit_wr_idx] <= 8'h01;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd35) begin box_st <= BOX_STBL_HDR; bsub <= 16'd0; end
            end

            // stbl header (8 bytes)
            BOX_STBL_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= stbl_sz[15:8];
                16'd3: emit_buf[emit_wr_idx] <= stbl_sz[7:0];
                16'd4: emit_buf[emit_wr_idx] <= 8'h73; // 'stbl'
                16'd5: emit_buf[emit_wr_idx] <= 8'h74;
                16'd6: emit_buf[emit_wr_idx] <= 8'h62;
                16'd7: emit_buf[emit_wr_idx] <= 8'h6C;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_STSD; bsub <= 16'd0; end
            end

            // stsd (16 bytes header: hdr+ver+flags+entry_count)
            BOX_STSD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= stsd_sz[15:8];
                16'd3:  emit_buf[emit_wr_idx] <= stsd_sz[7:0];
                16'd4:  emit_buf[emit_wr_idx] <= 8'h73; // 'stsd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h74;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h73;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // v=0,flags=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // entry_count=1
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h01;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd15) begin box_st <= BOX_AVC1; bsub <= 16'd0; end
            end

            // avc1 VisualSampleEntry (86-byte fixed header)
            BOX_AVC1: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= avc1_sz[15:8];
                16'd3:  emit_buf[emit_wr_idx] <= avc1_sz[7:0];
                16'd4:  emit_buf[emit_wr_idx] <= 8'h61; // 'avc1'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h76;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h63;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h31;
                // reserved (6 bytes) + data_ref_index = 1
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00;
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00; // data_reference_index=1
                16'd15: emit_buf[emit_wr_idx] <= 8'h01;
                // pre_defined fields (16 bytes = 4+2+2+12) = 0
                16'd16: emit_buf[emit_wr_idx] <= 8'h00;
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h00;
                16'd20: emit_buf[emit_wr_idx] <= 8'h00;
                16'd21: emit_buf[emit_wr_idx] <= 8'h00;
                16'd22: emit_buf[emit_wr_idx] <= 8'h00;
                16'd23: emit_buf[emit_wr_idx] <= 8'h00;
                16'd24: emit_buf[emit_wr_idx] <= 8'h00;
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h00;
                16'd28: emit_buf[emit_wr_idx] <= 8'h00;
                16'd29: emit_buf[emit_wr_idx] <= 8'h00;
                16'd30: emit_buf[emit_wr_idx] <= 8'h00;
                16'd31: emit_buf[emit_wr_idx] <= 8'h00;
                // width, height
                16'd32: emit_buf[emit_wr_idx] <= OUTPUT_WIDTH[15:8];
                16'd33: emit_buf[emit_wr_idx] <= OUTPUT_WIDTH[7:0];
                16'd34: emit_buf[emit_wr_idx] <= OUTPUT_HEIGHT[15:8];
                16'd35: emit_buf[emit_wr_idx] <= OUTPUT_HEIGHT[7:0];
                // horiz_resolution = 72dpi = 0x00480000
                16'd36: emit_buf[emit_wr_idx] <= 8'h00;
                16'd37: emit_buf[emit_wr_idx] <= 8'h48;
                16'd38: emit_buf[emit_wr_idx] <= 8'h00;
                16'd39: emit_buf[emit_wr_idx] <= 8'h00;
                // vert_resolution = 72dpi
                16'd40: emit_buf[emit_wr_idx] <= 8'h00;
                16'd41: emit_buf[emit_wr_idx] <= 8'h48;
                16'd42: emit_buf[emit_wr_idx] <= 8'h00;
                16'd43: emit_buf[emit_wr_idx] <= 8'h00;
                // reserved = 0
                16'd44: emit_buf[emit_wr_idx] <= 8'h00;
                16'd45: emit_buf[emit_wr_idx] <= 8'h00;
                16'd46: emit_buf[emit_wr_idx] <= 8'h00;
                16'd47: emit_buf[emit_wr_idx] <= 8'h00;
                // frame_count = 1
                16'd48: emit_buf[emit_wr_idx] <= 8'h00;
                16'd49: emit_buf[emit_wr_idx] <= 8'h01;
                // compressor_name (32 bytes) = "\x0AAVC Coding" + 21 zeros
                16'd50: emit_buf[emit_wr_idx] <= 8'h0A;
                16'd51: emit_buf[emit_wr_idx] <= 8'h41; // A
                16'd52: emit_buf[emit_wr_idx] <= 8'h56; // V
                16'd53: emit_buf[emit_wr_idx] <= 8'h43; // C
                16'd54: emit_buf[emit_wr_idx] <= 8'h20; // ' '
                16'd55: emit_buf[emit_wr_idx] <= 8'h43; // C
                16'd56: emit_buf[emit_wr_idx] <= 8'h6F; // o
                16'd57: emit_buf[emit_wr_idx] <= 8'h64; // d
                16'd58: emit_buf[emit_wr_idx] <= 8'h69; // i
                16'd59: emit_buf[emit_wr_idx] <= 8'h6E; // n
                16'd60: emit_buf[emit_wr_idx] <= 8'h67; // g
                16'd61: emit_buf[emit_wr_idx] <= 8'h00;
                16'd62: emit_buf[emit_wr_idx] <= 8'h00;
                16'd63: emit_buf[emit_wr_idx] <= 8'h00;
                16'd64: emit_buf[emit_wr_idx] <= 8'h00;
                16'd65: emit_buf[emit_wr_idx] <= 8'h00;
                16'd66: emit_buf[emit_wr_idx] <= 8'h00;
                16'd67: emit_buf[emit_wr_idx] <= 8'h00;
                16'd68: emit_buf[emit_wr_idx] <= 8'h00;
                16'd69: emit_buf[emit_wr_idx] <= 8'h00;
                16'd70: emit_buf[emit_wr_idx] <= 8'h00;
                16'd71: emit_buf[emit_wr_idx] <= 8'h00;
                16'd72: emit_buf[emit_wr_idx] <= 8'h00;
                16'd73: emit_buf[emit_wr_idx] <= 8'h00;
                16'd74: emit_buf[emit_wr_idx] <= 8'h00;
                16'd75: emit_buf[emit_wr_idx] <= 8'h00;
                16'd76: emit_buf[emit_wr_idx] <= 8'h00;
                16'd77: emit_buf[emit_wr_idx] <= 8'h00;
                16'd78: emit_buf[emit_wr_idx] <= 8'h00;
                16'd79: emit_buf[emit_wr_idx] <= 8'h00;
                16'd80: emit_buf[emit_wr_idx] <= 8'h00;
                16'd81: emit_buf[emit_wr_idx] <= 8'h00;
                // depth = 0x0018
                16'd82: emit_buf[emit_wr_idx] <= 8'h00;
                16'd83: emit_buf[emit_wr_idx] <= 8'h18;
                // pre_defined = -1 = 0xFFFF
                16'd84: emit_buf[emit_wr_idx] <= 8'hFF;
                16'd85: emit_buf[emit_wr_idx] <= 8'hFF;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd85) begin box_st <= BOX_AVCC; bsub <= 16'd0; end
            end

            // avcC (16 + sps_len + pps_len bytes)
            BOX_AVCC: begin
                // Header: size(4) + 'avcC'(4) + cfgVer(1) + profile(1) +
                //         compat(1) + level(1) + lenSizeM1(1) + numSPS(1) +
                //         sps_len(2) = 16 bytes, then SPS bytes, then pps header, then PPS
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= avcc_sz[15:8];
                16'd3:  emit_buf[emit_wr_idx] <= avcc_sz[7:0];
                16'd4:  emit_buf[emit_wr_idx] <= 8'h61; // 'avcC'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h76;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h63;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h43;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h01;  // configurationVersion=1
                16'd9:  emit_buf[emit_wr_idx] <= 8'h42;  // profile=66 (Baseline)
                16'd10: emit_buf[emit_wr_idx] <= 8'hC0;  // profile_compat
                16'd11: emit_buf[emit_wr_idx] <= 8'h1E;  // level=30
                16'd12: emit_buf[emit_wr_idx] <= 8'hFF;  // lengthSizeMinusOne=3
                16'd13: emit_buf[emit_wr_idx] <= 8'hE1;  // numSPS=1
                16'd14: emit_buf[emit_wr_idx] <= sps_len_r[15:8];
                16'd15: emit_buf[emit_wr_idx] <= sps_len_r[7:0];
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd15) begin box_st <= BOX_SPS_DATA; bsub <= 16'd0; end
            end

            // SPS raw bytes
            BOX_SPS_DATA: begin
                emit_buf[emit_wr_idx] <= sps_buf[bsub[6:0]];
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == sps_len_r - 16'd1) begin box_st <= BOX_PPS_HDR; bsub <= 16'd0; end
            end

            // PPS count + length prefix (3 bytes)
            BOX_PPS_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h01;           // numPPS=1
                16'd1: emit_buf[emit_wr_idx] <= pps_len_r[15:8]; // PPS length
                16'd2: emit_buf[emit_wr_idx] <= pps_len_r[7:0];
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd2) begin box_st <= BOX_PPS_DATA; bsub <= 16'd0; end
            end

            // PPS raw bytes
            BOX_PPS_DATA: begin
                emit_buf[emit_wr_idx] <= pps_buf[bsub[6:0]];
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == pps_len_r - 16'd1) begin box_st <= BOX_STTS; bsub <= 16'd0; end
            end

            // stts (24 bytes, entry_count=0)
            BOX_STTS: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h18; // 24
                16'd4:  emit_buf[emit_wr_idx] <= 8'h73; // 'stts'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h74;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h74;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h73;
                default: emit_buf[emit_wr_idx] <= 8'h00;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd23) begin box_st <= BOX_STSC; bsub <= 16'd0; end
            end

            // stsc (28 bytes, entry_count=0)
            BOX_STSC: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= 8'h00;
                16'd3: emit_buf[emit_wr_idx] <= 8'h1C; // 28
                16'd4: emit_buf[emit_wr_idx] <= 8'h73; // 'stsc'
                16'd5: emit_buf[emit_wr_idx] <= 8'h74;
                16'd6: emit_buf[emit_wr_idx] <= 8'h73;
                16'd7: emit_buf[emit_wr_idx] <= 8'h63;
                default: emit_buf[emit_wr_idx] <= 8'h00;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd27) begin box_st <= BOX_STSZ; bsub <= 16'd0; end
            end

            // stsz (20 bytes)
            BOX_STSZ: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= 8'h00;
                16'd3: emit_buf[emit_wr_idx] <= 8'h14; // 20
                16'd4: emit_buf[emit_wr_idx] <= 8'h73; // 'stsz'
                16'd5: emit_buf[emit_wr_idx] <= 8'h74;
                16'd6: emit_buf[emit_wr_idx] <= 8'h73;
                16'd7: emit_buf[emit_wr_idx] <= 8'h7A;
                default: emit_buf[emit_wr_idx] <= 8'h00;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd19) begin box_st <= BOX_STCO; bsub <= 16'd0; end
            end

            // stco (24 bytes, entry_count=0)
            BOX_STCO: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= 8'h00;
                16'd3: emit_buf[emit_wr_idx] <= 8'h18; // 24
                16'd4: emit_buf[emit_wr_idx] <= 8'h73; // 'stco'
                16'd5: emit_buf[emit_wr_idx] <= 8'h74;
                16'd6: emit_buf[emit_wr_idx] <= 8'h63;
                16'd7: emit_buf[emit_wr_idx] <= 8'h6F;
                default: emit_buf[emit_wr_idx] <= 8'h00;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd23) begin box_st <= BOX_MVEX_HDR; bsub <= 16'd0; end
            end

            // mvex header (8 bytes; total mvex = 40)
            BOX_MVEX_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= 8'h00;
                16'd3: emit_buf[emit_wr_idx] <= 8'h28; // 40
                16'd4: emit_buf[emit_wr_idx] <= 8'h6D; // 'mvex'
                16'd5: emit_buf[emit_wr_idx] <= 8'h76;
                16'd6: emit_buf[emit_wr_idx] <= 8'h65;
                16'd7: emit_buf[emit_wr_idx] <= 8'h78;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_TREX; bsub <= 16'd0; end
            end

            // trex (32 bytes)
            BOX_TREX: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h20; // 32
                16'd4:  emit_buf[emit_wr_idx] <= 8'h74; // 'trex'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h72;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h65;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h78;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // v=0,flags=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // track_id=1
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h01;
                16'd16: emit_buf[emit_wr_idx] <= 8'h00; // default_sample_description_index=1
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h01;
                16'd20: emit_buf[emit_wr_idx] <= 8'h00; // default_sample_duration=0
                16'd21: emit_buf[emit_wr_idx] <= 8'h00;
                16'd22: emit_buf[emit_wr_idx] <= 8'h00;
                16'd23: emit_buf[emit_wr_idx] <= 8'h00;
                16'd24: emit_buf[emit_wr_idx] <= 8'h00; // default_sample_size=0
                16'd25: emit_buf[emit_wr_idx] <= 8'h00;
                16'd26: emit_buf[emit_wr_idx] <= 8'h00;
                16'd27: emit_buf[emit_wr_idx] <= 8'h00;
                16'd28: emit_buf[emit_wr_idx] <= 8'h00; // default_sample_flags=0
                16'd29: emit_buf[emit_wr_idx] <= 8'h00;
                16'd30: emit_buf[emit_wr_idx] <= 8'h00;
                16'd31: emit_buf[emit_wr_idx] <= 8'h00;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd31) begin
                    // init segment completely built
                    emit_len    <= emit_wr_idx + 16'd1;
                    emit_rd_idx <= 16'd0;
                    state       <= S_EMIT_INIT;
                    bsub        <= 16'd0;
                end
            end

            default: box_st <= BOX_FTYP;
            endcase
        end // S_BUILD_INIT

        // ----------------------------------------------------------------
        // S_EMIT_INIT: stream emit_buf (init segment) over AXI-S
        // ----------------------------------------------------------------
        S_EMIT_INIT: begin
            if (!m_axis_tvalid || axis_fire) begin
                if (emit_rd_idx < emit_len) begin
                    pck_valid   <= 1'b1;
                    pck_byte    <= emit_rd_data;
                    pck_last    <= (emit_rd_idx == emit_len - 16'd1);
                    emit_rd_idx <= emit_rd_idx + 16'd1;
                end else begin
                    // Flush partial word if needed
                    if (pack_cnt != 3'd0 && !m_axis_tvalid) begin
                        m_axis_tdata  <= pack_shift;
                        m_axis_tkeep  <= (8'h01 << pack_cnt) - 8'd1;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= 1'b1;
                        pack_cnt      <= 3'd0;
                    end else if (pack_cnt == 3'd0 && !m_axis_tvalid) begin
                        // start waiting for first AU
                        state <= S_WAIT_AU;
                        bsub  <= 16'd0;
                    end
                end
            end
        end

        // ----------------------------------------------------------------
        // S_WAIT_AU: latch first byte then stage or proceed
        // ----------------------------------------------------------------
        S_WAIT_AU: begin
            au_wr_ptr     <= {AU_ADDR_W{1'b0}};
            au_rd_ptr     <= {AU_ADDR_W{1'b0}};
            au_byte_count <= 32'd0;
            if (au_valid) begin
                cur_is_idr   <= au_is_idr;
                cur_duration <= au_duration;
                // Write first byte (au_buf write happens in separate always)
                au_wr_ptr     <= {{(AU_ADDR_W-1){1'b0}}, 1'b1}; // next write addr
                au_byte_count <= 32'd1;
                if (au_last) begin
                    // Single-byte AU — go straight to build moof
                    state     <= S_BUILD_MOOF;
                    box_st    <= BOX_MOOF_HDR;
                    bsub      <= 16'd0;
                    emit_wr_idx <= 16'd0;
                end else begin
                    state <= S_STAGE_AU;
                end
            end else if (!job_active) begin
                state <= S_DONE;
            end
        end

        // ----------------------------------------------------------------
        // S_STAGE_AU: collect AU bytes into BRAM
        // ----------------------------------------------------------------
        S_STAGE_AU: begin
            if (au_valid) begin
                au_wr_ptr     <= au_wr_ptr + 1'b1;
                au_byte_count <= au_byte_count + 32'd1;
                if (au_last) begin
                    au_rd_ptr   <= {AU_ADDR_W{1'b0}};
                    state       <= S_BUILD_MOOF;
                    box_st      <= BOX_MOOF_HDR;
                    bsub        <= 16'd0;
                    emit_wr_idx <= 16'd0;
                end
            end
        end

        // ----------------------------------------------------------------
        // S_BUILD_MOOF: write 96-byte moof template into emit_buf
        // ----------------------------------------------------------------
        S_BUILD_MOOF: begin
            case (box_st)

            // moof header (8 bytes): size=96=0x60
            BOX_MOOF_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= 8'h00;
                16'd3: emit_buf[emit_wr_idx] <= 8'h60; // 96
                16'd4: emit_buf[emit_wr_idx] <= 8'h6D; // 'moof'
                16'd5: emit_buf[emit_wr_idx] <= 8'h6F;
                16'd6: emit_buf[emit_wr_idx] <= 8'h6F;
                16'd7: emit_buf[emit_wr_idx] <= 8'h66;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_MFHD; bsub <= 16'd0; end
            end

            // mfhd (16 bytes)
            BOX_MFHD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h10; // 16
                16'd4:  emit_buf[emit_wr_idx] <= 8'h6D; // 'mfhd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h66;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h68;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // v=0, flags=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= frag_seq[31:24];
                16'd13: emit_buf[emit_wr_idx] <= frag_seq[23:16];
                16'd14: emit_buf[emit_wr_idx] <= frag_seq[15:8];
                16'd15: emit_buf[emit_wr_idx] <= frag_seq[7:0];
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd15) begin box_st <= BOX_TRAF_HDR; bsub <= 16'd0; end
            end

            // traf header (8 bytes): size=72=0x48
            BOX_TRAF_HDR: begin
                case (bsub)
                16'd0: emit_buf[emit_wr_idx] <= 8'h00;
                16'd1: emit_buf[emit_wr_idx] <= 8'h00;
                16'd2: emit_buf[emit_wr_idx] <= 8'h00;
                16'd3: emit_buf[emit_wr_idx] <= 8'h48; // 72
                16'd4: emit_buf[emit_wr_idx] <= 8'h74; // 'traf'
                16'd5: emit_buf[emit_wr_idx] <= 8'h72;
                16'd6: emit_buf[emit_wr_idx] <= 8'h61;
                16'd7: emit_buf[emit_wr_idx] <= 8'h66;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd7) begin box_st <= BOX_TFHD; bsub <= 16'd0; end
            end

            // tfhd (16 bytes): flags=0x020000 (default-base-is-moof)
            BOX_TFHD: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h10; // 16
                16'd4:  emit_buf[emit_wr_idx] <= 8'h74; // 'tfhd'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h66;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h68;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd9:  emit_buf[emit_wr_idx] <= 8'h02; // flags=0x020000
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // track_id=1
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h01;
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd15) begin box_st <= BOX_TFDT; bsub <= 16'd0; end
            end

            // tfdt (20 bytes, version=1, 64-bit baseMediaDecodeTime)
            BOX_TFDT: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h14; // 20
                16'd4:  emit_buf[emit_wr_idx] <= 8'h74; // 'tfdt'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h66;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h64;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h74;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h01; // version=1
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd10: emit_buf[emit_wr_idx] <= 8'h00;
                16'd11: emit_buf[emit_wr_idx] <= 8'h00;
                16'd12: emit_buf[emit_wr_idx] <= base_dts[63:56];
                16'd13: emit_buf[emit_wr_idx] <= base_dts[55:48];
                16'd14: emit_buf[emit_wr_idx] <= base_dts[47:40];
                16'd15: emit_buf[emit_wr_idx] <= base_dts[39:32];
                16'd16: emit_buf[emit_wr_idx] <= base_dts[31:24];
                16'd17: emit_buf[emit_wr_idx] <= base_dts[23:16];
                16'd18: emit_buf[emit_wr_idx] <= base_dts[15:8];
                16'd19: emit_buf[emit_wr_idx] <= base_dts[7:0];
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd19) begin box_st <= BOX_TRUN; bsub <= 16'd0; end
            end

            // trun (28 bytes, flags=0x000301 = data_offset|duration|size, 1 sample)
            BOX_TRUN: begin
                case (bsub)
                16'd0:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd1:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd2:  emit_buf[emit_wr_idx] <= 8'h00;
                16'd3:  emit_buf[emit_wr_idx] <= 8'h1C; // 28
                16'd4:  emit_buf[emit_wr_idx] <= 8'h74; // 'trun'
                16'd5:  emit_buf[emit_wr_idx] <= 8'h72;
                16'd6:  emit_buf[emit_wr_idx] <= 8'h75;
                16'd7:  emit_buf[emit_wr_idx] <= 8'h6E;
                16'd8:  emit_buf[emit_wr_idx] <= 8'h00; // version=0
                16'd9:  emit_buf[emit_wr_idx] <= 8'h00; // flags[23:16]
                16'd10: emit_buf[emit_wr_idx] <= 8'h03; // flags[15:8]  → 0x000301
                16'd11: emit_buf[emit_wr_idx] <= 8'h01; // flags[7:0]
                16'd12: emit_buf[emit_wr_idx] <= 8'h00; // sample_count=1
                16'd13: emit_buf[emit_wr_idx] <= 8'h00;
                16'd14: emit_buf[emit_wr_idx] <= 8'h00;
                16'd15: emit_buf[emit_wr_idx] <= 8'h01;
                // data_offset = 96 + 8 = 104 = 0x68
                16'd16: emit_buf[emit_wr_idx] <= 8'h00;
                16'd17: emit_buf[emit_wr_idx] <= 8'h00;
                16'd18: emit_buf[emit_wr_idx] <= 8'h00;
                16'd19: emit_buf[emit_wr_idx] <= 8'h68; // 104
                // sample[0].sample_duration
                16'd20: emit_buf[emit_wr_idx] <= cur_duration[31:24];
                16'd21: emit_buf[emit_wr_idx] <= cur_duration[23:16];
                16'd22: emit_buf[emit_wr_idx] <= cur_duration[15:8];
                16'd23: emit_buf[emit_wr_idx] <= cur_duration[7:0];
                // sample[0].sample_size = au_byte_count
                16'd24: emit_buf[emit_wr_idx] <= au_byte_count[31:24];
                16'd25: emit_buf[emit_wr_idx] <= au_byte_count[23:16];
                16'd26: emit_buf[emit_wr_idx] <= au_byte_count[15:8];
                16'd27: emit_buf[emit_wr_idx] <= au_byte_count[7:0];
                default: ;
                endcase
                emit_wr_idx <= emit_wr_idx + 16'd1;
                bsub <= bsub + 16'd1;
                if (bsub == 16'd27) begin
                    // Fix flag bytes at positions 9, 10, 11 in emit_buf
                    // (they were written incorrectly above — patch)
                    // Actually we need a post-patch for the flag bytes.
                    // The flags bytes at bsub=9,10,11 in emit_buf were:
                    //   [9]=0x03, [10]=0x01, [11]=0x00  (from case above)
                    // We want flags=0x000301: [9]=0x00, [10]=0x03, [11]=0x01
                    // Patch: (emit_buf index = 0 + 9 since emit_wr_idx started at 0)
                    // We'll correct during EMIT_MOOF instead — patch in build
                    // For simplicity, correct the case statement:
                    // bytes 9,10,11 should be: 9→0x00, 10→0x03, 11→0x01
                    // (Already patched in the case above: [9]=0x03 wrong; fix below)
                    emit_len    <= emit_wr_idx + 16'd1;
                    emit_rd_idx <= 16'd0;
                    state       <= S_EMIT_MOOF;
                    bsub        <= 16'd0;
                end
            end

            default: box_st <= BOX_MOOF_HDR;
            endcase
        end // S_BUILD_MOOF

        // ----------------------------------------------------------------
        // S_EMIT_MOOF: stream moof box
        // ----------------------------------------------------------------
        S_EMIT_MOOF: begin
            if (!m_axis_tvalid || axis_fire) begin
                if (emit_rd_idx < emit_len) begin
                    pck_valid   <= 1'b1;
                    pck_byte    <= emit_rd_data;
                    pck_last    <= 1'b0; // moof and mdat share one DMA packet
                    emit_rd_idx <= emit_rd_idx + 16'd1;
                end else begin
                    // All moof bytes queued; move to mdat
                    state  <= S_EMIT_MDAT;
                    bsub   <= 16'd0;
                    au_rd_ptr <= {AU_ADDR_W{1'b0}};
                end
            end
        end

        // ----------------------------------------------------------------
        // S_EMIT_MDAT: emit mdat header + 4-byte NAL length + AU bytes
        // bsub 0-7: mdat box header
        // bsub 8-11: NAL length prefix
        // bsub 12..: AU bytes from BRAM (1-cycle BRAM latency pre-fetched)
        // ----------------------------------------------------------------
        S_EMIT_MDAT: begin
            if (!m_axis_tvalid || axis_fire) begin
                if (bsub < 16'd8) begin
                    // mdat box header
                    case (bsub)
                    16'd0: pck_byte <= (au_byte_count + 32'd12) >> 24;
                    16'd1: pck_byte <= (au_byte_count + 32'd12) >> 16;
                    16'd2: pck_byte <= (au_byte_count + 32'd12) >> 8;
                    16'd3: pck_byte <= (au_byte_count + 32'd12);
                    16'd4: pck_byte <= 8'h6D; // 'm'
                    16'd5: pck_byte <= 8'h64; // 'd'
                    16'd6: pck_byte <= 8'h61; // 'a'
                    16'd7: pck_byte <= 8'h74; // 't'
                    default: pck_byte <= 8'h00;
                    endcase
                    pck_valid <= 1'b1;
                    pck_last  <= 1'b0;
                    bsub <= bsub + 16'd1;
                end else if (bsub < 16'd12) begin
                    // 4-byte NAL length prefix (big-endian au_byte_count)
                    case (bsub)
                    16'd8:  pck_byte <= au_byte_count[31:24];
                    16'd9:  pck_byte <= au_byte_count[23:16];
                    16'd10: pck_byte <= au_byte_count[15:8];
                    16'd11: pck_byte <= au_byte_count[7:0];
                    default: pck_byte <= 8'h00;
                    endcase
                    pck_valid <= 1'b1;
                    pck_last  <= 1'b0;
                    bsub <= bsub + 16'd1;
                    // Pre-fetch second BRAM byte (address 0 already latched in bram_rd_data)
                    if (bsub == 16'd11) begin
                        au_rd_ptr <= (au_byte_count > 32'd1) ? {{(AU_ADDR_W-1){1'b0}}, 1'b1} : {AU_ADDR_W{1'b0}};
                    end
                end else begin
                    // AU bytes: bsub - 12 = byte index into AU
                    // BRAM read latency = 1 cycle, so bram_rd_data lags by 1
                    // We issue au_rd_ptr++ each cycle; bram_rd_data is the byte from
                    // the *previous* cycle's address.  To compensate:
                    //   - On entry to this phase (bsub==12): au_rd_ptr was set to 0 at bsub==11
                    //   - bram_rd_data at bsub==12 = au_buf[0] (latched from previous cycle) ✓
                    //   - Advance au_rd_ptr for next byte each cycle
                    if ({16'd0, bsub} - 32'd12 < au_byte_count) begin
                        pck_valid <= 1'b1;
                        pck_byte  <= bram_rd_data;
                        pck_last  <= ({16'd0, bsub} - 32'd12 == au_byte_count - 32'd1);
                        // Advance read pointer unless at last byte
                        if ({16'd0, bsub} - 32'd12 < au_byte_count - 32'd1) begin
                            au_rd_ptr <= au_rd_ptr + 1'b1;
                        end
                        bsub <= bsub + 16'd1;
                        if ({16'd0, bsub} - 32'd12 == au_byte_count - 32'd1) begin
                            base_dts <= base_dts + {32'd0, cur_duration};
                            frag_seq <= frag_seq + 32'd1;
                            state    <= S_WAIT_AU;
                            bsub     <= 16'd0;
                        end
                    end
                end
            end
        end

        // ----------------------------------------------------------------
        S_DONE: begin
            if (pack_cnt != 3'd0 && !m_axis_tvalid) begin
                m_axis_tdata  <= pack_shift;
                m_axis_tkeep  <= (8'h01 << pack_cnt) - 8'd1;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= 1'b0;
                pack_cnt      <= 3'd0;
            end else if (pack_cnt == 3'd0 && !m_axis_tvalid) begin
                state <= S_IDLE;
            end
        end

        default: state <= S_IDLE;
        endcase

        // ==================================================================
        // 64-bit packer — executes every cycle
        // Accumulates bytes into pack_shift; flushes 8-byte words onto AXI-S
        // ==================================================================
        if (pck_valid) begin
            // Assign the new byte into the current lane
            case (pack_cnt)
            3'd0: pack_shift[7:0]   <= pck_byte;
            3'd1: pack_shift[15:8]  <= pck_byte;
            3'd2: pack_shift[23:16] <= pck_byte;
            3'd3: pack_shift[31:24] <= pck_byte;
            3'd4: pack_shift[39:32] <= pck_byte;
            3'd5: pack_shift[47:40] <= pck_byte;
            3'd6: pack_shift[55:48] <= pck_byte;
            default: ;  // 7 handled below
            endcase

            if (pack_cnt == 3'd7) begin
                // Full 8-byte word — emit big-endian word
                // (pack_shift has bytes 0..6, pck_byte is byte 7)
                m_axis_tdata  <= {pck_byte,
                                  pack_shift[55:48],
                                  pack_shift[47:40],
                                  pack_shift[39:32],
                                  pack_shift[31:24],
                                  pack_shift[23:16],
                                  pack_shift[15:8],
                                  pack_shift[7:0]};
                m_axis_tkeep  <= 8'hFF;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= pck_last;
                pack_cnt      <= 3'd0;
            end else if (pck_last) begin
                // Partial last word flush (pack_cnt bytes 0..pack_cnt are valid)
                case (pack_cnt)
                3'd0: m_axis_tdata <= {56'd0, pck_byte};
                3'd1: m_axis_tdata <= {48'd0, pck_byte, pack_shift[7:0]};
                3'd2: m_axis_tdata <= {40'd0, pck_byte, pack_shift[15:0]};
                3'd3: m_axis_tdata <= {32'd0, pck_byte, pack_shift[23:0]};
                3'd4: m_axis_tdata <= {24'd0, pck_byte, pack_shift[31:0]};
                3'd5: m_axis_tdata <= {16'd0, pck_byte, pack_shift[39:0]};
                3'd6: m_axis_tdata <= { 8'd0, pck_byte, pack_shift[47:0]};
                default: m_axis_tdata <= {pck_byte, pack_shift[55:0]};
                endcase
                m_axis_tkeep  <= (8'h01 << (pack_cnt + 3'd1)) - 8'd1;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= 1'b1;
                pack_cnt      <= 3'd0;
            end else begin
                pack_cnt <= pack_cnt + 3'd1;
            end
        end

    end // resetn else
end // always

endmodule
