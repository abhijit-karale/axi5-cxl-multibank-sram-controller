// ============================================================================
// File: tb/uvm/axi5_agent.sv
// Description: UVM Agent encapsulating Sequencer, Driver, and Monitor.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_AGENT_SV
`define AXI5_AGENT_SV

class axi5_agent extends uvm_agent;
  `uvm_component_utils(axi5_agent)

  axi5_sequencer sequencer;
  axi5_driver    driver;
  axi5_monitor   monitor;

  uvm_analysis_port #(axi5_seq_item) item_collected_port;

  function new(string name = "axi5_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = axi5_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = axi5_sequencer::type_id::create("sequencer", this);
      driver    = axi5_driver::type_id::create("driver", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
    item_collected_port = monitor.item_collected_port;
  endfunction

endclass : axi5_agent

`endif // AXI5_AGENT_SV
