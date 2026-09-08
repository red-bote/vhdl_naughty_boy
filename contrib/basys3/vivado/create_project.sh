#!/bin/bash
# Create the initial Vivado Basys3 project for the Naughty Boy port and copy
# the tracked port assets into place.
#
# Layout is non-nested (like every other machine): the .xpr lives directly in
# basys3/ and the project sources tree is basys3/naughty_boy_basys3.srcs/.
# Unlike every other sf-darfpga-convention machine there is no separate
# extracted vhdl_<machine>_rev_.../ tree: this repo root itself is the
# pristine source (see contrib/basys3/PORTING_SPEC.md §0), so basys3/ is
# created directly at the repo root.
#
# No external scandoubler import is needed (unlike vhdl_congo_bongo): the
# pristine core already drives real video_hs/video_vs and contains its own
# line_doubler.
#
# 1. Create the project dirs.
# 2. Copy the .xpr.
# 3. Copy Basys-3-Master.xdc into constrs_1/imports/digilent-xdc-master/.
#
# clk_wiz_0 IP generation (make_clk_wiz_0.sh) and the top level are separate.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONTRIB="$ROOT/contrib/basys3"

PROJ_DIR="$ROOT/basys3"
CONSTRS_IMPORT="$PROJ_DIR/naughty_boy_basys3.srcs/constrs_1/imports/digilent-xdc-master"

step() { printf '\n==> %s\n' "$1"; }

step "1/2 Creating project directories"
mkdir -p "$PROJ_DIR" "$CONSTRS_IMPORT"

step "2/2 Copying naughty_boy_basys3.xpr and Basys-3-Master.xdc"
cp -f "$CONTRIB/vivado/naughty_boy_basys3.xpr" "$PROJ_DIR/naughty_boy_basys3.xpr"
cp -f "$CONTRIB/vivado/Basys-3-Master.xdc" "$CONSTRS_IMPORT/Basys-3-Master.xdc"

echo
echo "Project files in place:"
ls -l "$PROJ_DIR/naughty_boy_basys3.xpr"
ls -l "$CONSTRS_IMPORT/Basys-3-Master.xdc"
