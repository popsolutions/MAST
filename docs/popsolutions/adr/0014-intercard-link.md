<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# ADR-014 — Inter-card link architecture

**Status:** **DRAFT — NOT YET ACCEPTED.** Research only. Awaits human (cooperative) ratification.

**Date opened:** 2026-05-05 (issue #9)
**Date of this draft:** 2026-05-05
**Author:** Agent 1 (RTL Architect)
**Reviewers required for acceptance:** human (Marcos / cooperative members)

---

## 1. Why this ADR exists

The user requirement (2026-05-05, issue #9) is unambiguous:

> "*várias destas placas precisam funcionar em paralelo ou seja deve existir
> algum mecanismo de paralelização de processos para que estas placas possam
> juntas somar capacidade de processamento.*"

i.e., *multiple PopSolutions Sails cards must aggregate compute capacity*. The
project memory record `project_multicard_parallelism.md` puts this on equal
footing with cooperative governance (ADR-010), license stack (ADR-001), and
verification methodology — it is a first-class architectural requirement, not
a future flag.

This ADR's job is to choose **which inter-card link architecture** lets that
requirement land. It does **not** choose what the protocol *carries* (that is
per-workload software in the Spanker driver / Compute Unit firmware) — only
the wire-level fabric.

## 2. Decision-environment updates since the issue opened

Two facts have shifted since #9 was filed and they materially affect the
option space:

1. **Issue #13 / Stays#3 — LitePCIe has no ECP5 PHY.** The open-toolchain
   PCIe controller LitePCIe ships PHY modules for Cyclone V, Gowin GW5A,
   Lattice CertusPro-NX, and Xilinx 7-series / UltraScale / UltraScale+, but
   **not for ECP5**. There is zero history of ECP5 PCIe work upstream
   (`gh search issues / prs --repo enjoy-digital/litepcie "lattice OR ecp5"`
   returned 0 hits). The CertusPro-NX PHY is recent (©2024–2025), so the
   ecosystem is moving — but ECP5 is not on its path.

2. **Decision (made 2026-05-05, parent of this ADR):** rev-A uses **Gigabit
   Ethernet** as the host link (host card ↔ CPU). LitePCIe-on-ECP5 work
   moves to a stream-4 upstream contribution by Agent 4 and lands rev-B+.
   PCIe peer-to-peer between cards is therefore **off the table for rev-A**
   but available again from rev-B onward.

This ADR is written for **rev-A** decision-making. A rev-B revisit is
explicitly anticipated.

## 3. Options analysed

| ID | Option | Available rev-A? | Open-source IP situation | Notes |
|---|---|---|---|---|
| O1 | Custom LVDS over backplane (ECP5 SerDes) | **Yes** | We write the protocol; minimal upstream dependency | Maximum freedom; software stack from scratch. Discussed in §4–5. |
| O2 | Gigabit Ethernet as inter-card fabric (reuse the host-link PHY) | **Yes** | Mature open-source MACs (LiteEth, OpenCores) | Already in our BOM via the host link; familiar protocol; bandwidth-limited. |
| O3 | PCIe peer-to-peer (Gen2 ×4) | **No** (rev-A) | LitePCIe + ECP5 PHY pending Agent 4's upstream contribution | Returns at rev-B; revisit then. |
| O4 | CXL.cache / CXL.mem | **No** (rev-A or rev-B) | Open-source implementations are nascent | Discussed in §6. |
| O5 | Hybrid (e.g., GbE for control + LVDS for data) | **Yes** | Combination of O1 and O2 | Most flexible; highest software complexity. |

O3 and O4 are deferred. The substantive rev-A choice is among **O1, O2, O5**.

## 4. Bandwidth model — three reference workloads × N=2/4/8 cards

### 4.1 Workloads

The MAST mission documents commit to three reference inference workloads
(MVP-relevant, decode phase, batch=1):

| Workload | Hidden dim | Layers | Bytes per all-reduced activation in BF16 |
|---|---|---|---|
| TinyLlama-1.1B (chat-v1.0) | 2048 | 22 | 4 KB per layer per direction |
| Llama-7B (variants: 2-7B-chat, 3-7B) | 4096 | 32 | 8 KB per layer per direction |
| Llama-70B | 8192 | 80 | 16 KB per layer per direction |

Each transformer block in TP-sharded inference all-reduces the post-attention
output and the post-MLP output — **two all-reduces per layer** per token.

Per-token all-reduce payload (sum of both directions, BF16):

```
TinyLlama:  2 × hidden × layers × 2 B = 2 × 2048 × 22 × 2  =   180 KB / token
Llama-7B:   2 × 4096 × 32 × 2                              =   524 KB / token
Llama-70B:  2 × 8192 × 80 × 2                              = 2,621 KB / token
```

### 4.2 Ring all-reduce traffic across the link

Ring all-reduce ships `2(N−1)/N` of the payload across each card-to-card
link per all-reduce operation. For inference at **30 tokens/second** target
throughput (a chatbot-grade target consistent with cooperative-affordability
positioning):

| Workload | N=2 | N=4 | N=8 |
|---|---|---|---|
| TinyLlama-1.1B | 2.7 MB/s | 4.0 MB/s | 4.7 MB/s |
| Llama-7B | 7.7 MB/s | 11.5 MB/s | 13.4 MB/s |
| Llama-70B | 38.6 MB/s | 57.9 MB/s | 67.5 MB/s |

These are *steady-state* per-link rates; instantaneous bursts during the
all-reduce window are several × higher. Add ~30% overhead for protocol
framing, headers, and pipeline bubbles → planning numbers:

| Workload | Per-link planning bandwidth (with overhead, N=8) |
|---|---|
| TinyLlama-1.1B | ~6 MB/s (50 Mbps) |
| Llama-7B | ~17 MB/s (140 Mbps) |
| Llama-70B | ~88 MB/s (700 Mbps) |

Training is a different beast — gradient all-reduce per step on Llama-70B
shipped at FP32 ZeRO-3-sharded is multi-GB per epoch — but **rev-A is an
inference card** per the mission documents. Training-grade bandwidth is
explicitly out of scope.

### 4.3 What this tells us

* TinyLlama-1.1B inference at 30 t/s **fits inside Gigabit Ethernet** even
  at N=8 (50 Mbps ≪ 1 Gbps).
* Llama-7B at 30 t/s **fits inside Gigabit Ethernet** at N=8 (140 Mbps ≪
  1 Gbps), comfortably.
* Llama-70B at 30 t/s **stresses Gigabit Ethernet** at N=8 (700 Mbps; close
  to the practical 940 Mbps real-world ceiling). Headroom is tight, latency
  is not great because TCP/IP / UDP frames carry overhead per all-reduce,
  and the user-experience target of 30 t/s degrades non-linearly when the
  link saturates.

So **GbE is sufficient for TinyLlama and Llama-7B but marginal for Llama-70B**.
The first two are the realistic chatbot-grade targets for rev-A on
cooperative-affordability hardware. Llama-70B inference at 30 t/s is a
stretch goal that already requires aggressive memory-bandwidth and compute
tuning before the inter-card link becomes the bottleneck — so the link is
not the limiting factor for the realistic rev-A user.

## 5. Custom LVDS over ECP5 SerDes — characterization

The **ECP5-85F** target FPGA exposes SerDes channels with the following
characteristics (per Lattice ECP5 datasheet):

| Parameter | ECP5-85F |
|---|---|
| Number of SerDes lanes | 4 (in the BG756 package; package-dependent) |
| Per-lane raw line rate | 270 Mbps – 3.125 Gbps |
| Encoding | 8b/10b (typical) or 64b/66b (advanced) |
| Per-lane payload after 8b/10b | 2.5 Gbps |
| Per-lane payload after 64b/66b | ~3.03 Gbps |
| 4-lane aggregate (8b/10b, raw) | 12.5 Gbps |
| 4-lane aggregate (8b/10b, payload) | 10.0 Gbps = 1.25 GB/s |
| Practical effective payload (with framing / flow control / 70–80% utilization) | **0.8 – 1.0 GB/s per direction per card pair** |

Even at the conservative 0.8 GB/s lower bound, **a custom LVDS link would
exceed Llama-70B inference all-reduce demand by roughly 10×**. It would be
overprovisioned for TinyLlama and Llama-7B by 100×+.

The cost is in the protocol stack we have to write:

* PHY-level: SerDes byte alignment, 8b/10b training, lane deskew. Standard
  SerDes hard-IP behavior — minimal RTL.
* Link-level: framing (start-of-frame / end-of-frame markers), CRC,
  per-lane flow control. ~500 lines of RTL.
* Transport-level: reliability (ACK/NACK + replay), packet ordering,
  multi-card routing primitives. ~1,000–2,000 lines of RTL plus driver
  support in Spanker.

LiteIPCore from the LiteX ecosystem provides reusable building blocks for
the PHY and link layers; transport layer is custom by definition.

## 6. CXL open-source survey

The user briefing for this ADR's research lane explicitly listed:

* **Project Oxide** — Lattice's open Nexus / LIFCL toolchain. Targets
  CertusPro-NX, not ECP5. **No CXL implementation.** Project Oxide is a
  bitstream toolchain, not a CXL stack.
* **CXL Spectre** — no widely-known open-source project under this exact
  name as of 2026-05. The closest match in the open-source CXL space is
  *cxl-test-tool* (Linux kernel CXL driver test framework, soft-CXL device
  emulation in QEMU). These are software simulators of CXL endpoints, not
  hardware FPGA implementations. **Not usable for an FPGA card-to-card link.**
* **OpenCAPI-derived** — IBM contributed OpenCAPI Consortium specs and
  reference implementations targeting POWER9/10. Hardware reference is
  ASIC; FPGA ports exist for Xilinx UltraScale+ in research contexts but
  none target ECP5 or CertusPro-NX. **Not available on our toolchain in
  rev-A.**
* **CXL on FPGA broadly** — requires PCIe Gen3+ PHY. ECP5's PCIe hard IP
  is Gen2 only. **CXL is structurally unavailable on ECP5.** It is
  potentially available on **CertusPro-NX rev-B** if the upstream CXL
  open-source ecosystem matures meanwhile.

**Conclusion of the survey:** CXL is not a credible rev-A option, period.
It might become a credible rev-B option, but only if (a) CertusPro-NX is
the rev-B FPGA *and* (b) the open-source CXL FPGA ecosystem advances
beyond software emulators in the next ~12 months. Both are uncertain. CXL
is therefore deferred to a future revisit; ADR-014 should not commit to
it now.

## 7. Recommendation (not decision)

I recommend **Option 5 (Hybrid)** for rev-A, structured as follows:

### Rev-A inter-card fabric

* **Control plane:** Gigabit Ethernet, reusing the host-link PHY. Carries
  per-card discovery, topology query, scheduler hand-off, error reporting,
  and any low-rate management traffic. ~10 kbps steady-state per card.
* **Data plane (Llama-70B-grade workloads):** **custom LVDS over backplane**
  using ECP5 SerDes, single-lane minimum, 4-lane recommended. Carries
  tensor-parallel all-reduces, model-parallel activation hand-offs, and
  any bulk transfer.
* **Data plane (TinyLlama / Llama-7B-grade workloads):** **fall back to
  Gigabit Ethernet** if the LVDS link is omitted from the build (e.g., a
  cost-reduced SKU). Bandwidth is sufficient (§4.3).

### Why this is the right shape

1. **Rev-A is shippable on day-one open-source toolchain** (no LitePCIe-
   on-ECP5 dependency). Both GbE MACs and ECP5 SerDes have mature open
   support.
2. **Performance ceiling matches mission ambition.** Llama-70B at 30 t/s
   on N=8 fits inside the LVDS budget with 10× headroom.
3. **Cooperative-affordability target preserved.** Cards can ship without
   the LVDS PCB lanes (lower-tier SKU) and still run TinyLlama / Llama-7B
   workloads using the GbE fabric they need anyway for the host link.
4. **Forward-compatible with rev-B PCIe.** The Spanker driver's link
   abstraction is the same regardless of underlying transport (LVDS, GbE,
   PCIe p2p in rev-B). No driver rewrite needed when PCIe lands.
5. **Forward-compatible with rev-B+ CXL.** If CXL becomes credible on
   CertusPro-NX, it slots in as a third transport behind the same Spanker
   link abstraction.

### Why the simpler options are less attractive

* **Pure GbE (Option 2):** Llama-70B at 30 t/s is marginal. The mission
  document targets *include* Llama-70B as a stretch goal. Locking rev-A
  to GbE-only forecloses on that goal without a rev-B hardware change.
* **Pure custom LVDS (Option 1):** Forces every card to carry the LVDS
  lanes even when the workload doesn't need them, raising BOM cost on the
  cooperative-affordability tier. Also requires the host-link PHY anyway
  (GbE is the host link), so the cost saving is illusory.

### What this recommendation explicitly does NOT do

* It does **not** specify the LVDS protocol's wire format (framing, CRC
  polynomial, packet headers). Those are downstream RTL decisions in the
  Sprint 2+ implementation issues that follow this ADR's acceptance.
* It does **not** specify lane count beyond "≥1, ≤4, recommended 4". The
  Stays PCB layout (KiCad) commits to a connector that supports up to
  4 lanes; per-Sail product can populate fewer.
* It does **not** commit to CXL for any revision. Any future CXL adoption
  reopens this ADR.
* It does **not** specify topology (ring / mesh / fully-connected). The
  Stays connector pinout assumes ring-friendly (in + out per card); fully
  connected requires a switch chip and is out of cooperative-affordability
  scope.

## 8. Open questions for human ratification

Before this ADR can move to **Status: Accepted**, the cooperative needs
explicit answers to:

1. **Is Llama-70B at 30 t/s a hard rev-A goal, a stretch goal, or a
   rev-B goal?** The recommendation depends on the answer:
   - Hard rev-A goal → custom LVDS data plane is mandatory; GbE-only is
     not a viable SKU.
   - Stretch goal (current reading) → hybrid as recommended.
   - Rev-B goal → pure GbE is sufficient for rev-A; LVDS lanes can be
     deferred and the PCB simplified.

2. **What is the BOM-cost delta** of populating the LVDS connector +
   matched-impedance backplane traces vs. omitting them? The Stays team
   (Agent 2) needs to cost this before the cooperative can decide between
   hybrid and pure-GbE for the entry tier.

3. **Should Spanker's link abstraction be designed to multiplex two
   transports concurrently** (control on GbE, data on LVDS) or to route
   each transaction to one transport based on size/priority? This is a
   driver-side question for Agent 3 and influences the RTL framing.

4. **Does the cooperative accept the upstream-write-and-wait risk on
   LitePCIe-on-ECP5 for rev-B?** If Agent 4's upstream contribution
   stalls, rev-B has to find an alternative PCIe path (commercial PHY?
   CertusPro-NX PCIe hard-IP via LitePCIe's existing CertusPro-NX PHY?).

These four questions are the gate to ratification. Until they are
answered, this ADR stays **DRAFT**.

## 9. Implementation plan (conditional on acceptance)

If the cooperative ratifies the recommendation:

1. **Now (already landed):** RTL skeleton in
   `src/popsolutions/interconnect/intercard_link.sv` (#10 / PR #14, merged
   2026-05-05) locks the interface contract for the Stays PCB.
2. **Sprint 2 / agent-1:** Implement custom LVDS framing + CRC + flow
   control on top of the skeleton. Estimated 500 lines RTL + 8–10
   cocotb tests.
3. **Sprint 2 / agent-2:** Stays PCB lays out connector for 4 lanes,
   matched-impedance backplane traces, GbE PHY for host link.
4. **Sprint 3 / agent-3:** Spanker driver multi-transport link abstraction
   (GbE control plane + LVDS data plane).
5. **Sprint 3 / agent-1:** Integration test on InnerJib7EA dual-card
   bring-up.
6. **Rev-B revisit (post-tape-out):** Reopen this ADR to evaluate adding
   PCIe p2p transport (now that LitePCIe-on-ECP5 has matured upstream)
   and/or CXL on CertusPro-NX.

## 10. Consequences

(To be filled in once the ADR is **Accepted**. Currently empty because
this is a DRAFT.)

## 11. References

* Issue [#9](https://github.com/popsolutions/MAST/issues/9) — this ADR's
  tracking issue.
* Issue [#10](https://github.com/popsolutions/MAST/issues/10) — interconnect
  RTL skeleton (closed by PR #14).
* Issue [#13](https://github.com/popsolutions/MAST/issues/13) — LitePCIe
  ECP5 PHY gap (the parent decision that moved rev-A to GbE host link).
* `Stays/docs/upstream-contributions/0001-rev-a-known-upstream-issues.md`
  — Agent 4's ecosystem-health survey.
* `project_multicard_parallelism.md` (project memory) — original multi-card
  requirement.
* ADR-001 (this repo, `docs/popsolutions/ADRS.md`) — license stack and
  open-toolchain commitment.
* ADR-008 (this repo, `docs/popsolutions/ADRS.md`) — chiplet-vs-monolithic
  hybrid; provides framing for rev-A vs rev-B revisits.
* Lattice ECP5 datasheet (FPGA-DS-02012) — SerDes per-lane line rate.
* `intercard_pkg.sv` (this repo, `src/popsolutions/interconnect/`) —
  current `INTERCARD_LANES` default of 4 already aligns with the
  recommendation here.
