// ============================================================================
// File: rtl/axi5_sram_controller.sv
// Description: Top-Level Production-Grade AXI5 / CXL.mem Coherent Multi-Bank
//              SRAM Controller. Integrates 8-entry CAM hazard tracker,
//              4 independent 16KB SRAM banks (64-bit), dynamic Round-Robin
//              bank arbiters with write-priority overrides, and out-of-order
//              Reorder Buffer (ROB) response dispatcher.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz (5.0 ns clock, zero hold violations)
// ============================================================================

`timescale 1ns/1ps

import axi5_pkg::*;

module axi5_sram_controller #(
  parameter int unsigned AXI_ADDR_W = AXI_ADDR_WIDTH, // 32 bits
  parameter int unsigned AXI_DATA_W = AXI_DATA_WIDTH, // 64 bits
  parameter int unsigned AXI_STRB_W = AXI_STRB_WIDTH, // 8 bits
  parameter int unsigned AXI_ID_W   = AXI_ID_WIDTH,   // 4 bits
  parameter int unsigned NUM_BNKS   = NUM_BANKS,      // 4 banks
  parameter int unsigned BNK_DEPTH  = BANK_WORDS,     // 2048 words/bank
  parameter int unsigned BNK_ADDR_W = BANK_ADDR_WIDTH // 11 bits
)(
  // --------------------------------------------------------------------------
  // Global Clock and Active-Low Reset
  // --------------------------------------------------------------------------
  input  logic                      ACLK,
  input  logic                      ARESETn,

  // --------------------------------------------------------------------------
  // AXI5 Write Address Channel (AW)
  // --------------------------------------------------------------------------
  input  logic [AXI_ID_W-1:0]       AWID,
  input  logic [AXI_ADDR_W-1:0]     AWADDR,
  input  logic [AXI_LEN_WIDTH-1:0]  AWLEN,
  input  logic [AXI_SIZE_WIDTH-1:0] AWSIZE,
  input  logic [AXI_BURST_WIDTH-1:0]AWBURST,
  input  logic                      AWLOCK,
  input  logic [3:0]                AWCACHE,
  input  logic [2:0]                AWPROT,
  input  logic [3:0]                AWQOS,
  input  logic                      AWVALID,
  output logic                      AWREADY,

  // --------------------------------------------------------------------------
  // AXI5 Write Data Channel (W)
  // --------------------------------------------------------------------------
  input  logic [AXI_DATA_W-1:0]     WDATA,
  input  logic [AXI_STRB_W-1:0]     WSTRB,
  input  logic                      WLAST,
  input  logic                      WVALID,
  output logic                      WREADY,

  // --------------------------------------------------------------------------
  // AXI5 Write Response Channel (B)
  // --------------------------------------------------------------------------
  output logic [AXI_ID_W-1:0]       BID,
  output logic [AXI_RESP_WIDTH-1:0] BRESP,
  output logic                      BVALID,
  input  logic                      BREADY,

  // --------------------------------------------------------------------------
  // AXI5 Read Address Channel (AR)
  // --------------------------------------------------------------------------
  input  logic [AXI_ID_W-1:0]       ARID,
  input  logic [AXI_ADDR_W-1:0]     ARADDR,
  input  logic [AXI_LEN_WIDTH-1:0]  ARLEN,
  input  logic [AXI_SIZE_WIDTH-1:0] ARSIZE,
  input  logic [AXI_BURST_WIDTH-1:0]ARBURST,
  input  logic                      ARLOCK,
  input  logic [3:0]                ARCACHE,
  input  logic [2:0]                ARPROT,
  input  logic [3:0]                ARQOS,
  input  logic                      ARVALID,
  output logic                      ARREADY,

  // --------------------------------------------------------------------------
  // AXI5 Read Data Channel (R) - Supports Out-of-Order Delivery
  // --------------------------------------------------------------------------
  output logic [AXI_ID_W-1:0]       RID,
  output logic [AXI_DATA_W-1:0]     RDATA,
  output logic [AXI_RESP_WIDTH-1:0] RRESP,
  output logic                      RLAST,
  output logic                      RVALID,
  input  logic                      RREADY,

  // --------------------------------------------------------------------------
  // Telemetry & Hardware Performance Monitors (HPM)
  // --------------------------------------------------------------------------
  output logic [31:0]               telemetry_bank_conflicts,
  output logic [31:0]               telemetry_ooo_responses,
  output logic [31:0]               telemetry_raw_stalls,
  output logic [31:0]               telemetry_total_tx_completed
);

  // --------------------------------------------------------------------------
  // Internal Interconnect Signals
  // --------------------------------------------------------------------------
  logic                      alloc_req;
  tx_type_e                  alloc_tx_type;
  logic [AXI_ID_W-1:0]       alloc_id;
  logic [AXI_ADDR_W-1:0]     alloc_addr;
  logic [AXI_LEN_WIDTH-1:0]  alloc_len;
  logic [AXI_SIZE_WIDTH-1:0] alloc_size;
  axi_burst_e                alloc_burst;
  logic                      alloc_gnt;
  logic [ROB_IDX_WIDTH-1:0]  alloc_idx;
  logic                      cam_full;

  // Front-end Address Arbiter (AW vs AR priority)
  logic                      addr_arb_prio_aw; // Toggles or follows write override
  logic                      aw_selected;
  logic                      ar_selected;

  // CAM to Bank Arbiters
  logic [ROB_DEPTH-1:0]      bank_req      [NUM_BNKS];
  logic [ROB_DEPTH-1:0]      bank_is_write [NUM_BNKS];
  logic                      bank_gnt_valid[NUM_BNKS];
  logic [ROB_DEPTH-1:0]      bank_gnt_onehot[NUM_BNKS];
  logic [ROB_IDX_WIDTH-1:0]  bank_gnt_idx  [NUM_BNKS];
  logic [NUM_BNKS-1:0]       bank_conflict_flags;

  // CAM to Physical SRAM Macros
  logic                      sram_cs   [NUM_BNKS];
  logic                      sram_we   [NUM_BNKS];
  logic [BNK_ADDR_W-1:0]     sram_addr [NUM_BNKS];
  logic [AXI_DATA_W-1:0]     sram_wdata[NUM_BNKS];
  logic [AXI_STRB_W-1:0]     sram_wstrb[NUM_BNKS];
  logic [AXI_DATA_W-1:0]     sram_rdata[NUM_BNKS];

  // CAM & ROB Handshake
  cam_entry_t                cam_entries [ROB_DEPTH];
  logic [ROB_DEPTH-1:0]      retire_ack;

  // Status & Telemetry Events
  logic [3:0]                pending_writes;
  logic [3:0]                pending_reads;
  logic                      cam_write_prio_override;
  logic                      raw_hazard_stall_event;
  logic                      ooo_return_event;

  axi_resp_e                 internal_bresp;
  axi_resp_e                 internal_rresp;

  assign BRESP = internal_bresp;
  assign RRESP = internal_rresp;

  // --------------------------------------------------------------------------
  // Front-end Address Allocation Arbiter (AW vs AR)
  // Handles concurrent AW and AR arrival without deadlocks
  // --------------------------------------------------------------------------
  always_comb begin
    aw_selected = 1'b0;
    ar_selected = 1'b0;
    alloc_req   = 1'b0;
    alloc_tx_type = TX_TYPE_READ;
    alloc_id      = '0;
    alloc_addr    = '0;
    alloc_len     = '0;
    alloc_size    = '0;
    alloc_burst   = AXI_BURST_INCR;

    if (AWVALID && ARVALID) begin
      // Both channels requesting: arbitrate using priority pointer / override
      if (cam_write_prio_override || addr_arb_prio_aw) begin
        aw_selected   = 1'b1;
        alloc_req     = 1'b1;
        alloc_tx_type = TX_TYPE_WRITE;
        alloc_id      = AWID;
        alloc_addr    = AWADDR;
        alloc_len     = AWLEN;
        alloc_size    = AWSIZE;
        alloc_burst   = axi_burst_e'(AWBURST);
      end else begin
        ar_selected   = 1'b1;
        alloc_req     = 1'b1;
        alloc_tx_type = TX_TYPE_READ;
        alloc_id      = ARID;
        alloc_addr    = ARADDR;
        alloc_len     = ARLEN;
        alloc_size    = ARSIZE;
        alloc_burst   = axi_burst_e'(ARBURST);
      end
    end else if (AWVALID) begin
      aw_selected   = 1'b1;
      alloc_req     = 1'b1;
      alloc_tx_type = TX_TYPE_WRITE;
      alloc_id      = AWID;
      alloc_addr    = AWADDR;
      alloc_len     = AWLEN;
      alloc_size    = AWSIZE;
      alloc_burst   = axi_burst_e'(AWBURST);
    end else if (ARVALID) begin
      ar_selected   = 1'b1;
      alloc_req     = 1'b1;
      alloc_tx_type = TX_TYPE_READ;
      alloc_id      = ARID;
      alloc_addr    = ARADDR;
      alloc_len     = ARLEN;
      alloc_size    = ARSIZE;
      alloc_burst   = axi_burst_e'(ARBURST);
    end
  end

  assign AWREADY = aw_selected && alloc_gnt;
  assign ARREADY = ar_selected && alloc_gnt;

  // Toggle priority between AW and AR on grant to maintain fair bandwidth
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      addr_arb_prio_aw <= 1'b1;
    end else if (alloc_gnt) begin
      addr_arb_prio_aw <= ~addr_arb_prio_aw;
    end
  end

  // --------------------------------------------------------------------------
  // CAM Tracker Core Instance
  // --------------------------------------------------------------------------
  axi5_cam_tracker #(
    .NUM_ENTRIES(ROB_DEPTH),
    .IDX_WIDTH(ROB_IDX_WIDTH),
    .NUM_BNKS(NUM_BNKS),
    .BNK_ADDR_W(BNK_ADDR_W),
    .BNK_SEL_W(BANK_SEL_WIDTH)
  ) u_cam_tracker (
    .clk                    (ACLK),
    .rst_n                  (ARESETn),

    // Allocation
    .alloc_req              (alloc_req),
    .alloc_tx_type          (alloc_tx_type),
    .alloc_id               (alloc_id),
    .alloc_addr             (alloc_addr),
    .alloc_len              (alloc_len),
    .alloc_size             (alloc_size),
    .alloc_burst            (alloc_burst),
    .alloc_gnt              (alloc_gnt),
    .alloc_idx              (alloc_idx),
    .cam_full               (cam_full),

    // Write Data Channel
    .wdata_valid            (WVALID),
    .wdata_payload          (WDATA),
    .wstrb_payload          (WSTRB),
    .wlast_payload          (WLAST),
    .wdata_ready            (WREADY),

    // Bank Arbiters Handshake
    .bank_req               (bank_req),
    .bank_is_write          (bank_is_write),
    .bank_gnt_valid         (bank_gnt_valid),
    .bank_gnt_idx           (bank_gnt_idx),

    // Physical SRAM ports
    .sram_cs                (sram_cs),
    .sram_we                (sram_we),
    .sram_addr              (sram_addr),
    .sram_wdata             (sram_wdata),
    .sram_wstrb             (sram_wstrb),
    .sram_rdata             (sram_rdata),

    // ROB Handshake
    .entries                (cam_entries),
    .retire_ack             (retire_ack),

    // Telemetry
    .pending_writes         (pending_writes),
    .pending_reads          (pending_reads),
    .write_prio_override    (cam_write_prio_override),
    .raw_hazard_stall_event (raw_hazard_stall_event)
  );

  // --------------------------------------------------------------------------
  // Bank Arbiters (4 Independent Instances with Round-Robin & Write Override)
  // --------------------------------------------------------------------------
  genvar b;
  generate
    for (b = 0; b < NUM_BNKS; b++) begin : gen_bank_arbiters
      axi5_bank_arbiter #(
        .NUM_REQS(ROB_DEPTH),
        .REQ_PTR_W(ROB_IDX_WIDTH)
      ) u_bank_arbiter (
        .clk                    (ACLK),
        .rst_n                  (ARESETn),
        .req                    (bank_req[b]),
        .is_write               (bank_is_write[b]),
        .write_prio_override    (cam_write_prio_override),
        .bank_ready             (1'b1), // Single-cycle pipelined SRAM
        .grant_valid            (bank_gnt_valid[b]),
        .grant_onehot           (bank_gnt_onehot[b]),
        .grant_idx              (bank_gnt_idx[b]),
        .conflict_detected      (bank_conflict_flags[b])
      );
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Physical 16KB SRAM Bank Macros (SkyWater 130nm compatible)
  // --------------------------------------------------------------------------
  generate
    for (b = 0; b < NUM_BNKS; b++) begin : gen_sram_banks
      sram_bank_16k #(
        .ADDR_WIDTH(BNK_ADDR_W),
        .DATA_WIDTH(AXI_DATA_W),
        .STRB_WIDTH(AXI_STRB_W)
      ) u_sram_bank (
        .clk                    (ACLK),
        .rst_n                  (ARESETn),
        .cs                     (sram_cs[b]),
        .we                     (sram_we[b]),
        .addr                   (sram_addr[b]),
        .wdata                  (sram_wdata[b]),
        .wstrb                  (sram_wstrb[b]),
        .rdata                  (sram_rdata[b])
      );
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Out-of-Order Reorder Buffer (ROB) & Response Engine
  // --------------------------------------------------------------------------
  axi5_rob #(
    .NUM_ENTRIES(ROB_DEPTH),
    .IDX_WIDTH(ROB_IDX_WIDTH)
  ) u_rob (
    .clk                    (ACLK),
    .rst_n                  (ARESETn),
    .entries                (cam_entries),
    .retire_ack             (retire_ack),

    // R Channel
    .r_id                   (RID),
    .r_data                 (RDATA),
    .r_resp                 (internal_rresp),
    .r_last                 (RLAST),
    .r_valid                (RVALID),
    .r_ready                (RREADY),

    // B Channel
    .b_id                   (BID),
    .b_resp                 (internal_bresp),
    .b_valid                (BVALID),
    .b_ready                (BREADY),

    // Telemetry
    .ooo_return_event       (ooo_return_event)
  );

  // --------------------------------------------------------------------------
  // Telemetry & Hardware Performance Monitors (Counters)
  // --------------------------------------------------------------------------
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      telemetry_bank_conflicts     <= '0;
      telemetry_ooo_responses      <= '0;
      telemetry_raw_stalls         <= '0;
      telemetry_total_tx_completed <= '0;
    end else begin
      if (|bank_conflict_flags) begin
        telemetry_bank_conflicts <= telemetry_bank_conflicts + 1'b1;
      end
      if (ooo_return_event) begin
        telemetry_ooo_responses <= telemetry_ooo_responses + 1'b1;
      end
      if (raw_hazard_stall_event) begin
        telemetry_raw_stalls <= telemetry_raw_stalls + 1'b1;
      end
      if ((RVALID && RREADY && RLAST) || (BVALID && BREADY)) begin
        telemetry_total_tx_completed <= telemetry_total_tx_completed + 1'b1;
      end
    end
  end

endmodule : axi5_sram_controller
