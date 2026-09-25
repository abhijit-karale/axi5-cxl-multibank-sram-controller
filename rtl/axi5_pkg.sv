// ============================================================================
// File: rtl/axi5_pkg.sv
// Description: SystemVerilog Package for AXI5 / CXL.mem Coherent Multi-Bank
//              SRAM Controller. Defines protocol parameters, bus structs,
//              CAM states, and helper decoding functions.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_PKG_SV
`define AXI5_PKG_SV

package axi5_pkg;

  // --------------------------------------------------------------------------
  // Architectural Configuration Parameters
  // --------------------------------------------------------------------------
  localparam int unsigned AXI_ADDR_WIDTH   = 32;       // Standard 32-bit AXI address
  localparam int unsigned AXI_DATA_WIDTH   = 64;       // 64-bit wide data bus (8 bytes/beat)
  localparam int unsigned AXI_STRB_WIDTH   = AXI_DATA_WIDTH / 8; // 8 byte-strobes
  localparam int unsigned AXI_ID_WIDTH     = 4;        // Up to 16 IDs (spec mandates 4-bit)
  localparam int unsigned AXI_LEN_WIDTH    = 8;        // AXI4/AXI5 8-bit burst length (1-256)
  localparam int unsigned AXI_SIZE_WIDTH   = 3;        // Burst size (up to 128 bytes)
  localparam int unsigned AXI_BURST_WIDTH  = 2;        // Burst type
  localparam int unsigned AXI_RESP_WIDTH   = 2;        // Response width

  // Memory & Bank Geometry (4 independent 16KB SRAM banks = 64KB total)
  localparam int unsigned NUM_BANKS        = 4;        // 4 concurrent banks
  localparam int unsigned BANK_WORDS       = 2048;     // 2048 words of 64-bit per bank
  localparam int unsigned BANK_ADDR_WIDTH  = 11;       // 2^11 = 2048 rows
  localparam int unsigned BANK_SEL_WIDTH   = 2;        // 2 bits for 4 banks ($clog2(NUM_BANKS))
  localparam int unsigned BYTE_OFFSET_BITS = 3;        // 2^3 = 8 bytes per word
  localparam int unsigned MEM_TOTAL_BYTES  = NUM_BANKS * BANK_WORDS * AXI_STRB_WIDTH; // 65,536 (64KB)
  localparam int unsigned MEM_ADDR_WIDTH   = BANK_ADDR_WIDTH + BANK_SEL_WIDTH + BYTE_OFFSET_BITS; // 16 bits

  // Concurrency & Buffer Parameters
  localparam int unsigned ROB_DEPTH        = 8;        // Up to 8 concurrent outstanding transactions
  localparam int unsigned ROB_IDX_WIDTH    = 3;        // $clog2(ROB_DEPTH)
  localparam int unsigned WRITE_PRIO_THRESH= 3;        // Dynamic write override threshold

  // --------------------------------------------------------------------------
  // AXI5 / Protocol Enumerations
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10,
    AXI_BURST_RSVD  = 2'b11
  } axi_burst_e;

  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

  typedef enum logic {
    TX_TYPE_READ  = 1'b0,
    TX_TYPE_WRITE = 1'b1
  } tx_type_e;

  // CAM Tracking & Lifecycle States
  typedef enum logic [2:0] {
    CAM_STATE_FREE        = 3'b000, // Available slot
    CAM_STATE_ALLOCATED   = 3'b001, // Slot allocated, waiting for data/hazard check
    CAM_STATE_PENDING_BNK = 3'b010, // Hazard cleared, arbitrating for bank access
    CAM_STATE_BNK_ACTIVE  = 3'b011, // Bank granted, reading/writing SRAM
    CAM_STATE_RESP_READY  = 3'b100, // SRAM access finished, queued for AXI response
    CAM_STATE_COMPLETE    = 3'b101  // Retired/Freed
  } cam_state_e;

  // --------------------------------------------------------------------------
  // AXI Channel Structured Types
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic [AXI_ID_WIDTH-1:0]    id;
    logic [AXI_ADDR_WIDTH-1:0]  addr;
    logic [AXI_LEN_WIDTH-1:0]   len;
    logic [AXI_SIZE_WIDTH-1:0]  size;
    axi_burst_e                 burst;
    logic                       lock;
    logic [3:0]                 cache;
    logic [2:0]                 prot;
    logic [3:0]                 qos;
  } axi_addr_payload_t;

  typedef struct packed {
    logic [AXI_DATA_WIDTH-1:0]  data;
    logic [AXI_STRB_WIDTH-1:0]  strb;
    logic                       last;
  } axi_write_payload_t;

  typedef struct packed {
    logic [AXI_ID_WIDTH-1:0]    id;
    axi_resp_e                  resp;
  } axi_b_payload_t;

  typedef struct packed {
    logic [AXI_ID_WIDTH-1:0]    id;
    logic [AXI_DATA_WIDTH-1:0]  data;
    axi_resp_e                  resp;
    logic                       last;
  } axi_r_payload_t;

  // --------------------------------------------------------------------------
  // Internal CAM & ROB Entry Record
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic                       valid;
    cam_state_e                 state;
    tx_type_e                   tx_type;
    logic [AXI_ID_WIDTH-1:0]    id;
    logic [AXI_ADDR_WIDTH-1:0]  orig_addr;
    logic [BANK_SEL_WIDTH-1:0]  bank_id;
    logic [BANK_ADDR_WIDTH-1:0] bank_addr;
    logic [BYTE_OFFSET_BITS-1:0]byte_offset;
    logic [AXI_LEN_WIDTH-1:0]   len;
    logic [AXI_LEN_WIDTH-1:0]   beat_cnt;
    logic [AXI_SIZE_WIDTH-1:0]  size;
    axi_burst_e                 burst;
    logic [AXI_DATA_WIDTH-1:0]  wdata;
    logic [AXI_STRB_WIDTH-1:0]  wstrb;
    logic [AXI_DATA_WIDTH-1:0]  rdata;
    axi_resp_e                  resp;
    logic [ROB_DEPTH-1:0]       hazard_mask; // Mask of other CAM entries this depends on
    logic                       has_wdata;   // Set when WDATA has arrived for write
  } cam_entry_t;

  // --------------------------------------------------------------------------
  // Helper Functions: Address Decoding & Interleaving
  // Interleaving format:
  //   [31:16] : Aperture/Unused (matched against base address)
  //   [15:5]  : Bank row address (11 bits = 2048 words)
  //   [4:3]   : Bank selector (2 bits = 4 banks)
  //   [2:0]   : Byte offset (3 bits = 8 bytes per 64-bit word)
  // --------------------------------------------------------------------------
  function automatic logic [BANK_SEL_WIDTH-1:0] get_bank_id(input logic [AXI_ADDR_WIDTH-1:0] addr);
    return addr[BYTE_OFFSET_BITS +: BANK_SEL_WIDTH];
  endfunction

  function automatic logic [BANK_ADDR_WIDTH-1:0] get_bank_addr(input logic [AXI_ADDR_WIDTH-1:0] addr);
    return addr[(BYTE_OFFSET_BITS + BANK_SEL_WIDTH) +: BANK_ADDR_WIDTH];
  endfunction

  function automatic logic [BYTE_OFFSET_BITS-1:0] get_byte_offset(input logic [AXI_ADDR_WIDTH-1:0] addr);
    return addr[BYTE_OFFSET_BITS-1:0];
  endfunction

  // Next address calculation for bursts
  function automatic logic [AXI_ADDR_WIDTH-1:0] next_burst_addr(
    input logic [AXI_ADDR_WIDTH-1:0] current_addr,
    input axi_burst_e                burst,
    input logic [AXI_SIZE_WIDTH-1:0] size,
    input logic [AXI_LEN_WIDTH-1:0]  len
  );
    logic [AXI_ADDR_WIDTH-1:0] next_addr;
    logic [AXI_ADDR_WIDTH-1:0] wrap_size;
    logic [AXI_ADDR_WIDTH-1:0] wrap_mask;
    int unsigned num_bytes;

    num_bytes = 1 << size;
    case (burst)
      AXI_BURST_FIXED: next_addr = current_addr;
      AXI_BURST_INCR:  next_addr = current_addr + num_bytes;
      AXI_BURST_WRAP: begin
        wrap_size = num_bytes * (len + 1);
        wrap_mask = ~(wrap_size - 1);
        next_addr = (current_addr & wrap_mask) | ((current_addr + num_bytes) & (wrap_size - 1));
      end
      default:         next_addr = current_addr + num_bytes;
    endcase
    return next_addr;
  endfunction

endpackage : axi5_pkg

`endif // AXI5_PKG_SV
