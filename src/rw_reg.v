// ============================================================================
//  Module      : rw_reg
//  Description : Dual-clock register slice (spec: docs/hw/apb_uart/spec/rw_reg_spec.md)
//    Strict 2-FF four-phase full handshake between the APB and UART domains:
//      Phase 1 (I_CLK): accepted write -> ro_apb_reg <= PDATA, wr_req_apb = 1
//      Phase 2 (O_CLK): REQ crosses 2-FF -> capture data into ro_uart_reg,
//                       wr_ack_uart = 1, O_ACK 1-cycle pulse
//      Phase 3 (I_CLK): ACK crosses 2-FF -> wr_req_apb = 0
//      Phase 4 (O_CLK): REQ-low seen -> wr_ack_uart = 0 (idle, next transfer)
//    A write arriving while the handshake is pending is NOT accepted (strict).
// ============================================================================
module rw_reg #(
    parameter  DW       = 32,
    parameter  DAT_INI  = {DW{1'b0}}
)(
    // APB clock domain
    input           I_CLK,
    input           I_RST,      // active low
    input  [29:0]   PADDR,      // current APB word address, bits [31:2]
    input  [29:0]   WADDR,      // register word address, bits [31:2]
    input  [DW-1:0] PDATA,      // write data (already masked)
    input           WEN,

    // UART clock domain
    input           O_CLK,
    input           O_RST,      // active low

    // Outputs
    output [DW-1:0] O_APB_REG,  // APB shadow register
    output [DW-1:0] O_UART_REG, // UART domain register
    output          O_ACK       // O_CLK 1-cycle pulse: new value captured in O_UART_REG
);

    // ------------------------------------------------------------
    // APB domain: handshake REQ + shadow register + ACK synchroniser
    // ------------------------------------------------------------
    wire         hit_addr= (PADDR == WADDR);
    reg          wr_req_apb;
    reg  [DW-1:0] ro_apb_reg;
    reg          wr_ack_sync1;
    reg          wr_ack_sync2;

    reg          wr_req_sync1;
    reg          wr_req_sync2;
    reg          wr_req_sync3;
    reg          wr_ack_uart;
    reg  [DW-1:0] ro_uart_reg;

    always @(posedge I_CLK or negedge I_RST) begin
        if (!I_RST) begin
            wr_req_apb <= 1'b0;
            ro_apb_reg <= DAT_INI;
        end
        // Phase 1: accept only when the handshake is fully idle
        else if (hit_addr && WEN && ~wr_req_apb && ~wr_ack_sync2) begin
            wr_req_apb <= 1'b1;
            ro_apb_reg <= PDATA;
        end
        // Phase 3: ACK observed through the 2-FF synchroniser -> REQ low
        else if (wr_ack_sync2) begin
            wr_req_apb <= 1'b0;
        end
    end
    assign O_APB_REG = ro_apb_reg;

    always @(posedge I_CLK or negedge I_RST) begin
        if (!I_RST) begin
            wr_ack_sync1 <= 1'b0;
            wr_ack_sync2 <= 1'b0;
        end
        else begin
            wr_ack_sync1 <= wr_ack_uart;
            wr_ack_sync2 <= wr_ack_sync1;
        end
    end

    // ------------------------------------------------------------
    // UART domain: REQ 2-FF sync + data capture + ACK generator
    // ------------------------------------------------------------
    always @(posedge O_CLK or negedge O_RST) begin
        if (!O_RST) begin
            wr_req_sync1 <= 1'b0;
            wr_req_sync2 <= 1'b0;
            wr_req_sync3 <= 1'b0;
            wr_ack_uart  <= 1'b0;
            ro_uart_reg  <= DAT_INI;
        end
        else begin
            wr_req_sync1 <= wr_req_apb;
            wr_req_sync2 <= wr_req_sync1;
            wr_req_sync3 <= wr_req_sync2;

            // Phase 2: REQ rising (2-FF settled) -> capture, ACK assert
            if (wr_req_sync1 & ~wr_req_sync3) begin
                ro_uart_reg <= ro_apb_reg;   // data stable during REQ=1
                wr_ack_uart <= 1'b1;
            end
            // Phase 4: REQ-low seen -> ACK deassert (handshake idle)
            if (~wr_req_sync2) begin
                wr_ack_uart <= 1'b0;
            end
        end
    end

    assign O_UART_REG = ro_uart_reg;

    // 1-cycle O_CLK pulse in the cycle right after the capture edge:
    // O_UART_REG already holds the new value during the O_ACK cycle
    assign O_ACK      = wr_req_sync2 & ~wr_req_sync3;

endmodule
