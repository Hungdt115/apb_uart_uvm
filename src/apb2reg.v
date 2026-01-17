// Decode address
localparam [29:0] p_reg_uart_en      = (32'h0000_0000 >> 2);
localparam [29:0] p_reg_uart_csr     = (32'h0000_0004 >> 2);
localparam [29:0] p_reg_uart_sta     = (32'h0000_0008 >> 2);
localparam [29:0] p_reg_uart_mode    = (32'h0000_000c >> 2);
localparam [29:0] p_reg_uart_brg     = (32'h0000_0010 >> 2);
localparam [29:0] p_reg_uart_ie      = (32'h0000_0014 >> 2);
localparam [29:0] p_reg_uart_if      = (32'h0000_0018 >> 2);
localparam [29:0] p_reg_uart_ifclr   = (32'h0000_001c >> 2);

// Initial value
localparam [31:0] p_reg_uart_en_ini    = 32'h0000_0000;
localparam [31:0] p_reg_uart_csr_ini   = 32'h0000_0000;
localparam [31:0] p_reg_uart_sta_ini   = 32'h0000_0000;
localparam [31:0] p_reg_uart_mode_ini  = 32'h0000_0000;
localparam [31:0] p_reg_uart_brg_ini   = 32'h0000_0000;
localparam [31:0] p_reg_uart_ie_ini    = 32'h0000_0000;
localparam [31:0] p_reg_uart_if_ini    = 32'h0000_0000;
localparam [31:0] p_reg_uart_ifclr_ini = 32'h0000_0000;

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
    output [3 :0] O_REG_RD_WAIT,
    output [31:0] O_REG_RD_DATA,
    output        O_REG_ACK,
    output        O_REG_ERR,

    // Register control signals
    output        REG_UART_EN,
    output [31:0] REG_UART_CSR,
    output [31:0] REG_UART_STA,
    output [31:0] REG_UART_MODE,
    output [31:0] REG_UART_BRG,
    output [31:0] REG_UART_IE,
    output [31:0] REG_UART_IF,
    output [31:0] REG_UART_IFCLR
);

    // ------------------------------------------------------------
    // Internal signals
    // ------------------------------------------------------------
    wire [31:0] val_wr_data;
    wire [31:0] mod_wr_data;
    wire [31:0] raw_rd_data;
    wire        in_access;

    // APB side shadow registers
    wire [31:0] apb_reg_uart_en;
    wire [31:0] apb_reg_uart_csr;
    wire [31:0] apb_reg_uart_sta;
    wire [31:0] apb_reg_uart_mode;
    wire [31:0] apb_reg_uart_brg;
    wire [31:0] apb_reg_uart_ie;
    wire [31:0] apb_reg_uart_if;
    wire [31:0] apb_reg_uart_ifclr;
    
    reg  [31:0] r_reg_uart_en;
    reg  [31:0] r_reg_uart_csr;
    reg  [31:0] r_reg_uart_sta;
    reg  [31:0] r_reg_uart_mode;
    reg  [31:0] r_reg_uart_brg;
    reg  [31:0] r_reg_uart_ie;
    reg  [31:0] r_reg_uart_if;
    reg  [31:0] r_reg_uart_ifclr;

    // ------------------------------------------------------------
    // Write mask by address
    // ------------------------------------------------------------
    assign val_wr_data =(I_REG_ADDR[31:2] == p_reg_uart_en   ) ? 32'h0000_0001 : // bit0
                        (I_REG_ADDR[31:2] == p_reg_uart_csr  ) ? 32'h0000_003F : // bit0-5
                        (I_REG_ADDR[31:2] == p_reg_uart_sta  ) ? 32'h0000_0001 :
                        (I_REG_ADDR[31:2] == p_reg_uart_mode ) ? 32'h0000_000F : // bit0-3
                        (I_REG_ADDR[31:2] == p_reg_uart_brg  ) ? 32'h0000_FFFF : // bit0-15
                        (I_REG_ADDR[31:2] == p_reg_uart_ie   ) ? 32'h0000_0007 : // bit0-2
                        (I_REG_ADDR[31:2] == p_reg_uart_if   ) ? 32'h0000_0007 :
                        (I_REG_ADDR[31:2] == p_reg_uart_ifclr) ? 32'h0000_0007 :
                        32'h0000_0000;

    assign mod_wr_data = I_REG_WR_DATA & val_wr_data;

    // ------------------------------------------------------------
    // RW registers
    // ------------------------------------------------------------
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_en_ini))    u_uart_en    (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_en   ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_en   ), .O_UART_REG(r_reg_uart_en));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_csr_ini))   u_uart_csr   (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_csr  ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_csr  ), .O_UART_REG(r_reg_uart_csr));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_sta_ini))   u_uart_sta   (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_sta  ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_sta  ), .O_UART_REG(r_reg_uart_sta));
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_mode_ini))  u_uart_mode  (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_mode ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_mode ), .O_UART_REG(r_reg_uart_mode));    
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_brg_ini))   u_uart_brg   (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_brg  ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_brg  ), .O_UART_REG(r_reg_uart_brg));    
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_ie_ini))    u_uart_ie    (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_ie   ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_ie   ), .O_UART_REG(r_reg_uart_ie));    
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_if_ini))    u_uart_if    (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_if   ), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_if   ), .O_UART_REG(r_reg_uart_if));    
    rw_reg #(.DW(32), .DAT_INI(p_reg_uart_ifclr_ini)) u_uart_ifclr (.I_CLK(PCLK), .I_RST(PRESETN), .O_CLK(UART_CLK), .O_RST(RST_N), .WEN(I_REG_WR), .PADDR(I_REG_ADDR[31:2]), .WADDR(p_reg_uart_ifclr), .PDATA(mod_wr_data), .O_APB_REG(apb_reg_uart_ifclr), .O_UART_REG(r_reg_uart_ifclr));
    // ------------------------------------------------------------
    // APB read mux
    // ------------------------------------------------------------
    assign raw_rd_data =  (I_REG_ADDR[31:2] == p_reg_uart_en   ) ? apb_reg_uart_en   :
                          (I_REG_ADDR[31:2] == p_reg_uart_csr  ) ? apb_reg_uart_csr  :
                          (I_REG_ADDR[31:2] == p_reg_uart_sta  ) ? apb_reg_uart_sta  :
                          (I_REG_ADDR[31:2] == p_reg_uart_mode ) ? apb_reg_uart_mode :
                          (I_REG_ADDR[31:2] == p_reg_uart_brg  ) ? apb_reg_uart_brg  :
                          (I_REG_ADDR[31:2] == p_reg_uart_ie   ) ? apb_reg_uart_ie   :
                          (I_REG_ADDR[31:2] == p_reg_uart_if   ) ? apb_reg_uart_if   :
                          (I_REG_ADDR[31:2] == p_reg_uart_ifclr) ? apb_reg_uart_ifclr:
                          32'h0000_0000;
    // ------------------------------------------------------------
    // APB handshake (More details will be added later)
    // ------------------------------------------------------------    
    assign in_access     = I_REG_WR | I_REG_RD;
    assign O_REG_RD_WAIT = 4'h0;
    assign O_REG_ACK     = I_REG_WR | I_REG_RD;                          // logic will be added latter
    assign O_REG_ERR     = (raw_rd_data == 32'h0000_0000 && in_access) ? 1'b1 :       //Error: read address not hit
                           (val_wr_data == 32'h0000_0000 && in_access) ? 1'b1 : 1'b0; //Error: write address not hit                                         
    assign O_REG_RD_DATA = I_REG_RD ? raw_rd_data : 32'h0000_0000; 
    // ------------------------------------------------------------
    // Output register
    // ------------------------------------------------------------
    assign REG_UART_EN     = r_reg_uart_en;
    assign REG_UART_CSR    = r_reg_uart_csr;
    assign REG_UART_STA    = r_reg_uart_sta;
    assign REG_UART_MODE   = r_reg_uart_mode;
    assign REG_UART_BRG    = r_reg_uart_brg;
    assign REG_UART_IE     = r_reg_uart_ie;
    assign REG_UART_IF     = r_reg_uart_if;
    assign REG_UART_IFCLR  = r_reg_uart_ifclr;

endmodule