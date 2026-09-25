// ============================================================================
// File: tb/uvm/axi5_seq_item.sv
// Description: UVM Sequence Item for AXI5 transactions. Supports reads, writes,
//              bursts, targeted bank selection, byte strobes, and response logging.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_SEQ_ITEM_SV
`define AXI5_SEQ_ITEM_SV

class axi5_seq_item extends uvm_sequence_item;

  // Transaction Attributes
  rand tx_type_e                   tx_type;
  rand logic [AXI_ID_WIDTH-1:0]    id;
  rand logic [AXI_ADDR_WIDTH-1:0]  addr;
  rand logic [AXI_LEN_WIDTH-1:0]   len;
  rand logic [AXI_SIZE_WIDTH-1:0]  size;
  rand axi_burst_e                 burst;

  // Payloads
  rand logic [AXI_DATA_WIDTH-1:0]  wdata[];
  rand logic [AXI_STRB_WIDTH-1:0]  wstrb[];
  logic [AXI_DATA_WIDTH-1:0]       rdata[];
  axi_resp_e                       resp;

  // Constrained Bank Targeting Helper
  rand logic [BANK_SEL_WIDTH-1:0]  target_bank;
  rand bit                         enable_bank_override;
  bit                              wdata_captured = 0;

  // Timing & Performance Metrology
  realtime                         issue_time;
  realtime                         retire_time;

  `uvm_object_utils_begin(axi5_seq_item)
    `uvm_field_enum(tx_type_e, tx_type, UVM_ALL_ON)
    `uvm_field_int(id, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(len, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(size, UVM_ALL_ON | UVM_DEC)
    `uvm_field_enum(axi_burst_e, burst, UVM_ALL_ON)
    `uvm_field_array_int(wdata, UVM_ALL_ON | UVM_HEX)
    `uvm_field_array_int(wstrb, UVM_ALL_ON | UVM_HEX)
    `uvm_field_array_int(rdata, UVM_ALL_ON | UVM_HEX)
    `uvm_field_enum(axi_resp_e, resp, UVM_ALL_ON)
  `uvm_object_utils_end

  // --------------------------------------------------------------------------
  // Default Constraints
  // --------------------------------------------------------------------------
  constraint c_alignment {
    addr[BYTE_OFFSET_BITS-1:0] == '0; // 64-bit word aligned
  }

  constraint c_address_bounds {
    addr < 32'h0001_0000; // Within 64KB memory boundary
  }

  constraint c_burst_len {
    len inside {[0:3]}; // 1 to 4 beats per transaction
  }

  constraint c_burst_size {
    size == 3'b011; // 8 bytes (64-bit full bus width)
  }

  constraint c_burst_type {
    burst == AXI_BURST_INCR;
  }

  constraint c_bank_targeting {
    if (enable_bank_override) {
      addr[BYTE_OFFSET_BITS +: BANK_SEL_WIDTH] == target_bank;
    }
  }

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string name = "axi5_seq_item");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // Post-Randomization: Size arrays according to burst length
  // --------------------------------------------------------------------------
  function void post_randomize();
    int unsigned num_beats = len + 1;
    if (tx_type == TX_TYPE_WRITE) begin
      wdata = new[num_beats];
      wstrb = new[num_beats];
      for (int unsigned i = 0; i < num_beats; i++) begin
        wdata[i] = {$urandom(), $urandom()};
        wstrb[i] = '1; // Default to full byte-lane enable
      end
    end
    rdata = new[num_beats];
  endfunction

  // --------------------------------------------------------------------------
  // Custom Formatted String Representation
  // --------------------------------------------------------------------------
  virtual function string convert2string();
    string s;
    s = $sformatf("Type=%s ID=0x%0h Addr=0x%08h [Bank %0d Row 0x%03h] Len=%0d Size=%0d",
                  tx_type.name(), id, addr, get_bank_id(addr), get_bank_addr(addr), len, size);
    if (tx_type == TX_TYPE_WRITE && wdata.size() > 0) begin
      s = {s, $sformatf(" WDATA[0]=0x%016h WSTRB[0]=0x%02h", wdata[0], wstrb[0])};
    end
    if (tx_type == TX_TYPE_READ && rdata.size() > 0) begin
      s = {s, $sformatf(" RDATA[0]=0x%016h Resp=%s", rdata[0], resp.name())};
    end
    return s;
  endfunction

endclass : axi5_seq_item

`endif // AXI5_SEQ_ITEM_SV
