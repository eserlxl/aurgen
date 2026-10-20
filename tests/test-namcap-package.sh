#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-namcap-pkg.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
trace="$tmp/makepkg-args"

export PATH="$stub:$PATH"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/out.log"
export color_enabled=0
export DEBUG_LEVEL=0
export PKGNAME=demo
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"
: > "$trace"

# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
export color_enabled=0
init_colors
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"

cat > "$stub/makepkg" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$trace"
if [[ "\$1" == "-s" ]]; then
    printf 'pkg\\n' > "$tmp/\${PKGNAME}-1.0-1-any.pkg.tar.zst"
fi
exit 0
EOF
chmod +x "$stub/makepkg"

cat > "$stub/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' "$1 E: missing dependency"
exit 1
EOF
chmod +x "$stub/namcap"

cd "$tmp" || exit 1
if install_pkg local >"$tmp/e.out" 2>"$tmp/e.err"; then
    fail "E: finding should stop local install"
fi
grep -Fx -- '-s' "$trace" >/dev/null || fail "E: case should build with makepkg -s"
if grep -Fx -- '-i' "$trace" >/dev/null; then
    fail "E: finding should stop before makepkg -i"
fi
grep -F ' E: ' "$tmp/e.err" >/dev/null || fail "E: line was not printed"

cat > "$stub/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' "$1 W: extra file"
exit 0
EOF
chmod +x "$stub/namcap"
: > "$trace"
rm -f "$tmp/${PKGNAME}-1.0-1-any.pkg.tar.zst"

if ! install_pkg local >"$tmp/w.out" 2>"$tmp/w.err"; then
    fail "W: findings should still install"
fi
[[ "$(cat "$trace")" == $'-s\n-i' ]] || fail "W: case should build, then install"
grep -F ' W: ' "$tmp/w.out" >/dev/null || fail "W: line was not shown"
if grep -F ' E: ' "$tmp/w.out" "$tmp/w.err" >/dev/null; then
    fail "W-only namcap output should not report an error"
fi
