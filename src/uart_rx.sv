// ============================================================================
//  Module      : uart_rx
//  Description : UART receiver core with integrated RX FIFO
//
//    - 2-FF synchronizer on I_RXD + start-bit falling-edge detection
//    - 16x oversampling (O_TICK_16X) mid-bit sampling (os_cnt == 7)
//    - Receiver FSM (IDLE/START/DATA/PARITY/STOP/PUSH)
//    - Parity/stop runtime from I_MODE[3:0]
//    - I_MODE = 0 -> 8N1
//    - I_RX_FIFO_CLR rising edge -> flush FIFO, clear overflow & error flags
//    - sync_fifo (DW=8, DEPTH=RX_FIFO_DEPTH) buffers received bytes
//    - Asynchronous active-low reset
// ============================================================================

module uart_rx #(
    parameter DATA_BITS     = 8,
    parameter RX_FIFO_DEPTH = 32
)(
    input         I_CLK,
    input         I_RST_N,
    input         I_UART_EN,
    input  [15:0] I_BRG_DIV,
    input         I_BRG_WR_EN,
    input  [ 3:0] I_MODE,
    input         I_RXD,
    input         I_RX_RD_EN,
    input         I_RX_FIFO_CLR,

    output [ 7:0] O_RX_RD_DATA,
    output        O_RX_BUSY,
    output        O_RX_IDLE,
    output        O_RX_FIFO_FULL,
    output        O_RX_FIFO_EMPTY,
    output        O_RX_FIFO_ALMOST_FULL,
    output [ 5:0] O_RX_FIFO_COUNT,
    output        O_RX_OVF,
    output        O_RX_PARITY_ERR,
    output        O_RX_FRAME_ERR
);

    // =========================================================================
    // LOCALPARAMS & TYPES
    // =========================================================================

    localparam [3:0] OS_MID_TICK = 4'd7;

    typedef enum logic [2:0] {
        S_IDLE   = 3'd0,
        S_START  = 3'd1,
        S_DATA   = 3'd2,
        S_PARITY = 3'd3,
        S_STOP   = 3'd4,
        S_PUSH   = 3'd5
    } rx_state_e;

    // =========================================================================
    // REGS
    // =========================================================================

    // Synchronizer & edge detect
    reg                  r_rxd_s1;
    reg                  r_rxd_s2;
    reg                  r_rxd_prev;

    // FIFO flush / overflow / status flags
    reg                  r_clr_d;
    reg                  r_rx_ovf;
    reg                  r_parity_err;
    reg                  r_frame_err;

    // Oversampling & bit counters
    reg  [ 3:0]          os_cnt;
    reg  [ 3:0]          bit_cnt;
    reg  [ 1:0]          stop_cnt;

    // Shifter & latched frame config
    reg  [DATA_BITS-1:0] shift_reg;
    reg                  r_parity_en;
    reg                  r_parity_odd;
    reg  [ 1:0]          r_stop_target;

    // FSM state
    rx_state_e           state;

    // =========================================================================
    // WIRES
    // =========================================================================

    // FIFO signals
    wire                 fifo_wen;
    wire                 fifo_ren;
    wire [ 7:0]          fifo_rd_data;
    wire [ 7:0]          fifo_peek_data;
    wire                 fifo_full;
    wire                 fifo_empty;
    wire                 fifo_almost_full;
    wire [ 5:0]          fifo_count;

    // Baud generator
    wire                 w_tick_16x;
    wire                 w_brg_restart;

    // Control & completion flags
    wire                 w_rx_busy;
    wire                 w_rx_fifo_clr;
    wire                 w_start_edge;
    wire                 w_mid_sample;
    wire                 w_data_done;
    wire                 w_stop_done;
    wire                 w_exp_parity;

    // =========================================================================
    // CONTINUOUS ASSIGNS
    // =========================================================================

    assign w_rx_busy      = (state != S_IDLE);
    assign w_rx_fifo_clr  = I_RX_FIFO_CLR & ~r_clr_d;
    assign w_start_edge   = (state == S_IDLE) && I_UART_EN && (r_rxd_prev == 1'b1) && (r_rxd_s2 == 1'b0);
    assign w_brg_restart  = w_start_edge;
    assign w_mid_sample   = w_tick_16x && (os_cnt == OS_MID_TICK);

    assign w_data_done    = (state == S_DATA) && w_mid_sample && (bit_cnt == (DATA_BITS - 1));
    assign w_stop_done    = (state == S_STOP) && w_mid_sample && (stop_cnt == r_stop_target);

    // Expected parity calculated over received shift_reg
    assign w_exp_parity   = r_parity_odd ? ~(^shift_reg) : (^shift_reg);

    // FIFO write/read strobes
    assign fifo_wen       = (state == S_PUSH);
    assign fifo_ren       = I_RX_RD_EN & ~fifo_empty;

    // =========================================================================
    // BLOCK 1: BAUD ENABLE GENERATION
    // =========================================================================

    uart_baud_gen u_rx_baud_gen (
        .I_CLK       (I_CLK),
        .I_RST_N     (I_RST_N),
        .I_BRG_DIV   (I_BRG_DIV),
        .I_BRG_WR_EN (I_BRG_WR_EN),
        .I_ENABLE    (I_UART_EN | w_rx_busy),
        .I_RESTART   (w_brg_restart),
        .O_TICK_16X  (w_tick_16x),
        .O_TICK_1X   ()
    );

    // =========================================================================
    // BLOCK 2: INPUT SYNCHRONIZER & OVERSAMPLING / BIT COUNTERS
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            r_rxd_s1   <= 1'b1;
            r_rxd_s2   <= 1'b1;
            r_rxd_prev <= 1'b1;
        end
        else if (w_rx_fifo_clr) begin
            r_rxd_s1   <= 1'b1;
            r_rxd_s2   <= 1'b1;
            r_rxd_prev <= 1'b1;
        end
        else begin
            r_rxd_s1   <= I_RXD;
            r_rxd_s2   <= r_rxd_s1;
            r_rxd_prev <= r_rxd_s2;
        end
    end

    // 16x oversampling phase counter (0..15)
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            os_cnt <= 4'd0;
        end
        else if (w_rx_fifo_clr || w_start_edge || (state == S_IDLE)) begin
            os_cnt <= 4'd0;
        end
        else if (w_tick_16x) begin
            os_cnt <= os_cnt + 4'd1;
        end
    end

    // Data bit counter
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            bit_cnt <= 4'd0;
        end
        else if (w_rx_fifo_clr || w_start_edge || (state == S_IDLE)) begin
            bit_cnt <= 4'd0;
        end
        else if ((state == S_DATA) && w_mid_sample && !w_data_done) begin
            bit_cnt <= bit_cnt + 4'd1;
        end
    end

    // Stop-bit counter (1 or 2 stop bits)
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            stop_cnt <= 2'd1;
        end
        else if (w_rx_fifo_clr || w_start_edge || (state == S_IDLE) || (state == S_DATA) || (state == S_PARITY)) begin
            stop_cnt <= 2'd1;
        end
        else if ((state == S_STOP) && w_mid_sample && !w_stop_done) begin
            stop_cnt <= stop_cnt + 2'd1;
        end
    end

    // =========================================================================
    // BLOCK 3: RECEIVER FSM CONTROL
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            state <= S_IDLE;
        end
        else if (w_rx_fifo_clr) begin
            state <= S_IDLE;
        end
        else if (!I_UART_EN && (state == S_IDLE)) begin
            state <= S_IDLE;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (w_start_edge) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (w_mid_sample) begin
                        // Confirm valid low start bit at mid-point
                        if (r_rxd_s2 == 1'b0)
                            state <= S_DATA;
                        else
                            state <= S_IDLE;
                    end
                end

                S_DATA: begin
                    if (w_data_done) begin
                        state <= r_parity_en ? S_PARITY : S_STOP;
                    end
                end

                S_PARITY: begin
                    if (w_mid_sample) begin
                        state <= S_STOP;
                    end
                end

                S_STOP: begin
                    if (w_stop_done) begin
                        state <= S_PUSH;
                    end
                end

                S_PUSH: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // BLOCK 4: FIFO FLUSH / OVERFLOW / ERROR FLAGS
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) r_clr_d <= 1'b0;
        else          r_clr_d <= I_RX_FIFO_CLR;
    end

    // Sticky RX FIFO overflow flag
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N)           r_rx_ovf <= 1'b0;
        else if (w_rx_fifo_clr) r_rx_ovf <= 1'b0;
        else if (fifo_wen && fifo_full) r_rx_ovf <= 1'b1;
    end

    // Sticky parity error flag
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            r_parity_err <= 1'b0;
        end
        else if (w_rx_fifo_clr) begin
            r_parity_err <= 1'b0;
        end
        else if ((state == S_PARITY) && w_mid_sample) begin
            r_parity_err <= (r_rxd_s2 != w_exp_parity);
        end
    end

    // Sticky framing error flag (stop bit sampled low)
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            r_frame_err <= 1'b0;
        end
        else if (w_rx_fifo_clr) begin
            r_frame_err <= 1'b0;
        end
        else if ((state == S_STOP) && w_mid_sample) begin
            r_frame_err <= (r_rxd_s2 != 1'b1);
        end
    end

    // =========================================================================
    // BLOCK 5: RX FIFO INSTANCE
    // =========================================================================

    sync_fifo #(
        .DW    (8),
        .DEPTH (RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .I_CLK          (I_CLK),
        .I_RST          (I_RST_N),
        .I_CLR          (w_rx_fifo_clr),
        .I_WR_EN        (fifo_wen),
        .I_WR_DATA      (shift_reg),
        .I_RD_EN        (fifo_ren),
        .O_RD_DATA      (fifo_rd_data),
        .O_PEEK         (fifo_peek_data),
        .O_FULL         (fifo_full),
        .O_EMPTY        (fifo_empty),
        .O_ALMOST_FULL  (fifo_almost_full),
        .O_ALMOST_EMPTY (),
        .O_COUNT        (fifo_count)
    );

    // =========================================================================
    // BLOCK 6: FRAME CONFIGURATION LATCH
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            r_parity_en   <= 1'b0;
            r_parity_odd  <= 1'b0;
            r_stop_target <= 2'd1;
        end
        else if (w_start_edge) begin
            r_parity_en   <= I_MODE[1];
            r_parity_odd  <= I_MODE[2];
            r_stop_target <= I_MODE[0] ? 2'd2 : 2'd1;
        end
    end

    // =========================================================================
    // BLOCK 7: RECEIVE SHIFT REGISTER
    // =========================================================================

    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            shift_reg <= {DATA_BITS{1'b0}};
        end
        else if (w_start_edge) begin
            shift_reg <= {DATA_BITS{1'b0}};
        end
        else if ((state == S_DATA) && w_mid_sample) begin
            shift_reg <= {r_rxd_s2, shift_reg[DATA_BITS-1:1]};
        end
    end

    // =========================================================================
    // BLOCK 8: STATUS & DATA OUTPUTS
    // =========================================================================

    assign O_RX_RD_DATA            = fifo_peek_data;
    assign O_RX_BUSY               = w_rx_busy;
    assign O_RX_IDLE               = fifo_empty & ~w_rx_busy;
    assign O_RX_FIFO_FULL          = fifo_full;
    assign O_RX_FIFO_EMPTY         = fifo_empty;
    assign O_RX_FIFO_ALMOST_FULL   = fifo_almost_full;
    assign O_RX_FIFO_COUNT         = fifo_count;
    assign O_RX_OVF                = r_rx_ovf;
    assign O_RX_PARITY_ERR         = r_parity_err;
    assign O_RX_FRAME_ERR          = r_frame_err;

endmodule