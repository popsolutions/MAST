<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# NOTICE

This repository is a fork of [hughperkins/VeriGPU](https://github.com/hughperkins/VeriGPU)
(MIT License, Copyright (c) 2022 Hugh Perkins) and contains both upstream code
and PopSolutions cooperative additions under different licenses.

## Per-component licensing

| Scope | License | SPDX identifier |
|---|---|---|
| Upstream files (present at fork point) | MIT | `MIT` |
| New hardware contributions by PopSolutions (`.sv`, `.v`, `.vh`, PCB, schematics, design specs) | CERN-OHL-S v2 | `CERN-OHL-S-2.0` |
| New software contributions by PopSolutions (Python, C++, drivers, runtimes, test harnesses) | Apache 2.0 | `Apache-2.0` |
| New documentation contributions by PopSolutions (Markdown, diagrams, datasheets) | CC-BY-SA 4.0 | `CC-BY-SA-4.0` |

Every new file added by PopSolutions includes an SPDX license identifier in its
header. Upstream files retain their original headers (or absence thereof, in
which case MIT applies via the repository-root `LICENSE` file).

## Commercial licensing

The CERN-OHL-S v2 license is **strongly reciprocal**: any party that distributes
hardware derived from MAST under CERN-OHL-S terms must publish the source of
their modifications under the same license.

For parties that prefer not to operate under those terms, PopSolutions
Cooperative offers a **commercial license** for hardware contributions on a
case-by-case basis. Commercial licensing revenue funds cooperative operations,
contributor stipends, and tape-out costs.

Contact: `support@popsolutions.co`

## Attribution

PopSolutions extends and builds upon the work of:

- **Hugh Perkins** — original VeriGPU author (MIT, 2022).
- **The RISC-V community** — for the open RISC-V ISA.
- **The LiteX / Migen / LiteDRAM / LitePCIe communities** — for the open IP we plan to integrate.
- **CERN** — for the CERN-OHL family of open hardware licenses.
