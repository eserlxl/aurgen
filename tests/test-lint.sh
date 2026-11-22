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

export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
unset GIT_CONFIG GIT_CONFIG_SYSTEM GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_JSON AURGEN_STATUS_DIFF \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT ALLOW_DIRTY SOURCE_DATE_EPOCH nocheck build_only COLOR NO_COLOR CI DEBUG_LEVEL \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

# 1. Direct execution of lib/modes/lint.sh must exit 1 with the library message and no command-not-found error.
if bash "$ROOT/lib/modes/lint.sh" >"$tmp/direct.out" 2>"$tmp/direct.err"; then
    fail "direct execution of lib/modes/lint.sh should exit non-zero"
fi
grep -Fq 'This script is a library and must be sourced, not executed.' "$tmp/direct.err" \
    || fail "direct execution did not print the library guard message" "$tmp/direct.err"
if grep -Fq 'command not found' "$tmp/direct.err"; then
    fail "direct execution hit command not found" "$tmp/direct.err"
fi

run_mode_lint() {
    local root="$1"
    local run_path="${2:-$PATH}"
    (
        export PATH="$run_path"
        export PROJECT_ROOT="$root"
        export AURGEN_LOG="$tmp/aurgen.log"
        export AURGEN_ERROR_LOG="$tmp/aurgen-err.log"
        export color_enabled=0
        export DEBUG_LEVEL=0
        : >| "$AURGEN_LOG"
        : >| "$AURGEN_ERROR_LOG"
        # shellcheck source=../lib/colors.sh
        source "$ROOT/lib/colors.sh"
        init_colors
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/modes/lint.sh
        source "$ROOT/lib/modes/lint.sh"
        mode_lint
    )
}

# 2. Git worktree: passing scripts succeed, leading-dash filename is safe, and non-zero tool exit or -n output is captured verbatim.
repo="$tmp/gitrepo"
mkdir -p "$repo" "$tmp/stub"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
printf '#!/bin/bash\nprintf ok\n' >| "$repo/good.sh"
printf '#!/bin/bash\nprintf dash\n' >| "$repo/-n.sh"
git -C "$repo" add -- good.sh -n.sh
git -C "$repo" commit -q -m init

cat >| "$tmp/stub/shellcheck" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$tmp/stub/shellcheck"

if ! run_mode_lint "$repo" "$tmp/stub:$PATH" >"$tmp/pass.out" 2>"$tmp/pass.err"; then
    fail "mode_lint failed on clean scripts (including -n.sh)" "$tmp/pass.err"
fi
grep -Fq '2 passed, 0 failed' "$tmp/pass.out" || fail "unexpected pass summary" "$tmp/pass.out"

# Silent non-zero shellcheck exit must still mark the file failed, and leading -n diagnostic text must not be eaten by echo.
cat >| "$tmp/stub/shellcheck" <<'EOF'
#!/bin/bash
target="${!#}"
case "$target" in
    *good.sh)
        printf '%s\n' '-n warning on good.sh'
        exit 1
        ;;
    *-n.sh)
        exit 2
        ;;
esac
exit 0
EOF
chmod +x "$tmp/stub/shellcheck"

if run_mode_lint "$repo" "$tmp/stub:$PATH" >"$tmp/fail.out" 2>"$tmp/fail.err"; then
    fail "mode_lint should fail when shellcheck exits non-zero" "$tmp/fail.out"
fi
grep -Fq '0 passed, 2 failed' "$tmp/fail.out" || fail "both failing shellcheck targets should be counted" "$tmp/fail.out"
[[ "$(cat "$repo/aur/lint/./good.sh.shellcheck.txt" 2>/dev/null || cat "$repo/aur/lint/good.sh.shellcheck.txt")" == "-n warning on good.sh" ]] \
    || fail "leading -n shellcheck output was mangled in report file"

