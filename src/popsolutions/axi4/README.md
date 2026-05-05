<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# MAST AXI4 subsystem

Files in this directory implement the MAST internal interconnect per
[ADR-006 — Internal bus: AXI4](../../../docs/popsolutions/ADRS.md). They are
the foundation that lets us pull LiteDRAM (DDR5 controller), LitePCIe
(PCIe Gen5 shim), and other AXI4-native open IP without rewriting wrappers.

## Files

| File | Role |
|---|---|
| `axi4_const.sv` | File-scope parameters (`axi4_id_width`, `axi4_strb_width`, etc.) and channel payload typedefs (`axi4_addr_t`, `axi4_w_t`, `axi4_b_t`, `axi4_r_t`). Compiled as a source file alongside `src/const.sv`. |
| `axi4_mem_model.sv` | Functional AXI4 slave with an internal SRAM. Replaces the role of upstream `src/global_mem_controller.sv` for AXI4-attached masters in early simulation. |
| `README.md` | This file. |

## Profile (Generation A)

| Concern | Value |
|---|---|
| Variant | AXI4 full (not AXI4-Lite, not AXI3) |
| Data width | `mem_data_width = 256` (one cache line per beat) |
| Address width | `phys_addr_width = 48` (256 TB max) |
| ID width | `axi4_id_width = 4` (16 outstanding transactions per master) |
| Strobe width | `axi4_strb_width = 32` (one bit per byte, byte-granular writes) |
| Supported burst types | `INCR`, `FIXED` (WRAP not yet — falls back to INCR behavior) |
| Supported sizes | Full-width beats only (`AxSIZE = AXI4_SIZE_FULL = 5`); narrow transfers respond `SLVERR` |
| Exclusive accesses | Not supported (`AxLOCK` ignored, `EXOKAY` never emitted) |
| Protection signals | `AxPROT` propagated but not enforced |
| QoS | `AxQOS` propagated but not honored (no priority arbitration in v1) |
| User signals | `AxUSER`, `xUSER` — not present (zero width) |
| Region signals | `AxREGION` — not present |

These restrictions are **profile choices**, not protocol violations. They
narrow what we have to verify in v1. Each restriction has its own follow-up
issue when needed.

## Why AXI4 (not AXI4-Lite or TileLink)

Full AXI4 unlocks burst transfers, which we need for DDR5 efficiency and
HBM3 throughput. AXI4-Lite has no bursts. TileLink has its merits but the
open-source IP we want to leverage (LiteDRAM, LitePCIe, much of OpenCores)
speaks AXI4. See ADR-006 for the full rationale.

## How modules use this

Both files in this directory are compiled as **source files** in the
iverilog/verilator/yosys command, alongside `src/const.sv`. Their declarations
are then globally visible to all modules in the same compilation unit.
This matches the upstream VeriGPU convention and avoids the SV interface /
package compatibility issues that some tools still have.

Example iverilog invocation:

```bash
iverilog -g2012 \
    src/const.sv \
    src/popsolutions/axi4/axi4_const.sv \
    src/popsolutions/axi4/axi4_mem_model.sv \
    test/popsolutions/axi4/axi4_mem_model_tb.sv \
    -o sim.vvp
```

The `axi4_const.sv` file must come **after** `src/const.sv` (it depends on
`mem_data_width`, `phys_addr_width`, `cache_line_bytes`) and **before** any
module that uses the AXI4 parameters or types.

## Module port style

Module ports use **individual signals** (not packed structs), following the
upstream VeriGPU convention. The packed struct typedefs in `axi4_const.sv`
are provided for future use — for example, scoreboarding records in cocotb
testbenches, or interface bundles once iverilog/yosys interface-port support
matures across the toolchain.

Signal naming convention:

- Slave-side ports prefixed `s_` (e.g., `s_awvalid`, `s_rdata`)
- Master-side ports prefixed `m_` (when implemented)
- Channel signals retain AXI4 standard names (`awid`, `awaddr`, `awlen`, etc.)

## What's missing (tracked as follow-ups)

- AXI4 master skeleton (`axi4_master_simple.sv`) with a simple
  request/response wrapper for the Compute Unit
- WRAP burst support
- Narrow transfer support (sub-cache-line beats)
- Pipelined transactions (multiple outstanding per direction)
- Exclusive-access support (`AxLOCK` + `EXOKAY`)
- AXI4 → LiteDRAM adapter (DDR5 controller integration)
- AXI4 → LitePCIe adapter (PCIe Gen5 shim)
- cocotb testbench for `axi4_mem_model` (depends on Verilator+cocotb harness
  landing per MAST issue #3)

## References

- AMBA AXI4 specification: ARM IHI 0022 (Issue H or later)
- [ADR-006 — Internal bus: AXI4](../../../docs/popsolutions/ADRS.md)
- [ADR-002 — Project topology: MAST trunk + N Sails](../../../docs/popsolutions/ADRS.md)
- [`docs/popsolutions/architecture/PARAMETER_TAXONOMY.md`](../../../docs/popsolutions/architecture/PARAMETER_TAXONOMY.md)
