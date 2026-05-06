<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 PopSolutions Cooperative -->

# Inter-card SerDes RTL — liteiclink integration design

**Status:** Proposal (design doc) — accompanies ADR-014 transition from
DRAFT → Proposed.

**Stream:** 1 (RTL Architect) — proposal authored 2026-05-06.

**Tracking issue:** [popsolutions/MAST#34](https://github.com/popsolutions/MAST/issues/34)

**Related:**
- [ADR-014 — Inter-card link architecture](../adr/0014-intercard-link.md)
- [InnerJib7EA `intercard_link_upstream`/`_downstream` stubs (PR #15, ADR-003)](https://github.com/popsolutions/InnerJib7EA/pull/15)
- [InnerJib7EA `intercard-connector-pinout.md`](https://github.com/popsolutions/InnerJib7EA/blob/main/docs/hw/intercard-connector-pinout.md) — bandwidth math
- [Stays PR #31 — prjtrellis ECP5-85F recon](https://github.com/popsolutions/Stays) — `serdes_ecp5.py` finding
- [Stays PR #34 — LiteEth ECP5 SGMII recon](https://github.com/popsolutions/Stays) — same DCU/SerDes block, host-link side

---

## 1. Problem

Rev-A inter-card link is committed (per InnerJib7EA pinout §2 and ADR-014
§5) to:

- **4 differential lanes** per direction (TX0..3, RX0..3 on the 40-pin
  Samtec QSE-class connector).
- **1.25 Gbps per lane**, matching SGMII line rate.
- **8b/10b encoding** for clock recovery and DC balance.
- **Aggregate effective payload:** ~500 MB/s per direction with 8b/10b
  framing — 10× the planning bandwidth required for Llama-70B inference
  at 30 t/s on N=8 cards (ADR-014 §4).

Today, `popsolutions/InnerJib7EA/src/intercard_link_upstream.sv` and
`intercard_link_downstream.sv` (PR #15) declare the port surface and a
width contract (`INTERCARD_BUS_WIDTH = 128`) but have **empty bodies** —
TX outputs are tied to constants, sideband is high-Z. The actual
ECP5 DCU SerDes + 8b/10b PCS + link bring-up FSM is deferred to a
follow-up PR after the line-coding / IP-source ADR (ADR-014) lands.

**The decision this design document forces:**

> Do we hand-roll the ECP5 DCU primitive (DCUA + EXTREFB + PCSCLKDIV,
> with manual register init sequences from the Lattice TN1261/TN1255
> tech notes) — or do we wrap an existing, production-validated open
> SerDes core?

### 1.1 Why hand-rolling is bug-bait

The Lattice ECP5 DCU is a hardened transceiver block with non-trivial
initialization. Open-source DCU bring-up has historically taken
multiple iterations even for experienced FPGA engineers:

- **DCU register init order is not documented in the public datasheet.**
  The bring-up sequence is reverse-engineered from Lattice Diamond's
  generated wrappers and the prjtrellis fuzzer outputs.
- **`PCSCLKDIV` routing has a known nextpnr issue** (`nextpnr#860`,
  open since 2021) — the workaround is to drive divided clocks from
  fabric / PLL primitives rather than from `PCSCLKDIV` directly. A
  hand-rolled SerDes that doesn't know this loses days to a routing
  failure that liteiclink already routes around.
- **8b/10b encoder/decoder + comma alignment + word boundary detection**
  is ~400 lines of RTL on its own. Comma alignment edge cases (during
  reset, after RX loss-of-signal, when the upstream card is not yet
  powered) are notorious bug magnets.
- **Lane deskew across 4 bonded lanes** adds a per-lane FIFO + a
  bit-stuffing / idle-symbol insertion mechanism. ~200 more lines of RTL.

### 1.2 What liteiclink already gives us

`enjoy-digital/liteiclink/liteiclink/serdes/serdes_ecp5.py` (32 KB
Python/Migen) wraps the DCUA primitive in a production-grade Migen
module, generated to Verilog via the LiteX flow. Key properties (from
the Stays PR #31 recon):

- **Stable since 2023-Q1.** Last functional commit 2023-01-18; only
  refactors since.
- **Supports SGMII (1.25 Gbps) as a directly named preset** — exactly
  rev-A's intercard link rate.
- **Production-validated on two -85F-class boards** (Lattice
  Versa-ECP5 LFE5UM5G-85F-8BG381 and LambdaConcept ECPIX-5
  LFE5UM5G-85F-8BG554) via the upstream benches at
  `liteiclink/bench/serdes/versa_ecp5.py` and `ecpix5.py`.
- **Bundled with LiteX**, so the OSS CAD Suite nightly that we already
  use for yosys / nextpnr-ecp5 / prjtrellis includes it transitively
  through `litex` / `migen`.
- **License: BSD-2-Clause.** Compatible with our hardware/software/docs
  license stack (CERN-OHL-S v2 / Apache-2.0 / CC-BY-SA-4.0).
- **Implements 8b/10b coding, comma alignment, line-rate clock recovery,
  and per-lane reset** — every component the hand-rolled path would
  re-implement.

### 1.3 What liteiclink does NOT give us

The wrap is the PHY+PCS layer. Above it we still write:

- **Link layer:** framing (start-of-frame / end-of-frame), CRC, per-lane
  flow control, lane bonding / striping. ~500 lines of RTL on top of
  the SerDes.
- **Transport layer:** ACK/NACK + replay, packet ordering, multi-card
  routing. ~1000–2000 lines of RTL plus driver-side support in Spanker.
- **Bring-up FSM:** local reset → SerDes ready → 8b/10b lock → comma
  align → lane bonding → link up. ~150 lines, gated by `prsnt_n` and
  the SMBus sideband.

These layers are above the liteiclink boundary either way. The PHY+PCS
is what we are choosing to delegate.

## 2. Integration options

### Option A — Generate at build time

Run the LiteX/Migen Python script as a **build step** of the SystemVerilog
compilation (Verilator and yosys+nextpnr+prjtrellis). The generated
Verilog is produced fresh on every build and immediately consumed.

**Pros:**

- Always tracks the pinned `liteiclink` git commit. No drift between
  what's committed and what's built.
- Build the bitstream in one shot from a clean checkout.

**Cons:**

- Hard build-system dependency on Python + LiteX + Migen. The OSS CAD
  Suite includes them, but reviewers without OSS CAD Suite (or running
  vanilla Verilator) cannot lint the design without first installing
  the LiteX stack.
- Verilator / cocotb test runs must include the generation step. Slower
  CI (especially cold-start), and Python errors during generation now
  appear as confusing build failures in unrelated lint jobs.
- Generated Verilog is *not visible in code review*. Diffs for the
  SerDes IP itself are invisible — reviewers see only the Python pin
  bump.
- Reproducibility hazard: a `pip install litex` two months apart can
  produce different generated Verilog if upstream `liteiclink` shifted.

### Option B — Pre-generate + check in

Run the LiteX/Migen Python script **once** as a deliberate maintenance
step. Commit the resulting Verilog to the repo as
`src/popsolutions/intercard/intercard_serdes_generated.v` (with a
`README` next to it documenting the exact Python invocation, the
upstream commit hash, and the configuration parameters). Re-generate
when liteiclink updates and we choose to take the upgrade.

**Pros:**

- **Build is hermetic against Python toolchain drift.** Anyone with
  Verilator + iverilog can lint the design — no LiteX install needed
  for the inner-loop developer.
- **Generated Verilog is visible in PR diffs.** Upgrades to liteiclink
  go through code review like any other RTL change.
- **Reproducible by pinned commit hash + recorded command line.** A
  later contributor can re-run the same generation and confirm the
  bytes match.
- **CI footprint stays small.** Verilator + cocotb don't need the
  Python stack.

**Cons:**

- Two paths can drift: the committed Verilog and the upstream
  liteiclink. Mitigated by recording the upstream commit hash and the
  recon date in the generated file's header.
- Re-generation is a deliberate human step, not automated. A small
  CI job that re-runs generation and diffs against the committed file
  could flag drift; that job is *advisory*, not blocking.

### Option C — Adapter shim (SystemVerilog wrapper)

Independent of A vs. B: write a thin SystemVerilog wrapper in
`src/popsolutions/intercard/intercard_serdes.sv` that **instantiates
the generated module by name** and exposes our project's stable port
surface (`INTERCARD_LANES`, `INTERCARD_LANE_WIDTH`, AXI-Stream upstream
to the link-layer module). The wrapper insulates the rest of the RTL
from liteiclink-internal naming changes.

**Pros:**

- The interface our link layer talks to (the AXI-Stream upstream of
  the 8b/10b PCS) stays stable across liteiclink upgrades. Even if
  liteiclink renames a port between versions, only the shim changes.
- The shim is also where we resolve our InnerJib7EA-specific quirks:
  per-role clock direction (`intercard_link_upstream.sv` vs
  `_downstream.sv`), `prsnt_n` sideband behaviour, and the
  `nextpnr#860` `PCSCLKDIV` workaround.
- Cocotb tests target the shim's port surface, not liteiclink's
  internals — tests stay valid across liteiclink upgrades.

**Cons:**

- ~50–100 extra lines of "glue" RTL. Justified by the cross-version
  insulation.

### Option C is independent of A/B — they compose.

| | Hand-rolled DCU | Option A (build-time gen) | Option B (pre-gen) | Option B + C (recommended) |
|---|---|---|---|---|
| Build deps | Verilator only | Verilator + LiteX + Migen + Python | Verilator only | Verilator only |
| PR diff visibility | Yes | No (Python pin only) | Yes | Yes (incl. shim) |
| Upstream upgrade isolation | N/A | Hot-rebuild | Manual re-gen | Manual re-gen, shim absorbs API drift |
| Bug surface | High (DCU init, 8b/10b, comma) | Low (liteiclink) but Python-stack-dependent | Low (liteiclink) | Low (liteiclink) + stable interface |
| Cooperative-affordability fit | Bad (engineering cost) | Mediocre (CI cost) | Good | Best |

## 3. Recommendation: Option B + C combined

**Pre-generate the liteiclink SerDes module once, commit it to the
repo, and wrap it in a SystemVerilog shim that exposes our project's
stable port surface.** Re-generation is a deliberate maintenance PR,
not a build step.

This combination:

1. Keeps the build hermetic — anyone with Verilator + iverilog can
   lint the project.
2. Keeps liteiclink upgrades visible in code review.
3. Insulates the rest of the RTL from liteiclink-internal changes
   via the shim.
4. Aligns with how the LiteX ecosystem itself operates: LiteX
   reference targets generate Verilog at build time *because* they
   own the build environment (LiteX is Python-native). Our world is
   SystemVerilog-native — Option B fits our build environment, not
   liteiclink's.
5. Aligns with cooperative-affordability: a contributor with a
   spare laptop and the OSS CAD Suite can clone, lint, and run cocotb
   tests without first installing the full LiteX Python stack.

### 3.1 Layout

```
popsolutions/InnerJib7EA/
├── src/
│   ├── intercard_link_upstream.sv              ← existing stub (PR #15)
│   ├── intercard_link_downstream.sv            ← existing stub (PR #15)
│   └── popsolutions/
│       └── intercard/
│           ├── intercard_serdes.sv             ← NEW: Option C shim
│           ├── intercard_serdes_generated.v    ← NEW: Option B Verilog
│           └── README.md                        ← regen instructions
└── verif/
    └── intercard_link/
        ├── test_widths.sv                      ← existing (PR #15)
        ├── test_two_card_pair.sv               ← existing (PR #15, structural)
        └── test_serdes_loopback.py             ← NEW cocotb timing test
```

The generated Verilog goes under `popsolutions/InnerJib7EA/src/popsolutions/intercard/`,
not under MAST trunk, because it is FPGA-target-specific (ECP5
DCUA primitive). MAST trunk's `interconnect` block stays
chip-agnostic. The shim is the only thing that knows there is an
ECP5 DCU underneath.

### 3.2 Shim port surface (sketch — for design-doc reference, not committed RTL)

```systemverilog
module intercard_serdes #(
    parameter int LANES         = 4,
    parameter int LANE_WIDTH    = 32,
    parameter int LINE_RATE_BPS = 1_250_000_000,
    parameter bit ROLE_UPSTREAM = 1'b1   // 1 = drives forwarded clk; 0 = recovers it
)(
    input  wire                       ref_clk_125mhz,   // SerDes ref clock
    input  wire                       sys_clk,          // fabric clock for upstream side
    input  wire                       rst_n,
    // High-speed pins to connector
    output wire [LANES-1:0]           tx_p, tx_n,
    input  wire [LANES-1:0]           rx_p, rx_n,
    // Forwarded source-synchronous clock — direction set by ROLE_UPSTREAM
    inout  wire                       clk_p, clk_n,
    // AXI-Stream upstream to link-layer module (per lane)
    output wire [LANES-1:0]           lane_rx_valid,
    output wire [LANES*LANE_WIDTH-1:0] lane_rx_data,
    input  wire [LANES-1:0]           lane_tx_ready,
    input  wire [LANES*LANE_WIDTH-1:0] lane_tx_data,
    input  wire [LANES-1:0]           lane_tx_valid,
    // Status
    output wire                       link_up,
    output wire [LANES-1:0]           lane_aligned
);
```

Internally the shim instantiates `intercard_serdes_generated` (the
liteiclink output) and wires the per-lane ports to our 4-lane bonded
naming, plus handles role-dependent clock direction (`generate-if`).

## 4. Reproducer — minimal LiteX command line

The exact invocation used to generate `intercard_serdes_generated.v`
will be documented in the file header *and* in the README next to it.
The command (worked example, to be refined when the actual generation
PR lands):

```bash
# Pinned upstream commit (recorded in the generated file's header):
git -C $LITEICLINK_SRC rev-parse HEAD
# Expected output (recorded at generation time): a 40-character SHA

# Generate using the existing Versa-ECP5 bench as a template, with
# our config:
python3 -m liteiclink.serdes.gen_ecp5 \
    --device LFE5UM5G-85F-8BG381 \
    --speedgrade 8 \
    --refclk-freq 125e6 \
    --linerate 1.25e9 \
    --lanes 4 \
    --encoding 8b10b \
    --output intercard_serdes_generated.v

# Validate (no functional simulation — just lint):
verilator --lint-only intercard_serdes_generated.v
```

(The actual `gen_ecp5` entrypoint may be `liteiclink/bench/serdes/`
based — to be finalized in the implementation PR. The recon doc
points at `liteiclink/bench/serdes/versa_ecp5.py` and `ecpix5.py` as
production templates.)

The README accompanying the generated file will record:

1. Upstream `liteiclink` commit hash.
2. Upstream `litex` and `migen` commit hashes.
3. The exact Python invocation.
4. The OSS CAD Suite nightly tag in use at generation time.
5. The reviewer (Agent R) who approved the regeneration.

## 5. Test strategy

### 5.1 Today (PR #15, already merged): structural-only

`verif/intercard_link/test_two_card_pair.sv` instantiates one
`intercard_link_upstream` and one `intercard_link_downstream`, wires
their TX/RX/CLK pairs together, and confirms the design elaborates
under Verilator `--lint-only`. **No timing**, just a structural check
that the role split holds.

### 5.2 After the implementation PR (this design's outcome): timing test

`verif/intercard_link/test_serdes_loopback.py` (new cocotb test)
becomes the real timing test:

1. Instantiate the upstream module and the downstream module on
   opposite ends of a simulated channel. (No real PCB layout in
   simulation; just bit-true SerDes serialization with optional
   pipeline delay and bit-error injection in advanced sub-tests.)
2. Drive a known AXI-Stream payload into the upstream's `lane_tx_*`
   ports.
3. Wait for `link_up` to assert (bring-up FSM converges).
4. Read the AXI-Stream payload off the downstream's `lane_rx_*`
   ports and verify byte-for-byte match.
5. Assert end-to-end latency is within the budget set by the
   bandwidth model (Spanker PR #6 / MAST #14 contract).

Optional extensions (later PRs, not in the first transceiver PR):

- Bit-error injection — verify 8b/10b detect-and-flag behaviour.
- Lane-skew injection — verify lane bonding handles per-lane delay
  differences.
- Forced reset mid-stream — verify clean re-train on `RESET_N`.

### 5.3 Hardware bring-up (post-tape-out, Sprint H)

The two-card bring-up bench (a pair of fabricated InnerJib7EA boards,
mated through the inter-card connector) runs the same test plan but
against the FPGA-fabricated bitstream, with iperf-class throughput
measurement instead of cycle-accurate matching.

## 6. License posture

- `liteiclink`: **BSD-2-Clause**. We consume the generated Verilog
  as our own RTL. The BSD-2 attribution requirement is satisfied by
  the SPDX header on the generated file (which inherits BSD-2-Clause
  from the source) plus a NOTICE entry crediting the upstream.
- The Option C shim is our own code: **Apache-2.0** with SPDX
  header, matching the rest of `popsolutions/InnerJib7EA/src/`.
- Re-export and combination: BSD-2 → Apache-2.0 wrap is permitted
  because BSD-2 is a permissive license. Apache-2.0's patent grant
  is layered on top of our shim only, not on the BSD-2 portion.
- This design doc itself: **CC-BY-SA-4.0**, matching MAST docs.

The MAST `NOTICE.md` (or per-Sail equivalent) gains a new entry:

```
- liteiclink (https://github.com/enjoy-digital/liteiclink)
  BSD-2-Clause; portions vendored as
  popsolutions/InnerJib7EA/src/popsolutions/intercard/intercard_serdes_generated.v
  Generated 2026-MM-DD at upstream commit <SHA>. See file header.
```

## 7. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | liteiclink's generated module hits `nextpnr#860` (`PCSCLKDIV` routing) | Don't drive divided clocks from `PCSCLKDIV` in the shim. Drive them from PLL or fabric `DIV`. liteiclink may or may not already do this — confirm at first generation. If not, file an upstream PR per project mission (open FPGA upstream commitment). |
| R2 | Pre-generated Verilog drifts behind upstream and we miss a bug fix | Quarterly ecosystem-health survey (Agent 4) re-checks liteiclink HEAD against our pinned commit. If a relevant fix lands upstream, file a regeneration PR. |
| R3 | Upstream liteiclink renames a port between versions | The Option C shim absorbs the rename. Cocotb tests stay valid. |
| R4 | OSS CAD Suite nightly used for generation can't be reproduced 12 months later | Pin both the OSS CAD Suite tag *and* the upstream `liteiclink`/`litex`/`migen` commit hashes in the generated file header. |
| R5 | We need a different line rate later (e.g., 2.5 Gbps for higher-bandwidth Sails) | liteiclink already supports SATA Gen1 (1.5 Gbps), PCIe Gen1 (2.5 Gbps), SATA Gen2 (3.0 Gbps), and PCIe Gen2/USB3 (5.0 Gbps) presets. Re-generate with a different `--linerate`; the shim's port surface stays the same. |
| R6 | ECP5 DCU primitive is package-dependent (BG756 has 4 lanes, smaller packages have fewer) | Re-generate per package. Stays board-bringup ADR will pin the exact package. |

## 8. Decision summary for ADR-014

ADR-014 §9 ("Implementation plan") currently says:

> Sprint 2 / agent-1: Implement custom LVDS framing + CRC + flow
> control on top of the skeleton. Estimated 500 lines RTL + 8–10
> cocotb tests.

This design replaces the *PHY layer* portion of that estimate with a
liteiclink wrap. The framing + CRC + flow control + replay layers
(the link/transport layers) remain custom — the wrap only delegates
the SerDes + 8b/10b PCS. ADR-014 §9 is amended to reflect this in
the ADR amendment that lands alongside this design doc.

## 9. Out of scope for this design

- The actual `intercard_serdes_generated.v` file (a future PR after
  this design lands).
- The `intercard_serdes.sv` shim (same future PR).
- The cocotb timing test (same future PR).
- Modifying the `intercard_link_upstream.sv` / `_downstream.sv` stubs
  in InnerJib7EA — the role-split contract stays as-is; the bodies
  get filled in at the future PR via internal instantiation of
  `intercard_serdes`.
- The link-layer / transport-layer RTL above the SerDes (separate
  PRs, separate sprint).
- The ADR-014 final acceptance vote (this proposal moves it
  DRAFT → Proposed; final acceptance is for Agent R + cooperative
  human ratification).

## 10. References

- [popsolutions/MAST#34](https://github.com/popsolutions/MAST/issues/34) —
  this proposal's tracking issue.
- [ADR-014 (DRAFT)](../adr/0014-intercard-link.md) — parent decision.
- Stays PR #31 (merged 2026-05-06) — prjtrellis ECP5-85F recon. The
  finding: `liteiclink/serdes_ecp5.py` is production-validated for
  1.25 Gbps SGMII on -85F-class boards (Versa-ECP5, ECPIX-5).
- Stays PR #34 (merged 2026-05-06) — LiteEth ECP5 SGMII recon. Same
  liteiclink SerDes wrapper drives the host-link SGMII PHY (1 lane),
  so rev-A pulls liteiclink in transitively for the host link
  regardless of the inter-card decision. Inter-card just bonds 4
  lanes of the same primitive.
- [InnerJib7EA PR #15](https://github.com/popsolutions/InnerJib7EA/pull/15) —
  port-surface stubs for `intercard_link_upstream`/`_downstream`.
- [InnerJib7EA pinout doc](https://github.com/popsolutions/InnerJib7EA/blob/main/docs/hw/intercard-connector-pinout.md) —
  bandwidth math and connector pinout.
- [enjoy-digital/liteiclink](https://github.com/enjoy-digital/liteiclink) —
  upstream (BSD-2-Clause).
- `nextpnr#860` (PCSCLKDIV routing) — known toolchain edge to plan
  around.

Authored by Agent 1 (RTL Architect).
