// ============================================================================
// File: tb/uvm/test/axi5_stress_test.sv
// Description: UVM Stress Test running Out-of-Order Read sequences, Bank
//              Conflict sequences, RAW Hazard sequences, and randomized traffic.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_STRESS_TEST_SV
`define AXI5_STRESS_TEST_SV

class axi5_stress_test extends axi5_base_test;
  `uvm_component_utils(axi5_stress_test)

  function new(string name = "axi5_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_ooo_read_seq      ooo_seq;
    axi5_bank_conflict_seq bnk_seq;
    axi5_raw_hazard_seq    raw_seq;

    phase.raise_objection(this, "Starting axi5_stress_test");
    `uvm_info("STRESS_TEST", "==================================================", UVM_LOW)
    `uvm_info("STRESS_TEST", " STARTING AXI5 / CXL.mem COMPREHENSIVE STRESS TEST", UVM_LOW)
    `uvm_info("STRESS_TEST", "==================================================", UVM_LOW)

    // Phase 1: Out-of-Order Read Verification
    `uvm_info("STRESS_TEST", "--- Running Phase 1: Out-of-Order Read Sequence ---", UVM_LOW)
    ooo_seq = axi5_ooo_read_seq::type_id::create("ooo_seq");
    ooo_seq.start(env.agent.sequencer);

    #50ns;

    // Phase 2: Dynamic Bank Conflict & Write-Priority Override
    `uvm_info("STRESS_TEST", "--- Running Phase 2: Bank Conflict Arbitration Sequence ---", UVM_LOW)
    bnk_seq = axi5_bank_conflict_seq::type_id::create("bnk_seq");
    bnk_seq.start(env.agent.sequencer);

    #50ns;

    // Phase 3: RAW Hazard Avoidance & Pipeline Stalls
    `uvm_info("STRESS_TEST", "--- Running Phase 3: RAW Hazard Avoidance Sequence ---", UVM_LOW)
    raw_seq = axi5_raw_hazard_seq::type_id::create("raw_seq");
    raw_seq.start(env.agent.sequencer);

    #100ns;
    `uvm_info("STRESS_TEST", "==================================================", UVM_LOW)
    `uvm_info("STRESS_TEST", " AXI5 COMPREHENSIVE STRESS TEST COMPLETE", UVM_LOW)
    `uvm_info("STRESS_TEST", "==================================================", UVM_LOW)
    phase.drop_objection(this, "Finishing axi5_stress_test");
  endtask

endclass : axi5_stress_test

`endif // AXI5_STRESS_TEST_SV
