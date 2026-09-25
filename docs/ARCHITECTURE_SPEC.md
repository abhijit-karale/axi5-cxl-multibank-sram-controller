# Microarchitectural Specification: AXI5/CXL.mem Coherent Multi-Bank SRAM Controller

**Principal Silicon Architect & Staff DV Engineer:** Abhijit Karale  
**Target Process:** SkyWater 130nm (`sky130_fd_sc_hd`) @ 200 MHz (5.0 ns period)  
**Document Revision:** 1.0 - Production Baseline  

---

## 1. Architectural Overview & Design Objectives

The **AXI5/CXL.mem Coherent Multi-Bank SRAM Controller** is a high-bandwidth, low-latency, deterministic memory subsystem designed for heterogeneous compute nodes, CXL.mem device interfaces, and tightly-coupled hardware accelerators. The controller provides an AMBA AXI5 slave interface servicing up to **8 concurrent outstanding transactions** across **4 independent 16KB SRAM banks** (64KB total storage), delivering maximum sustained throughput via fine-grained bank parallelism, hardware hazard management, and out-of-order completion.

### Key Architectural Parameters
| Parameter | Value | Description |
| :--- | :--- | :--- |
| **Target Technology Node** | SkyWater 130nm | High-Density Standard Cells (`sky130_fd_sc_hd`) |
| **System Clock Frequency** | 200 MHz | 5.0 ns clock period, synchronous single-clock domain |
| **AXI Data Bus Width** | 64 bits (8 Bytes) | Peak theoretical bandwidth: **1.6 GB/s** |
| **AXI Address Bus Width** | 32 bits | 16-bit physical aperture (64KB), higher bits decoded |
| **Transaction ID Width** | 4 bits | Supports IDs `0x0` through `0xF` (up to 16 IDs) |
| **Concurrent Transactions** | Up to 8 in-flight | Managed by an 8-entry CAM Tracker & ROB |
| **Bank Architecture** | 4 Banks × 16KB | Independent synchronous single-port SRAM macros |
| **Bank Interleaving** | Word-Interleaved | 8-byte word interleaving (`addr[4:3]` selects bank) |
| **Bank Arbitration** | Dynamic Round-Robin | Fair scheduling with automatic write-priority override |
| **Hazard Avoidance** | CAM Address Match | Hardware RAW stall, WAW ordering, WAR serialization |
| **Response Engine** | Out-of-Order (OoO) | Completed reads return out-of-order tagged with `RID` |

---

## 2. Microarchitectural Block Diagram

```
====================================================================================================================
                                      AXI5 / CXL.mem COHERENT SRAM CONTROLLER
====================================================================================================================

      AXI5 MASTER INTERFACE
   +---------------------------+
   | AW Channel (AWID, AWADDR) |----+
   +---------------------------+    |
   | W Channel  (WDATA, WSTRB)  |----+    +--------------------------------------------------------------------+
   +---------------------------+    |    |                     FRONT-END ALLOCATION ARBITER                  |
   | AR Channel (ARID, ARADDR) |----+----> Dynamic AW vs AR priority arbiter (fair toggle / write-prio override) |
   +---------------------------+    |    +--------------------------------------------------------------------+
   | B Channel  (BID, BRESP)   |<---|                                      |
   +---------------------------+    |                           alloc_req, alloc_tx_type
   | R Channel  (RID, RDATA)   |<---|                                      v
   +---------------------------+    |    +--------------------------------------------------------------------+
                                    |    |              8-ENTRY CONTENT-ADDRESSABLE MEMORY (CAM)              |
                                    |    | - Parallel address comparator for RAW / WAW / WAR detection       |
                                    |    | - In-flight transaction state machines (FREE -> ACTIVE -> READY)   |
                                    |    | - WDATA capture logic & age tracking pointers                     |
                                    |    +--------------------------------------------------------------------+
                                    |           |                 |                 |                 |
                                    |       bank_req[0]       bank_req[1]       bank_req[2]       bank_req[3]
                                    |           v                 v                 v                 v
                                    |    +-------------+   +-------------+   +-------------+   +-------------+
                                    |    | Bank 0 Arb  |   | Bank 1 Arb  |   | Bank 2 Arb  |   | Bank 3 Arb  |
                                    |    | Round-Robin |   | Round-Robin |   | Round-Robin |   | Round-Robin |
                                    |    | Write-Prio  |   | Write-Prio  |   | Write-Prio  |   | Write-Prio  |
                                    |    +-------------+   +-------------+   +-------------+   +-------------+
                                    |           |                 |                 |                 |
                                    |      sram_cs/we[0]     sram_cs/we[1]     sram_cs/we[2]     sram_cs/we[3]
                                    |           v                 v                 v                 v
                                    |    +-------------+   +-------------+   +-------------+   +-------------+
                                    |    |  SRAM BNK 0 |   |  SRAM BNK 1 |   |  SRAM BNK 2 |   |  SRAM BNK 3 |
                                    |    |    16 KB    |   |    16 KB    |   |    16 KB    |   |    16 KB    |
                                    |    | 2048x64-bit |   | 2048x64-bit |   | 2048x64-bit |   | 2048x64-bit |
                                    |    +-------------+   +-------------+   +-------------+   +-------------+
                                    |           |                 |                 |                 |
                                    |       rdata[0]          rdata[1]          rdata[2]          rdata[3]
                                    |           +-----------------+-----------------+-----------------+
                                    |                             | (1-cycle capture)
                                    |                             v
                                    |    +--------------------------------------------------------------------+
                                    |    |                REORDER BUFFER (ROB) & RESPONSE DISPATCHER          |
                                    |    | - Out-of-order read data arbitration & RID matching                |
                                    |    | - RLAST generator for single-beat and multi-beat bursts            |
                                    +--->| - B channel response dispatcher (BVALID, BID, BRESP)               |
                                         | - CAM entry retirement acknowledgment (retire_ack[7:0])            |
                                         +--------------------------------------------------------------------+
                                                                          |
                                                                          v
                                         +--------------------------------------------------------------------+
                                         |             HARDWARE PERFORMANCE & TELEMETRY MONITORS              |
                                         | - Bank conflict counters, OoO events, RAW stalls, Completed TXs    |
                                         +--------------------------------------------------------------------+
====================================================================================================================
```

