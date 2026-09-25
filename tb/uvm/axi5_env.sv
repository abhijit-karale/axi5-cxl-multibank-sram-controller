// ============================================================================
// File: tb/uvm/axi5_env.sv
// Description: UVM Environment instantiating Agent and Scoreboard.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_ENV_SV
`define AXI5_ENV_SV

class axi5_env extends uvm_env;
  `uvm_component_utils(axi5_env)

  axi5_agent      agent;
  axi5_scoreboard scoreboard;

  function new(string name = "axi5_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = axi5_agent::type_id::create("agent", this);
    scoreboard = axi5_scoreboard::type_id::create("scoreboard", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.item_collected_port.connect(scoreboard.item_collected_export);
  endfunction

endclass : axi5_env

`endif // AXI5_ENV_SV
