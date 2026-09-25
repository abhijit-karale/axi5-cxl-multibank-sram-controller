// ============================================================================
// File: tb/uvm/tb_top.sv
// Description: Top-Level UVM Testbench for AXI5/CXL.mem SRAM Controller.
//              Generates 200 MHz clock, handles power-on reset, instantiates
//              physical DUT, connects virtual interfaces, and launches UVM tests.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz (5.0 ns clock period)
// ============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi5_pkg::*;
import axi5_uvm_pkg::*;

module tb_top;

  // --------------------------------------------------------------------------
  // Clock & Reset Generation (200 MHz Clock -> 5.0 ns Period)
  // --------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #2.5ns clk = ~clk; // 200 MHz
  end

  initial begin
    rst_n = 1'b0;
    #20ns;
    @(posedge clk);
    rst_n = 1'b1;
  end

  // --------------------------------------------------------------------------
  // Interface Instantiation
  // --------------------------------------------------------------------------
  axi5_if axi_bus (.ACLK(clk), .ARESETn(rst_n));

  // --------------------------------------------------------------------------
  // Design Under Test (DUT) Instantiation
  // --------------------------------------------------------------------------
  axi5_sram_controller #(
    .AXI_ADDR_W(AXI_ADDR_WIDTH),
    .AXI_DATA_W(AXI_DATA_WIDTH),
    .AXI_STRB_W(AXI_STRB_WIDTH),
    .AXI_ID_W  (AXI_ID_WIDTH),
    .NUM_BNKS  (NUM_BANKS),
    .BNK_DEPTH (BANK_WORDS),
    .BNK_ADDR_W(BANK_ADDR_WIDTH)
  ) u_dut (
    .ACLK                         (clk),
    .ARESETn                      (rst_n),

    // AW Channel
    .AWID                         (axi_bus.AWID),
    .AWADDR                       (axi_bus.AWADDR),
    .AWLEN                        (axi_bus.AWLEN),
    .AWSIZE                       (axi_bus.AWSIZE),
    .AWBURST                      (axi_bus.AWBURST),
    .AWLOCK                       (axi_bus.AWLOCK),
    .AWCACHE                      (axi_bus.AWCACHE),
    .AWPROT                       (axi_bus.AWPROT),
    .AWQOS                        (axi_bus.AWQOS),
    .AWVALID                      (axi_bus.AWVALID),
    .AWREADY                      (axi_bus.AWREADY),

    // W Channel
    .WDATA                        (axi_bus.WDATA),
    .WSTRB                        (axi_bus.WSTRB),
    .WLAST                        (axi_bus.WLAST),
    .WVALID                       (axi_bus.WVALID),
    .WREADY                       (axi_bus.WREADY),

    // B Channel
    .BID                          (axi_bus.BID),
    .BRESP                        (axi_bus.BRESP),
    .BVALID                       (axi_bus.BVALID),
    .BREADY                       (axi_bus.BREADY),

    // AR Channel
    .ARID                         (axi_bus.ARID),
    .ARADDR                       (axi_bus.ARADDR),
    .ARLEN                        (axi_bus.ARLEN),
    .ARSIZE                       (axi_bus.ARSIZE),
    .ARBURST                      (axi_bus.ARBURST),
    .ARLOCK                       (axi_bus.ARLOCK),
    .ARCACHE                      (axi_bus.ARCACHE),
    .ARPROT                       (axi_bus.ARPROT),
    .ARQOS                        (axi_bus.ARQOS),
    .ARVALID                      (axi_bus.ARVALID),
    .ARREADY                      (axi_bus.ARREADY),

    // R Channel
    .RID                          (axi_bus.RID),
    .RDATA                        (axi_bus.RDATA),
    .RRESP                        (axi_bus.RRESP),
    .RLAST                        (axi_bus.RLAST),
    .RVALID                       (axi_bus.RVALID),
    .RREADY                       (axi_bus.RREADY),

    // Telemetry Outputs
    .telemetry_bank_conflicts     (axi_bus.telemetry_bank_conflicts),
    .telemetry_ooo_responses      (axi_bus.telemetry_ooo_responses),
    .telemetry_raw_stalls         (axi_bus.telemetry_raw_stalls),
    .telemetry_total_tx_completed (axi_bus.telemetry_total_tx_completed)
  );

  // --------------------------------------------------------------------------
  // UVM Environment Configuration & Test Launch
  // --------------------------------------------------------------------------
  initial begin
    // Set virtual interface in config database
    uvm_config_db#(virtual axi5_if)::set(null, "*", "vif", axi_bus);

    // Waveform Generation
    if ($test$plusargs("DUMP_VCD")) begin
      $dumpfile("axi5_controller.vcd");
      $dumpvars(0, tb_top);
    end

    // Launch Test
    run_test();
  end

  // Simulation timeout watchdog
  initial begin
    #1000us;
    $display("[FATAL WATCHDOG] Simulation timeout reached!");
    $finish(2);
  end

endmodule : tb_top
