# SPDX-License-Identifier: CC-BY-SA-4.0
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
    $(PROJECT_ROOT)/verif/axi4_master_simple/axi4_master_mem_wrapper.sv

TOPLEVEL = axi4_master_mem_wrapper
MODULE = test_axi4_master_simple

include $(shell cocotb-config --makefiles)/Makefile.sim
