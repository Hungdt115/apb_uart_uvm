class apb_transaction extends uvm_sequence_item;

  `uvm_object_utils(apb_transaction)

  //typedef for READ/Write transaction type
  typedef enum bit {
    READ,
    WRITE
  } trans_type;
  rand bit        [31:0] PADDR;  //Address
  rand bit        [31:0] DATA;  //Data - For write or read response
  rand trans_type        PWRITE;  //command type

  constraint c1 {PADDR[31:0] inside {[32'd0 : 32'd256]};}
  constraint c2 {DATA[31:0] inside {[32'd0 : 32'd256]};}

  function new(string name = "apb_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("PWRITE=%h PADDR=0x%8h DATA=0x%8h", PWRITE, PADDR, DATA);
  endfunction

endclass