# SPDX-License-Identifier: CC-BY-SA-4.0
#
# Cocotb + Verilator testbench for src/global_mem_controller.sv (the AXI4
# skeleton rewrite — see the file header for the architecture).
#
# This testbench drives the bespoke external port surface (core1_* and
# contr_*) that upstream callers depend on, and proves that the AXI4
# subsystem behind it is correctly wired with phys_addr_width=48 and
# mem_data_width=256.
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
    $(PROJECT_ROOT)/src/const.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/axi4_const.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/axi4_mem_model.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/axi4_master_simple.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/core_axi4_adapter.sv \
    $(PROJECT_ROOT)/src/popsolutions/axi4/global_mem_axi4_adapter.sv \
    $(PROJECT_ROOT)/src/global_mem_controller.sv

TOPLEVEL = global_mem_controller
MODULE = test_global_mem_controller

include $(shell cocotb-config --makefiles)/Makefile.sim
