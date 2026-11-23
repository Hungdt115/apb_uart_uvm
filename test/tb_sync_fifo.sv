// ============================================================================
//  Testbench   : tb_sync_fifo
//  Description : Standalone module-level checkbench for sync_fifo
//                (wrapper/DUT untouched). Exercises:
//                  - write until FULL (overflow writes silently dropped)
//                  - read until EMPTY with data-order verification
//                  - FULL / EMPTY / ALMOST_FULL / ALMOST_EMPTY / COUNT flags
//                  - read-while-empty is ignored (data retained)
//                  - simultaneous read+write: empty-bypass and full cases
//                  - synchronous flush via I_CLR
//                Self-checking: prints PASS/FAIL and a final summary.
// ============================================================================
`timescale 1ns/1ps
module tb_sync_fifo;

  reg         CLK      = 0;
  reg         RST_N    = 0;
  reg         CLR      = 0;
  reg         WR_EN    = 0;
  reg  [7:0]  WR_DATA  = 0;
  reg         RD_EN    = 0;
  wire [7:0]  RD_DATA;
  wire        FULL;
  wire        EMPTY;
  wire        ALMOST_FULL;
  wire        ALMOST_EMPTY;
  wire [4:0]  COUNT;

  sync_fifo #(.DW(8), .DEPTH(16)) dut (
    .I_CLK          (CLK),
    .I_RST          (RST_N),
    .I_CLR          (CLR),
    .I_WR_EN        (WR_EN),
    .I_WR_DATA      (WR_DATA),
    .I_RD_EN        (RD_EN),
    .O_RD_DATA      (RD_DATA),
    .O_FULL         (FULL),
    .O_EMPTY        (EMPTY),
    .O_ALMOST_FULL  (ALMOST_FULL),
    .O_ALMOST_EMPTY (ALMOST_EMPTY),
    .O_COUNT        (COUNT)
  );

  always #5 CLK = ~CLK;

  int errs = 0;

  task automatic check(input logic [7:0] v, input logic [7:0] exp, input string msg);
    if (v !== exp) begin
      $display("FAIL @ %0t: %s got 0x%02x exp 0x%02x", $time, msg, v, exp);
      errs++;
    end
    else
      $display("PASS @ %0t: %s = 0x%02x", $time, msg, v);
  endtask

  // One write: WR_EN high for exactly one cycle
  task automatic write_byte(input logic [7:0] d);
    @(posedge CLK);
    WR_EN   <= 1'b1;
    WR_DATA <= d;
    @(posedge CLK);          // write captured at this edge (if not FULL)
    WR_EN   <= 1'b0;
  endtask

  // One read: RD_EN high for one cycle; returns the registered output
  task automatic read_byte(output logic [7:0] d);
    @(posedge CLK);
    RD_EN <= 1'b1;
    @(posedge CLK);          // read captured at this edge
    RD_EN <= 1'b0;
    #1;                      // let the registered output settle
    d = RD_DATA;
  endtask

  logic [7:0] d;

  initial begin
    // ---- reset ----
    repeat (3) @(posedge CLK);
    RST_N <= 1'b1;
    @(posedge CLK);
    #1;
    check(EMPTY, 1, "empty after reset");
    check(COUNT, 0, "count 0 after reset");

    // ---- phase 1: write 18 bytes (FIFO holds 16, last 2 dropped) ----
    for (int i = 0; i < 14; i++)
      write_byte(8'h00 + i);
    #1;
    check(ALMOST_FULL, 1, "ALMOST_FULL at count 14");
    check(FULL, 0, "not yet FULL at count 14");
    for (int i = 14; i < 18; i++)
      write_byte(8'h00 + i);
    #1;
    check(COUNT, 16, "count == DEPTH after 18 writes");
    check(FULL, 1, "FULL after overflow writes");
    check(ALMOST_FULL, 1, "ALMOST_FULL when full");

    // ---- phase 2: read until EMPTY, verify data order ----
    for (int i = 0; i < 16; i++) begin
      read_byte(d);
      if (d !== 8'h00 + i) begin
        $display("FAIL @ %0t: read[%0d] got 0x%02x exp 0x%02x", $time, i, d, 8'h00+i);
        errs++;
      end
      else
        $display("PASS @ %0t: read[%0d] = 0x%02x", $time, i, d);
      if (i == 13) begin
        #1;
        check(ALMOST_EMPTY, 1, "ALMOST_EMPTY at count 2");
      end
    end
    #1;
    check(EMPTY, 1, "EMPTY after draining");
    check(COUNT, 0, "count 0 after draining");
    check(ALMOST_EMPTY, 1, "ALMOST_EMPTY when empty");

    // ---- phase 3: read while EMPTY is ignored, data retained ----
    read_byte(d);
    check(EMPTY, 1, "empty read ignored (still EMPTY)");
    check(d, 8'h0F, "empty read retains last read data");

    // ---- phase 4: EMPTY + write + read same cycle (bypass) ----
    @(posedge CLK);
    WR_EN   <= 1'b1; WR_DATA <= 8'hA5;
    RD_EN   <= 1'b1;
    @(posedge CLK);
    WR_EN   <= 1'b0; RD_EN   <= 1'b0;
    #1;
    check(RD_DATA, 8'hA5, "bypass: read returns concurrently written byte");
    check(EMPTY, 1, "still EMPTY after empty+wr+rd");
    check(COUNT, 0, "count unchanged after empty+wr+rd");

    // ---- phase 5: fill to FULL, then FULL + write + read same cycle ----
    for (int i = 0; i < 16; i++)
      write_byte(8'h20 + i);
    #1;
    check(FULL, 1, "FULL before full+wr+rd");
    @(posedge CLK);
    WR_EN <= 1'b1; WR_DATA <= 8'hBB;
    RD_EN <= 1'b1;
    @(posedge CLK);
    WR_EN <= 1'b0; RD_EN <= 1'b0;
    #1;
    check(RD_DATA, 8'h20, "full+wr+rd: read returns old head");
    check(FULL, 1, "still FULL after full+wr+rd");
    check(COUNT, 16, "count unchanged after full+wr+rd");

    // ---- phase 6: synchronous flush via I_CLR ----
    @(posedge CLK);
    CLR <= 1'b1;
    @(posedge CLK);
    CLR <= 1'b0;
    #1;
    check(COUNT, 0, "count 0 after I_CLR flush");
    check(EMPTY, 1, "EMPTY after I_CLR flush");
    check(FULL, 0, "FULL deasserted after flush");

    if (errs == 0) $display("ALL SYNC_FIFO CHECKS PASSED");
    else           $display("SYNC_FIFO FAILURES: %0d", errs);
    $finish;
  end

  
  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars;
  end

endmodule
