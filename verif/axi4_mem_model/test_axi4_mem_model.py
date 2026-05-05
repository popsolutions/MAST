# SPDX-License-Identifier: Apache-2.0
"""
Cocotb testbench for src/popsolutions/axi4/axi4_mem_model.sv.

Exercises the AXI4 slave skeleton: post-reset readiness, single-beat
write/read round-trip, multi-beat INCR burst, and profile-rejection of
narrow transfers.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CLK_PERIOD_NS = 10

# AXI4 profile constants (must match src/popsolutions/axi4/axi4_const.sv)
AXI4_SIZE_FULL = 5  # log2(32) for 256-bit / 32-byte beats
AXI4_BURST_FIXED = 0
AXI4_BURST_INCR = 1
AXI4_BURST_WRAP = 2

AXI4_RESP_OKAY = 0
AXI4_RESP_EXOKAY = 1
AXI4_RESP_SLVERR = 2
AXI4_RESP_DECERR = 3

DATA_WIDTH = 256
STRB_WIDTH = DATA_WIDTH // 8        # = 32
STRB_ALL = (1 << STRB_WIDTH) - 1    # all 32 bytes enabled


async def reset_dut(dut):
    """Apply 5 clock cycles of reset, deassert, then settle."""
    dut.rst_n.value = 0

    # Initialise every input to a known safe value
    dut.s_awid.value = 0
    dut.s_awaddr.value = 0
    dut.s_awlen.value = 0
    dut.s_awsize.value = AXI4_SIZE_FULL
    dut.s_awburst.value = AXI4_BURST_INCR
    dut.s_awvalid.value = 0
    dut.s_wdata.value = 0
    dut.s_wstrb.value = 0
    dut.s_wlast.value = 0
    dut.s_wvalid.value = 0
    dut.s_bready.value = 0
    dut.s_arid.value = 0
    dut.s_araddr.value = 0
    dut.s_arlen.value = 0
    dut.s_arsize.value = AXI4_SIZE_FULL
    dut.s_arburst.value = AXI4_BURST_INCR
    dut.s_arvalid.value = 0
    dut.s_rready.value = 0

    # loader back-door (added with the program-loading feature)
    dut.loader_en.value = 0
    dut.loader_addr.value = 0
    dut.loader_data.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def axi_write(dut, addr, data, wstrb=STRB_ALL,
                    length=0, burst=AXI4_BURST_INCR, txn_id=0,
                    awsize=AXI4_SIZE_FULL):
    """Issue an AXI4 write burst.

    `data` may be a single int (one beat) or a list of ints (length+1 beats).
    Returns (bresp, bid).
    """
    if isinstance(data, int):
        data = [data]
    assert len(data) == length + 1, \
        f"data length {len(data)} != burst length+1 {length + 1}"

    # AW handshake
    dut.s_awid.value = txn_id
    dut.s_awaddr.value = addr
    dut.s_awlen.value = length
    dut.s_awsize.value = awsize
    dut.s_awburst.value = burst
    dut.s_awvalid.value = 1
    while True:
        await RisingEdge(dut.clk)
        if dut.s_awready.value == 1:
            break
    dut.s_awvalid.value = 0

    # W beats
    for i, beat in enumerate(data):
        dut.s_wdata.value = beat
        dut.s_wstrb.value = wstrb
        dut.s_wlast.value = 1 if i == len(data) - 1 else 0
        dut.s_wvalid.value = 1
        while True:
            await RisingEdge(dut.clk)
            if dut.s_wready.value == 1:
                break
    dut.s_wvalid.value = 0
    dut.s_wlast.value = 0

    # B handshake
    dut.s_bready.value = 1
    while True:
        await RisingEdge(dut.clk)
        if dut.s_bvalid.value == 1:
            break
    bresp = int(dut.s_bresp.value)
    bid = int(dut.s_bid.value)
    await RisingEdge(dut.clk)
    dut.s_bready.value = 0
    return bresp, bid


async def axi_read(dut, addr, length=0, burst=AXI4_BURST_INCR, txn_id=0,
                   arsize=AXI4_SIZE_FULL):
    """Issue an AXI4 read burst. Returns (rresp_first, rid_first, [data_beats])."""
    # AR handshake
    dut.s_arid.value = txn_id
    dut.s_araddr.value = addr
    dut.s_arlen.value = length
    dut.s_arsize.value = arsize
    dut.s_arburst.value = burst
    dut.s_arvalid.value = 1
    while True:
        await RisingEdge(dut.clk)
        if dut.s_arready.value == 1:
            break
    dut.s_arvalid.value = 0

    beats = []
    rresp_first = None
    rid_first = None
    dut.s_rready.value = 1
    for _ in range(length + 1):
        while True:
            await RisingEdge(dut.clk)
            if dut.s_rvalid.value == 1:
                break
        beats.append(int(dut.s_rdata.value))
        if rresp_first is None:
            rresp_first = int(dut.s_rresp.value)
            rid_first = int(dut.s_rid.value)
    await RisingEdge(dut.clk)
    dut.s_rready.value = 0
    return rresp_first, rid_first, beats


# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------

@cocotb.test()
async def test_reset(dut):
    """After reset, slave is ready to accept transactions; no spurious responses."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    assert dut.s_awready.value == 1, "awready should be 1 after reset"
    assert dut.s_arready.value == 1, "arready should be 1 after reset"
    assert dut.s_bvalid.value == 0, "bvalid should be 0 after reset"
    assert dut.s_rvalid.value == 0, "rvalid should be 0 after reset"


