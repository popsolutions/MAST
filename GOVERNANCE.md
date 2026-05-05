<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Governance — popsolutions/MAST

This document codifies how decisions are made in MAST and the broader
PopSolutions Sails program. See [ADR-010](docs/popsolutions/ADRS.md) for
the underlying decision; this file is the operational counterpart.

## Cooperative-only contribution

**Code contribution to MAST and its derived Sail repositories is
restricted to PopSolutions cooperative members.** This applies to
anyone — Brazilian, foreign, individual, or institutional — who wants
to land changes via pull request.

### Why

Hardware decisions have real cost. A tape-out commitment is a
six-figure financial decision that the cooperative is collectively
liable for. The license stack (CERN-OHL-S v2 + commercial dual-license
per ADR-001) generates revenue that flows back to the cooperative. Both
of these mean every contributor's choices touch cooperative money and
cooperative obligations. Membership ensures contributors have skin in
the game and accountability via the cooperative's internal processes.

This is not exclusion of outsiders. It is a cooperative reading of what
"open source" means in a hardware context where the artefacts cost
money to make and the licensing has a commercial leg.

### Pathway to membership

The cooperative is open to applicants worldwide. There is no minimum
financial commitment for a code-track membership. Process:

1. Open an issue titled `[membership] application: <your name>` on
   `popsolutions/MAST`. State the area you want to contribute to (RTL,
   verification, software stack, documentation, PCB design, etc.).
2. The cooperative board reviews applications at its monthly meeting.
3. Accepted applicants are added to a dedicated `contributors` GitHub
   team and granted PR-write access on the MAST org repos.
4. First contribution may be paired with an existing maintainer for
   onboarding.

Read-only access (clone, build, test, study the code) requires no
membership and is governed only by the project's open licenses.

## Role ladder

```
                   anyone (read-only)
                          │
                          ▼ (apply, get accepted)
                   contributor       — can open DCO-signed PRs
                          │
                          ▼ (consistent quality, time)
                   reviewer          — can approve PRs in their area
                          │
                          ▼ (broad expertise + trust)
                   maintainer        — can merge PRs in sub-area
                          │
                          ▼ (board appointment)
                   core maintainer   — can merge to MAST trunk
                          │
                          ▼ (board + technical lead)
                   tape-out coord    — authorises fab submissions
```

Promotion between levels happens via cooperative board decision after
demonstrated technical contribution. Demotion is the same path in
reverse. Tape-out coordinator is the only role with binding financial
authority on its own — see "Tape-out authority" below.

## Decision-making layers

Two distinct decision layers run in parallel:

**Technical** — code, RTL, verification methodology, ADR proposals.
- Mechanism: PR review + `docs/popsolutions/adr/` process.
- Voters: contributors and above per role ladder.
- Default: 14-day vote window on ADRs; merge-button on routine PRs after
  CI green and code review (see PR review process below).

**Strategic** — license, tape-out commitments, financial, role
appointments, partnership agreements, this governance document itself.
- Mechanism: cooperative board, one-member-one-vote.
- Voters: cooperative members.
- Default: board meetings as scheduled in cooperative bylaws.
- Veto: the board can veto any technical decision that crosses into
  strategic territory (e.g., an ADR proposing a license change).

## PR review process

Every PR follows:

1. Author opens PR linked to a tracking issue.
2. Continuous Integration runs (`.github/workflows/ci.yml`). PR cannot
   merge while CI is red.
3. At least one reviewer (anyone at reviewer level or above for the
   relevant area) reads the diff and either approves or requests
   changes. Severity classification per
   [`docs/popsolutions/code-review-rubric.md`](docs/popsolutions/code-review-rubric.md)
   (forthcoming):
   - CRITICAL (security, data loss): blocks merge.
   - HIGH (bug, quality): should fix before merge.
   - MEDIUM (maintainability): consider fixing.
   - LOW (style, minor): note, optional.
4. Author addresses CRITICAL and HIGH findings on the same branch and
   pushes fixes. CI re-runs.
5. Reviewer or a maintainer merges when no CRITICAL or HIGH findings
   remain.

**Self-review bridge for the solo / AI-assisted development phase.**
The project is currently developed by one cooperative member (the
human user) plus an AI agent acting as code author. During this phase
the AI agent is explicitly responsible for running an independent
review pass on every PR it authors, using the project's
`code-reviewer` agent (or the language-specific reviewer where
appropriate). Two enforceable constraints govern this bridge:

1. **Findings must surface to the human.** Any CRITICAL or HIGH
   severity finding from the AI reviewer must be left as a visible
   comment on the PR before merge, even if the AI agent also
   addresses the finding on the same branch. The human user must be
   able to see the original finding without having to dig through
   code-reviewer agent transcripts.

