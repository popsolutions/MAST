// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Test wrapper: instantiates axi4_master_simple connected to axi4_mem_model
// over the AXI4 5-channel bundle. Exposes the master's user-side req/resp
// interface as the testbench-visible top-level.
//
// Used only by verif/axi4_master_simple/ — not part of the deliverable RTL.

`default_nettype none

module axi4_master_mem_wrapper (
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        req_we,
    input  wire [phys_addr_width-1:0]  req_addr,
    input  wire [mem_data_width-1:0]   req_wdata,
    input  wire [axi4_strb_width-1:0]  req_wstrb,
    input  wire                        req_start,
    output wire                        req_busy,
    output wire                        req_done,
    output wire [mem_data_width-1:0]   req_rdata,
    output wire                        req_err
);

    // AXI4 channels between master and mem
    wire [axi4_id_width-1:0]    axi_awid;
    wire [phys_addr_width-1:0]  axi_awaddr;
    wire [axi4_len_width-1:0]   axi_awlen;
    wire [axi4_size_width-1:0]  axi_awsize;
    wire [axi4_burst_width-1:0] axi_awburst;
    wire                        axi_awvalid;
    wire                        axi_awready;

    wire [mem_data_width-1:0]   axi_wdata;
    wire [axi4_strb_width-1:0]  axi_wstrb;
    wire                        axi_wlast;
    wire                        axi_wvalid;
    wire                        axi_wready;

    wire [axi4_id_width-1:0]    axi_bid;
    wire [axi4_resp_width-1:0]  axi_bresp;
    wire                        axi_bvalid;
    wire                        axi_bready;

    wire [axi4_id_width-1:0]    axi_arid;
    wire [phys_addr_width-1:0]  axi_araddr;
    wire [axi4_len_width-1:0]   axi_arlen;
    wire [axi4_size_width-1:0]  axi_arsize;
    wire [axi4_burst_width-1:0] axi_arburst;
    wire                        axi_arvalid;
    wire                        axi_arready;

    wire [axi4_id_width-1:0]    axi_rid;
    wire [mem_data_width-1:0]   axi_rdata;
    wire [axi4_resp_width-1:0]  axi_rresp;
    wire                        axi_rlast;
    wire                        axi_rvalid;
    wire                        axi_rready;

    axi4_master_simple master (
        .clk(clk), .rst_n(rst_n),
        .req_we(req_we), .req_addr(req_addr), .req_wdata(req_wdata),
        .req_wstrb(req_wstrb), .req_start(req_start),
        .req_busy(req_busy), .req_done(req_done),
        .req_rdata(req_rdata), .req_err(req_err),

        .m_awid(axi_awid), .m_awaddr(axi_awaddr), .m_awlen(axi_awlen),
        .m_awsize(axi_awsize), .m_awburst(axi_awburst),
        .m_awvalid(axi_awvalid), .m_awready(axi_awready),

        .m_wdata(axi_wdata), .m_wstrb(axi_wstrb), .m_wlast(axi_wlast),
        .m_wvalid(axi_wvalid), .m_wready(axi_wready),

        .m_bid(axi_bid), .m_bresp(axi_bresp),
        .m_bvalid(axi_bvalid), .m_bready(axi_bready),

        .m_arid(axi_arid), .m_araddr(axi_araddr), .m_arlen(axi_arlen),
        .m_arsize(axi_arsize), .m_arburst(axi_arburst),
        .m_arvalid(axi_arvalid), .m_arready(axi_arready),

        .m_rid(axi_rid), .m_rdata(axi_rdata), .m_rresp(axi_rresp),
        .m_rlast(axi_rlast), .m_rvalid(axi_rvalid), .m_rready(axi_rready)
    );

    axi4_mem_model #(.DEPTH_WORDS(256)) mem (
        .clk(clk), .rst_n(rst_n),
        .s_awid(axi_awid), .s_awaddr(axi_awaddr), .s_awlen(axi_awlen),
        .s_awsize(axi_awsize), .s_awburst(axi_awburst),
        .s_awvalid(axi_awvalid), .s_awready(axi_awready),

        .s_wdata(axi_wdata), .s_wstrb(axi_wstrb), .s_wlast(axi_wlast),
        .s_wvalid(axi_wvalid), .s_wready(axi_wready),

        .s_bid(axi_bid), .s_bresp(axi_bresp),
        .s_bvalid(axi_bvalid), .s_bready(axi_bready),

        .s_arid(axi_arid), .s_araddr(axi_araddr), .s_arlen(axi_arlen),
        .s_arsize(axi_arsize), .s_arburst(axi_arburst),
        .s_arvalid(axi_arvalid), .s_arready(axi_arready),

        .s_rid(axi_rid), .s_rdata(axi_rdata), .s_rresp(axi_rresp),
        .s_rlast(axi_rlast), .s_rvalid(axi_rvalid), .s_rready(axi_rready)
    );

endmodule
