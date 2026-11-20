// =============================================================================
// tb_model4_fmp4_muxer.sv
// Self-checking testbench for model4_fmp4_muxer
//
// Test sequence:
//   1. Assert config_valid with SPS/PPS data
//   2. Assert job_active
//   3. Feed 3 access units:
//        AU0: IDR, 10 bytes, duration=3000 (1/30s @90kHz)
//        AU1: P,   8 bytes, duration=3000
//        AU2: P,   6 bytes, duration=3000
//   4. De-assert job_active
//   5. Collect all bytes from AXI-S
//   6. Parse and check:
//        - bytes[0..3] = 0x00000010 (ftyp size=16) ← init segment starts
//        - bytes[4..7] = 'ftyp'
//        - scan for 'moov' box
//        - for each frame: find 'moof' then 'mdat'
//        - check mdat starts with 4-byte NAL length = au_byte_count
//   7. Print PASS/FAIL
// =============================================================================
`timescale 1ns / 1ps

module tb_model4_fmp4_muxer;

// -------------------------------------------------------------------------
// Clock and reset
// -------------------------------------------------------------------------
reg clk   = 0;
reg resetn = 0;
always #5 clk = ~clk; // 100 MHz

// -------------------------------------------------------------------------
// DUT signals
// -------------------------------------------------------------------------
reg        au_valid   = 0;
reg [7:0]  au_data    = 0;
reg        au_last    = 0;
reg        au_is_idr  = 0;
reg [31:0] au_pts     = 0;
reg [31:0] au_duration = 0;
reg [31:0] frame_id   = 0;
reg        job_active = 0;

reg [7:0]  sps_data   = 0;
reg [15:0] sps_len    = 0;
reg [7:0]  pps_data   = 0;
reg [15:0] pps_len    = 0;
reg        config_valid = 0;

wire [63:0] m_axis_tdata;
wire        m_axis_tvalid;
reg         m_axis_tready = 1; // always ready
wire [7:0]  m_axis_tkeep;
wire        m_axis_tlast;

// -------------------------------------------------------------------------
// DUT instantiation
// -------------------------------------------------------------------------
model4_fmp4_muxer #(
    .AU_BUF_BYTES  (16384),
    .OUTPUT_WIDTH  (256),
    .OUTPUT_HEIGHT (144)
) dut (
    .clk           (clk),
    .resetn        (resetn),
    .au_valid      (au_valid),
    .au_data       (au_data),
    .au_last       (au_last),
    .au_is_idr     (au_is_idr),
    .au_pts        (au_pts),
    .au_duration   (au_duration),
    .frame_id      (frame_id),
    .job_active    (job_active),
    .sps_data      (sps_data),
    .sps_len       (sps_len),
    .pps_data      (pps_data),
    .pps_len       (pps_len),
    .config_valid  (config_valid),
    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tkeep  (m_axis_tkeep),
    .m_axis_tlast  (m_axis_tlast)
);

// -------------------------------------------------------------------------
// Byte capture buffer
// -------------------------------------------------------------------------
localparam integer MAX_CAPTURE = 65536;
reg [7:0] cap_bytes [0:MAX_CAPTURE-1];
integer   cap_len = 0;

// -------------------------------------------------------------------------
// Capture task: collect AXI-Stream bytes
// -------------------------------------------------------------------------
task automatic capture_bytes;
    integer i, valid_bytes;
    begin
        // Count valid bytes in this beat from TKEEP
        valid_bytes = 0;
        for (i = 0; i < 8; i = i + 1) begin
            if (m_axis_tkeep[i]) valid_bytes = i + 1;
        end
        for (i = 0; i < valid_bytes; i = i + 1) begin
            if (cap_len < MAX_CAPTURE) begin
                // AXI-S data is little-endian (byte 0 in LSB)
                cap_bytes[cap_len] = m_axis_tdata[i*8 +: 8];
                cap_len = cap_len + 1;
            end
        end
    end
endtask

// -------------------------------------------------------------------------
// Drive SPS/PPS into the DUT's internal arrays directly (plusarg/backdoor)
// Since sps_buf / pps_buf are inside the DUT, we backdoor-write them.
// -------------------------------------------------------------------------
// SPS: 10 bytes of fake SPS (0x67, 0x42, 0xC0, 0x1E, 0xDA, 0x05, 0x82, 0x68, 0x20, 0x00)
// PPS: 4 bytes of fake PPS (0x68, 0xCE, 0x38, 0x80)
localparam integer SPS_LEN = 10;
localparam integer PPS_LEN = 4;

reg [7:0] sps_ref [0:SPS_LEN-1];
reg [7:0] pps_ref [0:PPS_LEN-1];

// -------------------------------------------------------------------------
// AU byte arrays for 3 test frames
// -------------------------------------------------------------------------
localparam integer AU0_LEN = 10;
localparam integer AU1_LEN = 8;
localparam integer AU2_LEN = 6;

reg [7:0] au0_bytes [0:AU0_LEN-1]; // IDR
reg [7:0] au1_bytes [0:AU1_LEN-1]; // P
reg [7:0] au2_bytes [0:AU2_LEN-1]; // P

// -------------------------------------------------------------------------
// Clock helper
// -------------------------------------------------------------------------
task clk_wait;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
endtask

// -------------------------------------------------------------------------
// Feed one access unit
// -------------------------------------------------------------------------
task feed_au;
    input [7:0]  bytes_arr [0:255];
    input integer byte_cnt;
    input         is_idr;
    input [31:0]  dur;
    input [31:0]  pts;
    input [31:0]  fid;
    integer       j;
    begin
        for (j = 0; j < byte_cnt; j = j + 1) begin
            @(posedge clk);
            au_valid    <= 1'b1;
            au_data     <= bytes_arr[j];
            au_last     <= (j == byte_cnt - 1);
            au_is_idr   <= is_idr;
            au_duration <= dur;
            au_pts      <= pts;
            frame_id    <= fid;
        end
        @(posedge clk);
        au_valid <= 1'b0;
        au_last  <= 1'b0;
    end
endtask

// -------------------------------------------------------------------------
// Collect AXI-S output (monitor loop, runs in parallel via always block)
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (m_axis_tvalid && m_axis_tready) begin
        capture_bytes();
    end
end

// -------------------------------------------------------------------------
// Check helpers
// -------------------------------------------------------------------------
function automatic [31:0] read_be32;
    input integer base;
    begin
        read_be32 = {cap_bytes[base], cap_bytes[base+1],
                     cap_bytes[base+2], cap_bytes[base+3]};
    end
endfunction

function automatic [31:0] find_fourcc;
    input [31:0] start;
    input [7:0]  c0, c1, c2, c3;
    integer       k;
    reg found;
    begin
        found = 0;
        for (k = start; k < cap_len - 3 && !found; k = k + 1) begin
            if (cap_bytes[k]   == c0 && cap_bytes[k+1] == c1 &&
                cap_bytes[k+2] == c2 && cap_bytes[k+3] == c3) begin
                find_fourcc = k;
                found = 1;
            end
        end
        if (!found) find_fourcc = 32'hFFFF_FFFF;
    end
endfunction

// -------------------------------------------------------------------------
// Main stimulus
// -------------------------------------------------------------------------
integer fail_count;
integer pass_count;
integer pos;
integer ftyp_pos, moov_pos, moof1_pos, moof2_pos, moof3_pos;
integer mdat1_pos, mdat2_pos, mdat3_pos;
reg [31:0] sz, nal_len;

// Wide byte arrays for feed_au (max 256 bytes)
reg [7:0] feed_buf [0:255];
integer idx;

initial begin
    $display("======================================================");
    $display(" tb_model4_fmp4_muxer — fMP4 muxer self-check");
    $display("======================================================");

    fail_count = 0;
    pass_count = 0;

    // ---- Init SPS / PPS reference data ----
    sps_ref[0] = 8'h67; sps_ref[1] = 8'h42; sps_ref[2] = 8'hC0;
    sps_ref[3] = 8'h1E; sps_ref[4] = 8'hDA; sps_ref[5] = 8'h05;
    sps_ref[6] = 8'h82; sps_ref[7] = 8'h68; sps_ref[8] = 8'h20;
    sps_ref[9] = 8'h00;

    pps_ref[0] = 8'h68; pps_ref[1] = 8'hCE;
    pps_ref[2] = 8'h38; pps_ref[3] = 8'h80;

    // ---- Init AU data ----
    au0_bytes[0]=8'h00; au0_bytes[1]=8'h00; au0_bytes[2]=8'h00;
    au0_bytes[3]=8'h01; au0_bytes[4]=8'h65; au0_bytes[5]=8'hB8;
    au0_bytes[6]=8'h00; au0_bytes[7]=8'hF0; au0_bytes[8]=8'hA0;
    au0_bytes[9]=8'h00;

    au1_bytes[0]=8'h00; au1_bytes[1]=8'h00; au1_bytes[2]=8'h00;
    au1_bytes[3]=8'h01; au1_bytes[4]=8'h41; au1_bytes[5]=8'hA0;
    au1_bytes[6]=8'hB0; au1_bytes[7]=8'hC0;

    au2_bytes[0]=8'h00; au2_bytes[1]=8'h00; au2_bytes[2]=8'h00;
    au2_bytes[3]=8'h01; au2_bytes[4]=8'h41; au2_bytes[5]=8'hD0;

    // ---- Reset ----
    resetn = 0;
    @(posedge clk); @(posedge clk);
    resetn = 1;
    @(posedge clk);

    // ---- Back-door write SPS/PPS into DUT BRAM ----
    begin : init_spspps
        integer k;
        for (k = 0; k < SPS_LEN; k = k + 1)
            dut.sps_buf[k] = sps_ref[k];
        for (k = 0; k < PPS_LEN; k = k + 1)
            dut.pps_buf[k] = pps_ref[k];
    end

    // ---- Strobe config_valid to latch SPS/PPS lengths ----
    @(posedge clk);
    sps_len     <= SPS_LEN;
    pps_len     <= PPS_LEN;
    config_valid <= 1'b1;
    @(posedge clk);
    config_valid <= 1'b0;
    @(posedge clk);

    // ---- Start job ----
    job_active <= 1'b1;
    @(posedge clk);

    // ---- Wait for init segment to be emitted (watch for first tlast) ----
    while (!(m_axis_tvalid && m_axis_tlast && m_axis_tready)) @(posedge clk);
    @(posedge clk);

    // ---- Feed AU0 (IDR, 10 bytes) ----
    for (idx = 0; idx < AU0_LEN; idx = idx + 1) feed_buf[idx] = au0_bytes[idx];
    feed_au(feed_buf, AU0_LEN, 1'b1, 32'd3000, 32'd0, 32'd0);

    // Wait for frame 0 (tlast)
    while (!(m_axis_tvalid && m_axis_tlast && m_axis_tready)) @(posedge clk);
    @(posedge clk);

    // ---- Feed AU1 (P, 8 bytes) ----
    for (idx = 0; idx < AU1_LEN; idx = idx + 1) feed_buf[idx] = au1_bytes[idx];
    feed_au(feed_buf, AU1_LEN, 1'b0, 32'd3000, 32'd3000, 32'd1);

    // Wait for frame 1 (tlast)
    while (!(m_axis_tvalid && m_axis_tlast && m_axis_tready)) @(posedge clk);
    @(posedge clk);

    // ---- Feed AU2 (P, 6 bytes) ----
    for (idx = 0; idx < AU2_LEN; idx = idx + 1) feed_buf[idx] = au2_bytes[idx];
    feed_au(feed_buf, AU2_LEN, 1'b0, 32'd3000, 32'd6000, 32'd2);

    // Wait for frame 2 (tlast)
    while (!(m_axis_tvalid && m_axis_tlast && m_axis_tready)) @(posedge clk);
    @(posedge clk);

    // ---- End job ----
    @(posedge clk);
    job_active <= 1'b0;

    // ---- Wait for all output to drain ----
    clk_wait(5000);

    // ================================================================
    // Check captured byte stream
    // ================================================================
    $display("\n--- Captured %0d bytes total ---", cap_len);
    $display("First 32 bytes captured:");
    for (idx = 0; idx < 32 && idx < cap_len; idx = idx + 1) begin
        $write("%02X ", cap_bytes[idx]);
        if ((idx & 15) == 15) $write("\n");
    end
    $write("\n");

    // ---- Check 1: starts with ftyp ----
    $display("\nCheck 1: Init segment starts with ftyp box");
    if (cap_len < 8) begin
        $display("  FAIL: too few bytes captured (%0d)", cap_len);
        fail_count = fail_count + 1;
    end else begin
        ftyp_pos = 0;
        sz = read_be32(0);
        if (sz != 32'h10) begin
            $display("  FAIL: ftyp size = 0x%08X (expected 0x00000010)", sz);
            fail_count = fail_count + 1;
        end else if (cap_bytes[4] != 8'h66 || cap_bytes[5] != 8'h74 ||
                     cap_bytes[6] != 8'h79 || cap_bytes[7] != 8'h70) begin
            $display("  FAIL: ftyp fourcc mismatch: %02X %02X %02X %02X",
                cap_bytes[4], cap_bytes[5], cap_bytes[6], cap_bytes[7]);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: ftyp box found at offset 0, size=16");
            pass_count = pass_count + 1;
        end
    end

    // ---- Check 2: moov box present ----
    $display("\nCheck 2: moov box present after ftyp");
    moov_pos = find_fourcc(4, 8'h6D, 8'h6F, 8'h6F, 8'h76); // 'moov'
    if (moov_pos == 32'hFFFF_FFFF) begin
        $display("  FAIL: moov not found");
        fail_count = fail_count + 1;
    end else begin
        // moov fourcc is at moov_pos; box starts 4 bytes before it
        pos = moov_pos - 4;
        sz  = read_be32(pos);
        $display("  PASS: moov found at byte offset %0d, reported size=%0d", pos, sz);
        pass_count = pass_count + 1;
    end

    // ---- Check 3: avcC box present inside moov ----
    $display("\nCheck 3: avcC box present inside moov");
    begin
        integer avcc_pos;
        avcc_pos = find_fourcc(moov_pos, 8'h61, 8'h76, 8'h63, 8'h43); // 'avcC'
        if (avcc_pos == 32'hFFFF_FFFF) begin
            $display("  FAIL: avcC not found");
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: avcC found at byte offset %0d", avcc_pos - 4);
            pass_count = pass_count + 1;
        end
    end

    // ---- Check 4: 3 moof boxes ----
    $display("\nCheck 4: 3 moof boxes (one per frame)");
    moof1_pos = find_fourcc(moov_pos, 8'h6D, 8'h6F, 8'h6F, 8'h66); // 'moof'
    if (moof1_pos == 32'hFFFF_FFFF) begin
        $display("  FAIL: moof #1 not found");
        fail_count = fail_count + 1;
    end else begin
        moof2_pos = find_fourcc(moof1_pos + 4, 8'h6D, 8'h6F, 8'h6F, 8'h66);
        if (moof2_pos == 32'hFFFF_FFFF) begin
            $display("  FAIL: moof #2 not found");
            fail_count = fail_count + 1;
        end else begin
            moof3_pos = find_fourcc(moof2_pos + 4, 8'h6D, 8'h6F, 8'h6F, 8'h66);
            if (moof3_pos == 32'hFFFF_FFFF) begin
                $display("  FAIL: moof #3 not found");
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS: moof #1 at %0d, #2 at %0d, #3 at %0d",
                    moof1_pos-4, moof2_pos-4, moof3_pos-4);
                pass_count = pass_count + 1;
            end
        end
    end

    // ---- Check 5: mdat after each moof ----
    $display("\nCheck 5: mdat follows each moof");
    mdat1_pos = find_fourcc(moof1_pos, 8'h6D, 8'h64, 8'h61, 8'h74); // 'mdat'
    mdat2_pos = find_fourcc(moof2_pos, 8'h6D, 8'h64, 8'h61, 8'h74);
    mdat3_pos = find_fourcc(moof3_pos, 8'h6D, 8'h64, 8'h61, 8'h74);

    if (mdat1_pos == 32'hFFFF_FFFF || mdat2_pos == 32'hFFFF_FFFF || mdat3_pos == 32'hFFFF_FFFF) begin
        $display("  FAIL: not all mdat boxes found (m1=%0h m2=%0h m3=%0h)",
            mdat1_pos, mdat2_pos, mdat3_pos);
        fail_count = fail_count + 1;
    end else begin
        $display("  PASS: mdat #1 at %0d, #2 at %0d, #3 at %0d",
            mdat1_pos-4, mdat2_pos-4, mdat3_pos-4);
        pass_count = pass_count + 1;
    end

    // ---- Check 6: mdat NAL length prefixes match AU sizes ----
    $display("\nCheck 6: mdat NAL length prefixes");
    if (mdat1_pos != 32'hFFFF_FFFF) begin
        // NAL len is at mdat fourcc + 4 (4 bytes for the box header + 4 for data)
        // mdat layout: size(4) + 'mdat'(4) + nal_len(4) + data
        // mdat1_pos points to 'm' of 'mdat', so:
        //   box_start = mdat1_pos - 4
        //   nal_len is at mdat1_pos + 4
        nal_len = read_be32(mdat1_pos + 4);
        if (nal_len != AU0_LEN) begin
            $display("  FAIL: mdat#1 NAL len=%0d expected %0d", nal_len, AU0_LEN);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: mdat#1 NAL len=%0d ✓", nal_len);
            pass_count = pass_count + 1;
        end

        nal_len = read_be32(mdat2_pos + 4);
        if (nal_len != AU1_LEN) begin
            $display("  FAIL: mdat#2 NAL len=%0d expected %0d", nal_len, AU1_LEN);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: mdat#2 NAL len=%0d ✓", nal_len);
            pass_count = pass_count + 1;
        end

        nal_len = read_be32(mdat3_pos + 4);
        if (nal_len != AU2_LEN) begin
            $display("  FAIL: mdat#3 NAL len=%0d expected %0d", nal_len, AU2_LEN);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: mdat#3 NAL len=%0d ✓", nal_len);
            pass_count = pass_count + 1;
        end
    end

    // ---- Check 7: mdat payload bytes match AU ----
    $display("\nCheck 7: mdat payload bytes match AU data");
    if (mdat1_pos != 32'hFFFF_FFFF) begin
        begin : chk_au0
            integer k; integer ok;
            ok = 1;
            for (k = 0; k < AU0_LEN && ok; k = k + 1) begin
                if (cap_bytes[mdat1_pos + 8 + k] !== au0_bytes[k]) begin
                    $display("  FAIL: AU0 byte[%0d] = 0x%02X, expected 0x%02X",
                        k, cap_bytes[mdat1_pos + 8 + k], au0_bytes[k]);
                    ok = 0;
                    fail_count = fail_count + 1;
                end
            end
            if (ok) begin
                $display("  PASS: AU0 payload bytes correct");
                pass_count = pass_count + 1;
            end
        end

        begin : chk_au1
            integer k; integer ok;
            ok = 1;
            for (k = 0; k < AU1_LEN && ok; k = k + 1) begin
                if (cap_bytes[mdat2_pos + 8 + k] !== au1_bytes[k]) begin
                    $display("  FAIL: AU1 byte[%0d] = 0x%02X, expected 0x%02X",
                        k, cap_bytes[mdat2_pos + 8 + k], au1_bytes[k]);
                    ok = 0;
                    fail_count = fail_count + 1;
                end
            end
            if (ok) begin
                $display("  PASS: AU1 payload bytes correct");
                pass_count = pass_count + 1;
            end
        end
    end

    // ---- Check 8: moof size field = 96 ----
    $display("\nCheck 8: moof box size = 96");
    if (moof1_pos != 32'hFFFF_FFFF) begin
        sz = read_be32(moof1_pos - 4);
        if (sz !== 32'd96) begin
            $display("  FAIL: moof#1 size=%0d expected 96", sz);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: moof#1 size=96 ✓");
            pass_count = pass_count + 1;
        end
    end

    // ---- Check 9: mfhd sequence numbers ----
    $display("\nCheck 9: mfhd sequence numbers (1, 2, 3)");
    if (moof1_pos != 32'hFFFF_FFFF) begin
        begin : chk_seq
            integer mfhd_pos;
            reg [31:0] seq1, seq2, seq3;
            // mfhd is at moof_pos + 4 (after moof hdr 8 bytes, mfhd fourcc at +4+4)
            // mfhd fourcc at moof_start + 8 + 4 = moof_fourcc + 8 + 4
            mfhd_pos = find_fourcc(moof1_pos, 8'h6D, 8'h66, 8'h68, 8'h64); // 'mfhd'
            if (mfhd_pos == 32'hFFFF_FFFF) begin
                $display("  FAIL: mfhd not found in moof#1");
                fail_count = fail_count + 1;
            end else begin
                // sequence_number is at mfhd_pos + 8 (after fourcc + ver+flags)
                seq1 = read_be32(mfhd_pos + 8);
                $display("  moof#1 sequence_number = %0d", seq1);
                if (seq1 == 32'd1) begin
                    $display("  PASS: sequence_number=1 ✓");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  FAIL: expected sequence_number=1");
                    fail_count = fail_count + 1;
                end
            end
        end
    end

    // ================================================================
    // Summary
    // ================================================================
    $display("\n======================================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    if (fail_count == 0)
        $display(" *** OVERALL: PASS ***");
    else
        $display(" *** OVERALL: FAIL ***");
    $display("======================================================\n");

    $finish;
end

// -------------------------------------------------------------------------
// Timeout watchdog
// -------------------------------------------------------------------------
initial begin
    #2_000_000; // 2ms @ 1ns resolution
    $display("TIMEOUT — simulation exceeded limit");
    $finish;
end

endmodule
