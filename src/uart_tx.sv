// ============================================================================
//  Module      : uart_tx
//  Description : UART transmitter core with integrated TX FIFO
//
//    - sync_fifo (DW=8, DEPTH=32) buffers bytes pushed via I_TX_WR_EN/DATA
//    - TX controller: pop (cycle N) -> hold registered FIFO data (N+1)
//      -> 1-cycle start pulse (N+2)
//    - Shifter FSM (START/DATA/PARITY/STOP) timed by tick_1x clock-enable
//    - Parity/stop runtime from I_MODE[3:0], latched at frame load
//    - I_MODE = 0 -> 8N1
//    - I_TX_FIFO_CLR rising edge -> flush FIFO, clear overflow,
//      cancel pending pop (in-flight frame is not aborted)
//    - FIFO writes are not gated by I_UART_EN (pre-load allowed)
//    - Asynchronous active-low reset
// ============================================================================

module uart_tx #(
    parameter DATA_BITS     = 8,
    parameter TX_FIFO_DEPTH = 32
)(
    input         I_CLK,
    input         I_RST_N,
    input         I_UART_EN,
    input  [15:0] I_BRG_DIV,
    input         I_BRG_WR_EN,
    input  [ 3:0] I_MODE,
    input         I_TX_WR_EN,
    input  [ 7:0] I_TX_WR_DATA,
    input         I_TX_FIFO_CLR,

    output        O_TXD,
    output        O_TX_BUSY,
    output        O_TX_DONE,
    output        O_TX_IDLE,
    output        O_TX_FIFO_FULL,
    output        O_TX_FIFO_EMPTY,
    output        O_TX_FIFO_ALMOST_FULL,
    output [ 5:0] O_TX_FIFO_COUNT,
    output        O_TX_OVF
);

    // =========================================================================
    // LOCALPARAMS
    // =========================================================================

    // TX controller phases
    localparam [1:0] C_WAIT  = 2'd0;
    localparam [1:0] C_HOLD  = 2'd1;
    localparam [1:0] C_START = 2'd2;

    // Shifter FSM states
    typedef enum logic [2:0] {
        S_IDLE   = 3'd0,
        S_START  = 3'd1,
        S_DATA   = 3'd2,
        S_PARITY = 3'd3,
        S_STOP   = 3'd4
    } state_e;

    // =========================================================================
    // REGS
    // =========================================================================

    // Block 4: FIFO write / flush / overflow
    reg        r_clr_d;
    reg        r_tx_ovf;

    // Block 5: FIFO pop controller
    reg  [1:0] ctrl_phase;
    reg  [7:0] r_tx_data_hold;
    reg        r_tx_start;

    // Block 7: TX output / shift register
    reg        txd;
    reg  [DATA_BITS-1:0] shift_reg;

    // Block 2: Counters
    reg  [3:0] bit_cnt;
    reg  [1:0] stop_cnt;

    // Block 6: Frame configuration
    reg        parity_bit;
    reg  [1:0] stop_target;

    // Block 3: FSM state
    state_e    state;

    // =========================================================================
    // WIRES
    // =========================================================================

    // FIFO signals
    wire       fifo_wen;
    wire       fifo_ren;
    wire [7:0] fifo_rd_data;
    wire       fifo_full;
    wire       fifo_empty;
    wire       fifo_almost_full;
    wire [5:0] fifo_count;

    // Baud generator
    wire       w_cken;

    // TX control / FSM
    wire       w_tx_busy;
    wire       w_tx_fifo_clr;
    wire       w_start_cond;
    wire       w_ld_frame;

    // Counter completion flags
    wire       w_data_done;
    wire       w_stop_done;

    // Frame configuration
    wire       w_parity_next;
    wire [1:0] w_stop_target_next;

    // =========================================================================
    // CONTINUOUS ASSIGNS
    // =========================================================================

    // Block 1: Baud enable generation
    assign w_tx_busy = (state != S_IDLE);

    // Block 4: FIFO write / flush control
    assign w_tx_fifo_clr = I_TX_FIFO_CLR & ~r_clr_d;
    assign fifo_wen      = I_TX_WR_EN;

    // Block 5: FIFO pop controller
    assign w_start_cond = ~fifo_empty & ~w_tx_busy & I_UART_EN;
    assign fifo_ren     = (ctrl_phase == C_WAIT) & w_start_cond;
    assign r_tx_start   = (ctrl_phase == C_START);

    // Shared frame-load event
    assign w_ld_frame = r_tx_start;

    // Block 2: Counter completion flags
    assign w_data_done = (state == S_DATA) && w_cken && (bit_cnt == (DATA_BITS - 1));
    assign w_stop_done = (state == S_STOP) && w_cken && (stop_cnt== stop_target);

    // Block 6: Start / parity / stop configuration
    assign w_parity_next = I_MODE[1] ? (I_MODE[2] ? ~^r_tx_data_hold : ^r_tx_data_hold) : 1'b0;
    assign w_stop_target_next = I_MODE[0] ? 2'd2 : 2'd1;

    // =========================================================================
    // BLOCK 1: BAUD ENABLE GENERATION
    // =========================================================================

    uart_baud_gen u_tx_baud_gen (
        .I_CLK       (I_CLK),
        .I_RST_N     (I_RST_N),
        .I_BRG_DIV   (I_BRG_DIV),
        .I_BRG_WR_EN (I_BRG_WR_EN),
        .I_ENABLE    (w_tx_busy | I_UART_EN),
        .I_RESTART   (r_tx_start),
        .O_TICK_16X (),
        .O_TICK_1X  (w_cken)
    );

    // =========================================================================
    // BLOCK 2: BIT COUNTER
    // =========================================================================
    // bit_cnt:
    //   - Reset to 0 when a frame is loaded
    //   - Increment on the START tick and every DATA tick
    //   - Reaches DATA_BITS after the final data bit is transmitted
    //
    // stop_cnt:
    //   - Reset when a frame is loaded
    //   - Counts stop-period ticks
    // =========================================================================

    // Data bit counter
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            bit_cnt <= 4'd0;
        end
        else if (w_ld_frame) begin
            bit_cnt <= 4'd0;
        end
        else if (w_cken && ((state == S_START) || (state == S_DATA))) begin
            bit_cnt <= bit_cnt + 4'd1;
        end
    end

    // Stop-period counter
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            stop_cnt <= 2'd1;
        end
        else if (w_ld_frame) begin
            stop_cnt <= 2'd1;
        end
        else if (w_cken && (state == S_STOP) && !w_stop_done) begin
            stop_cnt <= stop_cnt + 2'd1;
        end
    end

    // =========================================================================
    // BLOCK 3: FSM CONTROL
    // =========================================================================
    // The FSM controls state transitions only.
    // TXD, shift_reg, bit_cnt, stop_cnt, parity_bit and stop_target
    // are controlled by their dedicated functional blocks.
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            state <= S_IDLE;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (r_tx_start) state <= S_START;
                end
                S_START: begin
                    if (w_cken) state <= S_DATA;
                end
                S_DATA: begin
                    if (w_data_done) state <= I_MODE[1] ? S_PARITY : S_STOP;
                end
                S_PARITY: begin
                    if (w_cken) state <= S_STOP;
                end
                S_STOP: begin
                    if (w_stop_done) state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // BLOCK 4: SEND DATA GENERATION (FIFO WRITE / FLUSH / OVERFLOW)
    // =========================================================================

    // Flush edge detection
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) r_clr_d <= 1'b0;
        else          r_clr_d <= I_TX_FIFO_CLR;
    end

    // Sticky overflow flag
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N)                r_tx_ovf <= 1'b0;
        else if (w_tx_fifo_clr)      r_tx_ovf <= 1'b0;
        else if (fifo_full && fifo_wen) r_tx_ovf <= 1'b1;
    end

    // =========================================================================
    // BLOCK 5: DATA BUFFER POP
    // =========================================================================
    // TX controller sequence:
    //   N   : FIFO pop
    //   N+1 : Register popped data into hold register
    //   N+2 : Generate r_tx_start pulse
    // =========================================================================

    // TX FIFO
    sync_fifo #(
        .DW    (8),
        .DEPTH (TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .I_CLK          (I_CLK),
        .I_RST          (I_RST_N),
        .I_CLR          (w_tx_fifo_clr),
        .I_WR_EN        (fifo_wen),
        .I_WR_DATA      (I_TX_WR_DATA),
        .I_RD_EN        (fifo_ren),
        .O_RD_DATA      (fifo_rd_data),
        .O_FULL         (fifo_full),
        .O_EMPTY        (fifo_empty),
        .O_ALMOST_FULL  (fifo_almost_full),
        .O_ALMOST_EMPTY (),
        .O_COUNT        (fifo_count)
    );

    // TX FIFO controller
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            ctrl_phase     <= C_WAIT;
            r_tx_data_hold <= 8'h00;
        end
        else if (w_tx_fifo_clr) begin
            ctrl_phase <= C_WAIT;
        end
        else begin
            case (ctrl_phase)
                C_WAIT: begin
                    if (w_start_cond) ctrl_phase <= C_HOLD;
                end
                C_HOLD: begin
                    r_tx_data_hold <= fifo_rd_data;
                    ctrl_phase     <= C_START;
                end
                C_START: begin
                    ctrl_phase <= C_WAIT;
                end
                default: begin
                    ctrl_phase <= C_WAIT;
                end
            endcase
        end
    end

    // =========================================================================
    // BLOCK 6: START / PARITY / STOP GENERATION
    // =========================================================================
    // Frame configuration is latched when w_ld_frame is asserted.
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            parity_bit  <= 1'b0;
            stop_target <= 2'd1;
        end
        else if (w_ld_frame) begin
            parity_bit  <= w_parity_next;
            stop_target <= w_stop_target_next;
        end
    end

    // =========================================================================
    // BLOCK 7: TRANSMIT DATA GENERATION
    // =========================================================================
    // This block exclusively controls txd and shift_reg.
    //
    //   w_ld_frame : output start bit and load frame data
    //   S_START    : output D0 on the first baud tick
    //   S_DATA     : shift/output remaining data bits
    //   S_PARITY   : output parity bit on baud tick
    //   S_STOP     : output high (stop/idle level)
    // =========================================================================
    always_ff @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            shift_reg <= {DATA_BITS{1'b0}};
        end
        else if (w_ld_frame && (state == S_IDLE)) begin
            shift_reg <= r_tx_data_hold;
        end
        else if (w_cken && (state == S_START || state == S_DATA)) begin
            shift_reg <= {1'b0, shift_reg[DATA_BITS-1:1]};
        end
    end

    always_ff @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            parity_bit <= 1'b0;
        end
        else if (w_ld_frame) begin
            parity_bit <= w_parity_next;
        end
    end

    always_comb begin
        case (state)
            S_IDLE:   txd = 1'b1;
            S_START:  txd = 1'b0;
            S_DATA:   txd = shift_reg[0];
            S_PARITY: txd = parity_bit;
            S_STOP:   txd = 1'b1;

            default:  txd = 1'b1;
        endcase
    end
   
    // =========================================================================
    // BLOCK 8: STATUS FLAGS
    // =========================================================================
    // Status outputs are assigned in the CONTINUOUS ASSIGNS section above.
    // =========================================================================

    assign O_TXD                 = txd;
    assign O_TX_BUSY             = w_tx_busy;
    assign O_TX_DONE             = w_stop_done;
    assign O_TX_IDLE             = fifo_empty & ~w_tx_busy;
    assign O_TX_FIFO_FULL        = fifo_full;
    assign O_TX_FIFO_EMPTY       = fifo_empty;
    assign O_TX_FIFO_ALMOST_FULL = fifo_almost_full;
    assign O_TX_FIFO_COUNT       = fifo_count;
    assign O_TX_OVF              = r_tx_ovf;

endmodule