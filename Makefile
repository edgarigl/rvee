-include .config.mk

SYSTEMC ?= /usr
SYSTEMC_INCLUDE ?=$(SYSTEMC)/include/
SYSTEMC_LIBDIR ?= $(SYSTEMC)/lib-linux64

SV2V ?= sv2v
YOSYS ?= yosys
VIVADO ?= vivado
VERILATOR ?= verilator
VERILATOR_ROOT?=$(shell $(VERILATOR) --getenv VERILATOR_ROOT 2>/dev/null || echo -n /usr/share/verilator)

VOBJ_DIR=obj_dir

VFLAGS += --exe
VFLAGS += --assert
VFLAGS += -Wno-fatal
VFLAGS += --trace
VFLAGS += --sc --pins-bv 2
VFLAGS += -Mdir $(VOBJ_DIR)
VFLAGS += -Irtl
VFLAGS += -DSIM_ECALL

VENV=SYSTEMC_INCLUDE=$(SYSTEMC_INCLUDE) SYSTEMC_LIBDIR=$(SYSTEMC_LIBDIR)

CPPFLAGS += -I. -I../ -I../tb -I$(VERILATOR_ROOT)/include/
CPPFLAGS += -I../libsystemctlm-soc/ -I../libsystemctlm-soc/tests/
CPPFLAGS += -I $(SYSTEMC_INCLUDE)
CPPFLAGS += -DVM_TRACE=1
OPT_FAST ?= -O2 -fno-stack-protector -fno-var-tracking-assignments
OPT_SLOW ?= -O1 -fstrict-aliasing -fno-var-tracking-assignments
export OPT_FAST
export OPT_SLOW

CXXFLAGS += -Wall -O3 -g -faligned-new
LDFLAGS  += -L $(SYSTEMC_LIBDIR)

SC_FILES_COMMON += libsystemctlm-soc/trace/trace.cc

# To make the filenames match the top module
# (and avoid additional args to verilator we use underscores instead
# of hyphens.

SC_FILES_rvee_fetch_tb += tb/rvee_fetch_tb.cc
SV_FILES_rvee_fetch_tb += tb/rvee_fetch_tb.sv
SV_FILES_rvee_fetch_tb += rtl/rvee/rvee-pcgen.sv
SV_FILES_rvee_fetch_tb += rtl/rvee/rvee-fetch.sv
ALL += $(VOBJ_DIR)/Vrvee_fetch_tb.build

SC_FILES_rvee_decode_tb += tb/rvee_decode_tb.cc
SV_FILES_rvee_decode_tb += tb/rvee_decode_tb.sv
SV_FILES_rvee_decode_tb += rtl/rvee/rvee-decode.sv
SV_FILES_rvee_decode_tb += rtl/rvee/rvee-csr.sv
SV_FILES_rvee_decode_tb += rtl/rvee/rvee-rf.sv
ALL += $(VOBJ_DIR)/Vrvee_decode_tb.build

SC_FILES_rvee_exec_tb += tb/rvee_exec_tb.cc
SV_FILES_rvee_exec_tb += tb/rvee_exec_tb.sv
SV_FILES_rvee_exec_tb += rtl/rvee/rvee-pcgen.sv
SV_FILES_rvee_exec_tb += rtl/rvee/rvee-exec.sv
SV_FILES_rvee_exec_tb += rtl/rvee/rvee-alu.sv
ALL += $(VOBJ_DIR)/Vrvee_exec_tb.build

SC_FILES_rvee_mem_tb += tb/rvee_mem_tb.cc
SV_FILES_rvee_mem_tb += tb/rvee_mem_tb.sv
SV_FILES_rvee_mem_tb += rtl/rvee/rvee-mem.sv
ALL += $(VOBJ_DIR)/Vrvee_mem_tb.build

SC_FILES_rvee_tb += tb/rvee_tb.cc
SC_FILES_rvee_tb += libsystemctlm-soc/tests/test-modules/memory.cc
SV_FILES_rvee_tb += tb/rvee_tb.sv
SV_FILES_rvee_tb += rtl/rvee/rvee.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-fetch.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-decode.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-alu.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-exec.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-mem.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-rf.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-csr.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-pcgen.sv
SV_FILES_rvee_tb += rtl/rvee/rvee-wrapper.sv
SV_FILES_rvee_tb += rtl/clint/clint.sv
ALL += $(VOBJ_DIR)/Vrvee_tb.build

SC_FILES_plic_tb += tb/plic_tb.cc
SV_FILES_plic_tb += tb/plic_tb.sv
SV_FILES_plic_tb += rtl/plic/plic.sv
ALL += $(VOBJ_DIR)/Vplic_tb.build

SC_FILES_clint_tb += tb/clint_tb.cc
SV_FILES_clint_tb += tb/clint_tb.sv
SV_FILES_clint_tb += rtl/clint/clint.sv
ALL += $(VOBJ_DIR)/Vclint_tb.build

all: $(ALL)

$(VOBJ_DIR)/V%.build:
	$(VENV) $(VERILATOR) $(VFLAGS) $(SV_FILES_$(*)) $(SC_FILES_COMMON) $(SC_FILES_$(*))
	$(MAKE) -C $(VOBJ_DIR) -f V$(*).mk CPPFLAGS="$(CPPFLAGS)" CXXFLAGS="$(CXXFLAGS)" V$(*)

pickle-%.v: Makefile $(SV_FILES_$(*))
	$(SV2V) -Irtl $(SV_FILES_$(*)) >$@

pickle: pickle-rvee_tb.v

stat:
	$(YOSYS) -s ./scripts/rvee-synth.yosys

vv-synth:
	$(VIVADO) -nojournal -nolog -mode batch -source ./scripts/vivado/rvee-synth.tcl

vv-ip:
	$(VIVADO) -nojournal -nolog -mode batch -source ./scripts/vivado/rvee-ip.tcl

check: $(ALL)
	for t in $(shell ls riscv-tests/isa/rv32ui-p-*.bin); do		\
		./obj_dir/Vrvee_tb $${t};						\
	done

clean distclean:
	$(RM) -fr $(VOBJ_DIR)