---

## 3. Memory Mapping & Bank Interleaving Architecture

The memory system exposes a 64KB physical address aperture mapped across 4 independent banks using **Word-Level Interleaving**:

```
 31                             16 15                      5 4       3 2       0
+---------------------------------+-------------------------+---------+---------+
|     Aperture / Base Match       |   Bank Row Word Addr    | Bank ID | Byte Off|
|           (16 bits)             |   (11 bits = 2048 rows) | (2 bits)| (3 bits)|
+---------------------------------+-------------------------+---------+---------+
```

### Addressing Bit Fields
1. **Byte Offset (`addr[2:0]` - 3 bits):** Selects byte within 64-bit (8-byte) word. Unaligned accesses use byte write strobes `WSTRB[7:0]`.
2. **Bank Index (`addr[4:3]` - 2 bits):**
   * `2'b00` -> Bank 0 (Base offset: 0x00)
   * `2'b01` -> Bank 1 (Base offset: 0x08)
   * `2'b10` -> Bank 2 (Base offset: 0x10)
   * `2'b11` -> Bank 3 (Base offset: 0x18)
3. **Bank Row Address (`addr[15:5]` - 11 bits):** Selects one of the 2,048 64-bit words within the target 16KB bank.
4. **Upper Address (`addr[31:16]`):** Base aperture decoding.

### Interleaving Benefits
Sequential accesses (e.g. burst increment `INCR`) naturally stripe across Banks 0, 1, 2, and 3. As a result, a 4-beat 64-bit burst accesses Bank 0, Bank 1, Bank 2, and Bank 3 in pipelined concurrency without experiencing a single internal bank stall!

---

## 4. Submodule Microarchitectures

### 4.1 Front-End Address Allocation Arbiter
* Arbitrates between `AWVALID` (Write Address) and `ARVALID` (Read Address) channels.
* Employs alternating round-robin priority between AW and AR on successive allocations to prevent channel starvation.
* **Write Priority Override:** If `cam_write_prio_override` is asserted by the CAM tracker, the arbiter prioritizes `AWVALID` over `ARVALID` to alleviate write queue congestion.
* Backpressures the master (`AWREADY = 0`, `ARREADY = 0`) when all 8 CAM slots are occupied (`cam_full = 1`).

