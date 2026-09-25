// ============================================================================
// File: tb/uvm/seq/axi5_ooo_read_seq.sv
// Description: UVM Sequence validating Out-of-Order (OoO) Read Data Returns.
//              Populates data across 4 distinct banks and issues divergent
//              reads to demonstrate younger ID completion prior to older ID.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_OOO_READ_SEQ_SV
`define AXI5_OOO_READ_SEQ_SV

class axi5_ooo_read_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_ooo_read_seq)

  function new(string name = "axi5_ooo_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("OOO_SEQ", "Starting Out-of-Order Read Verification Sequence...", UVM_LOW)

    // Step 1: Pre-populate memory across all 4 banks
    // Bank 0: 0x0000_0000
    // Bank 1: 0x0000_0008
    // Bank 2: 0x0000_0010
    // Bank 3: 0x0000_0018
    write_word(32'h0000_0000, 64'h1111_2222_3333_4444, 4'h0);
    write_word(32'h0000_0008, 64'h5555_6666_7777_8888, 4'h1);
    write_word(32'h0000_0010, 64'h9999_AAAA_BBBB_CCCC, 4'h2);
    write_word(32'h0000_0018, 64'hDDDD_EEEE_FFFF_0000, 4'h3);

    // Step 2: Issue interleaved reads with different transaction IDs
    // Read Bank 3 (ID=3), Read Bank 0 (ID=0), Read Bank 1 (ID=1), Read Bank 2 (ID=2)
    read_word(32'h0000_0018, 4'h3);
    read_word(32'h0000_0000, 4'h0);
    read_word(32'h0000_0008, 4'h1);
    read_word(32'h0000_0010, 4'h2);

    `uvm_info("OOO_SEQ", "Out-of-Order Read Verification Sequence Completed.", UVM_LOW)
  endtask

endclass : axi5_ooo_read_seq

`endif // AXI5_OOO_READ_SEQ_SV
