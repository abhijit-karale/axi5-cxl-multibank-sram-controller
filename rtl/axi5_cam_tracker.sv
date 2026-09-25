// ============================================================================
// File: rtl/axi5_cam_tracker.sv
// Description: CAM-based Hazard & Transaction Tracker for up to 8 concurrent
//              outstanding transactions. Features parallel address matching,
//              RAW/WAW/WAR hazard detection, dynamic bank request generation,
//              and pipeline tracking across 4 SRAM banks.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`timescale 1ns/1ps

import axi5_pkg::*;

module axi5_cam_tracker #(
  parameter int unsigned NUM_ENTRIES = ROB_DEPTH,      // 8 CAM entries
  parameter int unsigned IDX_WIDTH   = ROB_IDX_WIDTH,  // 3 bits
  parameter int unsigned NUM_BNKS    = NUM_BANKS,      // 4 banks
  parameter int unsigned BNK_ADDR_W  = BANK_ADDR_WIDTH,// 11 bits
  parameter int unsigned BNK_SEL_W   = BANK_SEL_WIDTH  // 2 bits
)(
  input  logic                                  clk,
  input  logic                                  rst_n,

  // --------------------------------------------------------------------------
  // Allocation Port (from AXI AW / AR Frontend)
  // --------------------------------------------------------------------------
  input  logic                                  alloc_req,
  input  tx_type_e                              alloc_tx_type,
  input  logic [AXI_ID_WIDTH-1:0]               alloc_id,
  input  logic [AXI_ADDR_WIDTH-1:0]             alloc_addr,
  input  logic [AXI_LEN_WIDTH-1:0]              alloc_len,
  input  logic [AXI_SIZE_WIDTH-1:0]             alloc_size,
  axi_burst_e                                   alloc_burst,
  output logic                                  alloc_gnt,
  output logic [IDX_WIDTH-1:0]                  alloc_idx,
  output logic                                  cam_full,

  // --------------------------------------------------------------------------
  // Write Data Channel (from AXI W Channel)
  // --------------------------------------------------------------------------
  input  logic                                  wdata_valid,
  input  logic [AXI_DATA_WIDTH-1:0]             wdata_payload,
  input  logic [AXI_STRB_WIDTH-1:0]             wstrb_payload,
  input  logic                                  wlast_payload,
  output logic                                  wdata_ready,

  // --------------------------------------------------------------------------
  // Bank Arbitration Requests & Status (to 4x Bank Arbiters)
  // --------------------------------------------------------------------------
  output logic [NUM_ENTRIES-1:0]                bank_req     [NUM_BNKS],
  output logic [NUM_ENTRIES-1:0]                bank_is_write[NUM_BNKS],
  input  wire logic                             bank_gnt_valid[NUM_BNKS],
  input  wire logic [IDX_WIDTH-1:0]             bank_gnt_idx  [NUM_BNKS],

  // --------------------------------------------------------------------------
  // SRAM Bank Physical Control Ports (to 4x SRAM instances)
  // --------------------------------------------------------------------------
  output logic                                  sram_cs   [NUM_BNKS],
  output logic                                  sram_we   [NUM_BNKS],
  output logic [BNK_ADDR_W-1:0]                 sram_addr [NUM_BNKS],
  output logic [AXI_DATA_WIDTH-1:0]             sram_wdata[NUM_BNKS],
  output logic [AXI_STRB_WIDTH-1:0]             sram_wstrb[NUM_BNKS],
  input  wire logic [AXI_DATA_WIDTH-1:0]        sram_rdata[NUM_BNKS],

  // --------------------------------------------------------------------------
  // Response & Retirement Ports (to/from ROB Engine)
  // --------------------------------------------------------------------------
  output cam_entry_t                            entries [NUM_ENTRIES],
  input  logic [NUM_ENTRIES-1:0]                retire_ack,

  // --------------------------------------------------------------------------
  // Telemetry & Control Overrides
  // --------------------------------------------------------------------------
  output logic [3:0]                            pending_writes,
  output logic [3:0]                            pending_reads,
  output logic                                  write_prio_override,
  output logic                                  raw_hazard_stall_event
);

  // --------------------------------------------------------------------------
  // Internal CAM Storage
  // --------------------------------------------------------------------------
  cam_entry_t cam_table [NUM_ENTRIES];
  assign entries = cam_table;

  // Pipeline tracking: register which entry is active on each bank
  logic [NUM_BNKS-1:0]               bank_pipe_valid;
  logic [IDX_WIDTH-1:0]              bank_pipe_idx [NUM_BNKS];
  logic [NUM_BNKS-1:0]               bank_pipe_is_write;

  // --------------------------------------------------------------------------
  // Free Entry Finding (Priority Encoder for Allocation)
  // --------------------------------------------------------------------------
  logic [NUM_ENTRIES-1:0] free_entries;
  logic [IDX_WIDTH-1:0]   first_free_idx;
  logic                   has_free_entry;

  always_comb begin
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      free_entries[i] = !cam_table[i].valid || (cam_table[i].state == CAM_STATE_FREE);
    end
  end

  always_comb begin
    first_free_idx = '0;
    has_free_entry = 1'b0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      if (free_entries[i]) begin
        first_free_idx = i[IDX_WIDTH-1:0];
        has_free_entry = 1'b1;
        break;
      end
    end
  end

  assign cam_full   = !has_free_entry;
  assign alloc_gnt  = alloc_req && has_free_entry;
  assign alloc_idx  = first_free_idx;

  // --------------------------------------------------------------------------
  // Write Data Association Logic
  // Matches incoming WDATA to the oldest allocated write entry waiting for data
  // --------------------------------------------------------------------------
  logic [NUM_ENTRIES-1:0] wdata_wait_mask;
  logic [IDX_WIDTH-1:0]   wdata_target_idx;
  logic                   has_wdata_target;

  always_comb begin
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      wdata_wait_mask[i] = cam_table[i].valid && 
                           (cam_table[i].tx_type == TX_TYPE_WRITE) && 
                           !cam_table[i].has_wdata &&
                           (cam_table[i].state == CAM_STATE_ALLOCATED);
    end
  end

  always_comb begin
    wdata_target_idx = '0;
    has_wdata_target = 1'b0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      if (wdata_wait_mask[i]) begin
        wdata_target_idx = i[IDX_WIDTH-1:0];
        has_wdata_target = 1'b1;
        break;
      end
    end
  end

  assign wdata_ready = has_wdata_target;

  // --------------------------------------------------------------------------
  // CAM Parallel Hazard Detection Logic
  // Detects RAW (Read-After-Write), WAW, and WAR hazards
  // --------------------------------------------------------------------------
  logic [NUM_ENTRIES-1:0] raw_hazard_detected;
  
  always_comb begin
    raw_hazard_stall_event = 1'b0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      raw_hazard_detected[i] = 1'b0;
      if (cam_table[i].valid && (cam_table[i].state == CAM_STATE_PENDING_BNK)) begin
        for (int unsigned j = 0; j < NUM_ENTRIES; j++) begin
          if ((i != j) && cam_table[j].valid && (cam_table[j].state != CAM_STATE_FREE)) begin
            // Address match on 64-bit word boundary (same bank and same bank row address)
            if ((cam_table[i].bank_id == cam_table[j].bank_id) &&
                (cam_table[i].bank_addr == cam_table[j].bank_addr)) begin
              // RAW Hazard: Current is Read, previous is Write that hasn't completed SRAM write
              if ((cam_table[i].tx_type == TX_TYPE_READ) && 
                  (cam_table[j].tx_type == TX_TYPE_WRITE) &&
                  (cam_table[j].state != CAM_STATE_RESP_READY) &&
                  (cam_table[j].state != CAM_STATE_COMPLETE)) begin
                raw_hazard_detected[i] = 1'b1;
                raw_hazard_stall_event = 1'b1;
              end
              // WAW Hazard: Maintain write order for older write entries
              if ((cam_table[i].tx_type == TX_TYPE_WRITE) &&
                  (cam_table[j].tx_type == TX_TYPE_WRITE) &&
                  (j < i) && // Age priority
                  (cam_table[j].state != CAM_STATE_RESP_READY) &&
                  (cam_table[j].state != CAM_STATE_COMPLETE)) begin
                raw_hazard_detected[i] = 1'b1;
              end
            end
          end
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Bank Request Generation
  // Drives request to the appropriate bank arbiter if hazard-free
  // --------------------------------------------------------------------------
  always_comb begin
    for (int unsigned b = 0; b < NUM_BNKS; b++) begin
      for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
        bank_req[b][i]      = 1'b0;
        bank_is_write[b][i] = 1'b0;

        if (cam_table[i].valid && 
            (cam_table[i].state == CAM_STATE_PENDING_BNK) &&
            (cam_table[i].bank_id == b[BNK_SEL_W-1:0]) &&
            !raw_hazard_detected[i]) begin
          bank_req[b][i]      = 1'b1;
          bank_is_write[b][i] = (cam_table[i].tx_type == TX_TYPE_WRITE);
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // SRAM Physical Control Multiplexing (Drive granted entry to SRAM macro)
  // --------------------------------------------------------------------------
  always_comb begin
    for (int unsigned b = 0; b < NUM_BNKS; b++) begin
      sram_cs[b]    = 1'b0;
      sram_we[b]    = 1'b0;
      sram_addr[b]  = '0;
      sram_wdata[b] = '0;
      sram_wstrb[b] = '0;

      if (bank_gnt_valid[b]) begin
        logic [IDX_WIDTH-1:0] gidx;
        gidx = bank_gnt_idx[b];
        sram_cs[b]    = 1'b1;
        sram_we[b]    = (cam_table[gidx].tx_type == TX_TYPE_WRITE);
        sram_addr[b]  = cam_table[gidx].bank_addr;
        sram_wdata[b] = cam_table[gidx].wdata;
        sram_wstrb[b] = cam_table[gidx].wstrb;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Telemetry: Pending counts & Write Priority Override Trigger
  // --------------------------------------------------------------------------
  always_comb begin
    int unsigned wr_cnt;
    int unsigned rd_cnt;
    wr_cnt = 0;
    rd_cnt = 0;
    for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
      if (cam_table[i].valid && (cam_table[i].state != CAM_STATE_FREE) && 
          (cam_table[i].state != CAM_STATE_RESP_READY)) begin
        if (cam_table[i].tx_type == TX_TYPE_WRITE) wr_cnt++;
        else rd_cnt++;
      end
    end
    pending_writes      = wr_cnt[3:0];
    pending_reads       = rd_cnt[3:0];
    write_prio_override = (wr_cnt >= WRITE_PRIO_THRESH);
  end

  // --------------------------------------------------------------------------
  // Sequential State Machine & Pipeline Registers
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
        cam_table[i].valid       <= 1'b0;
        cam_table[i].state       <= CAM_STATE_FREE;
        cam_table[i].tx_type     <= TX_TYPE_READ;
        cam_table[i].id          <= '0;
        cam_table[i].orig_addr   <= '0;
        cam_table[i].bank_id     <= '0;
        cam_table[i].bank_addr   <= '0;
        cam_table[i].byte_offset <= '0;
        cam_table[i].len         <= '0;
        cam_table[i].beat_cnt    <= '0;
        cam_table[i].size        <= '0;
        cam_table[i].burst       <= AXI_BURST_INCR;
        cam_table[i].wdata       <= '0;
        cam_table[i].wstrb       <= '0;
        cam_table[i].rdata       <= '0;
        cam_table[i].resp        <= AXI_RESP_OKAY;
        cam_table[i].hazard_mask <= '0;
        cam_table[i].has_wdata   <= 1'b0;
      end

      for (int unsigned b = 0; b < NUM_BNKS; b++) begin
        bank_pipe_valid[b]    <= 1'b0;
        bank_pipe_idx[b]      <= '0;
        bank_pipe_is_write[b] <= 1'b0;
      end
    end else begin

      // ----------------------------------------------------------------------
      // Bank Pipeline Capture: 1-cycle latency from SRAM read
      // ----------------------------------------------------------------------
      for (int unsigned b = 0; b < NUM_BNKS; b++) begin
        bank_pipe_valid[b]    <= bank_gnt_valid[b];
        bank_pipe_idx[b]      <= bank_gnt_idx[b];
        bank_pipe_is_write[b] <= bank_gnt_valid[b] ? (cam_table[bank_gnt_idx[b]].tx_type == TX_TYPE_WRITE) : 1'b0;

        // When SRAM read data returns (Cycle T+1 after grant)
        if (bank_pipe_valid[b]) begin
          logic [IDX_WIDTH-1:0] p_idx;
          p_idx = bank_pipe_idx[b];
          if (cam_table[p_idx].valid && (cam_table[p_idx].state == CAM_STATE_BNK_ACTIVE)) begin
            if (!bank_pipe_is_write[b]) begin
              // Capture read data returned from SRAM
              cam_table[p_idx].rdata <= sram_rdata[b];
            end
            cam_table[p_idx].resp  <= AXI_RESP_OKAY;
            cam_table[p_idx].state <= CAM_STATE_RESP_READY;
          end
        end
      end

      // ----------------------------------------------------------------------
      // Step 1: Allocation of New Transactions
      // ----------------------------------------------------------------------
      if (alloc_gnt) begin
        cam_table[alloc_idx].valid       <= 1'b1;
        cam_table[alloc_idx].tx_type     <= alloc_tx_type;
        cam_table[alloc_idx].id          <= alloc_id;
        cam_table[alloc_idx].orig_addr   <= alloc_addr;
        cam_table[alloc_idx].bank_id     <= get_bank_id(alloc_addr);
        cam_table[alloc_idx].bank_addr   <= get_bank_addr(alloc_addr);
        cam_table[alloc_idx].byte_offset <= get_byte_offset(alloc_addr);
        cam_table[alloc_idx].len         <= alloc_len;
        cam_table[alloc_idx].beat_cnt    <= '0;
        cam_table[alloc_idx].size        <= alloc_size;
        cam_table[alloc_idx].burst       <= alloc_burst;
        cam_table[alloc_idx].resp        <= AXI_RESP_OKAY;
        cam_table[alloc_idx].hazard_mask <= '0;

        if (alloc_tx_type == TX_TYPE_WRITE) begin
          cam_table[alloc_idx].state     <= CAM_STATE_ALLOCATED;
          cam_table[alloc_idx].has_wdata <= 1'b0;
        end else begin
          cam_table[alloc_idx].state     <= CAM_STATE_PENDING_BNK;
          cam_table[alloc_idx].has_wdata <= 1'b1;
        end
      end

      // ----------------------------------------------------------------------
      // Step 2: WDATA Capture for Write Transactions
      // ----------------------------------------------------------------------
      if (wdata_valid && wdata_ready) begin
        cam_table[wdata_target_idx].wdata     <= wdata_payload;
        cam_table[wdata_target_idx].wstrb     <= wstrb_payload;
        cam_table[wdata_target_idx].has_wdata <= 1'b1;
        cam_table[wdata_target_idx].state     <= CAM_STATE_PENDING_BNK;
      end

      // ----------------------------------------------------------------------
      // Step 3: Bank Grant Handling (Transitions PENDING -> BNK_ACTIVE)
      // ----------------------------------------------------------------------
      for (int unsigned b = 0; b < NUM_BNKS; b++) begin
        if (bank_gnt_valid[b]) begin
          logic [IDX_WIDTH-1:0] g_idx;
          g_idx = bank_gnt_idx[b];
          if (cam_table[g_idx].state == CAM_STATE_PENDING_BNK) begin
            cam_table[g_idx].state <= CAM_STATE_BNK_ACTIVE;
          end
        end
      end

      // ----------------------------------------------------------------------
      // Step 4: Retirement upon Response Acknowledgment from ROB
      // ----------------------------------------------------------------------
      for (int unsigned i = 0; i < NUM_ENTRIES; i++) begin
        if (retire_ack[i]) begin
          cam_table[i].valid <= 1'b0;
          cam_table[i].state <= CAM_STATE_FREE;
        end
      end

    end
  end

endmodule : axi5_cam_tracker
