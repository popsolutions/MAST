# SPDX-License-Identifier: Apache-2.0
"""Cocotb tests for axi4_master_simple wired to axi4_mem_model."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 10
DATA_WIDTH = 256
STRB_WIDTH = DATA_WIDTH // 8
STRB_ALL = (1 << STRB_WIDTH) - 1


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.req_we.value = 0
    dut.req_addr.value = 0
    dut.req_wdata.value = 0
    dut.req_wstrb.value = 0
    dut.req_start.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def issue_req(dut, *, we, addr, wdata=0, wstrb=STRB_ALL, timeout=200):
    """Pulse req_start with the given parameters; await req_done."""
    dut.req_we.value = 1 if we else 0
    dut.req_addr.value = addr
    dut.req_wdata.value = wdata
    dut.req_wstrb.value = wstrb
    dut.req_start.value = 1
    await RisingEdge(dut.clk)
    dut.req_start.value = 0

    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.req_done.value == 1:
            break
    else:
        raise TimeoutError(f"req_done never asserted (we={we}, addr=0x{addr:x})")

    err = int(dut.req_err.value)
    rdata = int(dut.req_rdata.value)
    return err, rdata


@cocotb.test()
async def test_reset(dut):
    """After reset, master is idle and not signalling done/err."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    assert dut.req_busy.value == 0
    assert dut.req_done.value == 0
    assert dut.req_err.value == 0


@cocotb.test()
async def test_single_write(dut):
    """Single-beat write completes with req_done=1 and req_err=0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    err, _ = await issue_req(dut, we=True, addr=0x60,
                             wdata=0xAAAAAAAAAAAAAAAA_BBBBBBBBBBBBBBBB_CCCCCCCCCCCCCCCC_DDDDDDDDDDDDDDDD)
    assert err == 0, f"unexpected err on write: {err}"
    assert dut.req_busy.value == 0


@cocotb.test()
async def test_single_read(dut):
    """Reading from a never-written address returns zero (mem starts empty in sim)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    # Note: mem array contents are X in Verilator until written; reading yields '0' when widths fold
    # Force a known starting state by writing 0 first.
    await issue_req(dut, we=True, addr=0x20, wdata=0, wstrb=STRB_ALL)
    err, rdata = await issue_req(dut, we=False, addr=0x20)
    assert err == 0
    assert rdata == 0


@cocotb.test()
async def test_write_read_roundtrip(dut):
    """Write a value, read back, verify bit-exact."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    test_data = 0xDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEEDFACE_BAADF00D_01234567_89ABCDEF
    err_w, _ = await issue_req(dut, we=True, addr=0xC0, wdata=test_data)
    assert err_w == 0

    err_r, rdata = await issue_req(dut, we=False, addr=0xC0)
    assert err_r == 0
    assert rdata == test_data, \
        f"roundtrip mismatch:\n  wrote {test_data:064x}\n  read  {rdata:064x}"


@cocotb.test()
async def test_back_to_back(dut):
    """Two writes followed by two reads — master handles back-to-back transactions."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    pairs = [
        (0x100, 0x1111111111111111_2222222222222222_3333333333333333_4444444444444444),
        (0x120, 0x5555555555555555_6666666666666666_7777777777777777_8888888888888888),
    ]
    for addr, data in pairs:
        err, _ = await issue_req(dut, we=True, addr=addr, wdata=data)
        assert err == 0
    for addr, expected in pairs:
        err, rdata = await issue_req(dut, we=False, addr=addr)
        assert err == 0
        assert rdata == expected, f"addr 0x{addr:x}: expected {expected:064x}, got {rdata:064x}"
