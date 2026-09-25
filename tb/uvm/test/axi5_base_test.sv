// ============================================================================
// File: tb/uvm/test/axi5_base_test.sv
// Description: UVM Base Test establishing test environment, timeouts, and
//              top-level execution phases.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_BASE_TEST_SV
`define AXI5_BASE_TEST_SV

class axi5_base_test extends uvm_test;
  `uvm_component_utils(axi5_base_test)

  axi5_env env;

  function new(string name = "axi5_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi5_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_base_seq seq;
    phase.raise_objection(this, "Starting axi5_base_test");
    seq = axi5_base_seq::type_id::create("seq");
    `uvm_info("BASE_TEST", "Executing Base Sanity Read/Write Test...", UVM_LOW)

    seq.start(env.agent.sequencer);

    #100ns;
    phase.drop_objection(this, "Finishing axi5_base_test");
  endtask

endclass : axi5_base_test

`endif // AXI5_BASE_TEST_SV

