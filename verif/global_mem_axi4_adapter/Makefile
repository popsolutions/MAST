# SPDX-License-Identifier: CC-BY-SA-4.0
#
# Cocotb + Verilator testbench for src/popsolutions/axi4/global_mem_axi4_adapter.sv.
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
    $(PROJECT_ROOT)/verif/global_mem_axi4_adapter/gma_with_mem_wrapper.sv

TOPLEVEL = gma_with_mem_wrapper
MODULE = test_global_mem_axi4_adapter

include $(shell cocotb-config --makefiles)/Makefile.sim
