// ============================================================================
//  Module      : apb_dut
//  Description : APB4-compliant DUT: apb_slave + apb2reg + uart_tx + uart_rx.
//                REG_UART_STA / REG_UART_IF are assembled internally and fed
//                to apb2reg as read-only inputs driven by the uart_top role.
//
//  Author      : hungdt110520@gmail.com
// ============================================================================

module apb_dut (
    input  logic         PCLK,       // APB clock (from top)
    input  logic         PRESETN,    // APB resetn (from top)
    input  logic         UART_CLK,   // UART clock (from top)
    input  logic         RST_N,      // UART resetn (from top)

    // APB4 Slave Interface (from APB master in testbench)
    input  logic         S_PWRITE,
    input  logic         S_PSEL,
    input  logic         S_PENABLE,
    input  logic [31:0]  S_PADDR,
    input  logic [31:0]  S_PWDATA,
    input  logic [3:0]   S_PSTRB,
    input  logic [2:0]   S_PPROT, // unused

    output logic         S_PREADY,
    output logic         S_PSLVERR,
    output logic [31:0]  S_PRDATA,

    // APB4 Master Interface (passthrough, unused)
    output logic         M_PWRITE,
    output logic         M_PSEL,
    output logic         M_PENABLE,
    output logic [31:0]  M_PADDR,
    output logic [31:0]  M_PWDATA,
    output logic [3:0]   M_PSTRB,
    output logic [2:0]   M_PPROT,
    input  logic         M_PREADY,
    input  logic         M_PSLVERR,
    input  logic [31:0]  M_PRDATA,

    // UART serial lines
    input  logic         UART_RXD,   // to uart_rx
    output logic         UART_TXD    // from uart_tx
);

    // Drive master passthrough
    assign M_PWRITE   = S_PWRITE;
    assign M_PSEL     = S_PSEL;
    assign M_PENABLE  = S_PENABLE;
    assign M_PADDR    = S_PADDR;
    assign M_PWDATA   = S_PWDATA;
    assign M_PSTRB    = S_PSTRB;
    assign M_PPROT    = S_PPROT;

    logic [31:0]  reg_rd_data;
    logic         reg_ack;
    logic         reg_err;

    logic [31:0]  reg_addr;
    logic         reg_wr;
    logic         reg_rd;
    logic [31:0]  reg_wr_data;
    logic         reg_err_ack;

    apb_slave #(
        .p_use_ack (1'h1),
        .p_wr_wait (4'h0),
        .p_rd_wait (4'h1)
    ) u_apb_slave (
        // APB side
        .I_PCLK        (PCLK),
        .I_PRESET      (PRESETN),
        .I_PADDR       (S_PADDR),
        .I_PPROT       (S_PPROT),
        .I_PSEL        (S_PSEL),
        .I_PENABLE     (S_PENABLE),
        .I_PWRITE      (S_PWRITE),
        .I_PWDATA      (S_PWDATA),
        .I_PSTRB       (S_PSTRB),

        // Register side
        .I_REG_RD_DATA (reg_rd_data),
        .I_REG_ACK     (reg_ack),
        .I_REG_ERR     (reg_err),

        // To APB outputs
        .O_PREADY      (S_PREADY),
        .O_PRDATA      (S_PRDATA),
        .O_PSLVERR     (S_PSLVERR),

        // To register outputs
        .O_REG_ADDR    (reg_addr),
        .O_REG_WR      (reg_wr),
        .O_REG_RD      (reg_rd),
        .O_REG_WR_DATA (reg_wr_data),
        .O_REG_ERR_ACK (reg_err_ack)
    );

    // ---- apb2reg UART-side signals ----
    logic        reg_uart_brg_wen;
    logic [7:0]  reg_uart_txd;
    logic        reg_uart_tx_wen;
    logic [7:0]  reg_uart_rxd;
    logic        reg_uart_rx_ren;

    // Register control signals
    logic         reg_uart_en;
    logic [31:0]  reg_uart_csr;
    logic [31:0]  reg_uart_sta;      // assembled internally (tx/rx status)
    logic [31:0]  reg_uart_mode;
    logic [15:0]  reg_uart_brg;      // brg_div
    logic [31:0]  reg_uart_ie;
    logic [31:0]  reg_uart_if;       // interrupt flags (extend with RX/IE/IF logic as needed)
    logic [31:0]  reg_uart_ifclr;

    apb2reg u_apb2reg (
        .UART_CLK        (UART_CLK),
        .RST_N           (RST_N),
        .PCLK            (PCLK),
        .PRESETN         (PRESETN),

        // Register outputs
        .I_REG_ADDR      (reg_addr),
        .I_REG_WR        (reg_wr),
        .I_REG_RD        (reg_rd),
        .I_REG_WR_DATA   (reg_wr_data),
        .I_REG_ERR_ACK   (reg_err_ack),  // to clear err flag

        // Register side
        .O_REG_RD_DATA   (reg_rd_data),
        .O_REG_ACK       (reg_ack),
        .O_REG_ERR       (reg_err),

        // Register control signals
        .REG_UART_EN     (reg_uart_en),
        .REG_UART_CSR    (reg_uart_csr),
        .REG_UART_STA     (reg_uart_sta),   // input of apb2reg (RO, from uart_top role)
        .REG_UART_MODE   (reg_uart_mode),
        .REG_UART_BRG    (reg_uart_brg),   // [15:0]
        .REG_UART_BRG_WEN(reg_uart_brg_wen),
        .REG_UART_IE     (reg_uart_ie),
        .REG_UART_IF      (reg_uart_if),    // input of apb2reg (RO)
        .REG_UART_IFCLR  (reg_uart_ifclr),

        // UART FIFO interface
        .REG_UART_TXD    (reg_uart_txd),
        .REG_UART_TX_WEN (reg_uart_tx_wen),
        .REG_UART_RXD     (reg_uart_rxd),
        .REG_UART_RX_REN (reg_uart_rx_ren)
    );

    // ================= uart_tx (TX part of the uart_top role) =================
    logic        tx_busy;
    logic        tx_idle;
    logic        tx_ovf;
    logic        tx_fifo_full;
    logic        tx_fifo_empty;
    logic        tx_fifo_almost_full;
    logic [5:0]  tx_fifo_count;

    uart_tx #(
        .DATA_BITS     (8),
        .TX_FIFO_DEPTH (32)
    ) u_uart_tx (
        .I_CLK                  (UART_CLK),
        .I_RST_N                (RST_N),
        .I_UART_EN              (reg_uart_en),
        .I_BRG_DIV              (reg_uart_brg),
        .I_BRG_WR_EN            (reg_uart_brg_wen),
        .I_MODE                 (reg_uart_mode[3:0]),
        .I_TX_WR_EN             (reg_uart_tx_wen),
        .I_TX_WR_DATA           (reg_uart_txd),
        .I_TX_FIFO_CLR          (reg_uart_csr[0]),   // CSR[0] = TX_FIFO_CLR
        .O_TXD                 (UART_TXD),
        .O_TX_BUSY             (tx_busy),
        .O_TX_DONE             (tx_stop_done),
        .O_TX_IDLE             (tx_idle),
        .O_TX_FIFO_FULL        (tx_fifo_full),
        .O_TX_FIFO_EMPTY       (tx_fifo_empty),
        .O_TX_FIFO_ALMOST_FULL (tx_fifo_almost_full),
        .O_TX_FIFO_COUNT       (tx_fifo_count),
        .O_TX_OVF              (tx_ovf)
    );

    // ================= uart_rx (RX part of the uart_top role) =================
    logic        rx_busy;
    logic        rx_idle;
    logic        rx_ovf;
    logic        rx_parity_err;
    logic        rx_frame_err;
    logic        rx_fifo_full;
    logic        rx_fifo_empty;
    logic        rx_fifo_almost_full;
    logic [5:0]  rx_fifo_count;

    // Loopback control: CSR[4] = LOOPBACK_EN
    wire uart_rx_in = reg_uart_csr[4] ? UART_TXD : UART_RXD;

    // Detect toggle of loopback mode (0->1 or 1->0) to auto-flush RX FIFO and reset receiver state
    reg r_loopback_en_d;
    always @(posedge UART_CLK or negedge RST_N) begin
        if (!RST_N)
            r_loopback_en_d <= 1'b0;
        else
            r_loopback_en_d <= reg_uart_csr[4];
    end
    wire w_loopback_toggle = reg_uart_csr[4] ^ r_loopback_en_d;
    // RX FIFO pop comes from the APB read in BOTH modes (no auto-pop in loopback)
    wire w_rx_fifo_ren = reg_uart_rx_ren;

    // Combined RX FIFO clear: software clear pulse (CSR[1]) OR automatic flush on loopback toggle
    wire rx_fifo_clr_comb = reg_uart_csr[1] | w_loopback_toggle;

    uart_rx #(
        .DATA_BITS     (8),
        .RX_FIFO_DEPTH (32)
    ) u_uart_rx (
        .I_CLK                  (UART_CLK),
        .I_RST_N                (RST_N),
        .I_UART_EN              (reg_uart_en),
        .I_BRG_DIV              (reg_uart_brg),
        .I_BRG_WR_EN            (reg_uart_brg_wen),
        .I_MODE                 (reg_uart_mode[3:0]),
        .I_RXD                  (uart_rx_in),
        .I_RX_RD_EN             (w_rx_fifo_ren),
        .I_RX_FIFO_CLR          (rx_fifo_clr_comb),
        .O_RX_RD_DATA          (reg_uart_rxd),
        .O_RX_BUSY             (rx_busy),
        .O_RX_IDLE             (rx_idle),
        .O_RX_FIFO_FULL        (rx_fifo_full),
        .O_RX_FIFO_EMPTY       (rx_fifo_empty),
        .O_RX_FIFO_ALMOST_FULL (rx_fifo_almost_full),
        .O_RX_FIFO_COUNT       (rx_fifo_count),
        .O_RX_OVF              (rx_ovf),
        .O_RX_PARITY_ERR       (rx_parity_err),
        .O_RX_FRAME_ERR        (rx_frame_err)
    );

    // ---- STA assembly ----
    // TX status: [0]=TX_BUSY, [1]=TX_IDLE, [2]=TX_OVF, [8:3]=TX_FIFO_COUNT,
    //            [9]=TX_FIFO_FULL, [10]=TX_FIFO_EMPTY, [11]=TX_FIFO_ALMOST_FULL
    // RX status: [16]=RX_BUSY, [17]=RX_IDLE, [18]=RX_OVF, [19]=RX_PARITY_ERR, [20]=RX_FRAME_ERR,
    //            [26:21]=RX_FIFO_COUNT, [27]=RX_FIFO_FULL, [28]=RX_FIFO_EMPTY, [29]=RX_FIFO_ALMOST_FULL
    assign reg_uart_sta = {
        2'b00,
        rx_fifo_almost_full,  // [29]
        rx_fifo_empty,        // [28]
        rx_fifo_full,         // [27]
        rx_fifo_count,        // [26:21]
        rx_frame_err,         // [20]
        rx_parity_err,        // [19]
        rx_ovf,               // [18]
        rx_idle,              // [17]
        rx_busy,              // [16]
        4'b0000,              // [15:12]
        tx_fifo_almost_full,  // [11]
        tx_fifo_empty,        // [10]
        tx_fifo_full,         // [9]
        tx_fifo_count,        // [8:3]
        tx_ovf,               // [2]
        tx_idle,              // [1]
        tx_busy               // [0]
    };

    // ---- IF assembly ----
    // Interrupt flags:
    // [0]=TX_EMPTY_IF, [1]=RX_READY_IF, [2]=TX_OVF_IF, [3]=RX_OVF_IF,
    // [4]=RX_PARITY_ERR_IF, [5]=RX_FRAME_ERR_IF, [6]=TX_ALMOST_FULL_IF, [7]=RX_ALMOST_FULL_IF
    assign reg_uart_if  = {
        23'h000000,
        tx_stop_done,                    // [8]
        rx_fifo_almost_full,             // [7]
        tx_fifo_almost_full,             // [6]
        rx_frame_err,                    // [5]
        rx_parity_err,                   // [4]
        rx_ovf,                          // [3]
        tx_ovf,                          // [2]
        ~rx_fifo_empty,                  // [1] (RX data ready)
        (tx_fifo_empty & tx_idle)        // [0] (TX empty & idle)
    };

endmodule