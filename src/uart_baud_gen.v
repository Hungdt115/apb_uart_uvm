// ============================================================================
//  Module      : uart_baud_gen
//  Description : Programmable UART baud-rate generator
//
//    - Shadow divisor div_val: loaded from I_BRG_DIV on I_BRG_WR_EN
//      (a write of 0 is ignored)
//    - Reset default P_DIV_RST = 326
//      (9600 bps @ UART_CLK = 50 MHz)
//    - 16-bit main counter -> O_TICK_16X (16x baud rate)
//    - 4-bit phase counter -> O_TICK_1X (1x baud rate)
//    - O_TICK_1X asserted 1 clock after the 16th O_TICK_16X pulse
//    - I_RESTART has the highest priority (clears both counters)
//    - I_ENABLE = 0: counters and phase are reset, no ticks
//    - Enable resumes from a new baud period (no pause/resume)
//    - Divisor write restarts baud timing immediately
//    - Asynchronous active-low reset (project convention)
// ============================================================================

module uart_baud_gen #(
    parameter P_DIV_RST = 16'd326
)(
    input           I_CLK,
    input           I_RST_N,
    input  [15:0]   I_BRG_DIV,
    input           I_BRG_WR_EN,
    input           I_ENABLE,
    input           I_RESTART,

    output          O_TICK_16X,
    output          O_TICK_1X
);

    // ------------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------------
    reg  [15:0] cnt;
    reg  [15:0] div_val;

    reg         tick_16x;
    reg  [3:0]  os_cnt;
    reg         tick_1x;
    reg         uart_brg_wen_d;

    // ------------------------------------------------------------------------
    // Divisor write detection
    // ------------------------------------------------------------------------
    wire div_wr_valid;
    wire cnt_16x_hit;

    always @(posedge I_CLK or negedge I_RST_N) begin : proc_uart_brg_wen_d
        if(~I_RST_N) begin
            uart_brg_wen_d <= 0;
        end else begin
            uart_brg_wen_d <= I_BRG_WR_EN;
        end
    end

    assign div_wr_valid = uart_brg_wen_d && (I_BRG_DIV != 16'h0);

    assign cnt_16x_hit = (cnt == (div_val - 16'd1));

    // ------------------------------------------------------------------------
    // Shadow divisor
    // ------------------------------------------------------------------------
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N)
            div_val <= P_DIV_RST;
        else if (div_wr_valid)
            div_val <= I_BRG_DIV;
    end

    // ------------------------------------------------------------------------
    // Main counter -> O_TICK_16X
    // ------------------------------------------------------------------------
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            cnt      <= 16'h0;
            tick_16x <= 1'b0;
        end
        else if (I_RESTART) begin
            cnt      <= 16'h0;
            tick_16x <= 1'b0;
        end
        else if (!I_ENABLE) begin
            cnt      <= 16'h0;
            tick_16x <= 1'b0;
        end
        else if (div_wr_valid) begin
            cnt      <= 16'h0;
            tick_16x <= 1'b0;
        end
        else if (cnt_16x_hit) begin
            cnt      <= 16'h0;
            tick_16x <= 1'b1;
        end
        else begin
            cnt      <= cnt + 16'd1;
            tick_16x <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Phase counter -> O_TICK_1X
    // ------------------------------------------------------------------------
    always @(posedge I_CLK or negedge I_RST_N) begin
        if (!I_RST_N) begin
            os_cnt  <= 4'h0;
            tick_1x <= 1'b0;
        end
        else if (I_RESTART) begin
            os_cnt  <= 4'h0;
            tick_1x <= 1'b0;
        end
        else if (!I_ENABLE) begin
            os_cnt  <= 4'h0;
            tick_1x <= 1'b0;
        end
        else if (div_wr_valid) begin
            os_cnt  <= 4'h0;
            tick_1x <= 1'b0;
        end
        else if (tick_16x) begin
            if (os_cnt == 4'd15) begin
                os_cnt  <= 4'h0;
                tick_1x <= 1'b1;
            end
            else begin
                os_cnt  <= os_cnt + 4'd1;
                tick_1x <= 1'b0;
            end
        end
        else begin
            tick_1x <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    assign O_TICK_16X = tick_16x;
    assign O_TICK_1X   = tick_1x;

endmodule