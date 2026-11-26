# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(CURDIR)/../src
PROJECT_SOURCES = project.v mac_codebook_core.v signed_mac.v
ifeq ($(GATES),yes)
ACCW ?= 16
ENTRIES ?= 8
CLOCK_PERIOD_NS ?= 60
else
ACCW ?= 24
ENTRIES ?= 16
CLOCK_PERIOD_NS ?= 20
endif
export ACCW ENTRIES CLOCK_PERIOD_NS

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl_cb$(ENTRIES)_acc$(ACCW)
COMPILE_ARGS += -Ptb.ACCW=$(ACCW) -Ptb.ENTRIES=$(ENTRIES)
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

ifneq ($(ENTRIES):$(ACCW),8:16)
$(error Gate-level tests use the signed-off ENTRIES=8 ACCW=16 netlist)
endif

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(CURDIR)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(CURDIR)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
