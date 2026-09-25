// ============================================================================
// File: tb/uvm/axi5_driver.sv
// Description: UVM Driver for AXI5/CXL.mem Master interface. Handles concurrent
//              AW, W, B, AR, and R channel handshakes with realistic backpressure.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_DRIVER_SV
`define AXI5_DRIVER_SV

class axi5_driver extends uvm_driver #(axi5_seq_item);
  `uvm_component_utils(axi5_driver)

  virtual axi5_if vif;

  // Configuration settings
  bit random_ready_backpressure = 0;

  function new(string name = "axi5_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi5_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("DRV_NOVIF", "Virtual interface 'vif' not found in uvm_config_db!")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    reset_signals();
    wait (vif.ARESETn == 1'b1);
    @(vif.cb_drv);

    fork
      get_and_drive();
      manage_rready();
      manage_bready();
    join
  endtask

  // Reset initial signal values
  virtual task reset_signals();
    vif.cb_drv.AWVALID <= 1'b0;
    vif.cb_drv.AWID    <= '0;
    vif.cb_drv.AWADDR  <= '0;
    vif.cb_drv.AWLEN   <= '0;
    vif.cb_drv.AWSIZE  <= '0;
    vif.cb_drv.AWBURST <= AXI_BURST_INCR;
    vif.cb_drv.AWLOCK  <= 1'b0;
    vif.cb_drv.AWCACHE <= '0;
    vif.cb_drv.AWPROT  <= '0;
    vif.cb_drv.AWQOS   <= '0;

    vif.cb_drv.WVALID  <= 1'b0;
    vif.cb_drv.WDATA   <= '0;
    vif.cb_drv.WSTRB   <= '0;
    vif.cb_drv.WLAST   <= 1'b0;

    vif.cb_drv.BREADY  <= 1'b1;

    vif.cb_drv.ARVALID <= 1'b0;
    vif.cb_drv.ARID    <= '0;
    vif.cb_drv.ARADDR  <= '0;
    vif.cb_drv.ARLEN   <= '0;
    vif.cb_drv.ARSIZE  <= '0;
    vif.cb_drv.ARBURST <= AXI_BURST_INCR;
    vif.cb_drv.ARLOCK  <= 1'b0;
    vif.cb_drv.ARCACHE <= '0;
    vif.cb_drv.ARPROT  <= '0;
    vif.cb_drv.ARQOS   <= '0;

    vif.cb_drv.RREADY  <= 1'b1;
  endtask

  // Main transaction processing loop
  virtual task get_and_drive();
    forever begin
      seq_item_port.get_next_item(req);
      req.issue_time = $realtime;

      if (req.tx_type == TX_TYPE_WRITE) begin
        drive_write_transaction(req);
      end else begin
        drive_read_transaction(req);
      end

      seq_item_port.item_done();
    end
  endtask

  // Drive Write Address and Write Data
  virtual task drive_write_transaction(axi5_seq_item item);
    // AW Phase
    @(vif.cb_drv);
    vif.cb_drv.AWVALID <= 1'b1;
    vif.cb_drv.AWID    <= item.id;
    vif.cb_drv.AWADDR  <= item.addr;
    vif.cb_drv.AWLEN   <= item.len;
    vif.cb_drv.AWSIZE  <= item.size;
    vif.cb_drv.AWBURST <= item.burst;

    // Concurrently drive W Phase
    vif.cb_drv.WVALID  <= 1'b1;
    vif.cb_drv.WDATA   <= item.wdata[0];
    vif.cb_drv.WSTRB   <= item.wstrb[0];
    vif.cb_drv.WLAST   <= (item.len == 0);

    // Wait for AWREADY
    do begin
      @(vif.cb_drv);
    end while (!vif.cb_drv.AWREADY);
    vif.cb_drv.AWVALID <= 1'b0;

    // Wait for WREADY for beat 0
    while (!vif.cb_drv.WREADY) begin
      @(vif.cb_drv);
    end

    // Subsequent burst beats if len > 0
    for (int unsigned b = 1; b <= item.len; b++) begin
      vif.cb_drv.WVALID <= 1'b1;
      vif.cb_drv.WDATA  <= item.wdata[b];
      vif.cb_drv.WSTRB  <= item.wstrb[b];
      vif.cb_drv.WLAST  <= (b == item.len);
      do begin
        @(vif.cb_drv);
      end while (!vif.cb_drv.WREADY);
    end
    vif.cb_drv.WVALID <= 1'b0;
    vif.cb_drv.WLAST  <= 1'b0;
  endtask

  // Drive Read Address
  virtual task drive_read_transaction(axi5_seq_item item);
    @(vif.cb_drv);
    vif.cb_drv.ARVALID <= 1'b1;
    vif.cb_drv.ARID    <= item.id;
    vif.cb_drv.ARADDR  <= item.addr;
    vif.cb_drv.ARLEN   <= item.len;
    vif.cb_drv.ARSIZE  <= item.size;
    vif.cb_drv.ARBURST <= item.burst;

    do begin
      @(vif.cb_drv);
    end while (!vif.cb_drv.ARREADY);
    vif.cb_drv.ARVALID <= 1'b0;
  endtask

  // Manage RREADY with optional backpressure
  virtual task manage_rready();
    forever begin
      @(vif.cb_drv);
      if (random_ready_backpressure) begin
        vif.cb_drv.RREADY <= $urandom_range(0, 10) > 2; // ~80% ready
      end else begin
        vif.cb_drv.RREADY <= 1'b1;
      end
    end
  endtask

  // Manage BREADY
  virtual task manage_bready();
    forever begin
      @(vif.cb_drv);
      vif.cb_drv.BREADY <= 1'b1;
    end
  endtask

endclass : axi5_driver

`endif // AXI5_DRIVER_SV
