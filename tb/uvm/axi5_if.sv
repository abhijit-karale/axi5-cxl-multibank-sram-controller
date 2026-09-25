// ============================================================================
// File: tb/uvm/axi5_if.sv
// Description: SystemVerilog Interface for AXI5/CXL.mem Coherent Multi-Bank
//              SRAM Controller, including clocking blocks and modports for
//              UVM driver and monitor.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`timescale 1ns/1ps

import axi5_pkg::*;

interface axi5_if (input logic ACLK, input logic ARESETn);

  // AW Channel
  logic [AXI_ID_WIDTH-1:0]    AWID;
  logic [AXI_ADDR_WIDTH-1:0]  AWADDR;
  logic [AXI_LEN_WIDTH-1:0]   AWLEN;
  logic [AXI_SIZE_WIDTH-1:0]  AWSIZE;
  logic [AXI_BURST_WIDTH-1:0] AWBURST;
  logic                       AWLOCK;
  logic [3:0]                 AWCACHE;
  logic [2:0]                 AWPROT;
  logic [3:0]                 AWQOS;
  logic                       AWVALID;
  logic                       AWREADY;

  // W Channel
  logic [AXI_DATA_WIDTH-1:0]  WDATA;
  logic [AXI_STRB_WIDTH-1:0]  WSTRB;
  logic                       WLAST;
  logic                       WVALID;
  logic                       WREADY;

  // B Channel
  logic [AXI_ID_WIDTH-1:0]    BID;
  logic [AXI_RESP_WIDTH-1:0]  BRESP;
  logic                       BVALID;
  logic                       BREADY;

  // AR Channel
  logic [AXI_ID_WIDTH-1:0]    ARID;
  logic [AXI_ADDR_WIDTH-1:0]  ARADDR;
  logic [AXI_LEN_WIDTH-1:0]   ARLEN;
  logic [AXI_SIZE_WIDTH-1:0]  ARSIZE;
  logic [AXI_BURST_WIDTH-1:0] ARBURST;
  logic                       ARLOCK;
  logic [3:0]                 ARCACHE;
  logic [2:0]                 ARPROT;
  logic [3:0]                 ARQOS;
  logic                       ARVALID;
  logic                       ARREADY;

  // R Channel
  logic [AXI_ID_WIDTH-1:0]    RID;
  logic [AXI_DATA_WIDTH-1:0]  RDATA;
  logic [AXI_RESP_WIDTH-1:0]  RRESP;
  logic                       RLAST;
  logic                       RVALID;
  logic                       RREADY;

  // Telemetry Monitor Signals
  logic [31:0]                telemetry_bank_conflicts;
  logic [31:0]                telemetry_ooo_responses;
  logic [31:0]                telemetry_raw_stalls;
  logic [31:0]                telemetry_total_tx_completed;

  // Driver Clocking Block
  clocking cb_drv @(posedge ACLK);
    default input #1step output #100ps;
    output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWVALID;
    input  AWREADY;
    output WDATA, WSTRB, WLAST, WVALID;
    input  WREADY;
    input  BID, BRESP, BVALID;
    output BREADY;
    output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARVALID;
    input  ARREADY;
    input  RID, RDATA, RRESP, RLAST, RVALID;
    output RREADY;
  endclocking

  // Monitor Clocking Block
  clocking cb_mon @(posedge ACLK);
    default input #1step;
    input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWVALID, AWREADY;
    input WDATA, WSTRB, WLAST, WVALID, WREADY;
    input BID, BRESP, BVALID, BREADY;
    input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARVALID, ARREADY;
    input RID, RDATA, RRESP, RLAST, RVALID, RREADY;
    input telemetry_bank_conflicts, telemetry_ooo_responses, telemetry_raw_stalls, telemetry_total_tx_completed;
  endclocking

  modport driver (clocking cb_drv, input ACLK, input ARESETn);
  modport monitor (clocking cb_mon, input ACLK, input ARESETn);

endinterface : axi5_if
