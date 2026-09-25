// ============================================================================
// File: rtl/axi5_bank_arbiter.sv
// Description: Dynamic Bank Arbiter with Fair Round-Robin Scheduling and
//              Write-Priority Override capability for multi-bank memory.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`timescale 1ns/1ps

import axi5_pkg::*;

module axi5_bank_arbiter #(
  parameter int unsigned NUM_REQS = ROB_DEPTH, // 8 competing CAM entries
  parameter int unsigned REQ_PTR_W = ROB_IDX_WIDTH // 3 bits
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // Arbitration Inputs from CAM
  input  logic [NUM_REQS-1:0]     req,                 // Active requests targeting this bank
  input  logic [NUM_REQS-1:0]     is_write,            // 1 = Write req, 0 = Read req
  input  logic                    write_prio_override, // Dynamic priority override for writes
  input  logic                    bank_ready,          // Bank is free to accept new transaction

  // Arbitration Outputs
  output logic                    grant_valid,         // Grant is valid
  output logic [NUM_REQS-1:0]     grant_onehot,        // One-hot grant vector
  output logic [REQ_PTR_W-1:0]    grant_idx,           // Binary granted CAM entry ID (0..7)
  output logic                    conflict_detected    // Telemetry: >1 simultaneous requests
);

  // Round-robin tracking pointer
  logic [REQ_PTR_W-1:0] rr_ptr;

  // Filtered requests based on write priority override
  logic [NUM_REQS-1:0] effective_req;
  logic [NUM_REQS-1:0] write_reqs;
  logic                has_write_req;

  assign write_reqs     = req & is_write;
  assign has_write_req  = |write_reqs;

  // Select effective request pool:
  // If write_prio_override is active and there are pending writes, service writes only;
  // otherwise, service all pending requests.
  always_comb begin
    if (write_prio_override && has_write_req) begin
      effective_req = write_reqs;
    end else begin
      effective_req = req;
    end
  end

  // Conflict detection telemetry: asserted when multiple entries compete for this bank
  always_comb begin
    int unsigned active_count;
    active_count = 0;
    for (int unsigned i = 0; i < NUM_REQS; i++) begin
      if (req[i]) active_count++;
    end
    conflict_detected = (active_count > 1);
  end

  // --------------------------------------------------------------------------
  // Round-Robin Arbitration Logic (Double-width Priority Arbiter)
  // --------------------------------------------------------------------------
  logic [NUM_REQS-1:0] mask_req;
  logic [NUM_REQS-1:0] grant_masked;
  logic [NUM_REQS-1:0] grant_unmasked;
  logic                has_masked_grant;

  // Mask off requests below the current round-robin pointer
  always_comb begin
    for (int unsigned i = 0; i < NUM_REQS; i++) begin
      mask_req[i] = effective_req[i] && (i >= rr_ptr);
    end
  end

  // Priority encoder on masked requests
  always_comb begin
    grant_masked = '0;
    for (int unsigned i = 0; i < NUM_REQS; i++) begin
      if (mask_req[i]) begin
        grant_masked[i] = 1'b1;
        break;
      end
    end
  end

  // Priority encoder on unmasked requests (wrap-around)
  always_comb begin
    grant_unmasked = '0;
    for (int unsigned i = 0; i < NUM_REQS; i++) begin
      if (effective_req[i]) begin
        grant_unmasked[i] = 1'b1;
        break;
      end
    end
  end

  assign has_masked_grant = |grant_masked;

  // Select grant vector: prefer masked (at or after pointer); wrap-around if none
  always_comb begin
    if (has_masked_grant) begin
      grant_onehot = grant_masked;
    end else begin
      grant_onehot = grant_unmasked;
    end
  end

  assign grant_valid = (|effective_req) && bank_ready;

  // Binary encoder for grant_idx
  always_comb begin
    grant_idx = '0;
    for (int unsigned i = 0; i < NUM_REQS; i++) begin
      if (grant_onehot[i]) begin
        grant_idx = i[REQ_PTR_W-1:0];
      end
    end
  end

  // Pointer update on successful grant
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_ptr <= '0;
    end else if (grant_valid) begin
      if (grant_idx == (NUM_REQS - 1)) begin
        rr_ptr <= '0;
      end else begin
        rr_ptr <= grant_idx + 1'b1;
      end
    end
  end

endmodule : axi5_bank_arbiter
