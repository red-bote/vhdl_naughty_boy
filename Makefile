# Default target: build the whole scripted Basys3 port tree.
TOOLS        := contrib/tools
BASYS3_TOOLS := contrib/basys3/tools
VIVADO       := contrib/basys3/vivado

.PHONY: all setup create_prj clk_wiz patch synth bitstream clean help

all: setup clk_wiz patch

setup:
	$(TOOLS)/setup_naughty_boy.sh

create_prj:
	$(VIVADO)/create_project.sh

clk_wiz: setup create_prj
	$(VIVADO)/make_clk_wiz_0.sh

# Regenerate naughty_boy_de10_lite_to_basys3.patch and naughty_boy_basys3.vhd top level.
patch: setup
	$(BASYS3_TOOLS)/make_de10_lite_to_basys3_patch.sh

# Run synthesis only (resets synth_1 first).
synth: setup clk_wiz patch
	$(BASYS3_TOOLS)/make_naughty_boy_basys3_bitstream.sh synth

# Implementation + write_bitstream (depends on synthesis).
bitstream: synth
	$(BASYS3_TOOLS)/make_naughty_boy_basys3_bitstream.sh bitstream

# Unlike every other sf-darfpga-convention machine, this port keeps its
# pristine source in place (no separate extracted vhdl_<machine>_rev_.../
# tree -- see contrib/basys3/PORTING_SPEC.md §0); clean removes only the
# generated Vivado project tree, plus the ephemeral romset/PROM staging dir.
clean:
	rm -rf basys3 tools/roms

help:
	@echo "Naughty Boy Basys3 port driver."
	@echo "Usage: make <target>"
	@echo
	@echo "  all         setup clk_wiz patch"
	@echo "  setup       apply fix patches (if any) + rom-prep (no archive fetch, see PORTING_SPEC.md §0)"
	@echo "  create_prj  create Vivado project (copies .xpr/.xdc)"
	@echo "  clk_wiz     generate clk_wiz_0 MMCM IP (100 -> 12 MHz)"
	@echo "  patch       regenerate naughty_boy_de10_lite_to_basys3.patch + top level"
	@echo "  synth       synthesis only (resets synth_1 first)"
	@echo "  bitstream   implementation + write_bitstream"
	@echo "  clean       remove the Vivado project tree + staged roms/PROM VHDL only"
