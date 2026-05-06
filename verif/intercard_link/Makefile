# SPDX-License-Identifier: CC-BY-SA-4.0
#
# Cocotb + Verilator testbench for src/popsolutions/interconnect/intercard_link.sv.
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

EXTRA_ARGS += -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

PROJECT_ROOT = $(shell git rev-parse --show-toplevel)

VERILOG_SOURCES = \
    $(PROJECT_ROOT)/src/popsolutions/interconnect/intercard_pkg.sv \
    $(PROJECT_ROOT)/src/popsolutions/interconnect/intercard_link.sv

TOPLEVEL = intercard_link
MODULE = test_intercard_link

include $(shell cocotb-config --makefiles)/Makefile.sim
