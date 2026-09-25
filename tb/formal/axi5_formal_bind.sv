// ============================================================================
// File: tb/formal/axi5_formal_bind.sv
// Description: Bind file instantiating axi5_sva into axi5_sram_controller.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`timescale 1ns/1ps

bind axi5_sram_controller axi5_sva #(
  .AXI_ADDR_W(AXI_ADDR_W),
  .AXI_DATA_W(AXI_DATA_W),
  .AXI_STRB_W(AXI_STRB_W),
  .AXI_ID_W  (AXI_ID_W),
  .NUM_BNKS  (NUM_BNKS),
  .ROB_D     (ROB_DEPTH)
) u_axi5_sva_bind (
  .ACLK                    (ACLK),
  .ARESETn                 (ARESETn),

  // AW Channel
  .AWID                    (AWID),
  .AWADDR                  (AWADDR),
  .AWLEN                   (AWLEN),
  .AWVALID                 (AWVALID),
  .AWREADY                 (AWREADY),

  // W Channel
  .WDATA                   (WDATA),
  .WSTRB                   (WSTRB),
  .WLAST                   (WLAST),
  .WVALID                  (WVALID),
  .WREADY                  (WREADY),

  // B Channel
  .BID                     (BID),
  .BRESP                   (BRESP),
  .BVALID                  (BVALID),
  .BREADY                  (BREADY),

  // AR Channel
  .ARID                    (ARID),
  .ARADDR                  (ARADDR),
  .ARLEN                   (ARLEN),
  .ARVALID                 (ARVALID),
  .ARREADY                 (ARREADY),

  // R Channel
  .RID                     (RID),
  .RDATA                   (RDATA),
  .RRESP                   (RRESP),
  .RLAST                   (RLAST),
  .RVALID                  (RVALID),
  .RREADY                  (RREADY),

  // Internal Signals
  .cam_full                (cam_full),
  .cam_entries             (cam_entries),
  .bank_req                (bank_req),
  .bank_is_write           (bank_is_write),
  .bank_gnt_valid          (bank_gnt_valid),
  .bank_gnt_onehot         (bank_gnt_onehot),
  .bank_gnt_idx            (bank_gnt_idx),
  .cam_write_prio_override (cam_write_prio_override),
  .raw_hazard_stall_event  (raw_hazard_stall_event),
  .ooo_return_event        (ooo_return_event)
);
