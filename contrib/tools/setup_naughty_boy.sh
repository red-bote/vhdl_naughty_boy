#!/bin/bash
# Apply fix patches to the pristine Dar source (if any), then chain into the
# rom-prep script.
#
# Unlike every other sf-darfpga-convention machine, this port has no
# SourceForge archive to fetch: vhdl_naughty_boy/ (this directory) IS the
# pristine source, pinned via its own git history (a checkout of
# https://github.com/darfpga/vhdl_naughty_boy). See contrib/basys3/PORTING_SPEC.md
# §0 for why.
#
# 1. Apply fix patches idempotently (patch -p1 --forward), if any exist yet.
#    Glob covers both contrib/*/code/*.patch and contrib/code/*.patch.
#    Excludes *_de10_lite_to_basys3.patch: that file is a record of the
#    top-level rewrite (authored by make_de10_lite_to_basys3_patch.sh, applied
#    to a different target file), not a fix to apply to the pristine tree.
# 2. Run contrib/tools/prep_roms.sh (compile make_vhdl_prom, convert .bat,
#    unzip romset, generate PROM VHDL).
#
# Roms and the generated PROM VHDL stay local (never distributed).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

step() { printf '\n==> %s\n' "$1"; }

step "1/2 Applying fix patches (contrib/*/code/*.patch and contrib/code/*.patch)"
for p in "$ROOT"/contrib/*/code/*.patch "$ROOT"/contrib/code/*.patch; do
    [ -e "$p" ] || continue
    case "$p" in
        *_de10_lite_to_basys3.patch) continue ;;
    esac
    # GNU patch's --forward still exits 1 (and writes a .rej) on an
    # already-applied patch instead of silently no-op'ing -- check via a
    # reverse dry-run first so re-running `make setup` is actually
    # idempotent (see vhdl_congo_bongo/contrib/basys3/PORTING_SPEC.md §0,
    # a known project-wide finding).
    if (cd "$ROOT" && patch -p1 -R --dry-run --forward < "$p" > /dev/null 2>&1); then
        echo "==> already applied, skipping $p"
    else
        echo "==> applying $p"
        (cd "$ROOT" && patch -p1 --forward < "$p")
    fi
done

step "2/2 Running rom-prep"
"$ROOT/contrib/tools/prep_roms.sh"

echo
echo "Setup complete. Source tree in:"
echo "  $ROOT"
