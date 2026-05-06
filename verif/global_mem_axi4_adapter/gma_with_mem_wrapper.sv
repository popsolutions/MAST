// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Test wrapper for src/popsolutions/axi4/global_mem_axi4_adapter.sv.
//
// Connects the adapter's AXI4 master ports to an axi4_mem_model slave,
// exposing only the core-side bespoke memory interface to the cocotb
// testbench. This is the topology that gpu_die.sv will use after PR-2b:
// adapter + mem model wired side-by-side.
//
// Used only by verif/global_mem_axi4_adapter/.

`default_nettype none

module gma_with_mem_wrapper (
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        core_mem_rd_req,
    input  wire                        core_mem_wr_req,
    input  wire [addr_width-1:0]       core_mem_addr,
    output wire [data_width-1:0]       core_mem_rd_data,
    input  wire [data_width-1:0]       core_mem_wr_data,
    output wire                        core_mem_busy,
    output wire                        core_mem_ack
);

    // --------- AXI4 net glue between adapter and mem model ---------
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

    global_mem_axi4_adapter u_adapter (
        .clk(clk), .rst_n(rst_n),
        .core_mem_rd_req(core_mem_rd_req),
        .core_mem_wr_req(core_mem_wr_req),
        .core_mem_addr(core_mem_addr),
        .core_mem_rd_data(core_mem_rd_data),
        .core_mem_wr_data(core_mem_wr_data),
        .core_mem_busy(core_mem_busy),
        .core_mem_ack(core_mem_ack),

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

    axi4_mem_model #(.DEPTH_WORDS(256)) u_mem (
        .clk(clk), .rst_n(rst_n),
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
        .loader_en(1'b0),
        .loader_addr('0),
        .loader_data('0)
    );

endmodule
