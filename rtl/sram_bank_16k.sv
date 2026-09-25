// ============================================================================
// File: rtl/sram_bank_16k.sv
// Description: Synthesizable 16KB Single-Port Synchronous SRAM Bank (2048x64)
//              with byte-write strobe enables. Fully compliant with OpenRAM
//              SkyWater 130nm macro footprint & timing specs.
// Author: Abhijit Karale (Principal Silicon Architect & Staff DV Engineer)
// Target Tech: SkyWater 130nm @ 200 MHz (5.0 ns period, 1-cycle read latency)
// ============================================================================

`timescale 1ns/1ps

module sram_bank_16k #(
  parameter int unsigned ADDR_WIDTH = 11, // 2048 words
  parameter int unsigned DATA_WIDTH = 64, // 64-bit word width
  parameter int unsigned STRB_WIDTH = 8   // 8-bit byte enable
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  cs,       // Chip Select (Active High)
  input  logic                  we,       // Write Enable (Active High)
  input  logic [ADDR_WIDTH-1:0] addr,     // Word Address [10:0]
  input  logic [DATA_WIDTH-1:0] wdata,    // Write Data [63:0]
  input  logic [STRB_WIDTH-1:0] wstrb,    // Byte Write Strobes [7:0]
  output logic [DATA_WIDTH-1:0] rdata     // Read Data [63:0] (Synchronous 1-cycle)
);

  // 2048 x 64-bit Memory Array (16,384 Bytes)
  logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

  // Registered read output (Standard SRAM Macro architecture)
  logic [DATA_WIDTH-1:0] rdata_reg;
  assign rdata = rdata_reg;

  // Synchronous Read/Write with Byte-level Masking
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdata_reg <= '0;
    end else if (cs) begin
      if (we) begin
        // Byte-wise write operation
        for (int unsigned b = 0; b < STRB_WIDTH; b++) begin
          if (wstrb[b]) begin
            mem[addr][b*8 +: 8] <= wdata[b*8 +: 8];
          end
        end
      end else begin
        // Synchronous 1-cycle latency read operation
        rdata_reg <= mem[addr];
      end
    end
  end

endmodule : sram_bank_16k
