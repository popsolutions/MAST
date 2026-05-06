// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Inter-card link skeleton — interface contract for the multi-card fabric.
// Behavior is intentionally stubbed: this module locks the *interface* (TX/RX
// handshake shape, link-state enum, lane parametrisation) so that the Stays
// PCB layout can commit to connector pinout in parallel with the ADR-014
// architectural decision (#9: PCIe p2p / CXL / custom LVDS / hybrid).
//
// Real protocol behavior — flit framing, peer training, error handling, flow
// control beyond a single ready/valid handshake — lands in follow-up issues
// once ADR-014 chooses a protocol.
//
// Port grouping mirrors the AXI4-style "valid/ready" handshakes used
// throughout MAST so the future protocol implementation can splice in
// without changing the integration layer above.
//
// See ./README.md for the full interface contract and the explicit list of
// what the skeleton does NOT do.

`default_nettype none

module intercard_link
  import intercard_pkg::*;
#(
    // Number of clock cycles `link_train_req` must stay asserted before the
    // skeleton declares LINK_UP. The default lets a cocotb testbench drive
    // link-up in tens of cycles; real PHY initialization training will
    // replace this with a proper LTSSM-like state machine.
    parameter int TRAIN_CYCLES = 16
) (
    input  wire                              clk,
    input  wire                              rst_n,

    // -------- Local-card TX (data leaving this card) --------
    input  wire [INTERCARD_BUS_WIDTH-1:0]    tx_data,
    input  wire                              tx_valid,
    output wire                              tx_ready,
    input  wire                              tx_last,

    // -------- Local-card RX (data arriving from the other card) --------
    output wire [INTERCARD_BUS_WIDTH-1:0]    rx_data,
    output wire                              rx_valid,
    input  wire                              rx_ready,
    output wire                              rx_last,

    // -------- Link state --------
    input  wire                              link_train_req,
    output link_state_t                      link_state,
    output wire                              link_up,

    // -------- PHY-side stubs (replaced once ADR-014 chooses a PHY) --------
    output wire [INTERCARD_BUS_WIDTH-1:0]    phy_tx_data,
    output wire                              phy_tx_valid,
    input  wire [INTERCARD_BUS_WIDTH-1:0]    phy_rx_data,
    input  wire                              phy_rx_valid
);

    // ====================================================================
    // Link state machine — minimal LINK_DOWN -> LINK_TRAINING -> LINK_UP.
    //
    // LINK_FAULT is defined in intercard_pkg.sv but never entered by the
    // skeleton; the protocol implementation will define its entry/exit
    // conditions.
    // ====================================================================

    localparam int TRAIN_CTR_W =
        (TRAIN_CYCLES <= 1) ? 1 : $clog2(TRAIN_CYCLES + 1);

    link_state_t              state_q;
    reg  [TRAIN_CTR_W-1:0]    train_ctr_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q     <= LINK_DOWN;
            train_ctr_q <= '0;
        end else begin
            case (state_q)
                LINK_DOWN: begin
                    if (link_train_req) begin
                        state_q     <= LINK_TRAINING;
                        train_ctr_q <= '0;
                    end
                end

                LINK_TRAINING: begin
                    if (!link_train_req) begin
                        state_q     <= LINK_DOWN;
                        train_ctr_q <= '0;
                    end else if (train_ctr_q == TRAIN_CTR_W'(TRAIN_CYCLES - 1)) begin
                        state_q <= LINK_UP;
                    end else begin
                        train_ctr_q <= train_ctr_q + 1'b1;
                    end
                end

                LINK_UP: begin
                    if (!link_train_req) begin
                        state_q <= LINK_DOWN;
                    end
                end

                LINK_FAULT: begin
                    // Skeleton never enters this state; protocol will define.
                    state_q <= LINK_DOWN;
                end

                default: state_q <= LINK_DOWN;
            endcase
        end
    end

    assign link_state = state_q;
    assign link_up    = (state_q == LINK_UP);

    // ====================================================================
    // TX/RX datapath — placeholder until ADR-014 closes.
    //
    // While LINK_UP:
    //   * tx_ready is asserted; upstream beats forward straight to phy_tx_*
    //     with no buffering or framing.
    //   * phy_rx_* beats forward straight to rx_*.
    //   * rx_last is tied 0 — packet boundaries belong to the chosen protocol.
    //
    // While not LINK_UP, both directions are gated to zero. There is no
    // buffering and no flow control beyond the immediate ready/valid
    // handshake; both arrive with the protocol implementation.
    //
    // tx_last and rx_ready are intentionally unused at this layer — they are
    // declared so the upstream/downstream integration ports already match the
    // shape the protocol layer will need, but their semantics are protocol-
    // defined and stay no-ops in the skeleton.
    // ====================================================================

    assign tx_ready     = link_up;
    assign phy_tx_data  = tx_data;
    assign phy_tx_valid = tx_valid & link_up;

    assign rx_data  = phy_rx_data;
    assign rx_valid = phy_rx_valid & link_up;
    assign rx_last  = 1'b0;

    // Document-by-reference: tx_last and rx_ready are reserved for the
    // protocol layer and intentionally unused at this depth. The Makefile
    // already passes -Wno-UNUSEDSIGNAL; this `_unused_ok` net is a hint to
    // future readers that the omission is deliberate, not an oversight.
    wire _unused_ok = &{1'b0, tx_last, rx_ready};

endmodule
