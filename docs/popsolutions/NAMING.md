<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Naming conventions

PopSolutions Sails uses two parallel naming schemes for every product: an
**internal codename** (used in source code, branches, internal docs) and a
**public SKU** (used on packaging, datasheets, marketing, NF-e).

## Public SKU format

```
POP<tier>_<memory><GenLetter>
```

| Component | Values | Meaning |
|---|---|---|
| `<tier>` | `C`, `H` | `C` = compact tier (inference / embedded, DDR5-only); `H` = high tier (training-capable, HBM3 + DDR5 tiered) |
| `<memory>` | integer | Capacity in GB. For POPH this is HBM3; for POPC this is DDR5 |
| `<GenLetter>` | `A`, `B`, `C`, ... | Silicon generation. `A` = first silicon (2026 design), `B` = refresh (e.g., 2029 design), and so on |

**Examples:** `POPC_16A`, `POPC_128A`, `POPH_80A`, `POPC_256B`.

Reading: the letter advances on every new silicon; the number tells you the
actual memory of that silicon.

## Internal codename format

```
<SailName><HexYear>
```

`SailName` follows tall-ship sail terminology (see fleet table below). `HexYear`
is the 3-digit hexadecimal representation of the design-start year:

| Decimal year | Hex | Codename suffix |
|---|---|---|
| 2026 | 7EA | `7EA` |
| 2027 | 7EB | `7EB` |
| 2028 | 7EC | `7EC` |
| 2029 | 7ED | `7ED` |
| 2030 | 7EE | `7EE` |
| ... | ... | ... |
| 4095 | FFF | `FFF` (3-hex-digit limit) |

3 hex digits cover up to year 4095, which is enough for several human
civilizational epochs.

## Mast → product family mapping

The metaphor of a tall ship maps onto the product line:

| Mast region | Family | Examples |
|---|---|---|
| Proa (jibs / staysails) | Embedded / edge / dev kits | `InnerJib`, `OuterJib`, `FlyingJib` |
| Foremast | Inference cards | `Foresail`, `ForeTopsail`, `ForeTopgallant`, `ForeRoyal` |
| Center staysails | Specialized coprocessors (NPU-only, vision, audio) | `MainStaysail` |
| Mainmast | Training cards | `Mainsail`, `MainTopsail`, `MainTopgallant`, `MainRoyal` |
| Mizzenmast | Cluster fabric / interconnect | `MizzenTopsail`, `MizzenRoyal` |
| Spanker (driver) | Control-plane software (helmsman, not a sail) | `Spanker` |

Within each mast, sail tier indicates SKU position from low to high:

```
course (entry) → topsail (mainstream) → topgallant (workstation)
              → royal (server) → skysail (datacenter) → moonsail (halo)
```

## Codename ↔ SKU mapping (Generation A, 2026 designs)

| Codename | SKU | Class | Notes |
|---|---|---|---|
| `InnerJib7EA` | `POPC_16A` | Embedded entry SBC | First tape-out, monolithic Skywater 130nm |
| `OuterJib7EA` | `POPC_8A` (TBD) | Embedded mid (planned) | Larger NPU |
| `Foresail7EA` | `POPC_64A` (TBD) | Inference entry (planned) | DDR5 single channel |
| `ForeTopsail7EA` | `POPC_128A` | Inference mainstream | 8-channel DDR5, chiplet |
| `Mainsail7EA` | `POPH_32A` (TBD) | Training entry (planned) | HBM3 32 GB |
| `MainTopsail7EA` | `POPH_80A` | Training mainstream | HBM3 80 GB + DDR5 tiered, chiplet |
| `Spanker7EA` | (n/a) | Software stack | Driver, runtime, GGML/PyTorch backends |

(TBD entries are placeholders; SKU numbers will be confirmed when the
respective Sail spec is locked.)

## Brand names

| Surface | Name | Where it appears |
|---|---|---|
| Cooperative | PopSolutions | Legal entity |
| Product line (collective) | PopSolutions Sails | Marketing, packaging |
| Individual product | `<SailName><HexYear>` codename for engineering, `POP<tier>_<mem><Gen>` SKU for retail | Both contexts |
| Shared IP repo | `MAST` | GitHub repo, internal discussions |

`MAST` is technical/internal only — it does **not** appear on packaging or
end-user marketing. The customer-facing brand is "PopSolutions Sails".
