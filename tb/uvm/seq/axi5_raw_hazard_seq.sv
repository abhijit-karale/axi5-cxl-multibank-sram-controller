// ============================================================================
// File: tb/uvm/seq/axi5_raw_hazard_seq.sv
// Description: UVM Sequence validating Read-After-Write (RAW) Hazard Avoidance.
//              Fires a write immediately followed by a read to the exact same
//              address, ensuring CAM hazard stalls prevent stale read data.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_RAW_HAZARD_SEQ_SV
`define AXI5_RAW_HAZARD_SEQ_SV

class axi5_raw_hazard_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_raw_hazard_seq)

  function new(string name = "axi5_raw_hazard_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("RAW_SEQ", "Starting Read-After-Write (RAW) Hazard Avoidance Sequence...", UVM_LOW)

    // Pattern 1: Same address (0x0000_0100 - Bank 0) Write immediately followed by Read
    write_word(32'h0000_0100, 64'hCAFE_BABE_DEAD_BEEF, 4'hA);
    read_word(32'h0000_0100, 4'hB);

    // Pattern 2: Same address (0x0000_0108 - Bank 1) Write immediately followed by Read
    write_word(32'h0000_0108, 64'hFEED_FACE_0123_4567, 4'hC);
    read_word(32'h0000_0108, 4'hD);

    // Pattern 3: Overwrite same address and read again
    write_word(32'h0000_0100, 64'h1234_5678_9ABC_DEF0, 4'hE);
    read_word(32'h0000_0100, 4'hF);

    `uvm_info("RAW_SEQ", "RAW Hazard Avoidance Sequence Completed Successfully.", UVM_LOW)
  endtask

endclass : axi5_raw_hazard_seq

`endif // AXI5_RAW_HAZARD_SEQ_SV
