//-- UVM Package and Macros
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "apb_if.sv"
//-- Test-related Includes
`include "test_top.sv"

//--------------------------------------------------------------------
// Module: top_test
// Description:
//   Top-level module for the APB UVM testbench using apb_dut_wrapper.
//   Instantiates DUT wrapper and APB interfaces (slave/master),
//   starts UVM test.
//--------------------------------------------------------------------

module top_test();

  //-- APB Slave Interface (input side to DUT)
  apb_if slave_vif();

  //-- APB Master Interface (output side from DUT)
  apb_if master_vif();  

  //--------------------------------------------------------------------
  //-- Clock Generation
  //--------------------------------------------------------------------
  initial begin
    slave_vif.PCLK = 1'b0;
    forever #5 slave_vif.PCLK = ~slave_vif.PCLK;
  end

  logic UART_CLK;
  initial begin
    UART_CLK = 1'b0;
    forever #10 UART_CLK = ~UART_CLK;
  end

  assign master_vif.PCLK = slave_vif.PCLK;

  //--------------------------------------------------------------------
  //-- Reset Generation
  //--------------------------------------------------------------------
  initial begin
    slave_vif.PRESETN = 1'b1;
    #15;
    slave_vif.PRESETN = 1'b0;
    #20;
    slave_vif.PRESETN = 1'b1;
  end

  assign master_vif.PRESETN = slave_vif.PRESETN;
  
  
  //-- DUT Wrapper Instance
  apb_dut_wrapper dut_wrapper (  	
    // Slave side (inputs)
    .PCLK      (slave_vif.PCLK),
    .PRESETN   (slave_vif.PRESETN),
    .S_PADDR   (slave_vif.PADDR),
    .S_PWRITE  (slave_vif.PWRITE),
    .S_PSEL    (slave_vif.PSEL),
    .S_PENABLE (slave_vif.PENABLE),
    .S_PWDATA  (slave_vif.PWDATA),
    .S_PSTRB   (slave_vif.PSTRB),
    .S_PPROT   (slave_vif.PPROT),
    .S_PRDATA  (slave_vif.PRDATA),
    .S_PREADY  (slave_vif.PREADY),
    .S_PSLVERR (slave_vif.PSLVERR),

    // Master side (outputs)
    .M_PADDR   (master_vif.PADDR),
    .M_PWRITE  (master_vif.PWRITE),
    .M_PSEL    (master_vif.PSEL),
    .M_PENABLE (master_vif.PENABLE),
    .M_PWDATA  (master_vif.PWDATA),
    .M_PSTRB   (master_vif.PSTRB),
    .M_PPROT   (master_vif.PPROT),
    .M_PRDATA  (master_vif.PRDATA),
    .M_PREADY  (master_vif.PREADY),
    .M_PSLVERR (master_vif.PSLVERR),
    
    //Uart interface
    .UART_CLK  (UART_CLK),
    .RST_N     (slave_vif.PRESETN)
  );

  //--------------------------------------------------------------------
  //-- UVM Test Execution
  //--------------------------------------------------------------------
  initial begin
    //-- Set virtual interface(s) for testbench
    uvm_config_db#(virtual apb_if)::set(null, "*", "vif", slave_vif);
    uvm_config_db#(virtual apb_if)::set(null, "*", "m_vif", master_vif);

    //-- Run the test
    run_test();
  end

  //--------------------------------------------------------------------
  //-- Waveform Dumping
  //--------------------------------------------------------------------
  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars;
  end

endmodule