# 3. Non-git directory fallback + missing shellcheck fallback still catches bash -n syntax errors.
plain="$tmp/plain"
mkdir -p "$plain/aur" "$plain/Backups" "$tmp/nosc"
printf '#!/bin/bash\nif\n' >| "$plain/aur/ignored.sh"
printf '#!/bin/bash\nif\n' >| "$plain/Backups/ignored.sh"
printf '#!/bin/bash\nprintf ok\n' >| "$plain/tool"
chmod +x "$plain/tool"

IFS=: read -r -a path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for bin in "$dir"/*; do
        [[ -x "$bin" ]] || continue
        name="${bin##*/}"
        [[ "$name" == "shellcheck" || -e "$tmp/nosc/$name" ]] && continue
        ln -s "$bin" "$tmp/nosc/$name"
    done
done

if ! run_mode_lint "$plain" "$tmp/nosc" >"$tmp/plain-ok.out" 2>"$tmp/plain-ok.err"; then
    fail "non-git mode_lint without shellcheck failed on valid script" "$tmp/plain-ok.err"
fi
grep -Fq 'shellcheck not found' "$tmp/plain-ok.out" "$tmp/plain-ok.err" || fail "missing shellcheck warning was not emitted" "$tmp/plain-ok.out"

printf '#!/bin/bash\nif\n' >| "$plain/broken.sh"
if run_mode_lint "$plain" "$tmp/nosc" >"$tmp/plain-bad.out" 2>"$tmp/plain-bad.err"; then
    fail "non-git mode_lint accepted broken.sh" "$tmp/plain-bad.out"
fi
[[ -s "$plain/aur/lint/broken.sh.bashn.txt" ]] || fail "bash -n report was not written for broken.sh"

# 4. aurgen clean (mode_clean) removes generated aur/lint reports while leaving unrelated files in aur/.
[[ -d "$repo/aur/lint" ]] || fail "expected $repo/aur/lint before clean"
printf 'keep-me\n' >| "$repo/aur/PKGBUILD.0"
git -C "$repo" remote add origin "https://github.com/example/demo.git"
if ! (
    cd "$repo" || exit 1
    export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" AURGEN_LOG="$tmp/clean.log" AURGEN_ERROR_LOG="$tmp/clean-err.log"
    mkdir -p "$HOME" "$XDG_STATE_HOME"
    "$ROOT/bin/aurgen" -n clean
) >"$tmp/clean.out" 2>"$tmp/clean.err"; then
    fail "aurgen clean failed on repo with aur/lint" "$tmp/clean.err"
fi
[[ ! -e "$repo/aur/lint" ]] || fail "aurgen clean did not remove $repo/aur/lint"
[[ -f "$repo/aur/PKGBUILD.0" ]] || fail "aurgen clean removed aur/PKGBUILD.0"

# 5. aurgen --json lint emits clean structured JSON on stdout for passing, failing, empty, and missing-shellcheck runs.
json_repo="$tmp/json-repo"
mkdir -p "$json_repo/sub"
printf '#!/bin/bash\nprintf "hi\\n"\n' >| "$json_repo/good.sh"
printf '#!/bin/bash\nunused=1\n' >| "$json_repo/sub/warn.sh"
git -C "$json_repo" init -q
git -C "$json_repo" remote add origin "https://github.com/example/demo.git"
git -C "$json_repo" add good.sh sub/warn.sh

# Mock shellcheck for deterministic CLI --json tests
json_sc="$tmp/json-sc-bin"
mkdir -p "$json_sc"
cat >| "$json_sc/shellcheck" <<'EOF'
#!/bin/bash
for arg in "$@"; do
    [[ "$arg" == "--" || ! -f "$arg" ]] && continue
    if grep -q 'unused=' "$arg"; then
        printf 'SC2034: unused appears unused.\n'
        exit 1
    fi
done
exit 0
EOF
chmod +x "$json_sc/shellcheck"

