// ============================================================================
// File: rtl/axi5_rob.sv
// Description: Reorder Buffer (ROB) and Response Dispatcher for AXI5/CXL.mem.
//              Handles out-of-order read data returns with RID tracking, RLAST
//              generation, and write response (B channel) dispatch with
//              standard AMBA valid/ready handshakes.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`timescale 1ns/1ps

import axi5_pkg::*;

module axi5_rob #(
  parameter int unsigned NUM_ENTRIES = ROB_DEPTH,     // 8 entries
  parameter int unsigned IDX_WIDTH   = ROB_IDX_WIDTH  // 3 bits
)(
  input  logic                        clk,
  input  logic                        rst_n,

  // --------------------------------------------------------------------------
  // Status from CAM Tracker
  // --------------------------------------------------------------------------
  input  wire cam_entry_t             entries [NUM_ENTRIES],
  output logic [NUM_ENTRIES-1:0]      retire_ack,

  // --------------------------------------------------------------------------
  // AXI Read Data Channel (R)
  // --------------------------------------------------------------------------
  output logic [AXI_ID_WIDTH-1:0]    r_id,
  output logic [AXI_DATA_WIDTH-1:0]  r_data,
  output axi_resp_e                  r_resp,
  output logic                       r_last,
  output logic                       r_valid,
  input  logic                       r_ready,

  // --------------------------------------------------------------------------
  // AXI Write Response Channel (B)
  // --------------------------------------------------------------------------
  output logic [AXI_ID_WIDTH-1:0]    b_id,
  output axi_resp_e                  b_resp,
  output logic                       b_valid,
  input  logic                       b_ready,

  // --------------------------------------------------------------------------
  // ROB Performance Telemetry
  // --------------------------------------------------------------------------
  output logic                       ooo_return_event // Read completed out-of-order vs issue order
);

  // --------------------------------------------------------------------------
  // Read Response Arbitration & Selection
  // --------------------------------------------------------------------------
  logic [NUM_ENTRIES-1:0] r_ready_mask;
  logic [IDX_WIDTH-1:0]   r_sel_idx;
  logic                   r_has_candidate;
  logic [IDX_WIDTH-1:0]   r_rr_ptr;

  always_comb begin
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      r_ready_mask[i] = entries[i].valid && 
                        (entries[i].tx_type == TX_TYPE_READ) && 
                        (entries[i].state == CAM_STATE_RESP_READY);
    end
  end

  // Fair Round-Robin selection among completed read responses
  logic [NUM_ENTRIES-1:0] r_mask_req;
  logic [NUM_ENTRIES-1:0] r_grant_masked;
  logic [NUM_ENTRIES-1:0] r_grant_unmasked;

  always_comb begin
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      r_mask_req[i] = r_ready_mask[i] && (i >= r_rr_ptr);
    end
  end

  always_comb begin
    r_grant_masked = '0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      if (r_mask_req[i]) begin
        r_grant_masked[i] = 1'b1;
        break;
      end
    end
  end

  always_comb begin
    r_grant_unmasked = '0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      if (r_ready_mask[i]) begin
        r_grant_unmasked[i] = 1'b1;
        break;
      end
    end
  end

  always_comb begin
    if (|r_grant_masked) begin
      r_sel_idx       = '0;
      r_has_candidate = 1'b1;
      for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
        if (r_grant_masked[i]) r_sel_idx = i[IDX_WIDTH-1:0];
      end
    end else if (|r_grant_unmasked) begin
      r_sel_idx       = '0;
      r_has_candidate = 1'b1;
      for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
        if (r_grant_unmasked[i]) r_sel_idx = i[IDX_WIDTH-1:0];
      end
    end else begin
      r_sel_idx       = '0;
      r_has_candidate = 1'b0;
    end
  end

  // Drive R Channel
  assign r_valid = r_has_candidate;
  assign r_id    = entries[r_sel_idx].id;
  assign r_data  = entries[r_sel_idx].rdata;
  assign r_resp  = entries[r_sel_idx].resp;
  assign r_last  = r_has_candidate && (entries[r_sel_idx].beat_cnt == entries[r_sel_idx].len);

  // --------------------------------------------------------------------------
  // Write Response Arbitration & Selection
  // --------------------------------------------------------------------------
  logic [NUM_ENTRIES-1:0] b_ready_mask;
  logic [IDX_WIDTH-1:0]   b_sel_idx;
  logic                   b_has_candidate;
  logic [IDX_WIDTH-1:0]   b_rr_ptr;

  always_comb begin
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      b_ready_mask[i] = entries[i].valid && 
                        (entries[i].tx_type == TX_TYPE_WRITE) && 
                        (entries[i].state == CAM_STATE_RESP_READY);
    end
  end

  // Priority selection for write response
  always_comb begin
    b_sel_idx       = '0;
    b_has_candidate = 1'b0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      if (b_ready_mask[i]) begin
        b_sel_idx       = i[IDX_WIDTH-1:0];
        b_has_candidate = 1'b1;
        break;
      end
    end
  end

  // Drive B Channel
  assign b_valid = b_has_candidate;
  assign b_id    = entries[b_sel_idx].id;
  assign b_resp  = entries[b_sel_idx].resp;

  // --------------------------------------------------------------------------
  // Retirement Generation
  // --------------------------------------------------------------------------
  always_comb begin
    retire_ack = '0;
    if (r_valid && r_ready && r_last) begin
      retire_ack[r_sel_idx] = 1'b1;
    end
    if (b_valid && b_ready) begin
      retire_ack[b_sel_idx] = 1'b1;
    end
  end

  // --------------------------------------------------------------------------
  // Out-of-Order Completion Telemetry Detection
  // Triggers if a higher-index read entry finishes before a lower-index read entry
  // --------------------------------------------------------------------------
  always_comb begin
    ooo_return_event = 1'b0;
    if (r_valid && r_ready) begin
      for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
        if ((i < r_sel_idx) && entries[i].valid && (entries[i].tx_type == TX_TYPE_READ) &&
            (entries[i].state != CAM_STATE_RESP_READY) && (entries[i].state != CAM_STATE_FREE)) begin
          ooo_return_event = 1'b1;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // State Updates & Pointer Rotations
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_rr_ptr <= '0;
      b_rr_ptr <= '0;
    end else begin
      if (r_valid && r_ready) begin
        if (r_sel_idx == (NUM_ENTRIES - 1)) begin
          r_rr_ptr <= '0;
        end else begin
          r_rr_ptr <= r_sel_idx + 1'b1;
        end
      end

      if (b_valid && b_ready) begin
        if (b_sel_idx == (NUM_ENTRIES - 1)) begin
          b_rr_ptr <= '0;
        end else begin
          b_rr_ptr <= b_sel_idx + 1'b1;
        end
      end
    end
  end

endmodule : axi5_rob
