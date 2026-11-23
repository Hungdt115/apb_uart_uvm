// ============================================================================
//  Module      : sync_fifo
//  Description : Single-clock synchronous FIFO
//                (spec: docs/hw/apb_uart/spec/sync_fifo_spec.md)
//    - Dual-port RAM (read-first) + write/read pointers + occupancy counter
//    - Registered O_RD_DATA: valid one cycle after I_RD_EN && !O_EMPTY
//    - Full / empty / almost flags derived combinationally from the
//      registered occupancy counter
//    - Synchronous reset (I_RST, active low) and synchronous flush
//      (I_CLR, active high); RAM contents are not cleared by either
//    - Simultaneous read+write supported (read frees / write fills a slot
//      in the same cycle, see spec 5.5)
// ============================================================================
module sync_fifo #(
    parameter  DW              = 8,
    parameter  DEPTH           = 16,        // number of entries, power of two
    parameter  ALMOST_FULL_TH  = DEPTH - 2,
    parameter  ALMOST_EMPTY_TH = 2,
    parameter  AW              = $clog2(DEPTH)   // address width (derived)
)(
    // Clock & reset
    input                I_CLK,
    input                I_RST,       // synchronous, active low
    input                I_CLR,       // synchronous flush, active high

    // Write interface (producer)
    input                I_WR_EN,     // ignored when O_FULL
    input  [DW-1:0]      I_WR_DATA,

    // Read interface (consumer)
    input                I_RD_EN,     // ignored when O_EMPTY
    output reg [DW-1:0]  O_RD_DATA,   // registered; valid 1 cycle after read
    output     [DW-1:0]  O_PEEK,      // combinational FIFO head (mem[rptr])

    // Status flags
    output               O_FULL,      // count == DEPTH
    output               O_EMPTY,     // count == 0
    output               O_ALMOST_FULL,   // count >= ALMOST_FULL_TH
    output               O_ALMOST_EMPTY,  // count <= ALMOST_EMPTY_TH
    output [AW:0]        O_COUNT      // current occupancy (0 .. DEPTH)
);

    // ------------------------------------------------------------
    // RAM (not cleared by reset / flush)
    // ------------------------------------------------------------
    reg [DW-1:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------
    // Pointers (AW+1 bits, extra MSB for wrap detection) & count
    // ------------------------------------------------------------
    reg [AW:0] wptr;
    reg [AW:0] rptr;
    reg [AW:0] count;

    // ------------------------------------------------------------
    // Flags derived from the occupancy counter
    // ------------------------------------------------------------
    assign O_FULL         = (count == DEPTH);
    assign O_EMPTY        = (count == 0);
    assign O_ALMOST_FULL  = (count >= ALMOST_FULL_TH);
    assign O_ALMOST_EMPTY = (count <= ALMOST_EMPTY_TH);
    assign O_COUNT        = count;

    // Combinational head (peek): valid immediately, no pop required —
    // for consumers that cannot tolerate the 1-cycle registered read
    // latency (e.g. uart_rx read-back through the APB)
    assign O_PEEK         = mem[rptr[AW-1:0]];

    // ------------------------------------------------------------
    // Access acceptance (spec 5.5): a simultaneous read/write is
    // always serviceable — the read frees a slot, the write fills one.
    // ------------------------------------------------------------
    wire w_wr_ok   = I_WR_EN & (~O_FULL  | I_RD_EN);
    wire w_rd_ok   = I_RD_EN & (~O_EMPTY | I_WR_EN);
    // FIFO empty + write + read: the read returns the concurrently
    // written word ("slot filled by write", spec 5.5)
    wire w_bypass  = O_EMPTY & I_WR_EN & I_RD_EN;

    // ------------------------------------------------------------
    // Sequential body
    // ------------------------------------------------------------
    always @(posedge I_CLK) begin
        if (!I_RST || I_CLR) begin
            wptr  <= {(AW+1){1'b0}};
            rptr  <= {(AW+1){1'b0}};
            count <= {(AW+1){1'b0}};
        end
        else begin
            if (w_wr_ok) begin
                mem[wptr[AW-1:0]] <= I_WR_DATA;
                wptr <= wptr + 1'b1;
            end
            if (w_rd_ok) begin
                // read-first: mem[] old value, unless bypassing (empty+wr+rd)
                O_RD_DATA <= w_bypass ? I_WR_DATA : mem[rptr[AW-1:0]];
                rptr <= rptr + 1'b1;
            end
            if (w_wr_ok && w_rd_ok)
                count <= count;              // no change
            else if (w_wr_ok)
                count <= count + 1'b1;
            else if (w_rd_ok)
                count <= count - 1'b1;
        end
    end

endmodule
