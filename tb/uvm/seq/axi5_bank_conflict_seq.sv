// ============================================================================
// File: tb/uvm/seq/axi5_bank_conflict_seq.sv
// Description: UVM Sequence to rigorously stress Bank Conflict Arbitration.
//              Generates simultaneous transactions targeting Bank 2 with
//              dynamic write-priority override triggering.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_BANK_CONFLICT_SEQ_SV
`define AXI5_BANK_CONFLICT_SEQ_SV

class axi5_bank_conflict_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_bank_conflict_seq)

  function new(string name = "axi5_bank_conflict_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("BNK_CONF_SEQ", "Starting Bank Conflict Arbitration Stress Test on Bank 2...", UVM_LOW)

    // Issue 4 back-to-back writes all targeting Bank 2 (addr[4:3] = 2'b10, so 0x10, 0x30, 0x50, 0x70)
    // This fills the CAM and triggers write_prio_override!
    write_word(32'h0000_0010, 64'hA001_B001_C001_D001, 4'h1);
    write_word(32'h0000_0030, 64'hA002_B002_C002_D002, 4'h2);
    write_word(32'h0000_0050, 64'hA003_B003_C003_D003, 4'h3);
    write_word(32'h0000_0070, 64'hA004_B004_C004_D004, 4'h4);

    // Issue competing reads to Bank 2
    read_word(32'h0000_0010, 4'h5);
    read_word(32'h0000_0030, 4'h6);
    read_word(32'h0000_0050, 4'h7);
    read_word(32'h0000_0070, 4'h8);

    `uvm_info("BNK_CONF_SEQ", "Bank Conflict Arbitration Stress Sequence Completed.", UVM_LOW)
  endtask

endclass : axi5_bank_conflict_seq

`endif // AXI5_BANK_CONFLICT_SEQ_SV
