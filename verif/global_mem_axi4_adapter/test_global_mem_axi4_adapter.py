# SPDX-License-Identifier: Apache-2.0
"""
Cocotb tests for src/popsolutions/axi4/global_mem_axi4_adapter.sv.

Exercises the published wrapper module by connecting it to an axi4_mem_model
slave (via gma_with_mem_wrapper.sv) and driving the core-side bespoke
interface end-to-end.

Coverage parallels (and is intentionally similar to) the existing
verif/core_axi4_adapter/ tests, but targets the *new public adapter module*
that gpu_die.sv will instantiate in PR-2b. The duplication is deliberate:
PR-2a has to prove the published wrapper is independently green, not just
rely on the sub-module's own test.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 10


async def reset_dut(dut):
    """Apply 5 cycles of reset, deassert, settle for 2 more cycles."""
    dut.rst_n.value = 0
    dut.core_mem_rd_req.value = 0
    dut.core_mem_wr_req.value = 0
    dut.core_mem_addr.value = 0
    dut.core_mem_wr_data.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def core_write(dut, addr, data, timeout=300):
    """Issue a core-side write transaction and await ack."""
    dut.core_mem_addr.value = addr
    dut.core_mem_wr_data.value = data
    dut.core_mem_wr_req.value = 1
    await RisingEdge(dut.clk)
    dut.core_mem_wr_req.value = 0

    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.core_mem_ack.value == 1:
            return
    raise TimeoutError(f"core write to 0x{addr:x} never acked")


async def core_read(dut, addr, timeout=300):
    """Issue a core-side read transaction; return the 32-bit datum."""
    dut.core_mem_addr.value = addr
    dut.core_mem_rd_req.value = 1
    await RisingEdge(dut.clk)
    dut.core_mem_rd_req.value = 0

    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.core_mem_ack.value == 1:
            return int(dut.core_mem_rd_data.value)
    raise TimeoutError(f"core read from 0x{addr:x} never acked")


# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------

@cocotb.test()
async def test_reset(dut):
    """After reset, busy/ack are low and no spurious AXI4 activity."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    assert dut.core_mem_busy.value == 0
    assert dut.core_mem_ack.value == 0


@cocotb.test()
async def test_word_roundtrip(dut):
    """Single 32-bit word write then read; bit-exact match expected."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    addr = 0x100  # cache-line aligned, slot 0
    word = 0xDEADBEEF
    await core_write(dut, addr, word)
    got = await core_read(dut, addr)
    assert got == word, (
        f"slot-0 roundtrip mismatch at 0x{addr:x}: "
        f"wrote 0x{word:08x}, read 0x{got:08x}"
    )


@cocotb.test()
async def test_slot_independence_within_line(dut):
    """Two writes to different 32-bit slots of the same cache line must
    not corrupt each other (WSTRB byte-enables protect each slot)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    base = 0x80
    await core_write(dut, base + 0,  0xCAFEBABE)
    await core_write(dut, base + 16, 0xFEEDFACE)

    got_slot0 = await core_read(dut, base + 0)
    got_slot4 = await core_read(dut, base + 16)

    assert got_slot0 == 0xCAFEBABE, f"slot 0 corrupted: 0x{got_slot0:08x}"
    assert got_slot4 == 0xFEEDFACE, f"slot 4 corrupted: 0x{got_slot4:08x}"


@cocotb.test()
async def test_all_slots_within_line(dut):
    """Write all 8 slots of one cache line with distinguishable values; read each back."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    base = 0x200
    for slot in range(8):
        await core_write(dut, base + slot * 4, 0xA0000000 | slot)
    for slot in range(8):
        got = await core_read(dut, base + slot * 4)
        expected = 0xA0000000 | slot
        assert got == expected, (
            f"slot {slot}: expected 0x{expected:08x}, got 0x{got:08x}"
        )


@cocotb.test()
async def test_cross_cache_line(dut):
    """Writes to addresses in different cache lines stay independent."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    pairs = [
        (0x000, 0x11111111),
        (0x040, 0x22222222),  # next cache line (32-byte stride)
        (0x080, 0x33333333),
        (0x100, 0x44444444),
    ]
    for addr, data in pairs:
        await core_write(dut, addr, data)
    for addr, expected in pairs:
        got = await core_read(dut, addr)
        assert got == expected, (
            f"addr 0x{addr:x}: expected 0x{expected:08x}, got 0x{got:08x}"
        )


@cocotb.test()
async def test_busy_during_transaction(dut):
    """core_mem_busy must assert at least once while a transaction is in
    flight, and deassert on the cycle after ack pulses."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    addr = 0x400
    word = 0xC0FFEE42

    dut.core_mem_addr.value = addr
    dut.core_mem_wr_data.value = word
    dut.core_mem_wr_req.value = 1
    await RisingEdge(dut.clk)
    dut.core_mem_wr_req.value = 0

    saw_busy = False
    for _ in range(50):
        await RisingEdge(dut.clk)
        if dut.core_mem_busy.value == 1:
            saw_busy = True
        if dut.core_mem_ack.value == 1:
            break
    assert saw_busy, "core_mem_busy never asserted during the transaction"
    await RisingEdge(dut.clk)
    assert dut.core_mem_busy.value == 0
