onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {GLOBAL CLOCK & RESET}
add wave -noupdate -color {Lime Green} /tb_standalone/ACLK
add wave -noupdate -color Cyan /tb_standalone/ARESETn

add wave -noupdate -divider {AXI5 WRITE ADDRESS (AW)}
add wave -noupdate -color Gold /tb_standalone/AWVALID
add wave -noupdate -color Yellow /tb_standalone/AWREADY
add wave -noupdate -radix hexadecimal /tb_standalone/AWID
add wave -noupdate -radix hexadecimal /tb_standalone/AWADDR
add wave -noupdate -radix unsigned /tb_standalone/AWLEN

add wave -noupdate -divider {AXI5 WRITE DATA (W)}
add wave -noupdate -color Gold /tb_standalone/WVALID
add wave -noupdate -color Yellow /tb_standalone/WREADY
add wave -noupdate -radix hexadecimal /tb_standalone/WDATA
add wave -noupdate -radix hexadecimal /tb_standalone/WSTRB
add wave -noupdate -color Orange /tb_standalone/WLAST

add wave -noupdate -divider {AXI5 WRITE RESPONSE (B)}
add wave -noupdate -color Cyan /tb_standalone/BVALID
add wave -noupdate -color Cyan /tb_standalone/BREADY
add wave -noupdate -radix hexadecimal /tb_standalone/BID
add wave -noupdate /tb_standalone/BRESP

add wave -noupdate -divider {AXI5 READ ADDRESS (AR)}
add wave -noupdate -color {Light Blue} /tb_standalone/ARVALID
add wave -noupdate -color {Light Blue} /tb_standalone/ARREADY
add wave -noupdate -radix hexadecimal /tb_standalone/ARID
add wave -noupdate -radix hexadecimal /tb_standalone/ARADDR
add wave -noupdate -radix unsigned /tb_standalone/ARLEN

add wave -noupdate -divider {AXI5 READ DATA (R) - OUT-OF-ORDER}
add wave -noupdate -color Magenta /tb_standalone/RVALID
add wave -noupdate -color Magenta /tb_standalone/RREADY
add wave -noupdate -color Yellow -radix hexadecimal /tb_standalone/RID
add wave -noupdate -radix hexadecimal /tb_standalone/RDATA
add wave -noupdate /tb_standalone/RRESP
add wave -noupdate -color Orange /tb_standalone/RLAST

add wave -noupdate -divider {MULTI-BANK ARBITRATION STATUS}
add wave -noupdate -radix binary /tb_standalone/dut/bank_req
add wave -noupdate -radix binary /tb_standalone/dut/bank_gnt_valid
add wave -noupdate -radix binary /tb_standalone/dut/bank_conflict_flags
add wave -noupdate -color Red /tb_standalone/dut/cam_write_prio_override

add wave -noupdate -divider {HARDWARE TELEMETRY MONITORS}
add wave -noupdate -radix unsigned /tb_standalone/telemetry_bank_conflicts
add wave -noupdate -radix unsigned /tb_standalone/telemetry_ooo_responses
add wave -noupdate -radix unsigned /tb_standalone/telemetry_raw_stalls
add wave -noupdate -radix unsigned /tb_standalone/telemetry_total_tx_completed

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {70000 ps} 0} {{Cursor 2} {120000 ps} 0}
configure wave -namecolwidth 220
configure wave -valuecolwidth 120
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
