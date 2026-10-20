#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-namcap.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
printf 'pkgname=demo\n' > "$tmp/PKGBUILD"

export PATH="$stub:$PATH"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/out.log"
export color_enabled=0
export DEBUG_LEVEL=0
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"

# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
export color_enabled=0
init_colors
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/test.sh
source "$ROOT/lib/modes/test.sh"

cat > "$stub/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' 'PKGBUILD E: invalid license'
exit 1
EOF
chmod +x "$stub/namcap"

TEST_ERRORS=0
TEST_LOG_FILE="$tmp/namcap-e.log"
: > "$TEST_LOG_FILE"
if test_namcap_pkgbuild "$tmp/PKGBUILD" >"$tmp/e.out" 2>"$tmp/e.err"; then
    fail "E: finding should fail"
fi
[[ "$TEST_ERRORS" -eq 1 ]] || fail "E: finding should count as one error"
grep -F ' E: ' "$tmp/e.err" >/dev/null || fail "E: line was not printed"
grep -F ' E: ' "$TEST_LOG_FILE" >/dev/null || fail "E: line was not written to the mode log"

cat > "$stub/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' 'PKGBUILD W: extra dependency'
printf '%s\n' 'PKGBUILD W: unused variable'
exit 0
EOF
chmod +x "$stub/namcap"

TEST_ERRORS=0
TEST_LOG_FILE="$tmp/namcap-w.log"
: > "$TEST_LOG_FILE"
if ! test_namcap_pkgbuild "$tmp/PKGBUILD" >"$tmp/w.out" 2>"$tmp/w.err"; then
    fail "W: findings should not fail"
fi
[[ "$TEST_ERRORS" -eq 0 ]] || fail "W: findings should not count as errors"
grep -F ' W: ' "$tmp/w.out" >/dev/null || fail "W: lines were not shown"
if grep -F ' E: ' "$tmp/w.out" "$tmp/w.err" >/dev/null; then
    fail "W-only namcap output should not report an error"
fi
