// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// MAST AXI4 profile: parameters, channel payload typedefs, and protocol
// constants. See ./README.md for the profile rationale and ADR-006 ("Internal
// bus: AXI4") for the architectural decision.
//
// This file is compiled as a source file alongside src/const.sv (which it
// depends on for mem_data_width, phys_addr_width, cache_line_bytes), making
// its declarations globally visible in the iverilog/verilator/yosys
// compilation unit.
//
// Tooling: requires SystemVerilog 2012 mode. Tested with iverilog -g2012 and
// Verilator >= 4.200.

// --- AXI4 profile parameters ---

parameter axi4_id_width    = 4;   // 16 outstanding transactions per master
parameter axi4_len_width   = 8;   // up to 256-beat bursts (AMBA AXI4 IHI 0022)
parameter axi4_size_width  = 3;
parameter axi4_burst_width = 2;
parameter axi4_resp_width  = 2;
parameter axi4_cache_width = 4;
parameter axi4_prot_width  = 3;
parameter axi4_qos_width   = 4;

parameter axi4_strb_width  = mem_data_width / 8;       // 32 byte enables for 256-bit data

// --- AXI4 protocol constants (per AMBA AXI4 IHI 0022) ---

// AxBURST encoding
parameter [1:0] AXI4_BURST_FIXED = 2'b00;
parameter [1:0] AXI4_BURST_INCR  = 2'b01;
parameter [1:0] AXI4_BURST_WRAP  = 2'b10;
// 2'b11 reserved

// xRESP encoding
parameter [1:0] AXI4_RESP_OKAY   = 2'b00;
parameter [1:0] AXI4_RESP_EXOKAY = 2'b01;  // unused — no exclusive accesses in MAST profile
parameter [1:0] AXI4_RESP_SLVERR = 2'b10;
parameter [1:0] AXI4_RESP_DECERR = 2'b11;

// AxSIZE for our full-width cache-line beat (256 bits = 32 bytes -> log2(32) = 5)
parameter [2:0] AXI4_SIZE_FULL = 3'd5;

// --- channel payload typedefs ---
//
// These structs are defined for future use (e.g., interface bundles, scoreboard
// records in cocotb testbenches). Current RTL modules use individual signals
// in their port lists for maximum tooling compatibility (iverilog/yosys still
// have rough edges with struct-typed ports).

typedef struct packed {
    logic [axi4_id_width-1:0]    id;
    logic [phys_addr_width-1:0]  addr;
    logic [axi4_len_width-1:0]   len;
    logic [axi4_size_width-1:0]  size;
    logic [axi4_burst_width-1:0] burst;
    logic                        lock;
    logic [axi4_cache_width-1:0] cache;
    logic [axi4_prot_width-1:0]  prot;
    logic [axi4_qos_width-1:0]   qos;
} axi4_addr_t;

typedef struct packed {
    logic [mem_data_width-1:0]   data;
    logic [axi4_strb_width-1:0]  strb;
    logic                        last;
} axi4_w_t;

typedef struct packed {
    logic [axi4_id_width-1:0]    id;
    logic [axi4_resp_width-1:0]  resp;
} axi4_b_t;

typedef struct packed {
    logic [axi4_id_width-1:0]    id;
    logic [mem_data_width-1:0]   data;
    logic [axi4_resp_width-1:0]  resp;
    logic                        last;
} axi4_r_t;
