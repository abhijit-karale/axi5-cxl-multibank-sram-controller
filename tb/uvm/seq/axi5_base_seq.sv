// ============================================================================
// File: tb/uvm/seq/axi5_base_seq.sv
// Description: UVM Base Sequence with utility methods for directed & random
//              AXI5 transactions.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_BASE_SEQ_SV
`define AXI5_BASE_SEQ_SV

class axi5_base_seq extends uvm_sequence #(axi5_seq_item);
  `uvm_object_utils(axi5_base_seq)

  function new(string name = "axi5_base_seq");
    super.new(name);
  endfunction

  // Helper task: Directed 64-bit Write
  task write_word(
    input logic [AXI_ADDR_WIDTH-1:0] addr,
    input logic [AXI_DATA_WIDTH-1:0] data,
    input logic [AXI_ID_WIDTH-1:0]   id = '0,
    input logic [AXI_STRB_WIDTH-1:0] strb = '1
  );
    axi5_seq_item item;
    item = axi5_seq_item::type_id::create("seq_wr_item");
    start_item(item);
    item.tx_type = TX_TYPE_WRITE;
    item.id      = id;
    item.addr    = addr;
    item.len     = '0;
    item.size    = 3'b011;
    item.burst   = AXI_BURST_INCR;
    item.wdata   = new[1];
    item.wstrb   = new[1];
    item.wdata[0]= data;
    item.wstrb[0]= strb;
    finish_item(item);
  endtask

  // Helper task: Directed 64-bit Read
  task read_word(
    input logic [AXI_ADDR_WIDTH-1:0] addr,
    input logic [AXI_ID_WIDTH-1:0]   id = '0
  );
    axi5_seq_item item;
    item = axi5_seq_item::type_id::create("seq_rd_item");
    start_item(item);
    item.tx_type = TX_TYPE_READ;
    item.id      = id;
    item.addr    = addr;
    item.len     = '0;
    item.size    = 3'b011;
    item.burst   = AXI_BURST_INCR;
    finish_item(item);
  endtask

  virtual task body();
    `uvm_info("BASE_SEQ", "Executing Base AXI5 Sanity Sequence...", UVM_LOW)
    write_word(32'h0000_0000, 64'hAAAA_BBBB_CCCC_DDDD, 4'h1);
    read_word(32'h0000_0000, 4'h1);
  endtask

endclass : axi5_base_seq

`endif // AXI5_BASE_SEQ_SV
