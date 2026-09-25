# Cycle-Accurate Waveform Guide: Bank Conflict Resolution & Out-of-Order Read Return

**Author:** Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)  
**Target:** SkyWater 130nm @ 200 MHz (Clock Period = 5.0 ns)  
**Document Revision:** 1.0 - Production Baseline  

---

## 1. Scenario Description

This cycle-accurate waveform depicts an 8-cycle sequence demonstrating two critical architectural features:
1. **Simultaneous Bank Conflict Resolution:**
   * At **Cycle 1**, Transaction $T_0$ (`ID=0x1`, Write to Bank 2) and Transaction $T_1$ (`ID=0x2`, Write to Bank 2) simultaneously request Bank 2.
   * The Bank 2 Arbiter resolves the conflict using Round-Robin scheduling: $T_0$ is granted at Cycle 2, while $T_1$ is held in `CAM_STATE_PENDING_BNK`. At Cycle 3, $T_1$ is granted.
2. **Out-of-Order Read Data Return:**
   * At **Cycle 2**, Master issues a Read $T_2$ (`ID=0x4`, targeting Bank 1).
   * At **Cycle 3**, Master issues a Read $T_3$ (`ID=0x7`, targeting Bank 0).
   * Bank 1 is under contention; Bank 0 is completely free.
   * $T_3$ is granted immediately at Cycle 4, completes SRAM access in Cycle 5, and returns its read data on the R channel at **Cycle 6** (`RID=0x7`).
   * $T_2$ is delayed by bank arbitration and returns on the R channel at **Cycle 7** (`RID=0x4`).
   * **Result:** Transaction $T_3$ returns **before** Transaction $T_2$, proving cycle-accurate Out-of-Order execution!

---

## 2. 8-Cycle ASCII Waveform Diagram

```
Cycle Number:       |   C0   |   C1   |   C2   |   C3   |   C4   |   C5   |   C6   |   C7   |   C8   |
Time (ns):          |   0.0  |   5.0  |  10.0  |  15.0  |  20.0  |  25.0  |  30.0  |  35.0  |  40.0  |

ACLK                : __/‾‾\_/‾‾\_/‾‾\_/‾‾\_/‾‾\_/‾‾\_/‾‾\_/‾‾\_/‾‾\_
ARESETn             : ________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

[ AXI WRITE CHANNELS ]
AWVALID             : ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________________________________________________
AWREADY             : ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________________________________________________
AWADDR              : <  IDLE ><  0x0010 (B2)   ><  0x0030 (B2)   ><              IDLE             >
AWID                : <  IDLE ><      0x1       ><      0x2       ><              IDLE             >
WVALID              : ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________________________________________________
WREADY              : ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________________________________________________
WDATA               : <  IDLE ><   0xA001_D001  ><   0xA002_D002  ><              IDLE             >

[ AXI READ CHANNELS ]
ARVALID             : __________________/‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾‾\_______________________________
ARREADY             : __________________/‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾‾\_______________________________
ARADDR              : <      IDLE       >< 0x0008 (B1) ><  IDLE  >< 0x0000 (B0) ><       IDLE       >
ARID                : <      IDLE       ><     0x4     ><  IDLE  ><     0x7     ><       IDLE       >

[ INTERNAL BANK REQUESTS & GRANTS ]
Bank 2 Req (T0, T1) : ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________________________________________
Bank 2 Conflict     : __________________/‾‾‾‾‾‾‾‾\_________________________________________________  <-- Conflict Flag!
Bank 2 Grant        : __________________/‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾‾\_______________________________
Granted Entry       : <      NONE       ><    T0 (e0)  ><    T1 (e1)  ><             NONE             >

Bank 0 Req (T3)     : ____________________________________/‾‾‾‾‾‾‾‾\_______________________________
Bank 0 Grant        : _____________________________________________/‾‾‾‾‾‾‾‾\_______________________
Granted Entry       : <                     NONE                     ><    T3 (e3)  ><     NONE     >

Bank 1 Req (T2)     : ___________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_______________________________
Bank 1 Grant        : ______________________________________________________/‾‾‾‾‾‾‾‾\_______________
Granted Entry       : <                           NONE                      ><    T2 (e2)  ><   NONE >

[ AXI RESPONSE CHANNELS - OUT-OF-ORDER RETIREMENT ]
BVALID (Write Resp) : ___________________________/‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾‾\______________________
BREADY              : ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
BID                 : <      IDLE       ><     0x1     ><   IDLE  ><     0x2     ><       IDLE       >

RVALID (Read Data)  : ______________________________________________________/‾‾‾‾‾‾‾‾\________/‾‾‾‾\
RREADY              : ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
RID                 : <                     IDLE                     ><  0x7 (T3)   ><  0x4 (T2)   > <-- OUT-OF-ORDER!
RDATA               : <                     IDLE                     >< Data_B0_T3  >< Data_B1_T2  >
RLAST               : ______________________________________________________/‾‾‾‾‾‾‾‾\________/‾‾‾‾\
```

---

## 3. Detailed Cycle-by-Cycle Event Log

| Cycle | Time | Channel Activity | Internal Microarchitectural Actions |
| :---: | :---: | :--- | :--- |
| **C0** | 0.0 ns | Reset Active | System power-on reset. All 8 CAM entries initialized to `CAM_STATE_FREE`. Bank arbiters reset `rr_ptr = 0`. |
| **C1** | 5.0 ns | `AWVALID` & `WVALID` for $T_0$ | $T_0$ arrives (`AWID=0x1`, `AWADDR=0x0010` [Bank 2]). Allocated into CAM Entry 0. WDATA captured. Transitions to `CAM_STATE_PENDING_BNK`. |
| **C2** | 10.0 ns | `AWVALID` & `WVALID` for $T_1$, `ARVALID` for $T_2$ | **Bank Conflict Detected on Bank 2:** Both Entry 0 ($T_0$) and Entry 1 ($T_1$) request Bank 2. Bank 2 Arbiter grants Entry 0 ($T_0$). Entry 1 is stalled. $T_2$ allocated to Entry 2 (Bank 1). |
| **C3** | 15.0 ns | `ARVALID` for $T_3$ | Bank 2 accesses SRAM for $T_0$. Bank 2 Arbiter now grants Entry 1 ($T_1$) via Round-Robin rotation. $T_3$ allocated to Entry 3 (Bank 0). |
| **C4** | 20.0 ns | Write Commit $T_0$, `BVALID` | $T_0$ commits write to Bank 2 SRAM macro. Transitions to `CAM_STATE_RESP_READY`. B channel drives `BID=0x1`. Bank 0 grants $T_3$ immediately. |
| **C5** | 25.0 ns | Write Commit $T_1$, Bank 0 Access | $T_1$ commits write to Bank 2 SRAM macro. B channel drives `BID=0x2`. Bank 0 reads word for $T_3$. Bank 1 grants $T_2$. |
| **C6** | 30.0 ns | **First Read Data Return ($T_3$)** | $T_3$ read data captured from Bank 0. ROB selects $T_3$ for R channel. **`RVALID` asserts with `RID=0x7` and `RLAST=1`!** (Out-of-Order: $T_3$ was issued *after* $T_2$, but finishes *first*!). |
| **C7** | 35.0 ns | **Second Read Data Return ($T_2$)** | $T_2$ read data captured from Bank 1. ROB drives R channel with `RID=0x4` and `RLAST=1`. All transactions completed. |
| **C8** | 40.0 ns | Idle / Clean State | All CAM entries retired to `CAM_STATE_FREE`. Zero outstanding transactions. |
