#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' 'pkgver=1.0.0' > "$tmp/PKGBUILD.0"
: > "$tmp/out.log"
: > "$tmp/err.log"

cat > "$tmp/aurgen" <<'EOF'
#!/bin/bash
mode="${2:-$1}"
# mode_golden must run each generation as a dry run.
if [[ "$mode" != clean && "$1" != --dry-run ]]; then
    exit 1
fi
case "$mode" in
    clean)
        # Like mode_clean: deletes the goldens and the published packaging files.
        rm -f "$GOLDEN_DIR"/PKGBUILD.*.golden "$AUR_DIR/PKGBUILD" "$AUR_DIR/.SRCINFO" "$AUR_DIR/PKGBUILD.prev"
        exit 0
        ;;
    local|aur)
        # A real --dry-run child writes under aur/dry-run/ and leaves $PKGBUILD alone.
        # A published aur/PKGBUILD visible here would feed the aur child's pkgrel.
        [[ -e "$AUR_DIR/PKGBUILD" ]] && : >| "$AUR_DIR/../saw-published-$mode"
        mkdir -p "$AUR_DIR/dry-run"
        printf '%s\n' "pkgname=demo-$mode" "pkgver=${GOLDEN_TEST_VER:-1.0.0}" >| "$AUR_DIR/dry-run/PKGBUILD"
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$tmp/aurgen"

export AURGEN_BIN="$tmp/aurgen"
export AURGEN_LOG="$tmp/out.log"
export AURGEN_ERROR_LOG="$tmp/err.log"
export PKGBUILD0="$tmp/PKGBUILD.0"
export PKGBUILD="$tmp/PKGBUILD"
export AUR_DIR="$tmp/aur"
export GOLDEN_DIR="$tmp/golden"
export color_enabled=0
export DEBUG_LEVEL=0

# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
export color_enabled=0
init_colors
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/golden.sh
source "$ROOT/lib/modes/golden.sh"

# The git dry run fails below: its previous golden must survive.
mkdir -p "$GOLDEN_DIR"
printf 'old git golden\n' >| "$GOLDEN_DIR/PKGBUILD.git.golden"
# golden must not touch the published packaging files or their rollback copies.
mkdir -p "$AUR_DIR"
for f in PKGBUILD .SRCINFO PKGBUILD.prev; do printf 'published %s\n' "$f" >| "$AUR_DIR/$f"; done

status=0
( mode_golden ) >| "$tmp/golden1.out" || status=$?
[[ "$(cat "$GOLDEN_DIR/PKGBUILD.git.golden")" == "old git golden" ]] || exit 1
grep -Fxq "Created $GOLDEN_DIR/PKGBUILD.local.golden" "$tmp/golden1.out" || { echo "a first golden was not reported as Created"; cat "$tmp/golden1.out"; exit 1; }
for f in PKGBUILD .SRCINFO PKGBUILD.prev; do
    [[ "$(cat "$AUR_DIR/$f" 2>/dev/null)" == "published $f" ]] || { echo "aurgen golden removed or changed aur/$f"; exit 1; }
done
for mode in local aur; do
    [[ ! -e "$AUR_DIR/../saw-published-$mode" ]] || { echo "the $mode golden child saw the published aur/PKGBUILD"; exit 1; }
done
[[ "$status" -eq 1 ]] || exit 1
golden_header='# This is a golden file for test comparison only. Do not use for actual builds or releases.'
for mode in local aur; do
    golden="$GOLDEN_DIR/PKGBUILD.$mode.golden"
    [[ -f "$golden" ]] || exit 1
    IFS= read -r first_line < "$golden" || exit 1
    [[ "$first_line" == "$golden_header" ]] || exit 1
    grep -F -x -q "pkgname=demo-$mode" "$golden" || exit 1
done

# A rerun reports each golden as Unchanged; a changed PKGBUILD is reported with its diff.
touch -d '2001-01-01 00:00' "$GOLDEN_DIR/PKGBUILD.local.golden"
( mode_golden ) >| "$tmp/golden2.out" || true
grep -Fxq "Unchanged $GOLDEN_DIR/PKGBUILD.local.golden" "$tmp/golden2.out" || { echo "an identical golden was not reported as Unchanged"; cat "$tmp/golden2.out"; exit 1; }
if grep -Fq "Updated $GOLDEN_DIR/PKGBUILD.local.golden" "$tmp/golden2.out"; then
    echo "an unchanged golden was also reported as Updated"
    cat "$tmp/golden2.out"
    exit 1
fi
[[ "$(stat -c %Y "$GOLDEN_DIR/PKGBUILD.local.golden")" == "$(date -d '2001-01-01 00:00' +%s)" ]] || { echo "an unchanged golden was rewritten"; exit 1; }
( GOLDEN_TEST_VER=2.0.0 mode_golden ) >| "$tmp/golden3.out" || true
grep -Fxq "Changed $GOLDEN_DIR/PKGBUILD.aur.golden:" "$tmp/golden3.out" || { echo "a changed golden was not reported as Changed"; cat "$tmp/golden3.out"; exit 1; }
grep -Fxq "+pkgver=2.0.0" "$tmp/golden3.out" || { echo "a changed golden did not show its diff"; cat "$tmp/golden3.out"; exit 1; }
grep -Fxq "pkgver=2.0.0" "$GOLDEN_DIR/PKGBUILD.aur.golden" || { echo "the changed golden was not written"; exit 1; }
