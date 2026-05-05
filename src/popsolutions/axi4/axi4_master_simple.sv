// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Simple AXI4 master with a single-transaction-at-a-time req/resp interface
// for user logic (Compute Unit, controller). Translates the simple interface
// to the 5-channel AXI4 protocol on the master side.
//
// Profile (Generation A — matches axi4_mem_model):
//   * Single outstanding transaction (no pipelining).
//   * Single-beat reads/writes only (AxLEN = 0).
//   * INCR burst type, full-width beats (AxSIZE = AXI4_SIZE_FULL).
//   * Bursts and pipelining are deferred to follow-up issues.

`default_nettype none

module axi4_master_simple (
    input  wire                        clk,
    input  wire                        rst_n,

    // User request interface
    input  wire                        req_we,
    input  wire [phys_addr_width-1:0]  req_addr,
    input  wire [mem_data_width-1:0]   req_wdata,
    input  wire [axi4_strb_width-1:0]  req_wstrb,
    input  wire                        req_start,
    output reg                         req_busy,
    output reg                         req_done,
    output reg  [mem_data_width-1:0]   req_rdata,
    output reg                         req_err,

    // AXI4 master — AW
    output reg  [axi4_id_width-1:0]    m_awid,
    output reg  [phys_addr_width-1:0]  m_awaddr,
    output reg  [axi4_len_width-1:0]   m_awlen,
    output reg  [axi4_size_width-1:0]  m_awsize,
    output reg  [axi4_burst_width-1:0] m_awburst,
    output reg                         m_awvalid,
    input  wire                        m_awready,

    // AXI4 master — W
    output reg  [mem_data_width-1:0]   m_wdata,
    output reg  [axi4_strb_width-1:0]  m_wstrb,
    output reg                         m_wlast,
    output reg                         m_wvalid,
    input  wire                        m_wready,

    // AXI4 master — B
    input  wire [axi4_id_width-1:0]    m_bid,
    input  wire [axi4_resp_width-1:0]  m_bresp,
    input  wire                        m_bvalid,
    output reg                         m_bready,

    // AXI4 master — AR
    output reg  [axi4_id_width-1:0]    m_arid,
    output reg  [phys_addr_width-1:0]  m_araddr,
    output reg  [axi4_len_width-1:0]   m_arlen,
    output reg  [axi4_size_width-1:0]  m_arsize,
    output reg  [axi4_burst_width-1:0] m_arburst,
    output reg                         m_arvalid,
    input  wire                        m_arready,

    // AXI4 master — R
    input  wire [axi4_id_width-1:0]    m_rid,
    input  wire [mem_data_width-1:0]   m_rdata,
    input  wire [axi4_resp_width-1:0]  m_rresp,
    input  wire                        m_rlast,
    input  wire                        m_rvalid,
    output reg                         m_rready
);

    localparam [2:0] IDLE  = 3'd0,
                     WR_AW = 3'd1,
                     WR_B  = 3'd2,
                     RD_AR = 3'd3,
                     RD_R  = 3'd4;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            req_busy  <= 1'b0;
            req_done  <= 1'b0;
            req_rdata <= '0;
            req_err   <= 1'b0;

            m_awid    <= '0;
            m_awaddr  <= '0;
            m_awlen   <= '0;
            m_awsize  <= AXI4_SIZE_FULL;
            m_awburst <= AXI4_BURST_INCR;
            m_awvalid <= 1'b0;

            m_wdata   <= '0;
            m_wstrb   <= '0;
            m_wlast   <= 1'b0;
            m_wvalid  <= 1'b0;

            m_bready  <= 1'b0;

            m_arid    <= '0;
            m_araddr  <= '0;
            m_arlen   <= '0;
            m_arsize  <= AXI4_SIZE_FULL;
            m_arburst <= AXI4_BURST_INCR;
            m_arvalid <= 1'b0;

            m_rready  <= 1'b0;
        end else begin
            req_done <= 1'b0;  // default — pulse only on transaction completion

            case (state)
                IDLE: begin
                    if (req_start) begin
                        req_busy <= 1'b1;
                        req_err  <= 1'b0;
                        if (req_we) begin
                            // Drive AW and W simultaneously for single-beat write
                            m_awid    <= '0;
                            m_awaddr  <= req_addr;
                            m_awlen   <= '0;
                            m_awsize  <= AXI4_SIZE_FULL;
                            m_awburst <= AXI4_BURST_INCR;
                            m_awvalid <= 1'b1;

                            m_wdata   <= req_wdata;
                            m_wstrb   <= req_wstrb;
                            m_wlast   <= 1'b1;
                            m_wvalid  <= 1'b1;

                            state <= WR_AW;
                        end else begin
                            m_arid    <= '0;
                            m_araddr  <= req_addr;
                            m_arlen   <= '0;
                            m_arsize  <= AXI4_SIZE_FULL;
                            m_arburst <= AXI4_BURST_INCR;
                            m_arvalid <= 1'b1;

                            state <= RD_AR;
                        end
                    end
                end

                WR_AW: begin
                    if (m_awvalid && m_awready) begin
                        m_awvalid <= 1'b0;
                    end
                    if (m_wvalid && m_wready) begin
                        m_wvalid <= 1'b0;
                        m_wlast  <= 1'b0;
                    end
                    // Both AW and W consumed; wait for B
                    if (!m_awvalid && !m_wvalid &&
                        !(m_awvalid && m_awready) && !(m_wvalid && m_wready)) begin
                        m_bready <= 1'b1;
                        state    <= WR_B;
                    end
                end

                WR_B: begin
                    if (m_bvalid && m_bready) begin
                        m_bready <= 1'b0;
                        if (m_bresp != AXI4_RESP_OKAY) req_err <= 1'b1;
                        req_done <= 1'b1;
                        req_busy <= 1'b0;
                        state    <= IDLE;
                    end
                end

                RD_AR: begin
                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready  <= 1'b1;
                        state     <= RD_R;
                    end
                end

                RD_R: begin
                    if (m_rvalid && m_rready) begin
                        req_rdata <= m_rdata;
                        if (m_rresp != AXI4_RESP_OKAY) req_err <= 1'b1;
                        m_rready  <= 1'b0;
                        req_done  <= 1'b1;
                        req_busy  <= 1'b0;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
