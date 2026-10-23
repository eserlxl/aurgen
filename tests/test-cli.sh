#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Unknown options are parse errors, not a missing GNU getopt.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-cli.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

# Check runner isolation before this fixture replaces any destinations.
if [[ -n "${AURGEN_TEST_STATE_ROOT:-}" ]]; then
    [[ "$HOME" == "$AURGEN_TEST_STATE_ROOT/home" && "${XDG_CONFIG_HOME:-}" == "$AURGEN_TEST_STATE_ROOT/config" ]] || fail "runner did not isolate HOME and XDG_CONFIG_HOME"
    global_config="$(env GIT_CONFIG_COUNT=0 git config --global --list)" || fail "runner global Git config is unreadable"
    [[ -z "$global_config" ]] || fail "runner inherited global Git config after fixture overrides"
    [[ -z "${RELEASE+x}" ]] || fail "runner kept the caller's RELEASE=$RELEASE"
fi

export AURGEN_LOG="$tmp/aurgen.log"
export AURGEN_ERROR_LOG="$tmp/aurgen-error.log"
# bin/aurgen creates its state dir and aur mode reads the AUR clone dir; keep both in tmp.
export XDG_STATE_HOME="$tmp/state"
export XDG_DATA_HOME="$tmp/data"
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

expect_parse_error() {
    local name="$1"
    shift
    if "$ROOT/bin/aurgen" "$@" >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail "$name: expected a non-zero exit" "$tmp/$name.err"
    fi
    if ! grep -F -q 'Failed to parse options' "$tmp/$name.err"; then
        fail "$name: missing parse error" "$tmp/$name.err"
    fi
    if grep -F -q 'GNU getopt required' "$tmp/$name.err"; then
        fail "$name: reported a missing getopt" "$tmp/$name.err"
    fi
    if ! grep -F -q 'Usage: aurgen' "$tmp/$name.out"; then
        fail "$name: missing usage" "$tmp/$name.out"
    fi
}

expect_parse_error bogus --bogus
expect_parse_error maxdepth --maxdepth

if (cd "$tmp" && "$ROOT/bin/aurgen" --build-only aur) >"$tmp/build-only.out" 2>"$tmp/build-only.err"; then
    fail "--build-only aur should fail" "$tmp/build-only.out"
fi
grep -F -q -- '--build-only is only valid with local' "$tmp/build-only.err" || fail "--build-only aur did not explain the error" "$tmp/build-only.err"
[[ ! -e "$tmp/aur" ]] || fail "--build-only aur should fail before initialization"

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
printf '#!/bin/bash\nprintf ok\n' > "$repo/ok.sh"
chmod +x "$repo/ok.sh"
git -C "$repo" add ok.sh
git -C "$repo" commit -q -m init
git -C "$repo" remote add origin "https://github.com/example/demo.git"

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 0\n' > "$stub/curl"
# Logged in; no release exists yet; creating and uploading succeed.
cat > "$stub/gh" <<'EOF'
#!/bin/bash
case "${1:-} ${2:-}" in
    "auth status"|"release create"|"release upload") exit 0 ;;
esac
exit 1
EOF
chmod +x "$stub/makepkg" "$stub/updpkgsums" "$stub/curl" "$stub/gh"

run_in_repo() {
    local name="$1"
    shift
    if ! (cd "$repo" && "$@") >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail "$name failed" "$tmp/$name.err"
    fi
}

run_in_repo lint-env env PATH="$stub:$PATH" MAXDEPTH=2 "$ROOT/bin/aurgen" lint
if ! grep -E -q 'depth 2([^0-9]|$)' "$tmp/lint-env.out"; then
    fail "MAXDEPTH=2 lint did not log depth 2" "$tmp/lint-env.out"
fi

