//--------------------------------------------------------------------
//-- Module Name : apb_slave
//-- Description :
//--   This module implements a simple APB (Advanced Peripheral Bus)
//--   slave interface. It connects an APB master to an internal
//--   register block and handles APB read/write transactions.
//
//--   Features:
//--   - Supports APB setup and access phases (PSEL / PENABLE)
//--   - Configurable read and write wait states
//--   - Optional register-level ACK handshake
//--   - Read/write control signal generation for register interface
//--   - Slave error reporting via PSLVERR
//--------------------------------------------------------------------
module apb_slave #(
  parameter p_use_ack     = 0,          //0:no use ack/1:use ack
  parameter p_wr_wait     = 4'h0,       // write wait time
  parameter p_rd_wait     = 4'h1        // read wait time
)(
  //-- input signal
  //-- from APB_MASTER
  input              I_PCLK,            // APB clock
  input              I_PRESET,          // APB reset 
  input       [31:0] I_PADDR,           // APB address
  input       [ 2:0] I_PPROT,           // APB protection(no use)
  input              I_PSEL,            // APB module select
  input              I_PENABLE,         // APB module enable
  input              I_PWRITE,          // APB write 1:write/0:read
  input       [31:0] I_PWDATA,          // APB write data
  input       [ 3:0] I_PSTRB,           // APB byte syrobe(no use)
  //-- from register
  input       [ 3:0] I_REG_RD_WAIT,     // register read wait
  input       [31:0] I_REG_RD_DATA,     // register read data
  input              I_REG_ACK,         // register read/write ack
  input              I_REG_ERR,         // register error
  
  //-- output signal
  //-- for APB_MASTER
  output             O_PREADY,          // APB ready
  output      [31:0] O_PRDATA,          // APB read data
  output             O_PSLVERR,         // APB slave error
  //-- for register
  output      [31:0] O_REG_ADDR,        // register address
  output             O_REG_WR,          // register write enable
  output             O_REG_RD,          // register read enable
  output      [31:0] O_REG_WR_DATA,     // register write data
  output             O_REG_ERR_ACK      // register error ack
);

  

  // ================= REGISTER =================
  reg          r_psel;
  reg  [3:0]   r_wait_cnt;
  reg          r_read_pos;
  reg          r_write_pos;
  reg          r_wait_ready;
  reg          r_ack_ready;
  reg          r_slv_err;
  reg  [31:0]  r_reg_addr;
  reg  [31:0]  r_reg_wr_data;
  reg  [31:0]  r_reg_rd_data;

  // ================= WIRE =================
  wire         w_psel;
  wire         w_penable;
  wire         w_psel_pos;
  wire         w_pwrite;
  wire         w_pread;
  wire         w_pwrite_pos;
  wire         w_pread_pos;
  wire         w_wait_wr_ready;
  wire         w_wait_rd_ready;
  wire         w_wr_cnt_chk;
  wire         w_rd_cnt_chk;
  wire         w_wait_ready;
  wire         w_ready;
  wire         w_nowait_rd_ready;
  wire         w_nowait_wr_ready;
  wire         w_psel_pos_wr;
  wire         w_psel_pos_rd;
  wire         w_pdone;
  wire  [3:0]  w_rd_wait;
  wire         w_sel_ack;
  wire         w_sel_pready;

  // ================= OUTPUT =================
  assign O_REG_RD      = r_read_pos;
  assign O_REG_WR      = r_write_pos;
  assign O_PREADY      = w_sel_pready;
  assign O_PSLVERR     = r_slv_err;
  assign O_REG_ADDR    = r_reg_addr;
  assign O_REG_WR_DATA = r_reg_wr_data;
  // assign O_PRDATA      = r_reg_rd_data;
  assign O_PRDATA      = I_REG_RD_DATA;
  assign O_REG_ERR_ACK = w_pdone;

  // ================= INPUT DECODE =================
  assign w_psel    =  I_PSEL & ~I_PENABLE;
  assign w_penable =  I_PSEL &  I_PENABLE;
  assign w_pwrite  =  I_PWRITE & I_PENABLE;
  assign w_pread   = ~I_PWRITE & I_PENABLE;
  assign w_pdone   =  I_PENABLE & O_PREADY;

  // ================= PSEL EDGE =================
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_psel <= 1'b0;
    else
      r_psel <= w_psel;
  end

  assign w_psel_pos   = w_psel & ~r_psel;
  assign w_pread_pos  = w_psel_pos & ~I_PWRITE;
  assign w_pwrite_pos = w_psel_pos &  I_PWRITE;

  // ================= READ / WRITE FLAG =================
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_read_pos <= 1'b0;
    else if (w_pdone)
      r_read_pos <= 1'b0;
    else if (w_pread_pos)
      r_read_pos <= 1'b1;
  end

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_write_pos <= 1'b0;
    else
      r_write_pos <= w_pwrite_pos;
  end

  // ================= WAIT COUNTER =================
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_wait_cnt <= 4'h0;
    else if (w_psel_pos | w_pdone)
      r_wait_cnt <= 4'h0;
    else if (w_penable)
      r_wait_cnt <= r_wait_cnt + 4'h1;
  end

  assign w_rd_wait       = (I_REG_RD_WAIT == 4'hF) ? 4'hF : I_REG_RD_WAIT + 4'h1;
  assign w_wr_cnt_chk    = (r_wait_cnt == (p_wr_wait - 4'h1));
  assign w_rd_cnt_chk    = (r_wait_cnt >= (w_rd_wait - 4'h1));

  assign w_wait_wr_ready = w_wr_cnt_chk & w_pwrite;
  assign w_wait_rd_ready = w_rd_cnt_chk & w_pread;
  assign w_wait_ready    = w_wait_wr_ready | w_wait_rd_ready;

  assign w_nowait_wr_ready = (p_wr_wait == 4'h0) ? r_write_pos : 1'b0;
  assign w_nowait_rd_ready = (p_rd_wait == 4'h0) ? r_read_pos  : 1'b0;

  assign w_psel_pos_wr = w_pwrite_pos & (p_wr_wait != 4'h0);
  assign w_psel_pos_rd = w_pread_pos  & (w_rd_wait != 4'h0);

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_wait_ready <= 1'b1;
    else if (w_psel_pos_wr | w_psel_pos_rd)
      r_wait_ready <= 1'b0;
    else if (w_wait_ready)
      r_wait_ready <= 1'b1;
  end

  assign w_ready = w_nowait_rd_ready | w_nowait_wr_ready | r_wait_ready;

  // ================= ACK READY =================
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_ack_ready <= 1'b1;
    else if (w_pdone)
      r_ack_ready <= 1'b1;
    else if (w_psel_pos)
      r_ack_ready <= 1'b0;
    else if (I_REG_ACK)
      r_ack_ready <= 1'b1;
  end

  assign w_sel_pready = (p_use_ack) ? r_ack_ready : w_ready;

  // ================= REGISTER ADDR / DATA =================
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_reg_addr <= 32'h0;
    else if (w_psel_pos)
      r_reg_addr <= I_PADDR;
  end

  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_reg_wr_data <= 32'h0;
    else if (w_pwrite_pos)
      r_reg_wr_data <= I_PWDATA;
  end

  assign w_sel_ack = (p_use_ack) ? I_REG_ACK : w_wait_rd_ready;


  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_reg_rd_data <= 32'h0;
    else if (w_sel_ack)
      r_reg_rd_data <= I_REG_RD_DATA;
    else
      r_reg_rd_data <= I_REG_RD_DATA;
  end


  // ================= ERROR =================
  always @(posedge I_PCLK or negedge I_PRESET) begin
    if (!I_PRESET)
      r_slv_err <= 1'b0;
    else if (w_pdone)
      r_slv_err <= 1'b0;
    else if (I_REG_ERR)
      r_slv_err <= 1'b1;
  end

endmodule