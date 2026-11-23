//--------------------------------------------------------------------
//-- Class: apb_simple_test
//-- Description: Basic uart_tx smoke test using the apb_single_read /
//--              apb_single_write helpers of apb_base_test:
//--                - configure BRG / MODE, enable the UART
//--                - push 3 bytes into the TX FIFO
//--                - poll STA until TX_IDLE, check no overflow
//--------------------------------------------------------------------
class apb_simple_test extends apb_base_test;
  `uvm_component_utils(apb_simple_test)

  function new(string name = "apb_simple_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    logic [31:0] rd;
    super.run_phase(phase);
    phase.raise_objection(this, "apb_simple_test");

    // Wait for reset release
    wait (vif.PRESETN === 1'b1);
    repeat (100) @(posedge vif.PCLK);

    `uvm_info(get_full_name(), "Configuring UART...", UVM_LOW)

    // Set mode lookback on
    apb_single_write(32'h0000_0004, 32'h0000_0013);
    apb_single_read (32'h0000_0004, rd);
    if (rd !== 32'h0000_0010)
      `uvm_error(get_full_name(), $sformatf("CSR readback 0x%08h exp 0x00000010", rd))
    else
      `uvm_info (get_full_name(), $sformatf("CSR readback OK = 0x%08h", rd), UVM_LOW)

    // 1. BRG = 3 -> 921600 bps @ UART_CLK = 50 MHz (fast sim)
    apb_single_write(32'h0000_0010, 32'h0000_0003);
    apb_single_read (32'h0000_0010, rd);
    if (rd !== 32'h0000_0003)
      `uvm_error(get_full_name(), $sformatf("BRG readback 0x%08h exp 0x00000003", rd))
    else
      `uvm_info (get_full_name(), $sformatf("BRG readback OK = 0x%08h", rd), UVM_LOW)

    // 2. MODE = 0 -> 8N1
    apb_single_write(32'h0000_000C, 32'h0000_0000);

    // 3. STA before traffic: expect idle, empty FIFO, no overflow
    apb_single_read(32'h0000_0008, rd);
    if (!rd[1] || rd[2] || (rd[8:3] != 6'd0))
      `uvm_error(get_full_name(), $sformatf("STA before traffic unexpected: 0x%08h", rd))
    else
      `uvm_info (get_full_name(), $sformatf("STA idle before traffic = 0x%08h", rd), UVM_LOW)

    // 4. Enable UART (EN bit1 = 1)
    apb_single_write(32'h0000_0000, 32'h0000_0002);
    apb_single_read (32'h0000_0000, rd);
    if (rd !== 32'h0000_0002)
      `uvm_error(get_full_name(), $sformatf("EN readback 0x%08h exp 0x00000002", rd))
    else
      `uvm_info (get_full_name(), "UART enabled", UVM_LOW)

    // 5. Push 3 bytes into the TX FIFO (0x00 included to test the zero path)
    `uvm_info(get_full_name(), "Pushing 3 bytes (A5, 5A, 00)...", UVM_LOW)
    apb_single_write(32'h0000_0100, 32'h0000_0055);
    apb_single_write(32'h0000_0100, 32'h0000_0055);
    apb_single_write(32'h0000_0100, 32'h0000_0055);
    apb_single_write(32'h0000_0100, 32'h0000_0055);
    apb_single_write(32'h0000_0100, 32'h0000_0055);
    apb_single_write(32'h0000_0100, 32'h0000_0000);

    // 6. TX must be active right after (busy or data still buffered)
    apb_single_read(32'h0000_0008, rd);
    if (!rd[0] && (rd[8:3] == 6'd0))
      `uvm_error(get_full_name(), $sformatf("TX not active after writes: STA=0x%08h", rd))
    else
      `uvm_info (get_full_name(), $sformatf("TX active after writes: STA=0x%08h", rd), UVM_LOW)

    // 7. Poll STA until TX_IDLE (bounded)
    repeat (2000) begin
      apb_single_read(32'h0000_0008, rd);
      if (rd[1]) break;
    end
    if (!rd[1])
      `uvm_error(get_full_name(), "TX_IDLE not reached (timeout)")
    else
      `uvm_info (get_full_name(), $sformatf("TX done: STA=0x%08h", rd), UVM_LOW)

    // 8. Final checks: no overflow, FIFO empty
    if (rd[2])
      `uvm_error(get_full_name(), "TX overflow flag set")
    if (rd[8:3] != 6'd0)
      `uvm_error(get_full_name(), $sformatf("FIFO not empty after TX: count=%0d", rd[8:3]))
    if (!rd[2] && (rd[8:3] == 6'd0))
      `uvm_info(get_full_name(), "apb_simple_test PASSED", UVM_LOW)

    phase.drop_objection(this, "apb_simple_test done");
  endtask

endclass
