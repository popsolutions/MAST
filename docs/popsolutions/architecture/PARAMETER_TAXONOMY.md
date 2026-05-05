<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Parameter taxonomy

This document describes the parameter naming scheme used in MAST and the
migration plan from the upstream VeriGPU parameter set.

## Why a new scheme

The upstream VeriGPU `src/const.sv` declares three width parameters:

| Parameter | Value | Used for |
|---|---|---|
| `data_width` | 32 | both CPU register width AND memory bus width |
| `addr_width` | 32 | physical address width |
| `instr_width` | 32 | instruction fetch width |

Conflating CPU register width with memory bus width works for a single-core
academic design but becomes incorrect once we want:

1. **Wide memory transactions.** AXI4 to DDR5 / HBM3 wants a 256-bit data
   channel (one cache line per beat). CPU registers stay at 32 bits.
2. **Larger physical address space.** A POPH card with 80 GB HBM3 + 256 GB
   DDR5 needs more than 32 bits of address (which only addresses 4 GB).

PopSolutions splits the conflated names into explicit ones.

## The new parameters

Declared in `src/const.sv` (PopSolutions extensions section) and visible
globally to all modules in the same iverilog/yosys/verilator compilation
unit (the same way the upstream parameters are).

### CPU side (RISC-V semantics)

| Parameter | Value | Description |
|---|---|---|
| `xlen` | 32 | RISC-V register width. RV32 baseline; RV64 deferred to ADR-005. |
| `instr_width` | 32 | Instruction fetch width (unchanged from upstream). |
| `num_regs` | 32 | GPR count for RVA23 (unchanged from upstream). |

### Memory subsystem (AXI4 / cache line)

| Parameter | Value | Description |
|---|---|---|
| `mem_data_width` | 256 | AXI4 data channel width = one cache line per beat. |
| `cache_line_bytes` | 32 | Convenience: `mem_data_width / 8`. |
| `phys_addr_width` | 48 | Physical address width on AXI4 (256 TB max). |
| `virt_addr_width` | 48 | Sv48 virtual addressing (only used when MMU is present). |

### Compute Unit (per-Sail tunable)

| Parameter | Default | Description |
|---|---|---|
| `cu_count` | 1 | Number of Compute Units per die. Override via `-DMAST_CU_COUNT=N`. |
| `simd_lanes` | 4 | SIMD/vector lanes per CU. Override via `-DMAST_SIMD_LANES=N`. |

The defaults are tuned for **InnerJib7EA (POPC_16A)** so that out-of-the-box
simulation runs match the first-silicon target. ForeTopsail7EA and
MainTopsail7EA will override at build time.

## Legacy aliases (transitional)

The upstream parameters `data_width`, `addr_width`, `instr_width`, `num_regs`,
and `reg_sel_width` are **preserved verbatim** in `src/const.sv`. All
upstream modules (`src/core.sv`, `src/global_mem_controller.sv`, etc.) and
the protostage modules in `prot/` continue to compile unchanged.

This is intentional. We do not want to break the upstream's working test
infrastructure (iverilog smoke tests, yosys synthesis flows, GLS scripts)
in a single sweeping change.

## Migration plan

Per-file migration from `data_width` / `addr_width` to the explicit names.
Each migration is its own PR with a focused scope.

### Phase 1 — additive (this commit)

- ✅ Introduce new parameter names alongside upstream parameters in `src/const.sv`
- ✅ Document taxonomy and migration plan (this file)

### Phase 2 — new IP uses new names

All new RTL added under `src/popsolutions/` uses the explicit names from
day one:

- AXI4 memory subsystem (`src/popsolutions/axi4_*`) — uses `mem_data_width`,
  `phys_addr_width`
- LiteDRAM adapter (`src/popsolutions/litedram_*`) — uses `mem_data_width`
- LitePCIe shim (`src/popsolutions/litepcie_*`) — uses `mem_data_width`
- Compute Unit wrapper (`src/popsolutions/compute_unit_*`) — uses `xlen`,
  `simd_lanes`

### Phase 3 — upstream migration (per-file PRs)

For each upstream file that uses `data_width`/`addr_width` for memory
purposes, a focused PR replaces them with `mem_data_width`/`phys_addr_width`.
Files currently in scope:

- `src/global_mem_controller.sv` — memory bus widths (replace with new AXI4 module)
- `src/gpu_die.sv` — internal wires that connect core ↔ memory
- `src/gpu_card.sv` — top-level wiring
- `src/gpu_controller.sv` — register-mapped I/O
- `src/core.sv` — only the register file uses CPU widths; memory interface
  uses memory widths

For files where `data_width` legitimately means CPU register width (e.g.,
register file, ALU operand width), the migration replaces `data_width` with
`xlen` for clarity but leaves behavior unchanged (both are 32).

### Phase 4 — alias removal

Once all migrations are complete, the legacy aliases can be removed from
`src/const.sv` in a final cleanup PR. No earlier than 2027 to give external
contributors using upstream-style references time to adapt.

## Compile-time configuration

Sail products override per-Sail parameters via build flags. Examples:

```bash
# InnerJib7EA: defaults — 1 CU, 4 SIMD lanes
iverilog -g2012 src/const.sv ... -o sim.vvp

# ForeTopsail7EA target: 8 CUs, 16 SIMD lanes
iverilog -g2012 -DMAST_CU_COUNT=8 -DMAST_SIMD_LANES=16 src/const.sv ...

# MainTopsail7EA target: 16 CUs, 32 SIMD lanes
verilator --build -DMAST_CU_COUNT=16 -DMAST_SIMD_LANES=32 src/const.sv ...
```

Per-Sail overrides will be codified in each Sail repository's `Makefile`
or build script, not in MAST itself.

## References

- [`src/const.sv`](../../../src/const.sv) — the parameter declarations
- [`docs/popsolutions/ADRS.md`](../ADRS.md) — ADR-005 (RISC-V profile, TBD),
  ADR-006 (AXI4)
- [Issue #1](https://github.com/popsolutions/MAST/issues/1) — the originating issue
