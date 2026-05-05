// SPDX-License-Identifier: MIT AND CERN-OHL-S-2.0
//
// Original parameters (the upstream block below, lines marked):
//   Copyright (c) 2022 Hugh Perkins (upstream VeriGPU, MIT)
//
// PopSolutions extensions (everything below the "PopSolutions extensions" header):
//   Copyright (c) 2026 PopSolutions Cooperative (CERN-OHL-S v2)
//
// See repository-root NOTICE.md for the full per-component licensing structure
// and docs/popsolutions/architecture/PARAMETER_TAXONOMY.md for the rationale
// behind the dual-naming scheme.

// ============================================================================
// Upstream parameters (preserved as-is for compatibility with existing modules
// in src/*.sv that reference them by name).
// ============================================================================

parameter num_regs = 32;

parameter data_width = 32;
parameter addr_width = 32;
parameter instr_width = 32;

// parameter num_regs = 4;
// parameter data_width = 32;
// parameter addr_width = 32;

// parameter num_regs = 1;
// parameter data_width = 10;
// parameter addr_width = 1;
// parameter instr_width = 10;// parameter op_width = 10;

parameter reg_sel_width = $clog2(num_regs);

// ============================================================================
// PopSolutions extensions
//
// The upstream parameters above conflate CPU register width and memory bus
// width into a single `data_width = 32`, which was sufficient for the original
// single-core academic design. PopSolutions Sails ships products that need:
//
//   - Physical addresses up to 48 bits (256 TB) so that POPH-class cards with
//     256 GB DDR5 + 80 GB HBM3 fit comfortably in a single address space, with
//     headroom for future chiplet aggregations and CXL.mem pooling.
//   - A wide memory data path (256 bits = 32-byte cache line) so that AXI4
//     bursts to LiteDRAM and HBM3 controllers can saturate available bandwidth.
//
// The new parameters below are used by PopSolutions IP added under
// `src/popsolutions/` (AXI4 controllers, cache, LiteDRAM/LitePCIe adapters,
// Compute Unit). Upstream files continue to reference `data_width` /
// `addr_width` until per-file migration completes — see migration plan in
// docs/popsolutions/architecture/PARAMETER_TAXONOMY.md.
// ============================================================================

// --- CPU side (RISC-V semantics) ---

// `xlen` is the canonical RISC-V term for register/GPR width. RV32 is the
// baseline for InnerJib7EA and the early Sails. RV64 is targeted by a later
// ADR (placeholder ADR-005) once we have validated 64-bit addressing
// end-to-end in the verification harness.
parameter xlen = 32;

// `instr_width` (declared upstream above) remains 32. The RISC-V C extension
// allows 16-bit compressed instructions, but the fetch unit always returns a
// 32-bit aligned word and the decoder splits compressed pairs.

// --- Memory subsystem (AXI4 / cache line) ---

// `mem_data_width` is the width of the AXI4 data channel and of one cache
// line transferred per beat. 256 bits matches typical DDR5 burst granularity
// and HBM3 channel width.
parameter mem_data_width = 256;

// Convenience derivation: bytes per cache line.
parameter cache_line_bytes = mem_data_width / 8;

// `phys_addr_width` is the physical address width emitted on the AXI4 address
// channel. 48 bits gives 256 TB headroom — far above any planned Sail
// (POPH_80A targets 80 GB HBM3 + 256 GB DDR5 = 336 GB, which fits in 39 bits
// already; the headroom is for chiplet-scale aggregations and CXL.mem
// pooling).
parameter phys_addr_width = 48;

// `virt_addr_width` matches Sv48 (RISC-V 48-bit virtual addressing). For
// products that do not implement an MMU (e.g., InnerJib7EA Generation A),
// this is unused and the implementation may strap it equal to phys_addr_width.
parameter virt_addr_width = 48;

// --- Compute Unit (per-Sail tunable) ---

// CU count and SIMD lane width are overridable per Sail via Verilator/yosys
// `-D` defines. Defaults below match InnerJib7EA (POPC_16A): 1 CU, 4 SIMD
// lanes — small enough to fit in a Skywater 130nm Open MPW shuttle slot.
//
// To override at compile time:
//   verilator -DMAST_CU_COUNT=4 -DMAST_SIMD_LANES=8 ...
//   iverilog -DMAST_CU_COUNT=4 ...

`ifndef MAST_CU_COUNT
`define MAST_CU_COUNT 1
`endif
parameter cu_count = `MAST_CU_COUNT;

`ifndef MAST_SIMD_LANES
`define MAST_SIMD_LANES 4
`endif
parameter simd_lanes = `MAST_SIMD_LANES;
