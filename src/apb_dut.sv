// ============================================================================
//  Module      : apb_dut
//  Description : APB4-compliant module that instances apb_mem.
//                Retains original port list, with unused master ports driven to default.
//
//  Author      : hungdt110520@gmail.com
//  Date        : 2025-07-21
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
    input  logic [2:0]   S_PPROT, // unused by apb_mem

    output logic         S_PREADY,
    output logic         S_PSLVERR,
    output logic [31:0]  S_PRDATA,

    // APB4 Master Interface (to APB slave in testbench, now unused)
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
    
    // Register control signals
    output logic         REG_UART_EN,
    output logic [31:0]  REG_UART_CSR,
    output logic [31:0]  REG_UART_STA,
    output logic [31:0]  REG_UART_MODE,
    output logic [31:0]  REG_UART_BRG,
    output logic [31:0]  REG_UART_IE,
    output logic [31:0]  REG_UART_IF,
    output logic [31:0]  REG_UART_IFCLR
    );

    // Drive master passthrough
    assign M_PWRITE   = S_PWRITE;
    assign M_PSEL     = S_PSEL;
    assign M_PENABLE  = S_PENABLE;
    assign M_PADDR    = S_PADDR;
    assign M_PWDATA   = S_PWDATA;
    assign M_PSTRB    = S_PSTRB;
    assign M_PPROT    = S_PPROT;
    
    logic [3:0]   reg_rd_wait;
    logic [31:0]  reg_rd_data;
    logic         reg_ack;
    logic         reg_err;

    logic [31:0]  reg_addr;
    logic         reg_wr;
    logic         reg_rd;
    logic [31:0]  reg_wr_data;
    logic         reg_err_ack;

    // Instance of apb_mem
    // Connect apb_dut's slave interface to apb_mem's interface
    apb_slave #(
        .p_use_ack (1'h0),
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
        .I_REG_RD_WAIT (reg_rd_wait),
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
    
    apb2reg u_apb2reg(
        .UART_CLK      (UART_CLK ),
        .RST_N         (RST_N    ),
        .PCLK          (PCLK     ),
        .PRESETN       (PRESETN  ),
        
        // Register outputs
        .I_REG_ADDR    (reg_addr),
        .I_REG_WR      (reg_wr),
        .I_REG_RD      (reg_rd),
        .I_REG_WR_DATA (reg_wr_data),
        .I_REG_ERR_ACK (reg_err_ack),  //to clear err flag
        
        // Register side
        .O_REG_RD_WAIT (reg_rd_wait),
        .O_REG_RD_DATA (reg_rd_data),
        .O_REG_ACK     (reg_ack),
        .O_REG_ERR     (reg_err),
        
        // Register control signal
        .REG_UART_EN   (REG_UART_EN),
        .REG_UART_CSR  (REG_UART_CSR),
        .REG_UART_STA  (REG_UART_STA),
        .REG_UART_MODE (REG_UART_MODE),
        .REG_UART_BRG  (REG_UART_BRG),
        .REG_UART_IE   (REG_UART_IE),
        .REG_UART_IF   (REG_UART_IF),
        .REG_UART_IFCLR(REG_UART_IFCLR)
    );

endmodule