@cocotb.test()
async def test_single_beat_write_read(dut):
    """Write a 256-bit value at addr 0, read it back, expect bit-exact match."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    test_data = 0xDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEEDFACE_BAADF00D_01234567_89ABCDEF
    bresp, _ = await axi_write(dut, addr=0, data=test_data)
    assert bresp == AXI4_RESP_OKAY, f"write returned {bresp}"

    rresp, _, beats = await axi_read(dut, addr=0)
    assert rresp == AXI4_RESP_OKAY, f"read returned {rresp}"
    assert len(beats) == 1
    assert beats[0] == test_data, \
        f"data mismatch:\n  wrote {test_data:064x}\n  read  {beats[0]:064x}"


@cocotb.test()
async def test_multi_beat_incr(dut):
    """4-beat INCR burst write then read back; verify each beat lands at its own address."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    base_addr = 0x40  # cache-line aligned (32-byte multiple)
    test_beats = [
        0x1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111,
        0x2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222,
        0x3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333,
        0x4444_4444_4444_4444_4444_4444_4444_4444_4444_4444_4444_4444_4444_4444_4444_4444,
    ]

    bresp, _ = await axi_write(dut, addr=base_addr, data=test_beats, length=3)
    assert bresp == AXI4_RESP_OKAY, f"write returned {bresp}"

    rresp, _, beats = await axi_read(dut, addr=base_addr, length=3)
    assert rresp == AXI4_RESP_OKAY, f"read returned {rresp}"
    assert len(beats) == 4
    for i, (got, expected) in enumerate(zip(beats, test_beats)):
        assert got == expected, \
            f"beat {i} mismatch:\n  expected {expected:064x}\n  got      {got:064x}"


@cocotb.test()
async def test_narrow_size_rejected(dut):
    """Profile rejects narrow transfers — request with AxSIZE != FULL must respond SLVERR."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    # Try a single-beat write with AxSIZE = 2 (4-byte beats — narrower than full 32-byte)
    bresp, _ = await axi_write(
        dut, addr=0, data=0xDEADBEEF, length=0,
        burst=AXI4_BURST_INCR, awsize=2
    )
    assert bresp == AXI4_RESP_SLVERR, \
        f"narrow transfer should respond SLVERR ({AXI4_RESP_SLVERR}), got {bresp}"


@cocotb.test()
async def test_byte_strobed_partial_write(dut):
    """Two writes to same addr with disjoint strobes; merged data must reflect both."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    addr = 0x80
    initial = 0xFEEDFACE_BAADF00D_01234567_89ABCDEF_DEADBEEF_CAFEBABE_12345678_9ABCDEF0
    bresp, _ = await axi_write(dut, addr=addr, data=initial)
    assert bresp == AXI4_RESP_OKAY

    # Overwrite only the lowest 4 bytes
    overwrite_data = 0xFFFFFFFF
    overwrite_strb = 0x0000000F
    bresp, _ = await axi_write(dut, addr=addr, data=overwrite_data, wstrb=overwrite_strb)
    assert bresp == AXI4_RESP_OKAY

    rresp, _, beats = await axi_read(dut, addr=addr)
    assert rresp == AXI4_RESP_OKAY
    expected = (initial & ~0xFFFFFFFF) | 0xFFFFFFFF
    assert beats[0] == expected, \
        f"strobed write mismatch:\n  expected {expected:064x}\n  got      {beats[0]:064x}"


@cocotb.test()
async def test_loader_then_axi4_read(dut):
    """Back-door loader writes 32-bit words by byte address; AXI4 reads see them.

    This is the program-loading path used by inner_jib_top tests:
    pre-populate the SRAM with instruction words via loader_en, then let
    the core (or master) fetch them through the AXI4 interface as if
    the words had always been there.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await reset_dut(dut)

    # Load 4 distinct 32-bit words across two consecutive 32-byte cache lines:
    #   byte addr 0x80 (line 4, slot 0): 0xCAFEBABE
    #   byte addr 0x84 (line 4, slot 1): 0xFEEDFACE
    #   byte addr 0x88 (line 4, slot 2): 0xDEADBEEF
    #   byte addr 0xA0 (line 5, slot 0): 0x12345678
    plan = [
        (0x80, 0xCAFEBABE),
        (0x84, 0xFEEDFACE),
        (0x88, 0xDEADBEEF),
        (0xA0, 0x12345678),
    ]
    for addr, word in plan:
        dut.loader_en.value = 1
        dut.loader_addr.value = addr
        dut.loader_data.value = word
        await RisingEdge(dut.clk)
    dut.loader_en.value = 0
    await RisingEdge(dut.clk)

    # Read line 4 (addr 0x80) via AXI4; expect the lower 96 bits to hold
    # CAFEBABE | FEEDFACE | DEADBEEF in slots 0/1/2, and slots 3..7 to be
    # untouched (X in Verilator initial; treat as don't-care here).
    rresp, _, beats = await axi_read(dut, addr=0x80)
    assert rresp == AXI4_RESP_OKAY
    line4 = beats[0]
    assert (line4 >> 0)  & 0xFFFFFFFF == 0xCAFEBABE, f"slot 0: {(line4>>0)&0xFFFFFFFF:08x}"
    assert (line4 >> 32) & 0xFFFFFFFF == 0xFEEDFACE, f"slot 1: {(line4>>32)&0xFFFFFFFF:08x}"
    assert (line4 >> 64) & 0xFFFFFFFF == 0xDEADBEEF, f"slot 2: {(line4>>64)&0xFFFFFFFF:08x}"

    # Read line 5 (addr 0xA0) via AXI4; expect slot 0 = 0x12345678.
    rresp, _, beats = await axi_read(dut, addr=0xA0)
    assert rresp == AXI4_RESP_OKAY
    line5 = beats[0]
    assert (line5 >> 0) & 0xFFFFFFFF == 0x12345678, f"slot 0: {(line5>>0)&0xFFFFFFFF:08x}"
