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

mode_bin="$tmp/mode-bin"
mkdir -p "$mode_bin"
for tool in mkdir rm date cat tr cp mv; do
    ln -s "$(command -v "$tool")" "$mode_bin/$tool"
done
cat >| "$mode_bin/aurgen" <<'EOF'
#!/bin/bash
[[ "$1" == --dry-run ]] || exit 1
# Each dry run writes its own PKGBUILD, as the real modes do.
mkdir -p "$AUR_DIR/dry-run"
printf 'generated %s\n' "$2" >| "$AUR_DIR/dry-run/PKGBUILD"
[[ -n "${KEY_LOG:-}" ]] && printf '%s\n' "${GPG_KEY_ID:-}" >> "$KEY_LOG"
if [[ "$2" == git && "$FAIL_GIT" == 1 ]]; then
    exit 1
fi
exit 0
EOF
chmod +x "$mode_bin/aurgen"

run_mode_test() (
    export PATH="$mode_bin"
    export FAIL_GIT="$1"
    export AURGEN_BIN="$mode_bin/aurgen"
    export TEST_DIR="$tmp/modes-$1"
    export GOLDEN_DIR="$tmp/golden"
    export AUR_DIR="$tmp/aur"
    export PKGBUILD="$tmp/PKGBUILD"
    cleanup() { :; }
    hint() { :; }
    mode_test
)

if run_mode_test 1 >| "$tmp/mode-failure.out" 2>&1; then
    fail "A failing dry-run mode should exit 1"
else
    status=$?
fi
[[ "$status" -eq 1 ]] || fail "A failing dry-run mode should exit 1, got $status"
grep -F 'git mode failed' "$tmp/mode-failure.out" >/dev/null || fail "The failing mode was not named"
grep -F '1 test mode(s) failed' "$tmp/mode-failure.out" >/dev/null || fail "The mode failure was not counted"

mkdir -p "$tmp/aur"
printf 'published\n' >| "$tmp/aur/PKGBUILD"
printf 'published srcinfo\n' >| "$tmp/aur/.SRCINFO"
if ! run_mode_test 0 >| "$tmp/mode-success.out" 2>&1; then
    fail "Successful dry-run modes should exit 0"
fi
[[ "$(cat "$tmp/aur/PKGBUILD")" == "published" ]] || fail "aurgen test did not restore the published PKGBUILD"
[[ "$(cat "$tmp/aur/.SRCINFO")" == "published srcinfo" ]] || fail "aurgen test did not restore the published .SRCINFO"

rm -f "$tmp/aur/PKGBUILD" "$tmp/aur/.SRCINFO"
if ! run_mode_test 0 >| "$tmp/mode-none.out" 2>&1; then
    fail "Successful dry-run modes without a PKGBUILD should exit 0"
fi
[[ ! -e "$tmp/aur/PKGBUILD" ]] || fail "aurgen test left a generated PKGBUILD where none was published"

# Children use the golden files' test key, never the caller's GPG_KEY_ID.
: >| "$tmp/keys.log"
if ! GPG_KEY_ID=ABCDEF0123456789 KEY_LOG="$tmp/keys.log" run_mode_test 0 >| "$tmp/mode-key.out" 2>&1; then
    fail "aurgen test with a preset GPG_KEY_ID should exit 0"
fi
[[ "$(sort -u "$tmp/keys.log")" == "TEST_KEY_FOR_DRY_RUN" ]] || fail "aurgen test children saw GPG_KEY_ID [$(sort -u "$tmp/keys.log" | tr '\n' ' ')]"
