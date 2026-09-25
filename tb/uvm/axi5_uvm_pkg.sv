// ============================================================================
// File: tb/uvm/axi5_uvm_pkg.sv
// Description: UVM Package consolidating items, drivers, monitors, scoreboards,
//              sequences, and tests for the AXI5 Multi-Bank SRAM Controller.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_UVM_PKG_SV
`define AXI5_UVM_PKG_SV

`timescale 1ns/1ps

package axi5_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi5_pkg::*;

  // UVM Architecture Components
  `include "axi5_seq_item.sv"
  `include "axi5_sequencer.sv"
  `include "axi5_driver.sv"
  `include "axi5_monitor.sv"
  `include "axi5_scoreboard.sv"
  `include "axi5_agent.sv"
  `include "axi5_env.sv"

  // Sequences
  `include "seq/axi5_base_seq.sv"
  `include "seq/axi5_bank_conflict_seq.sv"
  `include "seq/axi5_ooo_read_seq.sv"
  `include "seq/axi5_raw_hazard_seq.sv"

  // Tests
  `include "test/axi5_base_test.sv"
  `include "test/axi5_stress_test.sv"

endpackage : axi5_uvm_pkg

`endif // AXI5_UVM_PKG_SV
