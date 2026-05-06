// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Composition wrapper that takes the bespoke core-side memory interface
// (rd_req / wr_req / addr / rd_data / wr_data / busy / ack — same shape as
// core.sv exposes and as src/global_mem_controller.sv accepts on its
// `core1_*` ports) and presents a full AXI4 master to the parent.
//
// Internal composition:
//
//   core-iface ──► core_axi4_adapter ──► axi4_master_simple ──► AXI4 master
//                  (32-bit ↔ 256-bit                            (5 channels
//                   slot-mux + WSTRB)                            exposed up)
//
// Both sub-modules already exist under src/popsolutions/axi4/. This file
// is purely a structural composition; no new datapath or control logic is
// introduced here. That's why PR-2a is a small step: the substantive logic
// — slot-muxing for reads, WSTRB byte-enables for writes, single-outstanding
// AXI4 master FSM — was landed earlier in the AXI4 introduction PRs and is
// reused here verbatim.
//
// Intended consumers:
//   * gpu_die.sv (PR-2b will migrate it from global_mem_controller).
//   * Any future Compute Unit / DMA / scheduler block that has the bespoke
//     core memory interface and needs to talk to an AXI4 backbone (e.g.,
//     LiteDRAM controller, HBM controller, system-bus interconnect once
//     it lands).
//
// What this wrapper intentionally does NOT do:
//   * Arbitrate between multiple core-side requesters. Single producer.
//   * Handle the upstream `contr_*` (controller) port group from
//     global_mem_controller — those have separate read+write ports for
//     program loading and live in gpu_controller.sv. Migration of that
//     path is a follow-up; the loader back-door on axi4_mem_model
//     covers most of the testbench-level needs in the interim.
//   * Cache or buffer cache-line reads. Each core-side request issues one
//     full AXI4 transaction.
//
// Limitations inherited from sub-modules:
//   * 32-bit aligned core accesses only (lower 2 bits of addr ignored).
//   * Single outstanding transaction at a time.
//   * Single-beat AXI4 (AxLEN = 0); bursts are deferred to follow-up issues.
//
// =====================================================================
//  PUBLIC CONTRACT — core_mem_rd_data stability (issue #27)
// =====================================================================
//
// Stability invariant (NORMATIVE — consumers rely on this):
//
//   Once `core_mem_ack` pulses for a read transaction, the value driven on
//   `core_mem_rd_data` on that ack cycle MUST remain bit-stable on every
//   subsequent clock cycle until — but not including — the cycle on which
//   the next `core_mem_rd_req` or `core_mem_wr_req` is sampled high by
//   this adapter.
//
//   Restated: while the bus is idle (no new req), `core_mem_rd_data` does
//   NOT glitch, does NOT change value, and does NOT go to X. The last
//   read result is held verbatim. Consumers (e.g. global_mem_controller's
//   `core1_*` port group, gpu_die.sv, and any current/future block that
//   re-samples the read datum after the ack cycle) MUST be able to rely
//   on this for correctness.
//
// Why this contract is written down:
//
//   The current implementation satisfies this trivially: it is single-
//   outstanding and `core_mem_rd_data` is registered inside
//   axi4_master_simple's `req_rdata` and held in place by
//   core_axi4_adapter's slot mux until the next request arrives. No
//   active read driver chooses to change the value while the bus is
//   idle. That is an *implementation* property today, not a
//   *port-level* property.
//
//   A future multi-outstanding adapter, response-forwarding optimization,
//   or a refactor that drives `core_mem_rd_data` directly off `m_rdata`
//   (or off any signal that toggles between transactions) could silently
//   break this invariant — the affected consumer code (e.g. cm_rd_data
//   re-sampling in the controller path that PR #25's regression test
//   covers) would then glitch on the cycle after ack with no compile-time
//   error and no test failure unless that test is timing-precise.
//
//   This block elevates the invariant to a *port contract* of
//   global_mem_axi4_adapter. Any future implementation MUST preserve it.
//   If a future design genuinely cannot honor it (e.g. true multi-
//   outstanding with out-of-order response forwarding), the public port
//   surface MUST be renamed (e.g. `core_mem_rd_data_valid` + a separate
//   capture register exposed to the consumer) so existing consumers
//   break loudly at integration time rather than silently at runtime.
//
// Test that enforces this contract:
//
//   verif/global_mem_axi4_adapter/test_global_mem_axi4_adapter.py ::
//     test_rd_data_stable_between_requests
//
//   The test issues a read, captures `core_mem_rd_data` on the ack
//   cycle, then holds the bus idle for >=8 clocks while re-sampling
//   `core_mem_rd_data` on every cycle. Every sample must equal the
//   on-ack value.
//
// =====================================================================

