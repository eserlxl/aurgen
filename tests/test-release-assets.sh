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

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 1\n' > "$stub/gpg"
printf '#!/bin/bash\nexit 1\n' > "$stub/curl"
chmod +x "$stub/makepkg" "$stub/updpkgsums" "$stub/gpg" "$stub/curl"

cat > "$stub/gh" << 'EOF'
#!/bin/bash
if [[ "${GH_FAIL:-0}" == 1 ]]; then
    exit 1
fi
if [[ "$*" == *"--json"* ]]; then
    printf '%s\n' "${GH_ASSET_NAMES:-}"
    exit 0
fi
exit 0
EOF
chmod +x "$stub/gh"

: > "$tmp/err.log"
: > "$tmp/out.log"

check_asset() {
    local names="$1"
    local fail_gh="$2"
    local expect="$3"
    local label="$4"
    local status
    (
        set +u
        export GH_ASSET_NAMES="$names"
        export GH_FAIL="$fail_gh"
        export PATH="$stub:$PATH"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        asset_exists "https://github.com/example/demo/releases/download/1.0.0/demo-1.0.0.tar.gz" "1.0.0" "demo-1.0.0.tar.gz"
    )
    status=$?
    if [[ "$status" != "$expect" ]]; then
        fail "$label: expected exit $expect, got $status"
    fi
}

check_asset "demo-1.0.0.tar.gz" 0 0 "listed asset should count as present"
check_asset "other.zip" 0 1 "a release whose assets omit the tarball should count as missing"
check_asset "" 0 1 "an empty asset list should count as missing"
check_asset "demo-1.0.0.tar.gz" 1 1 "a failed release view should count as missing"

repo="$tmp/repo"
mkdir -p "$repo/aur"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'x\n' > "$repo/payload.txt"
git -C "$repo" add payload.txt
git -C "$repo" commit -q -m init
cat > "$repo/aur/PKGBUILD.0" << 'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
pkgdesc='demo'
arch=('x86_64')
url='https://example.com'
license=('GPL-3.0-or-later')
source=("https://example.com/demo-1.0.0.tar.gz")
b2sums=('SKIP')
EOF
cp "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD"

export GH_LOG="$tmp/gh.log"
export GH_STATE="$tmp/gh-state"
mkdir -p "$GH_STATE"

cat > "$stub/gh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_LOG"
action="${2:-}"
tag="${3:-}"
case "$1 $action" in
    "release view")
        if [[ "$*" == *"--json"* ]]; then
            if [[ -f "$GH_STATE/$tag.assets" ]]; then
                cat "$GH_STATE/$tag.assets"
                exit 0
            fi
            exit 1
        fi
        if [[ -f "$GH_STATE/$tag.exists" ]]; then
            exit 0
        fi
        exit 1
        ;;
    "release upload"|"release create")
        printf '%s\n' "$tag" >> "$GH_LOG.actions"
        exit 0
        ;;
esac
exit 1
EOF
chmod +x "$stub/gh"

mark_release() {
    local tag="$1"
    local assets="$2"
    touch "$GH_STATE/$tag.exists"
    printf '%s\n' "$assets" > "$GH_STATE/$tag.assets"
}

run_aur() {
    : > "$GH_LOG"
    : > "$GH_LOG.actions"
    (
        set +u
        export PATH="$stub:$PATH"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$repo/aur/PKGBUILD"
        export SRCINFO="$repo/aur/.SRCINFO"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        export dry_run=0
        export no_wait=1
        export PKGNAME=demo
        export GH_USER=example
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export LIB_INSTALL_DIR="$tmp/nolib"
        mkdir -p "$LIB_INSTALL_DIR"
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/modes/aur.sh
        source "$ROOT/lib/modes/aur.sh"
        filter_pkgbuild_sources() { cat; }
        mode_aur
    ) >"$tmp/aur.out" 2>"$tmp/aur.err" < /dev/null
}

source_tag() {
    grep -o 'releases/download/[^/"]*' "$repo/aur/PKGBUILD" | sed 's|releases/download/||' | sort -u
}

checked_tag() {
    awk '/--json/ { print $3 }' "$GH_LOG" | sort -u
}

assert_same_tag() {
    local expect="$1"
    local want_upload="$2"
    local label="$3"
    local got_url got_check got_upload
    got_url=$(source_tag)
    got_check=$(checked_tag)
    if [[ "$got_url" != "$expect" ]]; then
        fail "$label: source URL tag should be $expect, got ${got_url:-<none>}" "$repo/aur/PKGBUILD"
    fi
    if [[ "$got_check" != "$expect" ]]; then
        fail "$label: asset check tag should be $expect, got ${got_check:-<none>}" "$GH_LOG"
    fi
    if [[ "$want_upload" == 1 ]]; then
        if [[ ! -s "$GH_LOG.actions" ]]; then
            fail "$label: release without the asset should upload" "$GH_LOG"
        fi
        got_upload=$(sort -u "$GH_LOG.actions")
        if [[ "$got_upload" != "$expect" ]]; then
            fail "$label: upload tag should be $expect, got ${got_upload:-<none>}" "$GH_LOG.actions"
        fi
    elif [[ -s "$GH_LOG.actions" ]]; then
        fail "$label: existing asset should not upload" "$GH_LOG.actions"
    fi
}

# v$PKGVER exists, so the plain tag is not used even if it already has the tarball.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" "other.zip"
mark_release "1.0.0" "demo-1.0.0.tar.gz"
if ! run_aur; then
    fail "v-tag aur run failed" "$tmp/aur.err"
fi
assert_same_tag "v1.0.0" 1 "v-prefixed release without the tarball"

rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "1.0.0" "other.zip"
if ! run_aur; then
    fail "plain-tag aur run failed" "$tmp/aur.err"
fi
assert_same_tag "1.0.0" 1 "plain release without the tarball"
if grep -E -q 'release (upload|create) v1\.0\.0' "$GH_LOG"; then
    fail "plain release should not upload to the v-prefixed tag" "$GH_LOG"
fi

rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" "demo-1.0.0.tar.gz"
if ! run_aur; then
    fail "present-asset aur run failed" "$tmp/aur.err"
fi
assert_same_tag "v1.0.0" 0 "v-prefixed release that already has the tarball"
