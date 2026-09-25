# ==============================================================================
# File: syn/constraints.sdc
# Description: Synopsys Design Constraints (SDC) for AXI5/CXL.mem SRAM Controller.
# Target Tech: SkyWater 130nm High-Density (sky130_fd_sc_hd) @ 200 MHz
# Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Primary Clock Definition (200 MHz -> 5.0 ns Period)
# ------------------------------------------------------------------------------
create_clock -name ACLK -period 5.000 [get_ports ACLK]

# Clock Uncertainty & Jitter Budget (5% of cycle time for 130nm tech node)
set_clock_uncertainty 0.250 [get_clocks ACLK]

# Clock Transition / Slew
set_clock_transition 0.150 [get_clocks ACLK]

# ------------------------------------------------------------------------------
# 2. Reset Constraints
# ------------------------------------------------------------------------------
set_false_path -from [get_ports ARESETn]

# ------------------------------------------------------------------------------
# 3. Input Port Timing Constraints (20% of cycle time = 1.0 ns setup budget)
# ------------------------------------------------------------------------------
set_input_delay -clock ACLK -max 1.000 [get_ports {AW* W* AR* BREADY RREADY}]
set_input_delay -clock ACLK -min 0.200 [get_ports {AW* W* AR* BREADY RREADY}]

# Input Driving Cell (SkyWater 130nm typical inverter buffer drive)
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 [get_ports {AW* W* AR* BREADY RREADY}]

# ------------------------------------------------------------------------------
# 4. Output Port Timing Constraints (20% of cycle time = 1.0 ns delay budget)
# ------------------------------------------------------------------------------
set_output_delay -clock ACLK -max 1.000 [get_ports {AWREADY WREADY BVALID BID BRESP ARREADY RVALID RID RDATA RRESP RLAST}]
set_output_delay -clock ACLK -min 0.150 [get_ports {AWREADY WREADY BVALID BID BRESP ARREADY RVALID RID RDATA RRESP RLAST}]
set_output_delay -clock ACLK -max 1.500 [get_ports {telemetry_*}]

# Output Capacitive Load (35 fF typical interconnect and pin load)
set_load -pin_load 0.035 [all_outputs]

# ------------------------------------------------------------------------------
# 5. Design Rule Constraints (DRC)
# ------------------------------------------------------------------------------
set_max_fanout 16 [current_design]
set_max_transition 0.500 [current_design]

# Multicycle paths (if any) - Bank reads have deterministic 1-cycle pipeline
# Synchronous pipelined access preserves single-cycle path validity