if (
    cd "$json_repo" || exit 1
    export RELEASE=0 HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" AURGEN_LOG="$tmp/jlint.log" AURGEN_ERROR_LOG="$tmp/jlint-err.log" PATH="$json_sc:$PATH"
    mkdir -p "$HOME" "$XDG_STATE_HOME"
    "$ROOT/bin/aurgen" --json lint
) >|"$tmp/jlint-fail.out" 2>|"$tmp/jlint-fail.err"; then
    fail "--json lint unexpectedly passed with failing shellcheck script" "$tmp/jlint-fail.out"
fi
if grep -q '^\[INFO\]' "$tmp/jlint-fail.out" || ! grep -q '^\[INFO\] AURGen is running in DEVELOPMENT mode' "$tmp/jlint-fail.err"; then
    fail "--json lint leaked development banners to stdout instead of stderr" "$tmp/jlint-fail.out"
fi
python3 - "$tmp/jlint-fail.out" <<'PY' || fail "--json lint failing JSON schema mismatch" "$tmp/jlint-fail.out"
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["ok"] is False
assert data["shellcheck_available"] is True
assert data["report_dir"] == "aur/lint"
assert data["summary"] == {"total": 2, "passed": 1, "failed": 1}
by_path = {f["path"]: f for f in data["files"]}
assert by_path["good.sh"]["passed"] is True
assert by_path["good.sh"]["bashn_ok"] is True and by_path["good.sh"]["shellcheck_ok"] is True
assert by_path["good.sh"]["bashn_report"] is None and by_path["good.sh"]["shellcheck_report"] is None
assert by_path["sub/warn.sh"]["passed"] is False
assert by_path["sub/warn.sh"]["bashn_ok"] is True and by_path["sub/warn.sh"]["shellcheck_ok"] is False
assert by_path["sub/warn.sh"]["shellcheck_report"] == "aur/lint/sub/warn.sh.shellcheck.txt"
PY
[[ -s "$json_repo/aur/lint/sub/warn.sh.shellcheck.txt" ]] || fail "missing shellcheck report referenced by --json lint"

# Fix sub/warn.sh so passing run exits 0 and emits ok=true
printf '#!/bin/bash\nprintf "ok\\n"\n' >| "$json_repo/sub/warn.sh"
if ! (
    cd "$json_repo" || exit 1
    export RELEASE=0 HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" AURGEN_LOG="$tmp/jlint-ok.log" AURGEN_ERROR_LOG="$tmp/jlint-ok-err.log" PATH="$json_sc:$PATH"
    "$ROOT/bin/aurgen" --json lint
) >|"$tmp/jlint-ok.out" 2>|"$tmp/jlint-ok.err"; then
    fail "--json lint failed on clean scripts" "$tmp/jlint-ok.err"
fi
python3 - "$tmp/jlint-ok.out" <<'PY' || fail "--json lint passing JSON schema mismatch" "$tmp/jlint-ok.out"
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["ok"] is True
assert data["summary"] == {"total": 2, "passed": 2, "failed": 0}
assert all(f["passed"] is True for f in data["files"])
PY

# Empty git repo: report_dir is null, files is [], ok is true
empty_repo="$tmp/json-empty-repo"
mkdir -p "$empty_repo"
git -C "$empty_repo" init -q
git -C "$empty_repo" remote add origin "https://github.com/example/demo.git"
if ! (
    cd "$empty_repo" || exit 1
    export RELEASE=0 HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" AURGEN_LOG="$tmp/jlint-empty.log" AURGEN_ERROR_LOG="$tmp/jlint-empty-err.log" PATH="$json_sc:$PATH"
    "$ROOT/bin/aurgen" --json lint
) >|"$tmp/jlint-empty.out" 2>|"$tmp/jlint-empty.err"; then
    fail "--json lint failed on empty dir" "$tmp/jlint-empty.err"
fi
python3 - "$tmp/jlint-empty.out" <<'PY' || fail "--json lint empty JSON schema mismatch" "$tmp/jlint-empty.out"
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["ok"] is True
assert data["report_dir"] is None
assert data["summary"] == {"total": 0, "passed": 0, "failed": 0}
assert data["files"] == []
PY

