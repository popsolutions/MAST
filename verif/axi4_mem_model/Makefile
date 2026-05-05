# SPDX-License-Identifier: CC-BY-SA-4.0
#
# Cocotb + Verilator testbench for src/popsolutions/axi4/axi4_mem_model.sv.
#
# Run:    source ../.venv/bin/activate && make
# Waves:  make WAVES=1
# Clean:  make clean

TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 0

ifeq ($(WAVES),1)
EXTRA_ARGS += --trace --trace-structs
endif

# Allow Verilator to be more permissive with width mismatches (we'll tighten later)
EXTRA_ARGS += -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

PROJECT_ROOT = $(shell git rev-parse --show-toplevel)

VERILOG_SOURCES = \
    $(PROJECT_ROOT)/src/const.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/axi4_const.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/axi4_mem_model.sv

TOPLEVEL = axi4_mem_model
MODULE = test_axi4_mem_model

include $(shell cocotb-config --makefiles)/Makefile.sim