### 4.2 CAM-Based Hazard Tracker (`axi5_cam_tracker.sv`)
* Manages an 8-entry fully associative table tracking all in-flight memory transactions.
* **Parallel Content-Addressable Comparison:**
  * For every transaction attempting bank dispatch, compares target `bank_id` and `bank_addr` against all other active CAM entries.
  * **RAW (Read-After-Write) Hazard:** If an active read targets the exact word address of an uncommitted write, the read is held in `CAM_STATE_PENDING_BNK` until the write commits to SRAM, guaranteeing zero stale data reads.
  * **WAW (Write-After-Write) Hazard:** Sequential writes to the same address are strictly ordered by allocation age.
  * **WAR (Write-After-Read) Hazard:** Prevents write execution from overtaking an active read accessing the same address.
* **Write Data Association:** Matches incoming `WDATA` from the AXI W channel to the oldest allocated write entry awaiting data.

### 4.3 Dynamic Bank Arbiters (`axi5_bank_arbiter.sv`)
* 4 independent instances, each arbitrating competing requests from up to 8 CAM entries for that specific bank.
* **Double-Width Rotating Round-Robin Arbiter:** Uses a masked and unmasked priority encoder with pointer `rr_ptr` to ensure starvation-free scheduling.
* **Write-Priority Override Engine:**
  * When `write_prio_override` is asserted (pending writes $\ge 3$) and write requests are pending for that bank:
    * Services write requests exclusively via round-robin among writes.
  * Once write backlog clears, smoothly reverts to standard round-robin across all transactions.

### 4.4 16KB SRAM Bank Macros (`sram_bank_16k.sv`)
* 2048 words × 64-bit architecture implemented with single-cycle synchronous read latency.
* Individual byte write strobes (`wstrb[7:0]`) enabling partial word updates.
* Pin-compatible with SkyWater 130nm OpenRAM compiler generated SRAM blocks.

### 4.5 Reorder Buffer & Response Engine (`axi5_rob.sv`)
* Decouples bank completion order from request issue order.
* **Out-of-Order Read Data Return:**
  * Completed reads in `CAM_STATE_RESP_READY` compete for the AXI R channel.
  * Driven with original transaction ID (`RID = entry.id`), allowing out-of-order master retirement.
  * Automatic `RLAST` assertion on the terminal burst beat.
* **Write Response Engine:**
  * Dedicated B-channel dispatcher returning `BID` and `BRESP = AXI_RESP_OKAY` upon SRAM write commit.
* **CAM Retirement:** Emits single-cycle `retire_ack[entry_idx]` pulses to free completed CAM entries.

---

## 5. Transaction Lifecycle State Machine

```
      +---------------------+
      |   CAM_STATE_FREE    |  (Entry unoccupied, available for allocation)
      +---------------------+
                 |
                 | alloc_req && has_free_entry
                 v
      +---------------------+
      | CAM_STATE_ALLOCATED |  (Slot assigned; if WRITE, awaits WDATA)
      +---------------------+
                 |
                 | Read: immediate / Write: WDATA arrived
                 v
      +---------------------+
      | CAM_STATE_PENDING   |  (Hazard check evaluated; requests target bank)
      +---------------------+
                 |
                 | bank_gnt_valid[b] asserted by Bank Arbiter
                 v
      +---------------------+
      | CAM_STATE_ACTIVE    |  (SRAM macro accessed: 1-cycle pipeline)
      +---------------------+
                 |
                 | SRAM read captured / write committed
                 v
      +---------------------+
      | CAM_STATE_RESP_READY|  (Queued in ROB for AXI R / B handshake)
      +---------------------+
                 |
                 | Handshake completed: (RVALID && RREADY && RLAST) || (BVALID && BREADY)
                 v
      +---------------------+
      |   CAM_STATE_FREE    |  (Slot freed, counters updated)
      +---------------------+
```

---

## 6. Latency & Throughput Characteristics

| Access Scenario | Latency (Clock Cycles) | Peak Throughput | Notes |
| :--- | :---: | :---: | :--- |
| **Back-to-Back Sequential Read** | 3 cycles (1st beat), 1 cycle pipelined | 1.6 GB/s (100% bus utilization) | Zero bank conflicts due to word interleaving |
| **Back-to-Back Sequential Write** | 2 cycles | 1.6 GB/s | Write commits immediately at SRAM posedge |
| **Bank Conflict Read (2 Master Reqs)** | 3 cycles (Req 1), 4 cycles (Req 2) | Shared bank bandwidth | Round-robin arbitrates within 1 cycle |
| **RAW Hazard Read to same address** | Stalled until write commits | Fully coherent | Eliminates memory consistency bugs |
| **Maximum Outstanding Depth** | 8 concurrent transactions | 8 in-flight IDs | Sustained without head-of-line blocking |
