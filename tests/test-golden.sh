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
case "$mode" in
    clean)
        exit 0
        ;;
    local|aur)
        printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' > "$PKGBUILD"
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

status=0
( mode_golden ) || status=$?
[[ "$status" -eq 1 ]] || exit 1
golden_header='# This is a golden file for test comparison only. Do not use for actual builds or releases.'
for golden in "$GOLDEN_DIR/PKGBUILD.local.golden" "$GOLDEN_DIR/PKGBUILD.aur.golden"; do
    [[ -f "$golden" ]] || exit 1
    IFS= read -r first_line < "$golden" || exit 1
    [[ "$first_line" == "$golden_header" ]] || exit 1
    grep -F -x -q 'pkgname=demo' "$golden" || exit 1
done
