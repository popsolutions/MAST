<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Contributing to MAST

Thank you for your interest in contributing to PopSolutions Sails. This project
is community-driven and we welcome PRs of all sizes — typo fixes, ADR proposals,
RTL improvements, software stack work, documentation, or new test cases.

## Developer Certificate of Origin (DCO)

We use the **DCO** (not a CLA) to keep contribution friction low.

Every commit must include a `Signed-off-by:` trailer asserting that you have
the right to submit the change. Add it automatically with:

```bash
git commit -s -m "your message"
```

This adds:

```
Signed-off-by: Your Name <your.email@example.com>
```

The full text of the DCO is at <https://developercertificate.org/>. By signing
off you certify that the contribution is your work or that you have the right
to submit it under the project's open licenses (CERN-OHL-S v2 for hardware,
Apache 2.0 for software, CC-BY-SA 4.0 for docs).

## Workflow

1. Open an issue describing the problem or proposal (unless the change is trivial).
2. Fork the repository (yes, we're a fork too — fork-of-fork is fine).
3. Create a topic branch off `main`: `git checkout -b topic/your-change`.
4. Make your change. For non-trivial design decisions, draft an ADR under
   `docs/popsolutions/adr/` (see existing ADRs for the format).
5. Run the tests (`make test` once test infrastructure lands — see open issues).
6. Commit with `-s` to add the DCO sign-off.
7. Push and open a PR. Reference the originating issue.
8. A reviewer will provide feedback. Once approved by a maintainer, your PR
   will be merged.

## Architectural Decision Records (ADRs)

Significant decisions (new ISA extensions, license changes, cross-cutting
architectural shifts) require an ADR. The format is short — one page is
sufficient. See `docs/popsolutions/adr/` for examples.

ADR review process:
- Anyone may propose an ADR (open a PR adding the file with status "Proposed").
- Core maintainers vote within 14 days.
- Strategic ADRs (license, tape-out commitments, financial) require board
  ratification.

## Code style

- SystemVerilog: follow the existing upstream style. New files use
  `default_nettype none` and 4-space indentation. SPDX header on top.
- Python: PEP 8, type hints encouraged, ruff-compatible.
- C/C++: clang-format with the project's `.clang-format`.
- Markdown: 80-character soft wrap; reference-style links for long URLs.

## Reporting security issues

Please **do not** file public issues for vulnerabilities. See `SECURITY.md`
(forthcoming) or email `security@popsolutions.co`.

## Code of Conduct

By participating, you agree to follow our Code of Conduct (Contributor
Covenant 2.1, forthcoming bilingual PT/EN).