run_in_repo lint-flag env PATH="$stub:$PATH" MAXDEPTH=9 "$ROOT/bin/aurgen" --maxdepth 2 lint
if ! grep -E -q 'depth 2([^0-9]|$)' "$tmp/lint-flag.out"; then
    fail "--maxdepth did not override MAXDEPTH" "$tmp/lint-flag.out"
fi
if grep -E -q 'depth 9([^0-9]|$)' "$tmp/lint-flag.out"; then
    fail "--maxdepth kept the MAXDEPTH value" "$tmp/lint-flag.out"
fi

# Git lint includes new scripts, skips ignored/generated paths and respects depth.
(
    repo="$tmp/lint-repo"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" remote add origin https://github.com/example/lint-repo.git
    printf 'node_modules/\nbuild/\n' >| "$repo/.gitignore"
    mkdir -p "$repo/node_modules" "$repo/build" "$repo/aur" "$repo/Backups" \
        "$repo/nested/aur" "$repo/nested/Backups" "$repo/nested/deep"
    printf '#!/bin/bash\nprintf ok\n' >| "$repo/ok.sh"
    printf '#!/bin/bash\nif\n' >| "$repo/deleted.sh"
    git -C "$repo" add .gitignore ok.sh deleted.sh
    rm "$repo/deleted.sh"
    for path in node_modules/broken.sh build/broken.sh aur/broken.sh Backups/broken.sh \
        nested/aur/broken.sh nested/Backups/broken.sh nested/deep/broken.sh; do
        printf '#!/bin/bash\nif\n' >| "$repo/$path"
    done
    printf '#!/bin/bash\nprintf ok\n' >| "$repo/nested/ok.sh"
    run_in_repo lint-git env PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 2 lint
    grep -F -q 'nested/ok.sh' "$tmp/lint-git.out" || fail "lint skipped a file at maxdepth" "$tmp/lint-git.out"

    printf '#!/bin/bash\nif\n' >| "$repo/new.sh"
    if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 2 lint) >|"$tmp/lint-new.out" 2>|"$tmp/lint-new.err"; then
        fail "lint accepted a broken untracked script" "$tmp/lint-new.out"
    fi
    grep -F -q 'new.sh' "$tmp/lint-new.out" || fail "lint did not report the new script" "$tmp/lint-new.out"
    rm "$repo/new.sh"

    printf '#!/bin/bash\nif\n' >| "$repo/new-command"
    if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 2 lint) >|"$tmp/lint-shebang.out" 2>|"$tmp/lint-shebang.err"; then
        fail "lint accepted a broken extensionless Bash script" "$tmp/lint-shebang.out"
    fi
    grep -F -q 'new-command' "$tmp/lint-shebang.out" || fail "lint did not report the Bash shebang script" "$tmp/lint-shebang.out"
    rm "$repo/new-command"

    if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 3 lint) >|"$tmp/lint-depth.out" 2>|"$tmp/lint-depth.err"; then
        fail "lint skipped a broken script at maxdepth 3" "$tmp/lint-depth.out"
    fi
    grep -F -q 'nested/deep/broken.sh' "$tmp/lint-depth.out" || fail "lint did not report the deeper script" "$tmp/lint-depth.out"
    rm "$repo/nested/deep/broken.sh"
    run_in_repo lint-generated env PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 3 lint
) || exit 1

run_in_repo local-env env PATH="$stub:$PATH" DRY_RUN=1 "$ROOT/bin/aurgen" local
if ! grep -F -q 'Dry run: skipping install' "$tmp/local-env.out"; then
    fail "DRY_RUN=1 local did not skip install" "$tmp/local-env.out"
fi

run_in_repo local-flag env PATH="$stub:$PATH" DRY_RUN=0 "$ROOT/bin/aurgen" -d local
if ! grep -F -q 'Dry run: skipping install' "$tmp/local-flag.out"; then
    fail "-d did not override DRY_RUN=0" "$tmp/local-flag.out"
fi

