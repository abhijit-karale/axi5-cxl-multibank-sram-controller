# ==============================================================================
# File: Makefile
# Description: Production Build & Verification Automation Makefile for
#              AXI5/CXL.mem Coherent Multi-Bank SRAM Controller.
# Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
# Target Tech: SkyWater 130nm @ 200 MHz
# ==============================================================================

# Simulator and Tool Definitions
QUESTA_DIR ?= C:/questasim64_10.7c
VLOG       ?= $(QUESTA_DIR)/win64/vlog.exe
VSIM       ?= $(QUESTA_DIR)/win64/vsim.exe
VLIB       ?= $(QUESTA_DIR)/win64/vlib.exe
UVM_HOME   ?= $(QUESTA_DIR)/verilog_src/uvm-1.2
UVM_DPI    ?= $(QUESTA_DIR)/uvm-1.2/win64/uvm_dpi

YOSYS      ?= yosys
JASPERGOLD ?= jg
SBY        ?= sby

# RTL and TB File Lists
RTL_SRCS = \
	rtl/axi5_pkg.sv \
	rtl/sram_bank_16k.sv \
	rtl/axi5_bank_arbiter.sv \
	rtl/axi5_cam_tracker.sv \
	rtl/axi5_rob.sv \
	rtl/axi5_sram_controller.sv

SVA_SRCS = \
	tb/formal/axi5_sva.sv \
	tb/formal/axi5_formal_bind.sv

UVM_SRCS = \
	tb/uvm/axi5_if.sv \
	tb/uvm/axi5_uvm_pkg.sv \
	tb/uvm/tb_top.sv

STANDALONE_SRCS = \
	tb/formal/axi5_sva.sv \
	tb/sim/tb_standalone.sv

# Default Target
all: sim_standalone

# ------------------------------------------------------------------------------
# 1. Standalone Simulation (Zero UVM overhead, visual telemetry, VCD dump)
# ------------------------------------------------------------------------------
sim_standalone: clean_work
	@echo ">>> Compiling Standalone Simulation with QuestaSim..."
	$(VLIB) work
	$(VLOG) -sv $(RTL_SRCS) $(STANDALONE_SRCS)
	@echo ">>> Running Standalone Verification..."
	$(VSIM) -c -nodpiexports -do "run -all; quit -f" tb_standalone

# ------------------------------------------------------------------------------
# 2. Layered UVM 1.2 Suite Simulation
# ------------------------------------------------------------------------------
sim_uvm: clean_work
	@echo ">>> Compiling UVM 1.2 Verification Suite with QuestaSim..."
	$(VLIB) work
	$(VLOG) -sv "+incdir+$(UVM_HOME)/src" "+incdir+tb/uvm" "+incdir+rtl" \
		$(UVM_HOME)/src/uvm_pkg.sv $(RTL_SRCS) $(UVM_SRCS)
	@echo ">>> Executing UVM 1.2 Comprehensive Stress Test..."
	$(VSIM) -c -nodpiexports -sv_lib $(UVM_DPI) -do "run -all; quit -f" \
		tb_top +UVM_TESTNAME=axi5_stress_test

sim_uvm_base: clean_work
	@echo ">>> Compiling UVM 1.2 Verification Suite with QuestaSim..."
	$(VLIB) work
	$(VLOG) -sv "+incdir+$(UVM_HOME)/src" "+incdir+tb/uvm" "+incdir+rtl" \
		$(UVM_HOME)/src/uvm_pkg.sv $(RTL_SRCS) $(UVM_SRCS)
	@echo ">>> Executing UVM 1.2 Base Sanity Test..."
	$(VSIM) -c -nodpiexports -sv_lib $(UVM_DPI) -do "run -all; quit -f" \
		tb_top +UVM_TESTNAME=axi5_base_test

# ------------------------------------------------------------------------------
# 3. Formal Verification
# ------------------------------------------------------------------------------
sim_formal:
	@echo ">>> Launching JasperGold Formal Property Verification..."
	$(JASPERGOLD) -no_gui tb/formal/run_jg.tcl

sim_formal_sby:
	@echo ">>> Launching SymbiYosys Formal Verification..."
	cd tb/formal && $(SBY) -f sby.sby

# ------------------------------------------------------------------------------
# 4. Logic Synthesis & Technology Mapping (SkyWater 130nm)
# ------------------------------------------------------------------------------
synth:
	@echo ">>> Running Yosys Synthesis targeting SkyWater 130nm standard cells..."
	$(YOSYS) -s syn/yosys_synth.tcl

# ------------------------------------------------------------------------------
# 5. Clean Workspace
# ------------------------------------------------------------------------------
clean_work:
	@if exist work rmdir /s /q work
	@if exist transcript del /f /q transcript
	@if exist vsim.wlf del /f /q vsim.wlf

clean: clean_work
	@if exist *.vcd del /f /q *.vcd
	@if exist *.log del /f /q *.log
	@if exist *.rpt del /f /q *.rpt
	@if exist syn\axi5_sram_controller_gate.v del /f /q syn\axi5_sram_controller_gate.v
	@echo "Clean completed."

.PHONY: all sim_standalone sim_uvm sim_uvm_base sim_formal sim_formal_sby synth clean clean_work
