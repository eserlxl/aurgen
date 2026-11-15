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
