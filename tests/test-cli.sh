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

export AURGEN_LOG="$tmp/aurgen.log"
export AURGEN_ERROR_LOG="$tmp/aurgen-error.log"
# bin/aurgen creates its state dir and aur mode reads the AUR clone dir; keep both in tmp.
export XDG_STATE_HOME="$tmp/state"
export XDG_DATA_HOME="$tmp/data"

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
# No release exists yet; creating and uploading succeed.
cat > "$stub/gh" <<'EOF'
#!/bin/bash
case "${1:-} ${2:-}" in
    "release create"|"release upload") exit 0 ;;
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

run_in_repo lint-env env MAXDEPTH=2 "$ROOT/bin/aurgen" lint
if ! grep -E -q 'depth 2([^0-9]|$)' "$tmp/lint-env.out"; then
    fail "MAXDEPTH=2 lint did not log depth 2" "$tmp/lint-env.out"
fi

run_in_repo lint-flag env MAXDEPTH=9 "$ROOT/bin/aurgen" --maxdepth 2 lint
if ! grep -E -q 'depth 2([^0-9]|$)' "$tmp/lint-flag.out"; then
    fail "--maxdepth did not override MAXDEPTH" "$tmp/lint-flag.out"
fi
if grep -E -q 'depth 9([^0-9]|$)' "$tmp/lint-flag.out"; then
    fail "--maxdepth kept the MAXDEPTH value" "$tmp/lint-flag.out"
fi

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
run_in_repo maxdepth-ok "$ROOT/bin/aurgen" --maxdepth 3 lint

# A non-GitHub remote is refused before cleanup removes existing artifacts.
other="$tmp/other"
mkdir -p "$other/aur"
git -C "$other" init -q -b main
git -C "$other" remote add origin "https://gitlab.com/example/demo.git"
printf 'pkgname=demo\n' > "$other/aur/PKGBUILD"
if (cd "$other" && "$ROOT/bin/aurgen" -n local) >"$tmp/gitlab.out" 2>"$tmp/gitlab.err"; then
    fail "a GitLab remote should be refused" "$tmp/gitlab.out"
fi
if ! grep -F -q 'only supports GitHub projects' "$tmp/gitlab.err"; then
    fail "GitLab refusal did not name the GitHub requirement" "$tmp/gitlab.err"
fi
if [[ ! -f "$other/aur/PKGBUILD" ]]; then
    fail "refused run deleted aur/PKGBUILD" "$tmp/gitlab.err"
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

# CI=1 (aurgen test sets it for its child runs) must not switch an installed aurgen to
# development mode, where it took /usr/lib as its lib directory.
# shortcut: needs an installed /usr/lib/aurgen; skipped elsewhere, upgrade if the release lib dir becomes configurable.
if [[ -f /usr/lib/aurgen/helpers.sh ]]; then
    if ! (unset RELEASE; CI=1 "$inst/usr/bin/aurgen" --version) >"$tmp/ci.out" 2>&1; then
        fail "installed aurgen --version failed under CI=1" "$tmp/ci.out"
    fi
    if grep -F -q 'DEVELOPMENT mode' "$tmp/ci.out"; then
        fail "CI=1 switched an installed aurgen to development mode" "$tmp/ci.out"
    fi
fi