2. **AI self-merge is delegated by the founding member during the
   bootstrap phase.** The original draft of this clause prohibited AI
   self-merge. The founding cooperative member has explicitly
   delegated merge authority to the AI agent for routine engineering
   PRs, and the delegation is documented in the project's private
   memory store with date and rationale. The delegation is bounded:

   - **In scope** (AI may merge after the self-review steps above):
     - RTL changes, software changes, verification additions
     - Project-internal documentation
     - CI / tooling / test fixtures
     - Refactoring and cleanup
     - Dependency / submodule pin bumps that follow a green CI run

   - **Out of scope** (still requires explicit human action):
     - Strategic decisions: license, governance itself, MVP target
       redefinition, mission statement
     - Tape-out submissions to silicon foundries — the dual sign-off
       in `TAPE_OUT_AUTHORITY.md` requires both signatures and the
       AI cannot satisfy either
     - Public statements, marketing copy, partnership commitments,
       financial commitments — all owned by the cooperative board
     - Force-pushes to `main`, history rewrites, repo deletions, or
       any other destructive operation
     - Granting cooperative membership or role-ladder promotions

   The human user retains the right to revert any merge they
   disagree with; this delegation is trust, not abdication. If the
   user pushes back on a merge after the fact, the agent must treat
   that as a strong signal to recalibrate what blocks vs. what
   doesn't, and update the project's private memory accordingly.

This bridge applies until the cooperative grows enough contributors
to have human-only review by default. At that point the bridge is
removed by amendment per the process at the bottom of this document.

## Tape-out authority

Tape-out submissions to silicon foundries (Skywater Open MPW, future
TSMC / GlobalFoundries shuttles) commit cooperative money and create
multi-year obligations. Authority is **dual sign-off**:

- **Technical lead** signs RTL/verification readiness — confirms that
  the design has passed all required gates, the IP submodule pins are
  immutable post-tag, and known issues are documented.
- **Cooperative board** signs the financial and supply-chain commitment
  — confirms funds are available, foundry contract is in order, and
  any partnership obligations are met.

**Definition of "technical lead".** The technical lead for a given
tape-out is, by default, the founding cooperative member who initiated
the project (Marcos Méndez during the bootstrap phase). The board may
reassign the role to any current core maintainer by recorded vote.
There is no scenario in which the role is vacant and tape-out can
proceed; if the appointed technical lead is unavailable, the board
must designate a replacement before sign-off. The role exists in
addition to — and is distinct from — the "tape-out coordinator"
position in the role ladder above; tape-out coordinator is a process
role (paperwork, foundry liaison) while technical lead is the
substantive sign-off authority for design correctness.

Both signatures must be recorded in
`docs/popsolutions/tape-outs/<tape-out-id>.md` before the design is
sent. Either signature alone is insufficient. Either signature can be
withdrawn for cause prior to fab handoff, blocking the tape-out.

**Signature format until `TAPE_OUT_AUTHORITY.md` lands.** Until that
operational document defines a formal record format, signatures are
acceptable in either of two forms:

- A GPG-signed git commit creating
  `docs/popsolutions/tape-outs/<id>.md` with the signer named in
  the commit metadata and the commit message stating the role the
  signature represents (e.g., *"sign-off as technical lead for
  tape-out 7EA-001"*).
- A PR review comment on the tape-out submission PR, by the
  responsible party, explicitly citing
  `Approved as <role> for tape-out <id>`.

Both forms are auditable in git history. `TAPE_OUT_AUTHORITY.md` may
later supersede this fallback with a more formal procedure; until
then, neither form is privileged over the other.

## Code of Conduct enforcement

A Code of Conduct based on the Contributor Covenant 2.1 (forthcoming
bilingual PT/EN) applies to all spaces — this repo, issues, PRs, the
PopSolutions Forgejo, mailing lists, chat. Enforcement is by a
**3-person committee**:

- 1 cooperative board member (rotating annually)
- 2 contributor representatives (elected annually by the contributor
  group)

Reports of violations go to `coc@popsolutions.co` (private inbox).
Sanctions ladder:
1. Private warning.
2. Public warning + temporary cooldown from project spaces (1 week).
3. Temporary ban (30 days).
4. Permanent ban + revocation of cooperative membership where
   applicable.

The CoC committee publishes an annual transparency report listing
(anonymised) reports received and outcomes.

## Amendment process

This document is a strategic artefact. Amendments require:

1. PR proposing the change with rationale.
2. 30-day public comment period on the PR.
3. Cooperative board vote (one-member-one-vote, simple majority).

Routine clarifications (typos, formatting, link fixes) can land via
normal PR without the comment period, at the discretion of the
maintainer who merges them.
