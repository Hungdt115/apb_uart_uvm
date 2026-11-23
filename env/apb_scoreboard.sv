class apb_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(apb_scoreboard)

  uvm_analysis_imp #(apb_transaction, apb_scoreboard) mon_export;

  apb_transaction exp_queue[$];

  // Associative array indexed by 32-bit APB address
  bit [31:0] sc_mem[bit [31:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    mon_export = new("mon_export", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sc_mem.delete();
  endfunction

  // write task - receives the pkt from monitor and pushes into queue
  function void write(apb_transaction tr);
    // tr.print();
    exp_queue.push_back(tr);
  endfunction

  virtual task run_phase(uvm_phase phase);
    apb_transaction expdata;

    forever begin
      wait (exp_queue.size() > 0);
      expdata = exp_queue.pop_front();

      if (expdata.PWRITE == apb_transaction::APB_WRITE) begin
        sc_mem[expdata.PADDR]    = expdata.DATA;
        `uvm_info("APB_SCOREBOARD", $sformatf("WRITE  Addr=0x%08h  Data=0x%08h", expdata.PADDR, expdata.DATA), UVM_LOW)
      end else if (expdata.PWRITE == apb_transaction::APB_READ) begin
        if (!sc_mem.exists(expdata.PADDR)) begin
          `uvm_info("APB_SCOREBOARD", $sformatf("READ_UNWRITTEN  Addr=0x%08h  Data=0x%08h", expdata.PADDR, expdata.DATA), UVM_LOW)
        end else if (sc_mem[expdata.PADDR] == expdata.DATA) begin
          `uvm_info("APB_SCOREBOARD", $sformatf("READ_MATCH  Addr=0x%08h  Exp=0x%08h  Got=0x%08h", expdata.PADDR, sc_mem[expdata.PADDR], expdata.DATA), UVM_LOW)
        end else begin
          `uvm_error("APB_SCOREBOARD", $sformatf("READ_MISMATCH  Addr=0x%08h  Exp=0x%08h  Got=0x%08h", expdata.PADDR, sc_mem[expdata.PADDR], expdata.DATA))
        end
      end
    end
  endtask

endclass