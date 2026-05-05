<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Architecture Decision Records (consolidated)

This file collects the foundational ADRs adopted at fork time. As decisions
mature or evolve, individual ADRs may move to `docs/popsolutions/adr/000N-*.md`
files with full status histories.

Format: each ADR is a section with **Status**, **Context**, **Decision**, and
**Consequences**.

---

## ADR-001 — Dual licensing

**Status:** Accepted (2026-05-05)

**Context:** As an open-hardware cooperative project targeting AI accelerators,
we must protect the commons (prevent appropriation by NVIDIA-class players)
while also enabling cooperative revenue to fund tape-outs.

**Decision:**

- Hardware contributions by PopSolutions (RTL, PCB, schematics, design specs):
  **CERN-OHL-S v2** (strongly reciprocal). Modifications distributed to third
  parties must be published under the same license.
- A **commercial license** is offered for parties unwilling to operate under
  reciprocal terms. Revenue funds cooperative operations and tape-out costs.
- Software contributions by PopSolutions: **Apache 2.0** (industry standard,
  patent grant, integrates with RISC-V ecosystem upstream).
- Documentation contributions by PopSolutions: **CC-BY-SA 4.0**.
- Upstream code from VeriGPU: **MIT** preserved (Hugh Perkins, 2022).

**Consequences:**

- Strong protection against capture by closed-source competitors.
- Revenue stream from commercial licensing.
- Some commercial parties may avoid contributing for strategic reasons —
  acceptable trade-off given cooperative mission.
- DCO (not CLA) is the contributor sign-off mechanism. If commercial dual-
  licensing operations require copyright assignment in the future, we will
  migrate to CLA with prior notice (see ADR-010).

---

## ADR-002 — Project topology: MAST trunk + N Sail repositories

**Status:** Accepted (2026-05-05)

**Context:** A multi-product hardware project must balance shared IP reuse
against per-product tape-out freezes. Pure monorepo causes silicon tape-out
tags to pollute unrelated products. Pure multi-repo causes IP duplication and
drift.

**Decision:** Hybrid topology.

- One central repository, **MAST**, holds the shared IP trunk: RISC-V core,
  compute unit, memory controllers, NoC, PCIe shim, verification harness,
  toolchain.
- Each Sail product is a **separate repository** (e.g., `InnerJib7EA`,
  `ForeTopsail7EA`). Each Sail vendors MAST as a git submodule pinned to a
  specific MAST release.
- When a Sail tape-outs to silicon, it freezes its MAST submodule version
  forever. Silicon is immutable; the IP that produced it must be reproducible.
- MAST evolves under SemVer. Major versions track silicon-relevant API/ISA
  changes; minor versions track non-breaking enhancements.

**Consequences:**

- Each Sail's git history is uncluttered by unrelated product churn.
- Cross-cutting changes to shared IP land in MAST and propagate via submodule
  bumps in each Sail.
- Slightly higher overhead for contributors who touch both shared IP and
  product specifics in the same change — they file two PRs.
- Naming convention: codename `<SailName><HexYear>`, SKU `POP<tier>_<mem><Gen>`
  (see `NAMING.md`).

---

## ADR-006 — Internal bus: AXI4

**Status:** Accepted (2026-05-05)

**Context:** The on-chip interconnect protocol determines which open-source
IP we can pull. Two main candidates: AXI4 (ARM, industry standard) and
TileLink (SiFive/Berkeley, Chipyard-native).

**Decision:** **AXI4** (full profile, not Lite, except where performance is
not critical).

**Consequences:**

- Direct ability to pull LiteDRAM (DDR5 controller open), LitePCIe (PCIe Gen5
  open), and other AXI4-native open IP without writing wrappers. Saves an
  estimated 6–12 months of engineering for a small team.
- More signals than TileLink, slightly higher area cost per interface.
- Cache coherency requires extension (ACE or CHI) when needed. For Generation
  A, coherency is limited to the compute unit boundary; cross-CU coherency is
  a future extension.
- Engineers from USP/UNICAMP/CTI Renato Archer and the broader RISC-V
  community already know AXI4 — onboarding friction is minimal.

---

## ADR-007 — POPH positioning (Generation A)

**Status:** Accepted (2026-05-05)

**Context:** The POPH (high-tier, training-capable) line could in principle
target frontier pretraining (100B+ parameter models). Realistically, frontier
pretraining is a $100M+ engineering effort against NVIDIA's NVLink and HBM3
advantages, which we cannot win in Generation A.

**Decision:** For **Generation A only** (silicon 2026 designs):

- POPH_80A targets **fine-tuning**, **medium-scale training (≤13B parameters)**,
  and **research**. Frontier pretraining is out of scope for this generation.
- Spec: 80 GB HBM3 (1 stack, ~1 TB/s) + 256 GB DDR5 RDIMM tiered, 32 TFLOPS
  BF16 native + INT8 at 4× that, 200 GB/s inter-card via PCIe Gen5 + CXL.cache.
  ~400 W TDP. Target BOM R$ 25-30k.
- Audience: Brazilian universities, AI startups, sovereignty-focused
  government workloads, research labs.

