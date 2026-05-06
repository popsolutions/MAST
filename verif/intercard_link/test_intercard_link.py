# SPDX-License-Identifier: Apache-2.0
"""
Cocotb skeleton testbench for src/popsolutions/interconnect/intercard_link.sv.

Exercises only the *interface contract* the skeleton commits to:
  * link-up FSM (DOWN -> TRAINING -> UP under sustained link_train_req)
  * link-drop on link_train_req deassertion from any active state
  * TX/RX gating: phy_tx_*/rx_* are zeroed while link is not UP

Real protocol-conformance tests (framing, flit boundaries, error injection)
land once ADR-014 closes and the protocol implementation replaces this
skeleton.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 10
TRAIN_CYCLES = 16  # must match the default TRAIN_CYCLES parameter on the DUT

# link_state_t encoding (must match intercard_pkg.sv).
LINK_DOWN = 0
LINK_TRAINING = 1
LINK_UP = 2
LINK_FAULT = 3

# Composite bus width = INTERCARD_LANES (4) * INTERCARD_LANE_WIDTH (32) = 128 bits.
BUS_WIDTH = 128


async def reset_dut(dut):
    """5 clocks of reset, all inputs to known safe values."""
    dut.rst_n.value = 0

    dut.tx_data.value = 0
    dut.tx_valid.value = 0
    dut.tx_last.value = 0
    dut.rx_ready.value = 1
    dut.link_train_req.value = 0
    dut.phy_rx_data.value = 0
    dut.phy_rx_valid.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def bring_link_up(dut):
    """Assert link_train_req long enough that the FSM lands in LINK_UP.

    Slack budget = 5 cycles on top of TRAIN_CYCLES: 1 cycle for the cocotb 2.x
    signal-write to commit into the simulator, 1 cycle for DOWN -> TRAINING,
    TRAIN_CYCLES counter ticks, and a couple of cycles of margin.
    """
    dut.link_train_req.value = 1
    for _ in range(TRAIN_CYCLES + 5):
        await RisingEdge(dut.clk)
    assert int(dut.link_state.value) == LINK_UP, (
        f"link did not come up: state={int(dut.link_state.value)}"
    )


# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------

@cocotb.test()
async def test_reset_link_down(dut):
    """After reset and without train_req, link is DOWN and TX/RX gated to 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    assert int(dut.link_state.value) == LINK_DOWN
    assert dut.link_up.value == 0
    assert dut.tx_ready.value == 0
    assert dut.phy_tx_valid.value == 0
    assert dut.rx_valid.value == 0


@cocotb.test()
async def test_link_up_after_training(dut):
    """Sustained train_req brings the link to LINK_UP.

    Verifies the contract "enough cycles of sustained train_req while in
    DOWN -> link comes up" rather than the exact cycle count, which is
    implementation detail (and additionally affected by cocotb 2.x's
    one-delta deferred signal-write semantics).
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    dut.link_train_req.value = 1

    # Run enough cycles to traverse DOWN -> TRAINING -> UP with slack for
    # the cocotb 2.x signal-write to commit.
    for _ in range(TRAIN_CYCLES + 5):
        await RisingEdge(dut.clk)
    assert int(dut.link_state.value) == LINK_UP, (
        f"expected LINK_UP after sustained train_req; got "
        f"{int(dut.link_state.value)}"
    )
    assert dut.link_up.value == 1
    assert dut.tx_ready.value == 1


@cocotb.test()
async def test_link_drops_when_train_deasserts(dut):
    """Deasserting train_req from LINK_UP returns the FSM to LINK_DOWN.

    Two clocks after deassert: one for the cocotb signal-write to commit,
    one for the FSM to observe the deasserted input and update state_q.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)
    await bring_link_up(dut)

    dut.link_train_req.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert int(dut.link_state.value) == LINK_DOWN
    assert dut.link_up.value == 0
    assert dut.tx_ready.value == 0


@cocotb.test()
async def test_link_drops_from_training(dut):
    """Deasserting train_req mid-TRAINING aborts and returns to LINK_DOWN."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    dut.link_train_req.value = 1
    # Two clocks: one for write commit, one for the FSM to enter TRAINING.
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert int(dut.link_state.value) == LINK_TRAINING

    # Run a few more cycles inside TRAINING (still under TRAIN_CYCLES total)
    # so we can verify abort behavior mid-training.
    for _ in range(TRAIN_CYCLES // 2):
        await RisingEdge(dut.clk)
    assert int(dut.link_state.value) == LINK_TRAINING

    dut.link_train_req.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert int(dut.link_state.value) == LINK_DOWN


@cocotb.test()
async def test_tx_forwards_only_when_up(dut):
    """tx_data/tx_valid forward to phy_tx_* exactly when link is UP."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    payload = 0xCAFEBABE_DEADBEEF_12345678_9ABCDEF0  # 128 bits = BUS_WIDTH

    # While DOWN: tx_valid presented but phy_tx_valid must stay 0.
    dut.tx_data.value = payload
    dut.tx_valid.value = 1
    await RisingEdge(dut.clk)
    assert dut.phy_tx_valid.value == 0
    assert dut.tx_ready.value == 0

    # Bring link UP (with tx_valid temporarily deasserted to keep the test
    # focused on the gating behavior, not the upstream backpressure semantics).
    dut.tx_valid.value = 0
    await bring_link_up(dut)

    # Now tx beat must propagate.
    dut.tx_data.value = payload
    dut.tx_valid.value = 1
    await RisingEdge(dut.clk)
    assert dut.phy_tx_valid.value == 1
    assert int(dut.phy_tx_data.value) == payload, (
        f"phy_tx_data mismatch: expected {payload:032x}, "
        f"got {int(dut.phy_tx_data.value):032x}"
    )


@cocotb.test()
async def test_rx_forwards_only_when_up(dut):
    """phy_rx_* forwards to rx_* exactly when link is UP."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await reset_dut(dut)

    payload = 0xFEEDFACE_BAADF00D_01234567_89ABCDEF  # 128 bits

    # While DOWN: PHY presents valid data, but rx_valid must stay 0.
    dut.phy_rx_data.value = payload
    dut.phy_rx_valid.value = 1
    await RisingEdge(dut.clk)
    assert dut.rx_valid.value == 0

    # Bring link UP.
    dut.phy_rx_valid.value = 0
    await bring_link_up(dut)

    # Now PHY beat must propagate.
    dut.phy_rx_data.value = payload
    dut.phy_rx_valid.value = 1
    await RisingEdge(dut.clk)
    assert dut.rx_valid.value == 1
    assert int(dut.rx_data.value) == payload, (
        f"rx_data mismatch: expected {payload:032x}, "
        f"got {int(dut.rx_data.value):032x}"
    )
    assert dut.rx_last.value == 0  # tied to 0 in the skeleton
