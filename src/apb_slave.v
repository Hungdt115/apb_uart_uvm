//--------------------------------------------------------------------
//-- Module Name : apb_slave
//-- Description :
//--   APB4 slave interface, rewritten from the behavioral spec
//--   (docs/hw/apb_uart/spec/apb_slave_spec.md). No FSM: combinational
//--   phase decode + minimal registers.
//--
//--   Behavior:
//--   - SETUP  (PSEL=1, PENABLE=0):
//--       latch O_REG_ADDR, transfer direction wr_d, and write data
//--       byte-filtered by I_PSTRB (bytes with strobe=0 keep old value).
//--   - ACCESS (PSEL=1, PENABLE=1):
//--       wait_cnt counts up toward wait_target (= p_wr_wait / p_rd_wait).
//--       Counting is disabled once the target is reached (no roll-over)
//--       and disabled entirely in ACK mode (p_use_ack=1).
//--   - Request signals O_REG_WR / O_REG_RD:
//--       p_use_ack=0 : 1-cycle pulse at the ACCESS start edge
//--                     (w_penable_pos & PWRITE / ~PWRITE)
//--       p_use_ack=1 : level 1 from the ACCESS start until w_pdone
//--   - O_PREADY:
//--       p_use_ack=0 : wait_cnt reaches wait_target
//--                     (p_wr_wait=0 -> ready in the 1st ACCESS cycle)
//--       p_use_ack=1 : one cycle after I_REG_ACK (registered), so the
//--                     latched PRDATA is stable at the master's sample edge
//--   - O_PRDATA : registered read data, latched while O_REG_RD is active
//--   - O_PSLVERR: held from I_REG_ERR (during ACCESS) until w_pdone
//--   - O_REG_ERR_ACK : 1-cycle pulse at w_pdone
//--------------------------------------------------------------------
module apb_slave #(
  parameter p_use_ack     = 0,          //0: PREADY from wait counter / 1: PREADY from I_REG_ACK
  parameter p_wr_wait     = 4'h0,       // extra write wait states in ACCESS
  parameter p_rd_wait     = 4'h1        // extra read wait states in ACCESS
)(
  //-- from APB_MASTER
  input              I_PCLK,            // APB clock
  input              I_PRESET,          // APB reset (active low)
  input       [31:0] I_PADDR,           // APB address
  input       [ 2:0] I_PPROT,           // APB protection (unused)
  input              I_PSEL,            // APB module select
  input              I_PENABLE,         // APB module enable
  input              I_PWRITE,          // APB write 1:write/0:read
  input       [31:0] I_PWDATA,          // APB write data
  input       [ 3:0] I_PSTRB,           // APB byte strobes (byte-filter write data)
  //-- from register block
  input       [31:0] I_REG_RD_DATA,     // register read data
  input              I_REG_ACK,         // register access ack (p_use_ack=1)
  input              I_REG_ERR,         // register decode error
  //-- for APB_MASTER
  output             O_PREADY,          // APB ready
  output      [31:0] O_PRDATA,          // APB read data (registered)
  output             O_PSLVERR,         // APB slave error
  //-- for register block
  output      [31:0] O_REG_ADDR,        // register address
  output             O_REG_WR,          // register write request
  output             O_REG_RD,          // register read request
  output      [31:0] O_REG_WR_DATA,     // register write data
  output             O_REG_ERR_ACK      // register error ack
);

  // ================= PHASE DECODE =================
  wire         w_psel        = I_PSEL & ~I_PENABLE;   // SETUP
  wire         w_penable     = I_PSEL &  I_PENABLE;   // ACCESS
  wire         w_pdone       = I_PENABLE & O_PREADY;  // completion cycle

  reg          r_penable;
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_penable <= 1'b0;
    else
      r_penable <= w_penable;
  end
  wire         w_penable_pos = w_penable & ~r_penable; // first ACCESS cycle

  // ================= SETUP LATCH =================
  reg          wr_d;                                  // transfer direction
  reg  [31:0]  r_reg_addr;
  reg  [31:0]  r_reg_wr_data;

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      wr_d <= 1'b0;
    else if (w_psel)
      wr_d <= I_PWRITE;
  end

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_reg_addr <= 32'h0;
    else if (w_psel)
      r_reg_addr <= I_PADDR;
  end

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_reg_wr_data <= 32'h0;
    else if (w_psel & I_PWRITE) begin
      if (I_PSTRB[0]) r_reg_wr_data[ 7: 0] <= I_PWDATA[ 7: 0];
      if (I_PSTRB[1]) r_reg_wr_data[15: 8] <= I_PWDATA[15: 8];
      if (I_PSTRB[2]) r_reg_wr_data[23:16] <= I_PWDATA[23:16];
      if (I_PSTRB[3]) r_reg_wr_data[31:24] <= I_PWDATA[31:24];
    end
  end

  // ================= WAIT-STATE COUNTER =================
  reg  [3:0]  wait_cnt;
  wire [3:0]  w_wait_target = wr_d ? p_wr_wait : p_rd_wait;
  wire        w_wait_done   = (wait_cnt >= w_wait_target);

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      wait_cnt <= 4'h0;
    else if (w_psel | w_pdone)                     // SETUP or completion: reset
      wait_cnt <= 4'h0;
    else if (w_penable & ~w_wait_done & ~p_use_ack)// disable at target reached
      wait_cnt <= wait_cnt + 4'h1;                 // disable in ACK mode
  end

  // ================= REQUEST SIGNALS =================
  wire         w_wr_pulse = w_penable_pos &  I_PWRITE;
  wire         w_rd_pulse = w_penable_pos & ~I_PWRITE;

  reg          r_wr_req;
  reg          r_rd_req;

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_wr_req <= 1'b0;
    else if (p_use_ack) begin
      if (w_pdone)
        r_wr_req <= 1'b0;
      else if (w_wr_pulse)
        r_wr_req <= 1'b1;
    end
  end

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_rd_req <= 1'b0;
    else if (p_use_ack) begin
      if (w_pdone)
        r_rd_req <= 1'b0;
      else if (w_rd_pulse)
        r_rd_req <= 1'b1;
    end
  end

  // ================= ACK READY (p_use_ack=1) =================
  // Registered ACK: O_PREADY rises one cycle after I_REG_ACK so the
  // latched O_PRDATA is stable at the master's sample edge.
  reg          r_ack_ready;
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_ack_ready <= 1'b0;
    else if (w_psel)
      r_ack_ready <= 1'b0;                        // new transfer: wait for ACK
    else if (w_pdone)
      r_ack_ready <= 1'b0;                        // completion: ready drops
    else if (I_REG_ACK)
      r_ack_ready <= 1'b1;
  end

  // ================= READ DATA (registered) =================
  reg  [31:0]  r_reg_rd_data;
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_reg_rd_data <= 32'h0;
    else if (O_REG_RD)
      r_reg_rd_data <= I_REG_RD_DATA;
  end

  // ================= ERROR =================
  reg          r_slv_err;
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_slv_err <= 1'b0;
    else if (w_pdone)
      r_slv_err <= 1'b0;
    else if (w_penable & I_REG_ERR)
      r_slv_err <= 1'b1;
  end

  // ================= OUTPUTS =================
  assign O_REG_ADDR    = r_reg_addr;
  assign O_REG_WR_DATA = r_reg_wr_data;
  assign O_REG_WR      = (p_use_ack) ? r_wr_req : w_wr_pulse;
  assign O_REG_RD      = (p_use_ack) ? r_rd_req : w_rd_pulse;
  assign O_PRDATA      = r_reg_rd_data;
  assign O_PREADY      = (p_use_ack) ? (w_penable & r_ack_ready)
                                     : (w_penable & w_wait_done);
  assign O_PSLVERR     = r_slv_err;
  assign O_REG_ERR_ACK = w_pdone;

endmodule
