// SPDX-License-Identifier: MIT AND CERN-OHL-S-2.0
//
// Original module shape:
//   Copyright (c) 2022 Hugh Perkins (upstream VeriGPU, MIT)
//
// PopSolutions AXI4 skeleton rewrite (this file's body):
//   Copyright (c) 2026 PopSolutions Cooperative (CERN-OHL-S v2)
//
// Per ADR-006 (Internal bus: AXI4) and the migration plan in
// docs/popsolutions/architecture/PARAMETER_TAXONOMY.md, the original
// behavioural mock that lived here has been replaced with an AXI4-backed
// skeleton. The external port surface is preserved verbatim so that
// upstream consumers (gpu_die.sv, test/behav/*) continue to compile and
// simulate without modification — that migration is a separate PR.
//
// Internal composition:
//
//                 core1_*    contr_rd_*    contr_wr_*
//                    │           │             │
//                    ▼           ▼             ▼
//             ┌──────────────────────┐  ┌──────────────┐
//             │  arbiter (prio: c1)  │  │ loader port  │
//             └──────────────────────┘  └──────────────┘
//                    │                         │
//                    ▼                         │
//          global_mem_axi4_adapter             │
//          (core_mem_* ↔ AXI4 master)          │
//                    │                         │
//                    ▼                         ▼
//                  axi4_mem_model (256-bit / 48-bit subordinate)
//
// Why this shape:
//   * core1_*  — hot path for the upstream RISC-V core. Wired straight
//                through global_mem_axi4_adapter to the AXI4 manager
//                (32-bit core word ↔ 256-bit cache line via WSTRB and
//                slot-mux, matching the published wrapper semantics).
//   * contr_wr_* — controller program-load writes. Mapped to the
//                axi4_mem_model loader back-door (single-cycle, no
//                handshake). Simulation-only path; production builds
//                with a real DDR controller will route this through a
//                real AXI4 write instead.
//   * contr_rd_* — controller readback. Multiplexed onto the same
//                adapter as core1_*; core1_* wins ties. Acks are pulsed
//                back to the controller after the AXI4 read completes.
//
// What this skeleton intentionally does NOT do (deferred to follow-ups):
//   * Real DDR3/DDR5 controller (LiteDRAM) — see ADR-006. axi4_mem_model
//     is the placeholder subordinate; replacing it is a single
//     instantiation swap once the LiteDRAM wrapper lands.
//   * Pipelined / multi-outstanding transactions on either port group.
//   * Migration of upstream consumers (gpu_die.sv, core.sv, etc.) off
//     this module's bespoke port surface — Phase-3 of the taxonomy
//     migration plan.
//
// Width handling:
//   * External ports stay 32-bit (`addr_width`, `data_width`) so that
//     unchanged callers continue to compile.
//   * Internal AXI4 wires use `phys_addr_width = 48` and
//     `mem_data_width = 256` per PARAMETER_TAXONOMY.md. The adapter
//     zero-extends 32-bit addresses into the wider AXI4 address bus.
//
// Reset convention:
//   * The upstream port is `rst` (active-low — see `if(~rst)` in the
//     original body). The AXI4 sub-modules use `rst_n` (also active-low).
//     Both are equivalent here; we just pass `rst` straight through as
//     `rst_n`.