`default_nettype none

module global_mem_axi4_adapter (
    input  wire                        clk,
    input  wire                        rst_n,

    // --------- Core-side memory interface (bespoke) ---------
    // Identical port shape to core_axi4_adapter's input side and to
    // global_mem_controller's `core1_*` group (after rename), so this
    // module is a drop-in replacement candidate for the latter once the
    // parent also instantiates an AXI4 slave (e.g., axi4_mem_model).
    input  wire                        core_mem_rd_req,
    input  wire                        core_mem_wr_req,
    input  wire [addr_width-1:0]       core_mem_addr,
    output wire [data_width-1:0]       core_mem_rd_data,
    input  wire [data_width-1:0]       core_mem_wr_data,
    output wire                        core_mem_busy,
    output wire                        core_mem_ack,

    // --------- AXI4 master (5 channels) ---------
    output wire [axi4_id_width-1:0]    m_awid,
    output wire [phys_addr_width-1:0]  m_awaddr,
    output wire [axi4_len_width-1:0]   m_awlen,
    output wire [axi4_size_width-1:0]  m_awsize,
    output wire [axi4_burst_width-1:0] m_awburst,
    output wire                        m_awvalid,
    input  wire                        m_awready,

    output wire [mem_data_width-1:0]   m_wdata,
    output wire [axi4_strb_width-1:0]  m_wstrb,
    output wire                        m_wlast,
    output wire                        m_wvalid,
    input  wire                        m_wready,

    input  wire [axi4_id_width-1:0]    m_bid,
    input  wire [axi4_resp_width-1:0]  m_bresp,
    input  wire                        m_bvalid,
    output wire                        m_bready,

    output wire [axi4_id_width-1:0]    m_arid,
    output wire [phys_addr_width-1:0]  m_araddr,
    output wire [axi4_len_width-1:0]   m_arlen,
    output wire [axi4_size_width-1:0]  m_arsize,
    output wire [axi4_burst_width-1:0] m_arburst,
    output wire                        m_arvalid,
    input  wire                        m_arready,

    input  wire [axi4_id_width-1:0]    m_rid,
    input  wire [mem_data_width-1:0]   m_rdata,
    input  wire [axi4_resp_width-1:0]  m_rresp,
    input  wire                        m_rlast,
    input  wire                        m_rvalid,
    output wire                        m_rready
);

    // ----------- Internal nets between sub-modules -----------
    wire                        req_we;
    wire [phys_addr_width-1:0]  req_addr;
    wire [mem_data_width-1:0]   req_wdata;
    wire [axi4_strb_width-1:0]  req_wstrb;
    wire                        req_start;
    wire                        req_busy;
    wire                        req_done;
    wire [mem_data_width-1:0]   req_rdata;
    wire                        req_err;

    core_axi4_adapter u_core_adapter (
        .clk(clk), .rst_n(rst_n),
        .core_mem_rd_req(core_mem_rd_req),
        .core_mem_wr_req(core_mem_wr_req),
        .core_mem_addr(core_mem_addr),
        .core_mem_rd_data(core_mem_rd_data),
        .core_mem_wr_data(core_mem_wr_data),
        .core_mem_busy(core_mem_busy),
        .core_mem_ack(core_mem_ack),
        .m_req_we(req_we),
        .m_req_addr(req_addr),
        .m_req_wdata(req_wdata),
        .m_req_wstrb(req_wstrb),
        .m_req_start(req_start),
        .m_req_busy(req_busy),
        .m_req_done(req_done),
        .m_req_rdata(req_rdata),
        .m_req_err(req_err)
    );

    axi4_master_simple u_master (
        .clk(clk), .rst_n(rst_n),
        .req_we(req_we),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),
        .req_start(req_start),
        .req_busy(req_busy),
        .req_done(req_done),
        .req_rdata(req_rdata),
        .req_err(req_err),

        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_awvalid(m_awvalid), .m_awready(m_awready),

        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),

        .m_bid(m_bid), .m_bresp(m_bresp),
        .m_bvalid(m_bvalid), .m_bready(m_bready),

        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_arvalid(m_arvalid), .m_arready(m_arready),

        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

endmodule