# Missing shellcheck in PATH: shellcheck_available is false and shellcheck_ok is null, bash -n failure still sets ok=false
no_sc_repo="$tmp/json-nosc-repo"
mkdir -p "$no_sc_repo"
printf '#!/bin/bash\nprintf "ok\\n"\n' >| "$no_sc_repo/pass.sh"
printf '#!/bin/bash\nif\n' >| "$no_sc_repo/bad.sh"
git -C "$no_sc_repo" init -q
git -C "$no_sc_repo" remote add origin "https://github.com/example/demo.git"
git -C "$no_sc_repo" add pass.sh bad.sh
if (
    cd "$no_sc_repo" || exit 1
    export RELEASE=0 HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" AURGEN_LOG="$tmp/jlint-nosc.log" AURGEN_ERROR_LOG="$tmp/jlint-nosc-err.log" PATH="$tmp/nosc"
    "$ROOT/bin/aurgen" --json lint
) >|"$tmp/jlint-nosc.out" 2>|"$tmp/jlint-nosc.err"; then
    fail "--json lint passed with bash -n syntax error" "$tmp/jlint-nosc.out"
fi
python3 - "$tmp/jlint-nosc.out" <<'PY' || fail "--json lint missing-shellcheck schema mismatch" "$tmp/jlint-nosc.out"
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["ok"] is False
assert data["shellcheck_available"] is False
by_path = {f["path"]: f for f in data["files"]}
assert by_path["pass.sh"]["passed"] is True and by_path["pass.sh"]["shellcheck_ok"] is None
assert by_path["bad.sh"]["passed"] is False and by_path["bad.sh"]["bashn_ok"] is False
assert by_path["bad.sh"]["shellcheck_ok"] is None
assert by_path["bad.sh"]["bashn_report"] == "aur/lint/bad.sh.bashn.txt"
PY

# The install scriptlet the PKGBUILD.0 names is linted although aur/ is otherwise skipped.
sl_repo="$tmp/scriptlet-repo"
mkdir -p "$sl_repo/aur"
printf '#!/bin/bash\nprintf ok\n' >| "$sl_repo/good.sh"
printf "pkgname=demo\ninstall='demo.install'\n" >| "$sl_repo/aur/PKGBUILD.0"
printf 'post_upgrade() {\n    if true; then\n}\n' >| "$sl_repo/aur/demo.install"
if run_mode_lint "$sl_repo" "$tmp/nosc" >"$tmp/sl-bad.out" 2>"$tmp/sl-bad.err"; then
    fail "mode_lint accepted a scriptlet with a syntax error" "$tmp/sl-bad.out"
fi
grep -Fq 'demo.install' "$tmp/sl-bad.out" "$tmp/sl-bad.err" || fail "mode_lint did not name the broken scriptlet" "$tmp/sl-bad.out"
printf 'post_upgrade() {\n    printf "%%s\\n" upgraded\n}\n' >| "$sl_repo/aur/demo.install"
if ! run_mode_lint "$sl_repo" "$tmp/nosc" >"$tmp/sl-ok.out" 2>"$tmp/sl-ok.err"; then
    fail "mode_lint rejected a valid scriptlet" "$tmp/sl-ok.err"
fi

# After a dry run only aur/dry-run/PKGBUILD.0 names the scriptlet; lint still finds it.
dr_repo="$tmp/dryrun-scriptlet-repo"
mkdir -p "$dr_repo/aur/dry-run"
printf '#!/bin/bash\nprintf ok\n' >| "$dr_repo/good.sh"
printf "pkgname=demo\ninstall='demo.install'\n" >| "$dr_repo/aur/dry-run/PKGBUILD.0"
printf 'post_install() {\n    if true; then\n}\n' >| "$dr_repo/aur/dry-run/demo.install"
if run_mode_lint "$dr_repo" "$tmp/nosc" >"$tmp/dr-bad.out" 2>"$tmp/dr-bad.err"; then
    fail "mode_lint missed a broken scriptlet named only by aur/dry-run/PKGBUILD.0" "$tmp/dr-bad.out"
fi
