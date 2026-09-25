// ============================================================================
// File: tb/uvm/axi5_sequencer.sv
// Description: UVM Sequencer for AXI5 transactions.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_SEQUENCER_SV
`define AXI5_SEQUENCER_SV

class axi5_sequencer extends uvm_sequencer #(axi5_seq_item);
  `uvm_component_utils(axi5_sequencer)

  function new(string name = "axi5_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass : axi5_sequencer

`endif // AXI5_SEQUENCER_SV
