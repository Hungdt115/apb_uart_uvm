// ============================================================================
//  Module      : rw_reg
//  Description : Read/Write register with APB ↔ UART clock crossing
// ============================================================================
module rw_reg #(
    parameter  DW       = 32,
    parameter  DAT_INI  = {DW{1'b0}}
)(
    // APB clock domain
    input           I_CLK,
    input           I_RST,      // active low
    input [31:2]    PADDR,      // current APB address
    input [31:2]    WADDR,      // register word address
    input [DW-1:0]  PDATA,      // write data (already masked)
    input           WEN,

    // UART clock domain
    input           O_CLK,
    input           O_RST,      // active low

    // Outputs
    output [DW-1:0] O_APB_REG,  // APB shadow register
    output [DW-1:0] O_UART_REG  // UART domain register
);

    // ------------------------------------------------------------
    // APB write detect
    // ------------------------------------------------------------
    wire         hit_addr; 
    reg [DW-1:0] ri_sync_ff1;    
    reg [DW-1:0] ro_apb_reg;
    reg [DW-1:0] ro_uart_reg;
    
    assign hit_addr = (PADDR == WADDR);

    // ------------------------------------------------------------
    // APB clock domain register
    // ------------------------------------------------------------
    always @(posedge I_CLK or negedge I_RST) begin
        if (!I_RST) begin
            ro_apb_reg <= DAT_INI;
        end
        else if (hit_addr && WEN) begin
            ro_apb_reg <= PDATA;
        end
    end
    assign O_APB_REG = ro_apb_reg;
    
    // ------------------------------------------------------------
    // Synchronize APB reg into UART clock domain
    // ------------------------------------------------------------
    always @(posedge O_CLK or negedge O_RST) begin
        if (!O_RST) begin
            ri_sync_ff1   <= DAT_INI;
            ro_uart_reg   <= DAT_INI;
        end
        else begin
            ri_sync_ff1   <= ro_apb_reg;
            ro_uart_reg   <= ri_sync_ff1;
        end
    end
    assign O_UART_REG = ro_uart_reg;
endmodule