# ==============================================================================
# File: tb/formal/run_jg.tcl
# Description: Production JasperGold TCL script for Formal Property Verification
#              of AXI5/CXL.mem Coherent Multi-Bank SRAM Controller.
# Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
# Target Tech: SkyWater 130nm @ 200 MHz
# Usage: jg -no_gui tb/formal/run_jg.tcl
# ==============================================================================

# 1. Environment & Database Initialization
clear -all
set_sv_version 2012
set_message -suppress {VER-1300 VER-1301}

# 2. File Ingestion & Compilation
analyze -sv \
  rtl/axi5_pkg.sv \
  rtl/sram_bank_16k.sv \
  rtl/axi5_bank_arbiter.sv \
  rtl/axi5_cam_tracker.sv \
  rtl/axi5_rob.sv \
  rtl/axi5_sram_controller.sv \
  tb/formal/axi5_sva.sv \
  tb/formal/axi5_formal_bind.sv

# 3. Elaboration & Parameterization
elaborate -top axi5_sram_controller \
  -parameters {
    AXI_ADDR_W 32
    AXI_DATA_W 64
    AXI_STRB_W 8
    AXI_ID_W   4
    NUM_BNKS   4
    BNK_DEPTH  2048
    BNK_ADDR_W 11
  }

# 4. Clock and Reset Specifications
clock ACLK -period 5.0
reset -expression {!ARESETn}

# 5. Environment Assumptions (AXI Master Interface Constraints)
# Assumption 1: AW channel payload stability during stall
assume -name asm_aw_stable -env {
  (AWVALID && !AWREADY) |=> (AWVALID && $stable({AWID, AWADDR, AWLEN, AWSIZE, AWBURST}))
}

# Assumption 2: W channel payload stability during stall
assume -name asm_w_stable -env {
  (WVALID && !WREADY) |=> (WVALID && $stable({WDATA, WSTRB, WLAST}))
}

# Assumption 3: AR channel payload stability during stall
assume -name asm_ar_stable -env {
  (ARVALID && !ARREADY) |=> (ARVALID && $stable({ARID, ARADDR, ARLEN, ARSIZE, ARBURST}))
}

# Assumption 4: Valid strobe pattern (at least 1 byte enabled on write)
assume -name asm_wstrb_nonzero -env {
  WVALID |-> (|WSTRB)
}

# Assumption 5: Burst length bounded for formal bounded proof
assume -name asm_bounded_len -env {
  (AWVALID |-> (AWLEN <= 8'd3)) &&
  (ARVALID |-> (ARLEN <= 8'd3))
}

# 6. Formal Proof Engine Orchestration
set_engine_mode {Hp Ht B M N Q Tri}
set_prove_time_limit 600s
set_max_trace_length 50

# 7. Verification Execution
check_fv -init
puts "=========================================================="
puts "  STARTING FORMAL PROOF OF AXI5 SRAM CONTROLLER"
puts "=========================================================="

prove -all

# 8. Report Generation & Sign-off Audit
report -summary -results -file formal_results.rpt
report -covers -file formal_covers.rpt

puts "=========================================================="
puts "  FORMAL VERIFICATION COMPLETE. RESULTS RECORDED."
puts "=========================================================="
exit
