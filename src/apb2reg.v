module apb2reg (
    input         UART_CLK,
    input         RST_N,
    input         PCLK,
    input         PRESETN,
    
    // Register outputs (from APB side to register logic)
    input  [31:0] I_REG_ADDR,
    input         I_REG_WR,
    input         I_REG_RD,
    input  [31:0] I_REG_WR_DATA,
    input         I_REG_ERR_ACK,

    // Register side (from register logic back to APB side)
    output [31:0] O_REG_RD_DATA,
    output        O_REG_ACK,
    output        O_REG_ERR,

    // UART interface
    output [7:0] REG_UART_TXD,
    input  [7:0] REG_UART_RXD,
    output       REG_UART_TX_WEN,
    output       REG_UART_RX_REN,

    // Register control signals
    output        REG_UART_EN,
    output [31:0] REG_UART_CSR,
    output [31:0] REG_UART_MODE,
    output [15:0] REG_UART_BRG,
    output        REG_UART_BRG_WEN,
    output [2:0]  REG_UART_DBITS,
    output [31:0] REG_UART_IE,
    output [31:0] REG_UART_IFCLR,

    // Status / interrupt flags — read-only, driven directly by uart_top
    input  [31:0] REG_UART_STA,
    input  [31:0] REG_UART_IF
);

    // Decode address
    localparam [29:0] p_reg_uart_en      = 30'(32'h0000_0000 >> 2);
    localparam [29:0] p_reg_uart_csr     = 30'(32'h0000_0004 >> 2);
    localparam [29:0] p_reg_uart_sta     = 30'(32'h0000_0008 >> 2);
    localparam [29:0] p_reg_uart_mode    = 30'(32'h0000_000c >> 2);
    localparam [29:0] p_reg_uart_brg     = 30'(32'h0000_0010 >> 2);
    localparam [29:0] p_reg_uart_dbits   = 30'(32'h0000_0020 >> 2);
    localparam [29:0] p_reg_uart_ie      = 30'(32'h0000_0014 >> 2);
    localparam [29:0] p_reg_uart_if      = 30'(32'h0000_0018 >> 2);
    localparam [29:0] p_reg_uart_ifclr   = 30'(32'h0000_001c >> 2);
    localparam [29:0] p_reg_uart_txd     = 30'(32'h0000_0100 >> 2);
    localparam [29:0] p_reg_uart_rxd     = 30'(32'h0000_0200 >> 2);
    
    // Initial value
    localparam [31:0] p_reg_uart_en_ini    = 32'h0000_0001;
    localparam [31:0] p_reg_uart_csr_ini   = 32'h0000_0000;
    localparam [31:0] p_reg_uart_mode_ini  = 32'h0000_0000;
    localparam [31:0] p_reg_uart_brg_ini   = 32'h0000_0146;   // 326 = 9600 bps @ 50 MHz
    localparam [31:0] p_reg_uart_dbits_ini = 32'h0000_0000;
    localparam [31:0] p_reg_uart_ie_ini    = 32'h0000_0000;
    localparam [31:0] p_reg_uart_ifclr_ini = 32'h0000_0000;
    localparam [ 7:0] p_reg_uart_txd_ini   = 8'h00;
    localparam [31:0] p_reg_uart_rxd_ini   = 32'h0000_0000;

    // ------------------------------------------------------------
    // Internal signals
    // ------------------------------------------------------------
    wire [31:0] mask_wr_data;
    wire [31:0] mod_wr_data;
    wire [31:0] raw_rd_data;
    wire        in_access;

    // APB side shadow registers
    wire [31:0] apb_reg_uart_en;
    wire [31:0] apb_reg_uart_csr;
    wire [31:0] apb_reg_uart_sta;
    wire [31:0] apb_reg_uart_mode;
    wire [31:0] apb_reg_uart_brg;
    wire [31:0] apb_reg_uart_dbits;
    wire [31:0] apb_reg_uart_ie;
    wire [31:0] apb_reg_uart_if;
    wire [31:0] apb_reg_uart_ifclr;
    wire [31:0] apb_reg_uart_rxd;

    // UART-domain landing ACK per register (1-cycle UART_CLK pulse)
    wire        uart_en_ack;
    wire        uart_csr_ack;
    wire        uart_mode_ack;
    wire        uart_brg_ack;
    wire        uart_dbits_ack;
    wire        uart_ie_ack;
    wire        uart_ifclr_ack;
    wire        uart_txd_ack;
    
    reg  [31:0] r_reg_uart_en;
    reg  [31:0] r_reg_uart_csr;
    reg  [31:0] r_reg_uart_mode;
    reg  [31:0] r_reg_uart_brg;
    reg  [31:0] r_reg_uart_dbits;
    reg  [31:0] r_reg_uart_ie;
    reg  [31:0] r_reg_uart_ifclr;
    reg  [ 7:0] r_reg_uart_txd;

    // ------------------------------------------------------------
    // Write mask by address
    // ------------------------------------------------------------
    assign mask_wr_data =   (I_REG_ADDR[31:2] == p_reg_uart_en   ) ? 32'h0000_0001 : // bit0
                            (I_REG_ADDR[31:2] == p_reg_uart_csr  ) ? 32'h0000_00FF : // bit0-7
                            (I_REG_ADDR[31:2] == p_reg_uart_sta  ) ? 32'h0000_0000 : // RO (uart_top)
                            (I_REG_ADDR[31:2] == p_reg_uart_mode ) ? 32'h0000_000F : // bit0-3
                            (I_REG_ADDR[31:2] == p_reg_uart_brg  ) ? 32'h0000_FFFF : // bit0-15
                            (I_REG_ADDR[31:2] == p_reg_uart_dbits) ? 32'h0000_0007 : // bit0-2: data-bits select
                            (I_REG_ADDR[31:2] == p_reg_uart_ie   ) ? 32'h0000_00FF : // bit0-7
                            (I_REG_ADDR[31:2] == p_reg_uart_if   ) ? 32'h0000_0000 : // RO (uart_top)
                            (I_REG_ADDR[31:2] == p_reg_uart_ifclr) ? 32'h0000_00FF : // bit0-7
                            (I_REG_ADDR[31:2] == p_reg_uart_txd  ) ? 32'h0000_00FF : // bit0-7
                            (I_REG_ADDR[31:2] == p_reg_uart_rxd  ) ? 32'h0000_0000 : // RO
                            32'h0000_0000;

    assign mod_wr_data = I_REG_WR_DATA & mask_wr_data;

    // ------------------------------------------------------------
    // RW registers
    // ------------------------------------------------------------
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_en_ini))    u_uart_en    (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_en   ), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_en   ), .O_UART_REG(r_reg_uart_en), .O_ACK(uart_en_ack));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_csr_ini))   u_uart_csr   (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_csr  ), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_csr  ), .O_UART_REG(r_reg_uart_csr), .O_ACK(uart_csr_ack));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_mode_ini))  u_uart_mode  (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_mode ), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_mode ), .O_UART_REG(r_reg_uart_mode), .O_ACK(uart_mode_ack));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_brg_ini))   u_uart_brg   (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_brg  ), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_brg  ), .O_UART_REG(r_reg_uart_brg), .O_ACK(uart_brg_ack));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_dbits_ini)) u_uart_dbits (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_dbits), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_dbits), .O_UART_REG(r_reg_uart_dbits), .O_ACK(uart_dbits_ack));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_ie_ini))    u_uart_ie    (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_ie   ), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_ie   ), .O_UART_REG(r_reg_uart_ie), .O_ACK(uart_ie_ack));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_ifclr_ini)) u_uart_ifclr (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_ifclr), .PDATA(mod_wr_data[31:0]), .O_APB_REG(apb_reg_uart_ifclr), .O_UART_REG(r_reg_uart_ifclr), .O_ACK(uart_ifclr_ack));
    rw_reg #(.DW(8 ), .DAT_INI(p_reg_uart_txd_ini))   u_uart_txd   (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_txd  ), .PDATA(mod_wr_data[ 7:0]), .O_APB_REG( /*Read only*/    ), .O_UART_REG(r_reg_uart_txd[7:0]), .O_ACK(uart_txd_ack));

    // ------------------------------------------------------------
    // RX FIFO read crossing (APB -> UART)
    // ------------------------------------------------------------
    wire w_rx_rd_req    = I_REG_RD & (I_REG_ADDR[31:2] == p_reg_uart_rxd);
    reg  r_rx_rd_req_d;
    reg  r_rx_rd_toggle;
    reg  r_rx_rd_sync1;
    reg  r_rx_rd_sync2;
    reg  r_rx_rd_sync3;

    always @(posedge PCLK or negedge PRESETN) begin
        if (!PRESETN) begin
            r_rx_rd_req_d  <= 1'b0;
            r_rx_rd_toggle <= 1'b0;
        end
        else begin
            r_rx_rd_req_d  <= w_rx_rd_req;
            if (w_rx_rd_req & ~r_rx_rd_req_d)
                r_rx_rd_toggle <= ~r_rx_rd_toggle;
        end
    end

    always @(posedge UART_CLK or negedge RST_N) begin
        if (!RST_N) begin
            r_rx_rd_sync1 <= 1'b0;
            r_rx_rd_sync2 <= 1'b0;
            r_rx_rd_sync3 <= 1'b0;
        end
        else begin
            r_rx_rd_sync1 <= r_rx_rd_toggle;
            r_rx_rd_sync2 <= r_rx_rd_sync1;
            r_rx_rd_sync3 <= r_rx_rd_sync2;
        end
    end

    assign REG_UART_RX_REN = r_rx_rd_sync2 ^ r_rx_rd_sync3;

    // ------------------------------------------------------------
    // RX data return (uart_top -> APB)
    // ------------------------------------------------------------
    assign apb_reg_uart_rxd = {24'h000000, REG_UART_RXD};

    // ------------------------------------------------------------
    // STA / IF status return (uart_top -> APB
    // ------------------------------------------------------------
    assign apb_reg_uart_sta = REG_UART_STA;
    assign apb_reg_uart_if  = REG_UART_IF;

    // ------------------------------------------------------------
    // APB read mux
    // ------------------------------------------------------------
    // CSR read data: W1S bits (bits 0, 1, 5) auto-clear and read as 0
    wire [31:0] rd_reg_uart_csr = {
        apb_reg_uart_csr[31:8],
        apb_reg_uart_csr[7:6],
        1'b0,                  // bit 5: ERR_CLR (w1s reads 0)
        apb_reg_uart_csr[4:2],
        1'b0,                  // bit 1: RX_FIFO_CLR (w1s reads 0)
        1'b0                   // bit 0: TX_FIFO_CLR (w1s reads 0)
    };

    assign raw_rd_data =  (I_REG_ADDR[31:2] == p_reg_uart_en   ) ? apb_reg_uart_en   :
                          (I_REG_ADDR[31:2] == p_reg_uart_csr  ) ? rd_reg_uart_csr   :
                          (I_REG_ADDR[31:2] == p_reg_uart_sta  ) ? apb_reg_uart_sta  :
                          (I_REG_ADDR[31:2] == p_reg_uart_mode ) ? apb_reg_uart_mode :
                          (I_REG_ADDR[31:2] == p_reg_uart_brg  ) ? apb_reg_uart_brg  :
                          (I_REG_ADDR[31:2] == p_reg_uart_dbits) ? apb_reg_uart_dbits:
                          (I_REG_ADDR[31:2] == p_reg_uart_ie   ) ? apb_reg_uart_ie   :
                          (I_REG_ADDR[31:2] == p_reg_uart_if   ) ? apb_reg_uart_if   :
                          (I_REG_ADDR[31:2] == p_reg_uart_ifclr) ? apb_reg_uart_ifclr:
                          (I_REG_ADDR[31:2] == p_reg_uart_rxd  ) ? apb_reg_uart_rxd  :
                          32'h0000_0000;
    // ------------------------------------------------------------
    // APB handshake
    // ------------------------------------------------------------
    wire w_uart_wr_ack = uart_en_ack    | uart_csr_ack  | uart_mode_ack |
                         uart_brg_ack   | uart_dbits_ack | uart_ie_ack  | uart_ifclr_ack |
                         uart_txd_ack;

    reg r_wr_ack_toggle;
    always @(posedge UART_CLK or negedge RST_N) begin
        if (!RST_N)
            r_wr_ack_toggle <= 1'b0;
        else if (w_uart_wr_ack)
            r_wr_ack_toggle <= ~r_wr_ack_toggle;
    end

    reg r_ack_sync1;
    reg r_ack_sync2;

    always @(posedge PCLK or negedge PRESETN) begin
        if (!PRESETN) begin
            r_ack_sync1 <= 1'b0;
            r_ack_sync2 <= 1'b0;

        end else begin
            r_ack_sync1 <= r_wr_ack_toggle;
            r_ack_sync2 <= r_ack_sync1;

        end
    end

    wire w_wr_ack_pclk = r_ack_sync1 ^ r_ack_sync2;   // 1-cycle PCLK pulse per landed write

    assign in_access     = I_REG_WR | I_REG_RD;
    assign O_REG_ACK     = I_REG_RD | w_wr_ack_pclk;

    // Address-based decode error. The previous data-based check would flag a
    // read that legitimately returns 0x00 (e.g. an RX FIFO byte) as an error.
    wire w_rd_hit = (I_REG_ADDR[31:2] == p_reg_uart_en   ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_csr  ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_sta  ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_mode ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_brg  ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_dbits) |
                    (I_REG_ADDR[31:2] == p_reg_uart_ie   ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_if   ) |
                    (I_REG_ADDR[31:2] == p_reg_uart_ifclr) |
                    (I_REG_ADDR[31:2] == p_reg_uart_rxd  );   // TXD is write-only -> read miss

    assign O_REG_ERR     = ((~w_rd_hit) & I_REG_RD) |                        //Error: read address not hit
                           ((mask_wr_data == 32'h0000_0000) & I_REG_WR);     //Error: write address not hit
    assign O_REG_RD_DATA = I_REG_RD ? raw_rd_data : 32'h0000_0000;

    // UART_BRG setting enable (1-cycle UART_CLK pulse from rw_reg)
    assign REG_UART_BRG_WEN = uart_brg_ack;
    // ------------------------------------------------------------
    // Output register
    // ------------------------------------------------------------
    assign REG_UART_EN     = r_reg_uart_en[0];
    assign REG_UART_TXD    = r_reg_uart_txd;

    // W1S clear pulse generation in UART_CLK domain (1-cycle UART_CLK pulse)
    wire csr_tx_fifo_clr_pulse = r_reg_uart_csr[0] & uart_csr_ack;
    wire csr_rx_fifo_clr_pulse = r_reg_uart_csr[1] & uart_csr_ack;
    wire csr_err_clr_pulse     = r_reg_uart_csr[5] & uart_csr_ack;

    // REG_UART_CSR: Bit-by-bit assignment based on field type
    assign REG_UART_CSR[0]    = csr_tx_fifo_clr_pulse; // bit 0: TX_FIFO_CLR (w1s: 1-cycle UART_CLK pulse)
    assign REG_UART_CSR[1]    = csr_rx_fifo_clr_pulse; // bit 1: RX_FIFO_CLR (w1s: 1-cycle UART_CLK pulse)
    assign REG_UART_CSR[2]    = r_reg_uart_csr[2];     // bit 2: TX_EN (rw: level)
    assign REG_UART_CSR[3]    = r_reg_uart_csr[3];     // bit 3: RX_EN (rw: level)
    assign REG_UART_CSR[4]    = r_reg_uart_csr[4];     // bit 4: LOOPBACK_EN (rw: level)
    assign REG_UART_CSR[5]    = csr_err_clr_pulse;     // bit 5: ERR_CLR (w1s: 1-cycle UART_CLK pulse)
    assign REG_UART_CSR[6]    = r_reg_uart_csr[6];     // bit 6: IRQ_EN (rw: level)
    assign REG_UART_CSR[7]    = r_reg_uart_csr[7];     // bit 7: AUTO_FLOW_EN (rw: level)
    assign REG_UART_CSR[31:8] = 24'h000000;            // bits 31:8: Reserved (ro: 0)

    assign REG_UART_MODE   = r_reg_uart_mode;
    assign REG_UART_BRG    = r_reg_uart_brg[15:0];
    assign REG_UART_DBITS  = r_reg_uart_dbits[2:0];
    assign REG_UART_IE     = r_reg_uart_ie;
    assign REG_UART_IFCLR  = r_reg_uart_ifclr;
    assign REG_UART_TX_WEN = uart_txd_ack;

endmodule
