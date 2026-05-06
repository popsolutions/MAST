// SPDX-License-Identifier: CERN-OHL-S-2.0
// Copyright (c) 2026 PopSolutions Cooperative
//
// Inter-card link package — parameters and protocol-agnostic typedefs for
// the skeleton interconnect under src/popsolutions/interconnect/.
//
// This package locks ONLY the parameters that the Stays PCB layout needs to
// commit to connector pinout in parallel with ADR-014 (#9): lane count, lane
// width, and the link-state enum. Real protocol fields (framing, flit
// format, LTSSM-like training states) land once ADR-014 chooses a protocol.
//
// Tooling: requires SystemVerilog 2012 mode (Verilator 4.200+, iverilog -g2012).

package intercard_pkg;

  // Number of physical lanes on the inter-card connector. Override per-Sail
  // at compile time by passing -DMAST_INTERCARD_LANES=<n> to the simulator
  // command line (Verilator, iverilog, yosys all accept this form).
  // The PCB (Stays kicad/) commits to this when laying out the connector.
  `ifndef MAST_INTERCARD_LANES
  `define MAST_INTERCARD_LANES 4
  `endif
  parameter int INTERCARD_LANES = `MAST_INTERCARD_LANES;

  // Per-lane parallel data width, in bits. 32 is the conservative default —
  // it matches the typical post-deserialization width of LVDS / PCIe SerDes
  // primitives and keeps the composite bus a multiple of the AXI4-side
  // 32-byte cache line for trivial alignment in the future protocol layer.
  parameter int INTERCARD_LANE_WIDTH = 32;

  // Composite TX/RX bus width = lanes × per-lane width. With the defaults
  // above this is 128 bits (4 lanes × 32).
  parameter int INTERCARD_BUS_WIDTH = INTERCARD_LANES * INTERCARD_LANE_WIDTH;

  // Link state — minimal placeholder. Detailed states (e.g., recovery,
  // configuration, LTSSM-like substates) come with the chosen protocol.
  // LINK_FAULT is reserved: the skeleton never enters it; the protocol
  // implementation defines entry/exit conditions (CRC error rate, training
  // timeout, etc.) once ADR-014 closes.
  typedef enum logic [1:0] {
    LINK_DOWN     = 2'd0,
    LINK_TRAINING = 2'd1,
    LINK_UP       = 2'd2,
    LINK_FAULT    = 2'd3
  } link_state_t;

endpackage : intercard_pkg
