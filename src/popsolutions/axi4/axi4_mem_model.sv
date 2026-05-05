// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// AXI4 slave with internal SRAM. Behavioral model intended for early
// simulation: replaces the role of upstream src/global_mem_controller.sv for
// AXI4-attached masters.
//
// Profile (current limitations — to be extended in follow-up issues):
//   * Full-width beats only (AxSIZE must equal AXI4_SIZE_FULL = 5 for 256-bit
//     data path); narrow transfers respond SLVERR.
//   * INCR and FIXED bursts; WRAP not yet implemented (responds as INCR).
//   * Single outstanding transaction per direction (read FSM is independent
//     from write FSM, but neither pipelines requests). Pipelining lands when
//     the Compute Unit master needs it.
//   * No exclusive accesses (AxLOCK ignored, EXOKAY never emitted).
//   * No protection enforcement (AxPROT ignored).
//
// See ./README.md for the full profile and integration notes.

`default_nettype none

module axi4_mem_model #(
    parameter int DEPTH_WORDS = 256
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // -------- AW channel (slave) --------
    input  wire [axi4_id_width-1:0]    s_awid,
    input  wire [phys_addr_width-1:0]  s_awaddr,
    input  wire [axi4_len_width-1:0]   s_awlen,
    input  wire [axi4_size_width-1:0]  s_awsize,
    input  wire [axi4_burst_width-1:0] s_awburst,
    input  wire                        s_awvalid,
    output reg                         s_awready,

    // -------- W channel (slave) --------
    input  wire [mem_data_width-1:0]   s_wdata,
    input  wire [axi4_strb_width-1:0]  s_wstrb,
    input  wire                        s_wlast,
    input  wire                        s_wvalid,
    output reg                         s_wready,

    // -------- B channel (slave) --------
    output reg  [axi4_id_width-1:0]    s_bid,
    output reg  [axi4_resp_width-1:0]  s_bresp,
    output reg                         s_bvalid,
    input  wire                        s_bready,

    // -------- AR channel (slave) --------
    input  wire [axi4_id_width-1:0]    s_arid,
    input  wire [phys_addr_width-1:0]  s_araddr,
    input  wire [axi4_len_width-1:0]   s_arlen,
    input  wire [axi4_size_width-1:0]  s_arsize,
    input  wire [axi4_burst_width-1:0] s_arburst,
    input  wire                        s_arvalid,
    output reg                         s_arready,

    // -------- R channel (slave) --------
    output reg  [axi4_id_width-1:0]    s_rid,
    output reg  [mem_data_width-1:0]   s_rdata,
    output reg  [axi4_resp_width-1:0]  s_rresp,
    output reg                         s_rlast,
    output reg                         s_rvalid,
    input  wire                        s_rready,

    // -------- testbench / boot loader back-door --------
    // Synchronous 32-bit-word write into the backing SRAM by byte address.
    // Intended ONLY for testbench program loading and (optionally) on-chip
    // bootrom-style initialisation. Tie loader_en to 0 in synthesis builds
    // that do not need the back-door.
    input  wire                        loader_en,
    input  wire [phys_addr_width-1:0]  loader_addr,
    input  wire [data_width-1:0]       loader_data
);

    localparam int IDX_WIDTH = (DEPTH_WORDS <= 1) ? 1 : $clog2(DEPTH_WORDS);
    localparam int OFF_WIDTH = $clog2(cache_line_bytes);  // 5 for 32-byte line

    // Backing storage (one entry per cache line)
    reg [mem_data_width-1:0] mem [0:DEPTH_WORDS-1];

    // ====================================================================
    // Loader back-door: 32-bit word writes by byte address
    // ====================================================================
    // Lands the 32-bit datum in the correct slot of the 256-bit cache line:
    //   slot byte offset = loader_addr[OFF_WIDTH-1:0] (must be 4-byte aligned)
    //   cache line index = loader_addr[OFF_WIDTH +: IDX_WIDTH]
    // No handshake — caller must hold loader_addr/loader_data stable for one
    // clock with loader_en=1. The loader path runs in parallel with the AXI4
    // write FSM; if both target the same cache line in the same cycle, the
    // loader wins (testbench convention). Production loader_en is tied 0.

    wire [IDX_WIDTH-1:0]  loader_idx      = loader_addr[OFF_WIDTH +: IDX_WIDTH];
    wire [OFF_WIDTH-1:0]  loader_byte_off = loader_addr[OFF_WIDTH-1:0];
    // bit position within the cache line where the 32-bit datum lands
    wire [OFF_WIDTH+2:0]  loader_bit_off  = {loader_byte_off, 3'b000};

    always @(posedge clk) begin
        if (loader_en) begin
            mem[loader_idx][loader_bit_off +: data_width] <= loader_data;
        end
    end

    // ====================================================================
    // Write side FSM
    // ====================================================================

    localparam [1:0] WR_IDLE = 2'd0,
                     WR_DATA = 2'd1,
                     WR_RESP = 2'd2;

    reg [1:0]                  wr_state;
    reg [axi4_id_width-1:0]    wr_id_q;
    reg [phys_addr_width-1:0]  wr_addr_q;
    reg [axi4_len_width-1:0]   wr_beat_q;
    reg [axi4_len_width-1:0]   wr_len_q;
    reg [axi4_burst_width-1:0] wr_burst_q;
    reg [axi4_size_width-1:0]  wr_size_q;
    reg                        wr_err_q;

    wire [IDX_WIDTH-1:0] wr_idx = wr_addr_q[OFF_WIDTH +: IDX_WIDTH];

    integer wb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state   <= WR_IDLE;
            s_awready  <= 1'b0;
            s_wready   <= 1'b0;
            s_bvalid   <= 1'b0;
            s_bid      <= '0;
            s_bresp    <= AXI4_RESP_OKAY;
            wr_id_q    <= '0;
            wr_addr_q  <= '0;
            wr_beat_q  <= '0;
            wr_len_q   <= '0;
            wr_burst_q <= AXI4_BURST_INCR;
            wr_size_q  <= '0;
            wr_err_q   <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_awready <= 1'b1;
                    s_wready  <= 1'b0;
                    s_bvalid  <= 1'b0;
                    if (s_awvalid && s_awready) begin
                        wr_id_q    <= s_awid;
                        wr_addr_q  <= s_awaddr;
                        wr_len_q   <= s_awlen;
                        wr_burst_q <= s_awburst;
                        wr_size_q  <= s_awsize;
                        wr_beat_q  <= '0;
                        wr_err_q   <= (s_awsize != AXI4_SIZE_FULL);
                        s_awready  <= 1'b0;
                        s_wready   <= 1'b1;
                        wr_state   <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_wvalid && s_wready) begin
                        if (!wr_err_q) begin
                            for (wb = 0; wb < axi4_strb_width; wb = wb + 1) begin
                                if (s_wstrb[wb]) begin
                                    mem[wr_idx][wb*8 +: 8] <= s_wdata[wb*8 +: 8];
                                end
                            end
                        end

                        if (s_wlast || wr_beat_q == wr_len_q) begin
                            s_wready <= 1'b0;
                            s_bvalid <= 1'b1;
                            s_bid    <= wr_id_q;
                            s_bresp  <= wr_err_q ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
                            wr_state <= WR_RESP;
                        end else begin
                            wr_beat_q <= wr_beat_q + 1'b1;
                            if (wr_burst_q == AXI4_BURST_INCR) begin
                                wr_addr_q <= wr_addr_q + (phys_addr_width'(1) << wr_size_q);
                            end
                        end
                    end
                end

                WR_RESP: begin
                    if (s_bvalid && s_bready) begin
                        s_bvalid <= 1'b0;
                        wr_state <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // ====================================================================
    // Read side FSM (independent from write FSM)
    // ====================================================================

    localparam RD_IDLE = 1'b0,
               RD_DATA = 1'b1;

    reg                        rd_state;
    reg [axi4_id_width-1:0]    rd_id_q;
    reg [phys_addr_width-1:0]  rd_addr_q;
    reg [axi4_len_width-1:0]   rd_beat_q;
    reg [axi4_len_width-1:0]   rd_len_q;
    reg [axi4_burst_width-1:0] rd_burst_q;
    reg [axi4_size_width-1:0]  rd_size_q;
    reg                        rd_err_q;

    // combinatorial next-address for INCR bursts (FIXED keeps current addr)
    wire [phys_addr_width-1:0] rd_next_addr =
        (rd_burst_q == AXI4_BURST_INCR)
            ? (rd_addr_q + (phys_addr_width'(1) << rd_size_q))
            : rd_addr_q;
    wire [IDX_WIDTH-1:0] rd_next_idx = rd_next_addr[OFF_WIDTH +: IDX_WIDTH];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state    <= RD_IDLE;
            s_arready   <= 1'b0;
            s_rvalid    <= 1'b0;
            s_rdata     <= '0;
            s_rid       <= '0;
            s_rresp     <= AXI4_RESP_OKAY;
            s_rlast     <= 1'b0;
            rd_id_q     <= '0;
            rd_addr_q   <= '0;
            rd_beat_q   <= '0;
            rd_len_q    <= '0;
            rd_burst_q  <= AXI4_BURST_INCR;
            rd_size_q   <= '0;
            rd_err_q    <= 1'b0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_arready <= 1'b1;
                    s_rvalid  <= 1'b0;
                    s_rlast   <= 1'b0;
                    if (s_arvalid && s_arready) begin
                        rd_id_q    <= s_arid;
                        rd_addr_q  <= s_araddr;
                        rd_len_q   <= s_arlen;
                        rd_burst_q <= s_arburst;
                        rd_size_q  <= s_arsize;
                        rd_beat_q  <= '0;
                        rd_err_q   <= (s_arsize != AXI4_SIZE_FULL);
                        s_arready  <= 1'b0;

                        // Pre-load and present the first beat in the same cycle
                        s_rid    <= s_arid;
                        s_rdata  <= mem[s_araddr[OFF_WIDTH +: IDX_WIDTH]];
                        s_rresp  <= (s_arsize != AXI4_SIZE_FULL)
                                    ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
                        s_rlast  <= (s_arlen == 0);
                        s_rvalid <= 1'b1;
                        rd_state <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (s_rvalid && s_rready) begin
                        if (rd_beat_q == rd_len_q) begin
                            // last beat just consumed; close the transaction
                            s_rvalid <= 1'b0;
                            s_rlast  <= 1'b0;
                            rd_state <= RD_IDLE;
                        end else begin
                            // present next beat
                            rd_beat_q <= rd_beat_q + 1'b1;
                            rd_addr_q <= rd_next_addr;
                            s_rdata   <= mem[rd_next_idx];
                            s_rlast   <= (rd_beat_q + 1 == rd_len_q);
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