run_in_repo aur-env env PATH="$stub:$PATH" DRY_RUN=0 NO_WAIT=1 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$ROOT/bin/aurgen" aur
if ! grep -F -q 'Skipping post-upload wait' "$tmp/aur-env.err"; then
    fail "NO_WAIT=1 aur did not skip the upload wait" "$tmp/aur-env.err"
fi
if grep -F -q 'Waiting for GitHub to propagate' "$tmp/aur-env.err"; then
    fail "NO_WAIT=1 aur still waited" "$tmp/aur-env.err"
fi

run_in_repo aur-flag env PATH="$stub:$PATH" DRY_RUN=0 NO_WAIT=0 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$ROOT/bin/aurgen" --no-wait aur
if ! grep -F -q 'Skipping post-upload wait' "$tmp/aur-flag.err"; then
    fail "--no-wait did not override NO_WAIT=0" "$tmp/aur-flag.err"
fi

if "$ROOT/bin/aurgen" --maxdepth abc lint >"$tmp/maxdepth.out" 2>"$tmp/maxdepth.err"; then
    fail "--maxdepth abc should fail" "$tmp/maxdepth.out"
fi
if ! grep -F -q 'Invalid --maxdepth: abc (expected a positive integer)' "$tmp/maxdepth.err"; then
    fail "--maxdepth abc did not explain the error" "$tmp/maxdepth.err"
fi
run_in_repo maxdepth-ok env PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 3 lint

# clean has no dry run, so --dry-run clean is refused and deletes nothing.
mkdir -p "$repo/aur"
printf 'pkgname=demo\n' > "$repo/aur/PKGBUILD"
if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --dry-run clean) >"$tmp/dry-clean.out" 2>"$tmp/dry-clean.err"; then
    fail "--dry-run clean should fail" "$tmp/dry-clean.out"
fi
[[ -f "$repo/aur/PKGBUILD" ]] || fail "--dry-run clean deleted aur/PKGBUILD" "$tmp/dry-clean.err"

