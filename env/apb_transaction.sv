class apb_transaction extends uvm_sequence_item;

  //typedef for READ/Write transaction type
  typedef enum bit {
    APB_READ,
    APB_WRITE
  } trans_type;

  rand bit        [31:0] PADDR;  //Address
  rand bit        [31:0] DATA;   //Data - For write or read response
  rand trans_type        PWRITE; //command type

  `uvm_object_utils_begin(apb_transaction)
    `uvm_field_int (PADDR,  UVM_ALL_ON)
    `uvm_field_int (DATA,   UVM_ALL_ON)
    `uvm_field_enum(trans_type, PWRITE, UVM_ALL_ON)
  `uvm_object_utils_end

  constraint c1 {PADDR[31:0] inside {[32'd0 : 32'd256]};}
  constraint c2 {DATA[31:0]  inside {[32'd0 : 32'd256]};}

  function new(string name = "apb_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("PWRITE=%s PADDR=0x%8h DATA=0x%8h", PWRITE.name(), PADDR, DATA);
  endfunction

endclass