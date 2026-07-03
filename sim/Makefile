# axi4lite_regfile - Week 2 Questa Makefile
# Run from the sim/ directory:
#     make          # compile + run in batch
#     make wave     # open GUI, add waves, run
#     make clean    # remove work library and logs

RTL_DIR := ../rtl
TB_DIR  := ../tb

# Compile order matters:
#   - Package (constants) first
#   - Interface next (BFM class references it via 'virtual axi_lite_if')
#   - BFM package next (defines the class)
#   - RTL top-level
#   - TB (uses both the package and the interface)
RTL_FILES := \
    $(RTL_DIR)/axi4lite_regfile_pkg.sv \
    $(TB_DIR)/axi_lite_if.sv \
    $(TB_DIR)/axi_lite_master_bfm.sv \
    $(RTL_DIR)/axi4lite_regfile.sv

TB_FILES := \
    $(TB_DIR)/tb_axi4lite_regfile.sv

TOP := tb_axi4lite_regfile

.PHONY: all comp sim wave clean

all: sim

work:
	vlib work
	vmap work work

comp: work
	vlog -sv -lint $(RTL_FILES) $(TB_FILES)

sim: comp
	vsim -c -do "run -all; quit -f" $(TOP)

wave: comp
	vsim -do "add wave -r /$(TOP)/*; run -all" $(TOP)

clean:
	rm -rf work transcript vsim.wlf modelsim.ini
