// ============================================================================
//  Module      : apb_dut_wrapper
//  Description : Wrapper module for the APB DUT passthrough
//                - Instantiates `apb_dut_passthrough`
//                - Connects APB master and slave interfaces transparently
//
//  Author      : hungdt110520@gmail.com
//  Date        : 2025-07-21
// ============================================================================

module apb_dut_wrapper (
    input  logic         PCLK,
    input  logic         PRESETN,
    input  logic         UART_CLK,   // UART clock (from top)
    input  logic         RST_N,      // UART resetn (from top)

    // Slave interface (connected to APB master)
    input  logic         S_PWRITE,
    input  logic         S_PSEL,
    input  logic         S_PENABLE,
    input  logic [31:0]  S_PADDR,
    input  logic [31:0]  S_PWDATA,
    input  logic [3:0]   S_PSTRB,
    input  logic [2:0]   S_PPROT,

    output logic         S_PREADY,
    output logic         S_PSLVERR,
    output logic [31:0]  S_PRDATA,

    // Master interface (connected to APB slave)
    output logic         M_PWRITE,
    output logic         M_PSEL,
    output logic         M_PENABLE,
    output logic [31:0]  M_PADDR,
    output logic [31:0]  M_PWDATA,
    output logic [3:0]   M_PSTRB,
    output logic [2:0]   M_PPROT,
    input  logic         M_PREADY,
    input  logic         M_PSLVERR,
    input  logic [31:0]  M_PRDATA
);

    // Instantiate DUT passthrough
    apb_dut dut (
        .PCLK      (PCLK),
        .PRESETN   (PRESETN),
        .UART_CLK  (UART_CLK),
        .RST_N     (RST_N),

        .S_PWRITE  (S_PWRITE),
        .S_PSEL    (S_PSEL),
        .S_PENABLE (S_PENABLE),
        .S_PADDR   (S_PADDR),
        .S_PWDATA  (S_PWDATA),
        .S_PSTRB   (S_PSTRB),
        .S_PPROT   (S_PPROT),

        .S_PREADY  (S_PREADY),
        .S_PSLVERR (S_PSLVERR),
        .S_PRDATA  (S_PRDATA),

        .M_PWRITE  (M_PWRITE),
        .M_PSEL    (M_PSEL),
        .M_PENABLE (M_PENABLE),
        .M_PADDR   (M_PADDR),
        .M_PWDATA  (M_PWDATA),
        .M_PSTRB   (M_PSTRB),
        .M_PPROT   (M_PPROT),
        .M_PREADY  (M_PREADY),
        .M_PSLVERR (M_PSLVERR),
        .M_PRDATA  (M_PRDATA)
    );

endmodule