# A non-GitHub remote is refused before cleanup removes existing artifacts, even
# when github.com appears elsewhere in the URL.
other="$tmp/other"
mkdir -p "$other/aur"
git -C "$other" init -q -b main
git -C "$other" remote add origin "https://gitlab.com/example/demo.git"
for url in "https://gitlab.com/example/demo.git" "https://evilgithub.com/example/demo.git" \
    "https://gitlab.com/github.com/demo.git" "git@notgithub.com:example/demo.git"; do
    git -C "$other" remote set-url origin "$url"
    printf 'pkgname=demo\n' > "$other/aur/PKGBUILD"
    if (cd "$other" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/gitlab.out" 2>"$tmp/gitlab.err"; then
        fail "remote $url should be refused" "$tmp/gitlab.out"
    fi
    if ! grep -F -q 'only supports GitHub projects' "$tmp/gitlab.err"; then
        fail "refusal of $url did not name the GitHub requirement" "$tmp/gitlab.err"
    fi
    if [[ ! -f "$other/aur/PKGBUILD" ]]; then
        fail "refused run for $url deleted aur/PKGBUILD" "$tmp/gitlab.err"
    fi
done

# aurgen's own package (aurgen and aurgen-git alike) installs its lib and VERSION
# where the installed bin/aurgen looks for them.
grep -F -q 'LIB_INSTALL_DIR="/usr/lib/aurgen"' "$ROOT/bin/aurgen" || fail "bin/aurgen no longer searches /usr/lib/aurgen"
(
    export AUR_DIR="$ROOT/aur" AURGEN_ERROR_LOG="$tmp/own-config.err" DEBUG_LEVEL=0 color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    load_aurgen_config >/dev/null 2>&1 || exit 1
    [[ "$COPY_RULES_LIB" == usr/lib/aurgen:* ]] || { echo "lib rule: $COPY_RULES_LIB"; exit 1; }
    [[ "${PKG_POST_PACKAGE[*]}" == *'/usr/lib/aurgen/VERSION'* ]] || { echo "post_package: ${PKG_POST_PACKAGE[*]}"; exit 1; }
) >"$tmp/own-config.out" 2>&1 || fail "aurgen's own config installs its lib outside /usr/lib/aurgen" "$tmp/own-config.out"

# www.github.com is GitHub too: it gets past the refusal.
git -C "$other" remote set-url origin "https://www.github.com/example/demo.git"
(cd "$other" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/www.out" 2>"$tmp/www.err"
if grep -F -q 'only supports GitHub projects' "$tmp/www.err"; then
    fail "a www.github.com remote was refused" "$tmp/www.err"
fi

# A Turkish locale must not drop i from the [a-z] ranges that validate names.
if locale -a 2>/dev/null | grep -qix 'tr_TR\.utf-\?8'; then
    trrepo="$tmp/linux-cleaner"
    mkdir -p "$trrepo/bin"
    git -C "$trrepo" init -q -b main
    git -C "$trrepo" remote add origin "https://github.com/example/linux-cleaner.git"
    printf '#!/bin/sh\necho hi\n' > "$trrepo/bin/linux-cleaner"
    (cd "$trrepo" && env LC_ALL=tr_TR.UTF-8 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/tr.out" 2>"$tmp/tr.err"
    if grep -F -q 'Invalid package name' "$tmp/tr.out" "$tmp/tr.err"; then
        fail "a Turkish LC_ALL rejected the name linux-cleaner" "$tmp/tr.err"
    fi
    # The default package name is the repo name in ASCII lowercase, never a dotless i.
    caprepo="$tmp/ImageTool"
    mkdir -p "$caprepo/bin"
    git -C "$caprepo" init -q -b main
    git -C "$caprepo" remote add origin "https://github.com/example/ImageTool.git"
    printf '#!/bin/sh\necho hi\n' > "$caprepo/bin/imagetool"
    (cd "$caprepo" && env LC_ALL=tr_TR.UTF-8 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/trcap.out" 2>"$tmp/trcap.err"
    if grep -F -q 'Invalid package name' "$tmp/trcap.out" "$tmp/trcap.err"; then
        fail "a Turkish LC_ALL folded ImageTool into an invalid package name" "$tmp/trcap.err"
    fi
    grep -F -q 'imagetool' "$tmp/trcap.out" "$tmp/trcap.err" || fail "ImageTool did not become the package name imagetool" "$tmp/trcap.out"
fi

# Installed layout: bin/ and lib/ live apart and VERSION sits in the lib dir.
inst="$tmp/inst"
mkdir -p "$inst/usr/bin" "$inst/usr/lib/aurgen"
cp "$ROOT/bin/aurgen" "$inst/usr/bin/aurgen"
cp -r "$ROOT/lib/." "$inst/usr/lib/aurgen/"
printf '9.9.9\n' > "$inst/usr/lib/aurgen/VERSION"
if ! RELEASE=0 AURGEN_LIB_DIR="$inst/usr/lib/aurgen" "$inst/usr/bin/aurgen" --version >"$tmp/inst.out" 2>&1; then
    fail "installed aurgen --version failed" "$tmp/inst.out"
fi
if ! grep -F -q 'aurgen version 9.9.9' "$tmp/inst.out"; then
    fail "installed aurgen did not read VERSION from its lib dir" "$tmp/inst.out"
fi

# A copied aurgen runs in release mode on the lib AURGEN_LIB_DIR names, with no
# fallback to development mode. CI=1 (aurgen test sets it for its child runs) must
# not switch it to development mode either.
for env_case in "RELEASE=1" "CI=1"; do
    if ! (unset RELEASE; env "$env_case" AURGEN_LIB_DIR="$inst/usr/lib/aurgen" "$inst/usr/bin/aurgen" --version) >"$tmp/rel.out" 2>&1; then
        fail "installed aurgen --version failed under $env_case" "$tmp/rel.out"
    fi
    grep -F -q 'aurgen version 9.9.9' "$tmp/rel.out" || fail "$env_case: AURGEN_LIB_DIR was not used" "$tmp/rel.out"
    if grep -E -q 'DEVELOPMENT mode|Falling back' "$tmp/rel.out"; then
        fail "$env_case: installed aurgen left release mode" "$tmp/rel.out"
    fi
done


# A relative lib path must survive aur mode changing from a subdirectory to the project root.
cat >> "$inst/usr/lib/aurgen/aur-integration.sh" <<'EOF'
printf 'relative-lib: %s|%s\n' "$PWD" "$LIB_INSTALL_DIR"
EOF
mkdir -p "$repo/subdir"
ln -s "$inst/usr/lib/aurgen" "$repo/subdir/lib"
for release in 0 1; do
    for cdpath in '' .; do
        if ! (cd "$repo/subdir" && env CDPATH="$cdpath" PATH="$stub:$PATH" RELEASE="$release" AURGEN_LIB_DIR="lib" GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$inst/usr/bin/aurgen" --dry-run aur) >| "$tmp/relative-lib.out" 2>&1; then
            fail "RELEASE=$release CDPATH=$cdpath: relative AURGEN_LIB_DIR failed" "$tmp/relative-lib.out"
        fi
        grep -F -x -q "relative-lib: $repo|$repo/subdir/lib" "$tmp/relative-lib.out" || fail "RELEASE=$release CDPATH=$cdpath: lib was not absolute and loaded after cd" "$tmp/relative-lib.out"
    done
done


# A color choice made before lib/colors.sh is sourced again (-n, CI) must survive it.
# The check needs a terminal: init_colors already turns color off without one.
color_probe() {
    script -qec "bash -c '$1 AURGEN_ERROR_LOG=/dev/null; source \"$ROOT/lib/colors.sh\"; init_colors; printf \"[%s]\" \"\$YELLOW\"'" /dev/null | tr -d '\r'
}
[[ "$(color_probe '')" == "["$'\e'* ]] || fail "colors.sh should color a terminal by default (pty probe broken?)"
[[ "$(color_probe 'color_enabled=0;')" == "[]" ]] || fail "re-sourcing colors.sh turned color back on after color_enabled=0"

# COLOR=0 or 1 forces color after --no-color and CI. Count escapes in a real run on a terminal.
# script -e passes aurgen's exit status through, so a crash cannot pass as zero escapes.
color_run() {
    local rc=0
    (cd "$repo" && script -qec "env $1 '$ROOT/bin/aurgen' $2 --maxdepth 1 lint" /dev/null) >| "$tmp/color.out" || rc=$?
    # stderr: callers read stdout as the count.
    (( rc == 0 )) || fail "aurgen lint failed on a terminal ($1 $2, exit $rc)" "$tmp/color.out" >&2
    grep -c $'\e\[' "$tmp/color.out" || true
}
[[ "$(color_run X=1 '')" -gt 0 ]] || fail "aurgen lint printed no color on a terminal (pty probe broken?)"
[[ "$(color_run COLOR=0 '')" -eq 0 ]] || fail "COLOR=0 still printed color"
[[ "$(color_run COLOR=1 -n)" -gt 0 ]] || fail "COLOR=1 did not override --no-color"

# aur and git only write packaging files; the AUR push is aur-deploy (or --deploy).
"$ROOT/bin/aurgen" --help >"$tmp/help.out" 2>&1 || fail "--help failed" "$tmp/help.out"
if grep -E -q '^  (aur|git) .*upload to AUR' "$tmp/help.out"; then
    fail "--help says aur or git uploads to the AUR" "$tmp/help.out"
fi
if grep -E -q 'Lint PKGBUILD|on this script' "$tmp/help.out"; then
    fail "--help says lint checks the PKGBUILD or only this script" "$tmp/help.out"
fi
