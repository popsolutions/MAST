<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# `src/popsolutions/interconnect/` — Inter-card link

Skeleton RTL for the inter-card / inter-chiplet link that lets multiple
PopSolutions Sails cards aggregate compute capacity (per the
`project_multicard_parallelism` requirement and ADR-014).

> **Status: skeleton only.** This module locks the *interface contract* —
> TX/RX handshake shape, link-state enum, lane-count and lane-width
> parameters — so that the Stays PCB layout (KiCad) can commit to
> connector pinout in parallel with the ADR-014 architectural decision
> (#9). Real protocol behavior (framing, training, error handling) lands
> with the chosen protocol.

## Files

| File | Purpose |
|---|---|
| `intercard_pkg.sv` | `INTERCARD_LANES`, `INTERCARD_LANE_WIDTH`, `INTERCARD_BUS_WIDTH`, and the `link_state_t` enum |
| `intercard_link.sv` | One-side-of-link skeleton module: link-up FSM + TX/RX gating |

## Parameters

`INTERCARD_LANES` defaults to **4** and is overridable at compile time
via `-DMAST_INTERCARD_LANES=<n>`. `INTERCARD_LANE_WIDTH` is fixed at
**32 bits** per lane (typical post-deserialization width for LVDS /
PCIe SerDes primitives).

The composite TX/RX bus width is therefore
`INTERCARD_LANES × INTERCARD_LANE_WIDTH` (default **128 bits**).

## Link state machine (skeleton)

```
                       link_train_req=1
LINK_DOWN ───────────────────────────────► LINK_TRAINING
   ▲                                            │
   │ link_train_req=0                            │ TRAIN_CYCLES elapsed
   │                                            ▼
   └───────────────────────────────────────── LINK_UP
                       link_train_req=0
```

`LINK_FAULT` is declared in the package but never entered by the
skeleton; the protocol implementation will define entry/exit conditions
once ADR-014 closes.

## TX/RX behavior (placeholder)

While `LINK_UP`:

* `tx_ready` is asserted; upstream beats forward to `phy_tx_*` directly,
  with no buffering or framing.
* `phy_rx_*` beats forward to `rx_*` directly. `rx_last` is tied 0 —
  packet boundaries belong to the chosen protocol.

While not `LINK_UP`, both directions are gated to zero. There is no
buffering, no framing, and no flow control beyond the immediate
ready/valid handshake.

## Test coverage

`verif/intercard_link/` — six cocotb tests (Verilator + cocotb 2.x):

1. After reset and without `link_train_req`, link reports `LINK_DOWN`
   and gates TX/RX to zero.
2. Asserting `link_train_req` for `TRAIN_CYCLES` brings the link to
   `LINK_UP`; `link_up` and `tx_ready` assert.
3. Deasserting `link_train_req` from `LINK_UP` returns the FSM to
   `LINK_DOWN` on the next clock.
4. Deasserting `link_train_req` from `LINK_TRAINING` aborts and returns
   to `LINK_DOWN`.
5. TX beats forward to `phy_tx_*` only when `LINK_UP`; gated otherwise.
6. RX beats from `phy_rx_*` forward to `rx_*` only when `LINK_UP`;
   gated otherwise.

## What this skeleton intentionally does NOT do

* Frame data into packets / flits.
* Negotiate link width / lane count with the peer.
* Detect or correct bit errors (CRC, ECC, replay).
* Implement flow control beyond a single immediate ready/valid handshake.
* Define `LINK_FAULT` entry/exit conditions.
* Implement `tx_last` / `rx_last` packet-boundary semantics.

These all land with the protocol decision in ADR-014 (#9) and follow-up
issues.

## References

* Issue [#10](https://github.com/popsolutions/MAST/issues/10) — this
  skeleton.
* Issue [#9](https://github.com/popsolutions/MAST/issues/9) — ADR-014,
  the protocol decision the skeleton is parked behind.
* Project memory: `project_multicard_parallelism.md` — original
  multi-card requirement.
