class apb_driver extends uvm_driver #(apb_transaction);

  `uvm_component_utils(apb_driver)

  virtual apb_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
      `uvm_error("build_phase", "driver virtual interface failed")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    this.vif.PSEL    <= 0;
    this.vif.PENABLE <= 0;
    this.vif.PSTRB   <= 4'h0;

    forever begin
      apb_transaction tr;
      @(posedge this.vif.PCLK);
      //First get an item from sequencer
      seq_item_port.get_next_item(tr);
      @(posedge this.vif.PCLK);
      uvm_report_info("APB_DRIVER ", $sformatf("Got Transaction %s", tr.convert2string()));
      //Decode the APB Command and call either the read/write function
      case (tr.PWRITE)
        apb_transaction::APB_READ:  drive_read(tr.PADDR, tr.DATA);
        apb_transaction::APB_WRITE: drive_write(tr.PADDR, tr.DATA);
      endcase
      //Handshake DONE back to sequencer
      seq_item_port.item_done();
    end
  endtask

  virtual protected task drive_read(input bit [31:0] addr, output logic [31:0] data);
    this.vif.PADDR  <= addr;
    this.vif.PWRITE <= 0;
    this.vif.PSTRB  <= 4'h0;
    this.vif.PSEL   <= 1;
    @(posedge this.vif.PCLK);
    this.vif.PENABLE <= 1;
    // Wait until the slave asserts PREADY, then sample PRDATA
    do @(posedge this.vif.PCLK); while (this.vif.PREADY !== 1'b1);
    data = this.vif.PRDATA;
    this.vif.PSEL    <= 0;
    this.vif.PENABLE <= 0;
  endtask

  virtual protected task drive_write(input bit [31:0] addr, input bit [31:0] data);
    this.vif.PADDR  <= addr;
    this.vif.PWDATA <= data;
    this.vif.PWRITE <= 1;
    this.vif.PSTRB  <= 4'hF; // full-word write
    this.vif.PSEL   <= 1;
    @(posedge this.vif.PCLK);
    this.vif.PENABLE <= 1;
    // Wait until the slave asserts PREADY before ending the transfer
    do @(posedge this.vif.PCLK); while (this.vif.PREADY !== 1'b1);
    this.vif.PSEL    <= 0;
    this.vif.PENABLE <= 0;
  endtask

endclass