`default_nettype none

module global_mem_controller (
    input wire clk,
    input wire rst,

    // ---------- core1_* port group (hot path, shared addr) ----------
    input  wire                        core1_rd_req,
    input  wire                        core1_wr_req,
    input  wire [addr_width - 1:0]     core1_addr,
    output wire [data_width - 1:0]     core1_rd_data,
    input  wire [data_width - 1:0]     core1_wr_data,
    output wire                        core1_busy,
    output wire                        core1_ack,

    // ---------- contr_* port group (program loader / readback) ------
    input  wire                        contr_wr_en,
    input  wire                        contr_rd_en,
    input  wire [addr_width - 1:0]     contr_wr_addr,
    input  wire [data_width - 1:0]     contr_wr_data,
    input  wire [addr_width - 1:0]     contr_rd_addr,
    output reg  [data_width - 1:0]     contr_rd_data,
    output reg                         contr_rd_ack
);

    // ===================================================================
    // AXI4 master ↔ subordinate net glue
    // ===================================================================
    wire [axi4_id_width-1:0]    ax_awid;
    wire [phys_addr_width-1:0]  ax_awaddr;
    wire [axi4_len_width-1:0]   ax_awlen;
    wire [axi4_size_width-1:0]  ax_awsize;
    wire [axi4_burst_width-1:0] ax_awburst;
    wire                        ax_awvalid;
    wire                        ax_awready;

    wire [mem_data_width-1:0]   ax_wdata;
    wire [axi4_strb_width-1:0]  ax_wstrb;
    wire                        ax_wlast;
    wire                        ax_wvalid;
    wire                        ax_wready;

    wire [axi4_id_width-1:0]    ax_bid;
    wire [axi4_resp_width-1:0]  ax_bresp;
    wire                        ax_bvalid;
    wire                        ax_bready;

    wire [axi4_id_width-1:0]    ax_arid;
    wire [phys_addr_width-1:0]  ax_araddr;
    wire [axi4_len_width-1:0]   ax_arlen;
    wire [axi4_size_width-1:0]  ax_arsize;
    wire [axi4_burst_width-1:0] ax_arburst;
    wire                        ax_arvalid;
    wire                        ax_arready;

    wire [axi4_id_width-1:0]    ax_rid;
    wire [mem_data_width-1:0]   ax_rdata;
    wire [axi4_resp_width-1:0]  ax_rresp;
    wire                        ax_rlast;
    wire                        ax_rvalid;
    wire                        ax_rready;

    // ===================================================================
    // Arbiter for the shared core_mem_* port on global_mem_axi4_adapter.
    //
    // Two requesters fight for one core-mem slot:
    //   - core1_*    (rd or wr; priority = HIGH)
    //   - contr_rd_* (read-only; priority = LOW, only when core1 has
    //                 nothing to do AND no contr_rd is in flight)
    //
    // contr_wr_* does NOT compete for this port — those writes go
    // straight to the axi4_mem_model loader back-door, which has no
    // handshake and completes in one cycle.
    //
    // State: a single bit `contr_rd_inflight` records whether the most
    // recent core_mem_* transaction was issued on behalf of contr_rd
    // (so we can route the response back correctly and pulse
    // contr_rd_ack instead of core1_ack).
    // ===================================================================

    reg                       contr_rd_inflight;
    reg [addr_width-1:0]      contr_rd_addr_q;
    // Pending bit: set when a contr_rd_en pulse arrives while core1 is
    // active or another contr_rd is already in flight. The bit is held
    // until the arbiter is able to issue the deferred read, at which
    // point grant_contr_rd fires and the inflight tracker takes over.
    reg                       contr_rd_pending;
    reg [addr_width-1:0]      contr_rd_pending_addr;

    // Priority: core1 wins. contr_rd is granted when core1 is idle
    // (no rd or wr request this cycle) AND we don't already have a
    // contr_rd in flight. The request can be either a fresh
    // contr_rd_en pulse or a previously latched pending request.
    wire core1_active        = core1_rd_req | core1_wr_req;
    wire contr_rd_req_now    = contr_rd_en | contr_rd_pending;
    wire [addr_width-1:0] contr_rd_req_addr =
        contr_rd_pending ? contr_rd_pending_addr : contr_rd_addr;
    // Don't issue a new contr_rd while the adapter is still busy with
    // a previous transaction (core1 or otherwise) — `cm_busy` covers
    // every in-flight case from the adapter's perspective.
    wire grant_contr_rd      = contr_rd_req_now & ~core1_active
                               & ~contr_rd_inflight & ~cm_busy;

    wire                       cm_rd_req    = core1_rd_req | grant_contr_rd;
    wire                       cm_wr_req    = core1_wr_req;
    wire [addr_width-1:0]      cm_addr      = core1_active ? core1_addr : contr_rd_req_addr;
    wire [data_width-1:0]      cm_wr_data   = core1_wr_data;
    wire [data_width-1:0]      cm_rd_data;
    wire                       cm_busy;
    wire                       cm_ack;

    // ===================================================================
    // Track whether the in-flight transaction is core1 or contr_rd, so
    // the response demultiplexer routes ack/data back to the right port.
    // ===================================================================
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            contr_rd_inflight     <= 1'b0;
            contr_rd_addr_q       <= '0;
            contr_rd_pending      <= 1'b0;
            contr_rd_pending_addr <= '0;
            contr_rd_data         <= '0;
            contr_rd_ack          <= 1'b0;
        end else begin
            // default: ack pulses low
            contr_rd_ack <= 1'b0;

            // Latch a fresh contr_rd_en pulse when we cannot service it
            // this cycle (core1 won the arbiter or there's already a
            // contr_rd in flight). The pending bit is consumed below
            // when grant_contr_rd finally fires.
            if (contr_rd_en && !grant_contr_rd) begin
                contr_rd_pending      <= 1'b1;
                contr_rd_pending_addr <= contr_rd_addr;
            end

            // When the arbiter grants a contr_rd this cycle, mark it
            // in flight, capture the address, and clear the pending
            // bit (which may or may not have been set — either way
            // we're now servicing it).
            if (grant_contr_rd) begin
                contr_rd_inflight <= 1'b1;
                contr_rd_addr_q   <= contr_rd_req_addr;
                contr_rd_pending  <= 1'b0;
            end

            // When the adapter pulses cm_ack and we are tracking a
            // contr_rd transaction, capture the data and pulse
            // contr_rd_ack (the core1_ack output stays low because the
            // demux below masks it).
            if (cm_ack && contr_rd_inflight) begin
                contr_rd_data     <= cm_rd_data;
                contr_rd_ack      <= 1'b1;
                contr_rd_inflight <= 1'b0;
            end
        end
    end

    // ===================================================================
    // Response demultiplex: ack / rd_data are routed to whichever
    // requester is currently tracked. core1_busy stays asserted whenever
    // the adapter is busy AND the in-flight transaction belongs to core1
    // (otherwise core1 is free to issue new requests once contr_rd
    // completes — but in practice they don't overlap since contr_rd is
    // only granted when core1 is idle).
    // ===================================================================
    assign core1_rd_data = cm_rd_data;
    assign core1_ack     = cm_ack & ~contr_rd_inflight;
    assign core1_busy    = cm_busy & ~contr_rd_inflight;

    // ===================================================================
    // global_mem_axi4_adapter: bespoke core-mem ↔ AXI4 master
    // ===================================================================
    global_mem_axi4_adapter u_adapter (
        .clk(clk), .rst_n(rst),

        .core_mem_rd_req(cm_rd_req),
        .core_mem_wr_req(cm_wr_req),
        .core_mem_addr(cm_addr),
        .core_mem_rd_data(cm_rd_data),
        .core_mem_wr_data(cm_wr_data),
        .core_mem_busy(cm_busy),
        .core_mem_ack(cm_ack),

        .m_awid(ax_awid), .m_awaddr(ax_awaddr), .m_awlen(ax_awlen),
        .m_awsize(ax_awsize), .m_awburst(ax_awburst),
        .m_awvalid(ax_awvalid), .m_awready(ax_awready),

        .m_wdata(ax_wdata), .m_wstrb(ax_wstrb), .m_wlast(ax_wlast),
        .m_wvalid(ax_wvalid), .m_wready(ax_wready),

        .m_bid(ax_bid), .m_bresp(ax_bresp),
        .m_bvalid(ax_bvalid), .m_bready(ax_bready),

        .m_arid(ax_arid), .m_araddr(ax_araddr), .m_arlen(ax_arlen),
        .m_arsize(ax_arsize), .m_arburst(ax_arburst),
        .m_arvalid(ax_arvalid), .m_arready(ax_arready),

        .m_rid(ax_rid), .m_rdata(ax_rdata), .m_rresp(ax_rresp),
        .m_rlast(ax_rlast), .m_rvalid(ax_rvalid), .m_rready(ax_rready)
    );

    // ===================================================================
    // axi4_mem_model: 256-bit AXI4 subordinate with byte-addressable
    // 32-bit loader back-door (used for contr_wr_*).
    //
    // DEPTH_WORDS=256 cache lines × 32 bytes/line = 8 KiB total. Matches
    // the early-stage smoke-test footprint; will be sized up when real
    // workloads land.
    // ===================================================================
    axi4_mem_model #(.DEPTH_WORDS(256)) u_mem (
        .clk(clk), .rst_n(rst),

        .s_awid(ax_awid), .s_awaddr(ax_awaddr), .s_awlen(ax_awlen),
        .s_awsize(ax_awsize), .s_awburst(ax_awburst),
        .s_awvalid(ax_awvalid), .s_awready(ax_awready),

        .s_wdata(ax_wdata), .s_wstrb(ax_wstrb), .s_wlast(ax_wlast),
        .s_wvalid(ax_wvalid), .s_wready(ax_wready),

        .s_bid(ax_bid), .s_bresp(ax_bresp),
        .s_bvalid(ax_bvalid), .s_bready(ax_bready),

        .s_arid(ax_arid), .s_araddr(ax_araddr), .s_arlen(ax_arlen),
        .s_arsize(ax_arsize), .s_arburst(ax_arburst),
        .s_arvalid(ax_arvalid), .s_arready(ax_arready),

        .s_rid(ax_rid), .s_rdata(ax_rdata), .s_rresp(ax_rresp),
        .s_rlast(ax_rlast), .s_rvalid(ax_rvalid), .s_rready(ax_rready),

        // contr_wr_* ⇒ loader back-door. The contr_wr_addr is a 32-bit
        // upstream address; zero-extend into the 48-bit phys_addr_width
        // bus the loader port expects.
        .loader_en(contr_wr_en),
        .loader_addr({{(phys_addr_width-addr_width){1'b0}}, contr_wr_addr}),
        .loader_data(contr_wr_data)
    );

endmodule
