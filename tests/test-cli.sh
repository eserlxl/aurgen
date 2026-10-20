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
