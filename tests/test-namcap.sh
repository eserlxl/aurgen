#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-namcap.XXXXXX")"
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

# Direct execution of lib/modes/test.sh must exit non-zero with the library guard message.
if bash "$ROOT/lib/modes/test.sh" >| "$tmp/direct.out" 2>| "$tmp/direct.err"; then
    fail "direct execution of lib/modes/test.sh should exit non-zero"
fi
grep -Fq 'This script is a library and must be sourced, not executed.' "$tmp/direct.err" \
    || fail "direct execution did not print the library guard message"
if grep -Fq 'command not found' "$tmp/direct.err"; then
    fail "direct execution hit command not found"
fi

mode_bin="$tmp/mode-bin"
mkdir -p "$mode_bin"
for tool in mkdir rm date cat tr cp mv diff tail grep; do
    ln -s "$(command -v "$tool")" "$mode_bin/$tool"
done
cat >| "$mode_bin/aurgen" <<'EOF'
#!/bin/bash
if [[ "$1" != --dry-run ]]; then
    [[ "${PASS_INVALID_ARGS:-0}" == 1 ]] && exit 0
    exit 1
fi
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
    export PATH="${4:-$mode_bin}"
    export FAIL_GIT="$1"
    export AURGEN_BIN="$mode_bin/aurgen"
    export TEST_DIR="$tmp/modes-${2:-$1}"
    export GOLDEN_DIR="${3:-$tmp/golden}"
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

# Golden PKGBUILD diff: matching golden files (ignoring line-1 stamp) pass; mismatched diffs fail and count errors.
golden_match="$tmp/golden-match"
mkdir -p "$golden_match"
for mode in local aur git; do
    printf '# stamp ignored by tail -n +2\ngenerated %s\n' "$mode" >| "$golden_match/PKGBUILD.$mode.golden"
done
if ! run_mode_test 0 golden-match "$golden_match" >| "$tmp/mode-golden-match.out" 2>&1; then
    fail "Matching golden PKGBUILDs should pass mode_test"
fi
for mode in local aur git; do
    grep -Fq "$mode PKGBUILD matches golden file." "$tmp/mode-golden-match.out" \
        || fail "Missing golden match log for $mode"
    [[ ! -s "$tmp/modes-golden-match/diff-$mode.log" ]] \
        || fail "Unexpected non-empty diff-$mode.log on matching golden file"
done

golden_mismatch="$tmp/golden-mismatch"
mkdir -p "$golden_mismatch"
cp "$golden_match"/PKGBUILD.*.golden "$golden_mismatch/"
printf '# stamp ignored by tail -n +2\nexpected mismatch\n' >| "$golden_mismatch/PKGBUILD.aur.golden"
if run_mode_test 0 golden-mismatch "$golden_mismatch" >| "$tmp/mode-golden-mismatch.out" 2>&1; then
    fail "Mismatched golden PKGBUILD should cause mode_test to fail"
else
    status=$?
fi
[[ "$status" -eq 1 ]] || fail "Mismatched golden PKGBUILD should exit 1, got $status"
grep -Fq 'aur PKGBUILD does not match golden file!' "$tmp/mode-golden-mismatch.out" \
    || fail "Missing golden mismatch diagnostic for aur"
grep -Fq '1 test mode(s) failed' "$tmp/mode-golden-mismatch.out" \
    || fail "Golden mismatch did not increment TEST_ERRORS"
grep -Fq -- '-expected mismatch' "$tmp/modes-golden-mismatch/diff-aur.log" \
    || fail "diff-aur.log did not record expected golden content"
grep -Fq '+generated aur' "$tmp/modes-golden-mismatch/diff-aur.log" \
    || fail "diff-aur.log did not record generated PKGBUILD content"

# mode_test namcap integration: warnings keep exit 0; errors count TEST_ERRORS without aborting remaining modes.
mode_namcap_bin="$tmp/mode-namcap-bin"
mkdir -p "$mode_namcap_bin"
cat >| "$mode_namcap_bin/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$NAMCAP_CALLS"
if [[ "${NAMCAP_FAIL_AUR:-0}" == 1 ]] && grep -Fq 'generated aur' "$1"; then
    printf '%s\n' 'PKGBUILD E: missing license'
    exit 1
fi
printf '%s\n' 'PKGBUILD W: minor warning'
exit 0
EOF
chmod +x "$mode_namcap_bin/namcap"

: >| "$tmp/namcap-warn.calls"
if ! NAMCAP_CALLS="$tmp/namcap-warn.calls" NAMCAP_FAIL_AUR=0 run_mode_test 0 namcap-warn "$tmp/golden" "$mode_namcap_bin:$mode_bin" >| "$tmp/mode-namcap-warn.out" 2>&1; then
    fail "namcap warnings inside mode_test should exit 0"
fi
[[ "$(wc -l < "$tmp/namcap-warn.calls")" -eq 3 ]] || fail "mode_test did not invoke namcap for all 3 modes"
grep -Fq '[namcap] PKGBUILD W: minor warning' "$tmp/mode-namcap-warn.out" \
    || fail "mode_test did not emit namcap warning"

: >| "$tmp/namcap-err.calls"
if NAMCAP_CALLS="$tmp/namcap-err.calls" NAMCAP_FAIL_AUR=1 run_mode_test 0 namcap-err "$tmp/golden" "$mode_namcap_bin:$mode_bin" >| "$tmp/mode-namcap-err.out" 2>&1; then
    fail "namcap error inside mode_test should exit 1"
else
    status=$?
fi
[[ "$status" -eq 1 ]] || fail "namcap error inside mode_test should exit 1, got $status"
[[ "$(wc -l < "$tmp/namcap-err.calls")" -eq 3 ]] || fail "namcap error on aur aborted remaining modes"
grep -Fq '[namcap] PKGBUILD E: missing license' "$tmp/mode-namcap-err.out" \
    || fail "mode_test did not emit namcap error"
grep -Fq '1 test mode(s) failed' "$tmp/mode-namcap-err.out" \
    || fail "namcap error inside mode_test was not counted"

# Invalid arguments returning exit 0 must fail mode_test and count every offending combo.
if PASS_INVALID_ARGS=1 run_mode_test 0 invalid-args >| "$tmp/mode-invalid.out" 2>&1; then
    fail "Invalid argument returning exit 0 should fail mode_test"
else
    status=$?
fi
[[ "$status" -eq 1 ]] || fail "Invalid argument returning exit 0 should exit 1, got $status"
grep -Fq "Invalid args '-0' did NOT fail as expected!" "$tmp/mode-invalid.out" \
    || fail "mode_test did not name invalid args failure"
grep -Fq '15 test mode(s) failed' "$tmp/mode-invalid.out" \
    || fail "mode_test did not count all 15 invalid arg combos"
