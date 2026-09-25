# ==============================================================================
# File: syn/yosys_synth.tcl
# Description: Production Yosys Synthesis Script targeting SkyWater 130nm
#              standard cells (sky130_fd_sc_hd) @ 200 MHz.
# Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
# Usage: yosys -s syn/yosys_synth.tcl
# ==============================================================================

# 1. Read SystemVerilog RTL Codebase
read_verilog -sv rtl/axi5_pkg.sv
read_verilog -sv rtl/sram_bank_16k.sv
read_verilog -sv rtl/axi5_bank_arbiter.sv
read_verilog -sv rtl/axi5_cam_tracker.sv
read_verilog -sv rtl/axi5_rob.sv
read_verilog -sv rtl/axi5_sram_controller.sv

# 2. Elaborate Design Hierarchy
hierarchy -check -top axi5_sram_controller

# 3. High-Effort RTL Optimization
proc
opt
fsm
opt
memory -nomap
opt

# 4. Flip-Flop Mapping to SkyWater 130nm DFF Cells
dfflibmap -liberty syn/sky130_hd.lib

# 5. Combinational Logic Optimization & Technology Mapping via ABC
abc -liberty syn/sky130_hd.lib -constr syn/constraints.sdc

# 6. Post-Mapping Cleanup & Sanity Check
clean -purge
check

# 7. Print Cell Counts, Utilization, and Area Metrics
stat -liberty syn/sky130_hd.lib

# 8. Export Gate-Level Netlist
write_verilog -noattr syn/axi5_sram_controller_gate.v

puts "\n[SYNTHESIS COMPLETE] Gate-level netlist written to syn/axi5_sram_controller_gate.v\n"
