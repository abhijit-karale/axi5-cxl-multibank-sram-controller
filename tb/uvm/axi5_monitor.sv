// ============================================================================
// File: tb/uvm/axi5_monitor.sv
// Description: UVM Monitor for AXI5/CXL.mem Master interface. Passively samples
//              all five AMBA channels, constructs completed transactions,
//              and publishes them to the scoreboard via analysis port.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz
// ============================================================================

`ifndef AXI5_MONITOR_SV
`define AXI5_MONITOR_SV

class axi5_monitor extends uvm_monitor;
  `uvm_component_utils(axi5_monitor)

  virtual axi5_if vif;
  uvm_analysis_port #(axi5_seq_item) item_collected_port;

  // Internal pending queues for reconstructing transactions
  axi5_seq_item pending_writes[$];
  axi5_seq_item pending_reads[$];

  function new(string name = "axi5_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi5_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("MON_NOVIF", "Virtual interface 'vif' not found in uvm_config_db!")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    wait (vif.ARESETn == 1'b1);
    fork
      monitor_aw_w_b_channels();
      monitor_ar_r_channels();
    join
  endtask

  // Monitor Write Pipeline (AW -> W -> B)
  virtual task monitor_aw_w_b_channels();
    axi5_seq_item wr_item;
    forever begin
      @(vif.cb_mon);

      // 1. Capture AW Phase
      if (vif.cb_mon.AWVALID && vif.cb_mon.AWREADY) begin
        wr_item = axi5_seq_item::type_id::create("mon_wr_item");
        wr_item.tx_type    = TX_TYPE_WRITE;
        wr_item.id         = vif.cb_mon.AWID;
        wr_item.addr       = vif.cb_mon.AWADDR;
        wr_item.len        = vif.cb_mon.AWLEN;
        wr_item.size       = vif.cb_mon.AWSIZE;
        wr_item.burst      = axi_burst_e'(vif.cb_mon.AWBURST);
        wr_item.wdata      = new[vif.cb_mon.AWLEN + 1];
        wr_item.wstrb      = new[vif.cb_mon.AWLEN + 1];
        wr_item.issue_time = $realtime;
        pending_writes.push_back(wr_item);
      end

      // 2. Capture W Phase
      if (vif.cb_mon.WVALID && vif.cb_mon.WREADY) begin
        // Find the oldest pending write that has not yet captured WDATA
        for (int unsigned i = 0; i < pending_writes.size(); i++) begin
          if (!pending_writes[i].wdata_captured) begin
            pending_writes[i].wdata[0]        = vif.cb_mon.WDATA;
            pending_writes[i].wstrb[0]        = vif.cb_mon.WSTRB;
            pending_writes[i].wdata_captured  = 1'b1;
            break;
          end
        end
      end

      // 3. Capture B Phase (Write Completion)
      if (vif.cb_mon.BVALID && vif.cb_mon.BREADY) begin
        // Match write response by BID
        int unsigned match_idx;
        bit found = 0;
        for (int unsigned i = 0; i < pending_writes.size(); i++) begin
          if (pending_writes[i].id == vif.cb_mon.BID) begin
            match_idx = i;
            found = 1;
            break;
          end
        end

        if (found) begin
          axi5_seq_item completed_wr;
          completed_wr = pending_writes[match_idx];
          pending_writes.delete(match_idx);
          completed_wr.resp        = axi_resp_e'(vif.cb_mon.BRESP);
          completed_wr.retire_time = $realtime;
          item_collected_port.write(completed_wr);
        end
      end
    end
  endtask

  // Monitor Read Pipeline (AR -> R)
  virtual task monitor_ar_r_channels();
    axi5_seq_item rd_item;
    forever begin
      @(vif.cb_mon);

      // 1. Capture AR Phase
      if (vif.cb_mon.ARVALID && vif.cb_mon.ARREADY) begin
        rd_item = axi5_seq_item::type_id::create("mon_rd_item");
        rd_item.tx_type    = TX_TYPE_READ;
        rd_item.id         = vif.cb_mon.ARID;
        rd_item.addr       = vif.cb_mon.ARADDR;
        rd_item.len        = vif.cb_mon.ARLEN;
        rd_item.size       = vif.cb_mon.ARSIZE;
        rd_item.burst      = axi_burst_e'(vif.cb_mon.ARBURST);
        rd_item.rdata      = new[vif.cb_mon.ARLEN + 1];
        rd_item.issue_time = $realtime;
        pending_reads.push_back(rd_item);
      end

      // 2. Capture R Phase
      if (vif.cb_mon.RVALID && vif.cb_mon.RREADY) begin
        // Match read response by RID (supports Out-of-Order!)
        int unsigned match_idx;
        bit found = 0;
        for (int unsigned i = 0; i < pending_reads.size(); i++) begin
          if (pending_reads[i].id == vif.cb_mon.RID) begin
            match_idx = i;
            found = 1;
            break;
          end
        end

        if (found) begin
          pending_reads[match_idx].rdata[0] = vif.cb_mon.RDATA;
          pending_reads[match_idx].resp     = axi_resp_e'(vif.cb_mon.RRESP);

          if (vif.cb_mon.RLAST) begin
            axi5_seq_item completed_rd;
            completed_rd = pending_reads[match_idx];
            pending_reads.delete(match_idx);
            completed_rd.retire_time = $realtime;
            item_collected_port.write(completed_rd);
          end
        end
      end
    end
  endtask

endclass : axi5_monitor

`endif // AXI5_MONITOR_SV
