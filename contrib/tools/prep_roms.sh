#!/bin/bash
# Linux rom-prep for the Naughty Boy Basys3 port.
#
# 1. Compile make_vhdl_prom from the tracked tools_prom_src on the host (gcc),
#    into tools/ (alongside the pristine .bat, not in roms/); gitignored.
# 2. Convert the tracked tools/make_naughty_boy_proms.bat to
#    tools/make_naughty_boy_proms.sh -- generated, but placed alongside the
#    pristine .bat (not in roms/); gitignored.
# 3. Unzip the romset ($ROMZIP, default ~/roms/naughtyb.zip) into tools/roms/
#    as-is -- its 18 filenames already match make_naughty_boy_proms.bat's
#    expected inputs byte-for-byte (contrib/basys3/PORTING_SPEC.md §8), so no
#    filename translation table is needed here, unlike vhdl_congo_bongo.
# 4. Run make_naughty_boy_proms.sh (from tools/, cwd set to roms/ so its bare
#    relative filenames resolve) to generate the PROM VHDL.
#
# Roms and the generated PROM VHDL stay local (never distributed).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UNZIP_DIR="$ROOT/tools"
ROMS_DIR="$UNZIP_DIR/roms"
TOOLS_SRC="$ROOT/tools/tools_prom_src/src"

ROMZIP="${ROMZIP:-$HOME/roms/naughtyb.zip}"

step() { printf '\n==> %s\n' "$1"; }

if [ ! -f "$TOOLS_SRC/make_vhdl_prom.c" ]; then
    echo "error: source tree not found: $TOOLS_SRC" >&2
    exit 1
fi
if [ ! -f "$UNZIP_DIR/make_naughty_boy_proms.bat" ]; then
    echo "error: $UNZIP_DIR/make_naughty_boy_proms.bat not found" >&2
    exit 1
fi

mkdir -p "$ROMS_DIR"

step "1/4 Compiling make_vhdl_prom on the host"
gcc "$TOOLS_SRC/make_vhdl_prom.c" -lm -o "$UNZIP_DIR/make_vhdl_prom"

step "2/4 Converting make_naughty_boy_proms.bat to .sh"
# make_naughty_boy_proms.sh runs with cwd = roms/ (step 4) so its bare
# relative rom filenames resolve; make_vhdl_prom lives one level up in
# tools/, hence '../make_vhdl_prom' rather than './make_vhdl_prom'.
sed -E \
    -e 's/\r$//' \
    -e '/^rem/d' \
    -e 's/^copy \/B (.*) ([^ ]+)$/cat \1 > \2/' \
    -e 's/ \+ / /g' \
    -e 's/^make_vhdl_prom /..\/make_vhdl_prom /' \
    -e 's/^del /rm /' \
    "$UNZIP_DIR/make_naughty_boy_proms.bat" > "$UNZIP_DIR/make_naughty_boy_proms.sh"
sed -i '1i #!/bin/bash' "$UNZIP_DIR/make_naughty_boy_proms.sh"
chmod +x "$UNZIP_DIR/make_naughty_boy_proms.sh" "$UNZIP_DIR/make_vhdl_prom"

step "3/4 Unzipping romset"
unzip -o "$ROMZIP" -d "$ROMS_DIR"

# Fail loudly here rather than let a wrong ROMZIP silently produce
# empty/missing PROM VHDL: `cat` on a missing input still writes an (empty)
# output and `make_vhdl_prom` on a missing input silently produces no .vhd
# at all, so without this check a wrong/incomplete ROMZIP fails only much
# later, opaquely, when Vivado can't find a generated source file.
expected_roms=(1.30 2.29 3.28 4.27 5.26 6.25 7.24 8.23 9.50 10.49 11.48 12.47 \
                13.46 14.45 15.44 16.43 6301-1.63 6301-1.64)
missing=()
for f in "${expected_roms[@]}"; do
    [ -f "$ROMS_DIR/$f" ] || missing+=("$f")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "error: ROMZIP ($ROMZIP) is missing files make_naughty_boy_proms.sh expects:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
fi

step "4/4 Generating PROM VHDL"
( cd "$ROMS_DIR" && "$UNZIP_DIR/make_naughty_boy_proms.sh" )

missing_vhd=()
for f in prom_graphx_1_bit0 prom_graphx_1_bit1 prom_graphx_2_bit0 prom_graphx_2_bit1 \
         prom_prog prom_palette_1 prom_palette_2; do
    [ -s "$ROMS_DIR/$f.vhd" ] || missing_vhd+=("$f.vhd")
done
if [ "${#missing_vhd[@]}" -gt 0 ]; then
    echo "error: make_naughty_boy_proms.sh did not produce all expected PROM VHDL:" >&2
    printf '  %s\n' "${missing_vhd[@]}" >&2
    exit 1
fi

echo
echo "Rom-prep complete. PROM VHDL generated in:"
ls -1 "$ROMS_DIR"/*.vhd