**For Generation B and beyond:** the cooperative board will re-evaluate
positioning before committing to next-gen tape-out, informed by Gen A
deployment lessons, funding state, and technology evolution (HBM4, open
NVLink-equivalents, mature UCIe, advanced packaging availability in Brazil
or partner countries). Frontier pretraining is **not foreclosed** — it is
deferred to a structured re-evaluation gate.

**Consequences:**

- Clear focus enables Gen A delivery within cooperative resource constraints.
- Marketing and developer expectations are calibrated honestly.
- Optionality on future ambition is preserved. The non-goal is generation-
  scoped, not permanent.

---

## ADR-008 — Chiplet vs monolithic strategy: Hybrid

**Status:** Accepted (2026-05-05)

**Context:** Chiplets enable heterogeneous process nodes (compute in 28nm,
I/O in 130nm), better yield, modularity, and incremental refresh — aligning
with the user's "future expansion" goal. However, chiplet packaging is more
expensive and complex than monolithic, and open-source UCIe IP is nascent.

**Decision:** Hybrid path tied to product line:

- **InnerJib7EA (POPC_16A)** = **monolithic** in Skywater 130nm via Google
  Open MPW shuttle (~US$ 10–50k tape-out, possibly free shuttle slot). This
  is the validation tape-out: proves design flow, RTL, verification, and
  driver, with near-zero risk and near-zero cost.
- **ForeTopsail7EA (POPC_128A)** and **MainTopsail7EA (POPH_80A)** =
  **chiplet** from day 1. Compute chiplet in 28nm, I/O chiplet in 130nm,
  HBM I/O specialization for the POPH. Packaging via interposer (silicon or
  organic).

**Consequences:**

- First silicon ships at lowest possible cost, generating community proof
  and credibility while larger Sails are still in design.
- Risks documented:
  - **UCIe IP nascent in open-source.** First Sails will likely use a
    project-internal `MAST-link` (simple, lower-bandwidth UCIe-precursor).
  - **28nm tape-out funding gate.** ~US$ 500k–1M per chiplet tape-out is a
    real funding dependency before Gen A Sails go to fab.
  - **Packaging dependency.** Either international partnership (Taiwan/Korea
    OSAT) or local capacity (CTI Renato Archer in Brazil, with limits). This
    is a strategic supply-chain decision deferred to a later ADR.

---

## ADR-010 — Governance: Contributor Covenant + DCO + role ladder

**Status:** Accepted (2026-05-05)

**Context:** A cooperative open-source project with global ambition needs
clear, low-friction contribution and decision-making processes that respect
cooperative principles.

**Decision:**

- **Code of Conduct:** Contributor Covenant 2.1, **bilingual PT/EN**.
  Enforcement by a 3-member committee (1 from cooperative board + 2
  contributor representatives elected annually). Bilingual version is
  forthcoming as a follow-up issue; Covenant 2.1 English baseline applies in
  the interim.
- **Sign-off:** **DCO** (Developer Certificate of Origin). Every commit must
  carry `Signed-off-by:`. **No CLA** at this time. CLA may be considered
  later if commercial dual-license operations require copyright assignment;
  introduction will require ADR amendment and 30-day notice to contributors.
- **Role ladder:**
  1. Anyone can open issues and comment.
  2. Contributors can open DCO-signed PRs.
  3. Reviewers (recognized by maintainer nomination) can review PRs.
  4. Maintainers can merge PRs in their sub-area.
  5. Core maintainers can merge PRs to MAST trunk.
  6. Tape-out coordinators (explicit role) authorize fab submissions.
- **Decision making:** Two layers.
  - **Code/technical:** PR review + ADR process (technical meritocracy).
  - **Strategic** (license, tape-out commitments, financial, role
    appointments): cooperative board, one-member-one-vote.
- **Tape-out authority:** Both technical (lead maintainer signing readiness)
  AND board (signing financial commitment) are required to authorize a
  tape-out. Documented in `TAPE_OUT_AUTHORITY.md` (forthcoming).
- **ADR process:** Anyone proposes via PR adding ADR file with status
  "Proposed". Core maintainers vote within 14 days. Strategic ADRs require
  board ratification.

**Consequences:**

- Low contributor friction with DCO; minimal legal overhead.
- Clear escalation path for both code and strategic decisions.
- Cooperative principles preserved at the strategic layer; technical
  meritocracy at the code layer.
- Tape-out gating prevents unilateral commitments of cooperative funds.

---

## Future ADRs (placeholders)

- **ADR-003** — Custom matrix extension `Xpop_matmul` design (TBD)
- **ADR-004** — SKU and codename naming convention (documented in `NAMING.md`)
- **ADR-005** — RISC-V profile selection: RVA23 + RVV 1.0 + custom (TBD)
- **ADR-009** — Memory hierarchy: HBM3 + DDR5 tiered for POPH (TBD)
- **ADR-011** — Verification methodology: Verilator + cocotb (TBD)
- **ADR-012** — Toolchain pinning and reproducible builds (TBD)
- **ADR-013** — Packaging strategy: international vs local (TBD)
