#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
# Scratch-repo commits must never sign with the user's key (commit.gpgsign in ~/.gitconfig).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
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
printf '#!/bin/bash\nexit "${CURL_STATUS:-22}"\n' > "$stub/curl"
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
    local curl_status="${5:-22}"
    local status
    (
        set +u
        export GH_ASSET_NAMES="$names"
        export GH_FAIL="$fail_gh"
        export CURL_STATUS="$curl_status"
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

check_url() {
    local url="$1"
    local curl_status="$2"
    local expect="$3"
    local label="$4"
    local status
    (
        set +u
        export CURL_STATUS="$curl_status"
        export PATH="$stub:$PATH"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        asset_exists "$url" "1.0.0" "demo-1.0.0.tar.gz"
    )
    status=$?
    if [[ "$status" != "$expect" ]]; then
        fail "$label: expected exit $expect, got $status"
    fi
}

check_asset "demo-1.0.0.tar.gz" 0 0 "listed asset should count as present"
check_asset "other.zip" 0 1 "a release whose assets omit the tarball should count as missing"
check_asset "" 0 1 "an empty asset list should count as missing"
check_asset "demo-1.0.0.tar.gz" 1 1 "a failed release view with HTTP 404 should count as missing" 22
check_asset "demo-1.0.0.tar.gz" 1 0 "a failed release view with a present HEAD response should count as present" 0
check_asset "demo-1.0.0.tar.gz" 1 2 "a failed release view and a non-HTTP HEAD failure should be unknown" 6
check_url "https://example.com/demo-1.0.0.tar.gz" 0 0 "a HEAD request that succeeds should count as present"
check_url "https://example.com/demo-1.0.0.tar.gz" 22 1 "a HEAD request that returns 22 should count as missing"
check_url "https://example.com/demo-1.0.0.tar.gz" 6 2 "a HEAD request that fails outside HTTP should be unknown"

repo="$tmp/repo"
mkdir -p "$repo/aur"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'x\n' > "$repo/payload.txt"
git -C "$repo" add payload.txt
git -C "$repo" commit -q -m init || fail "test repo commit failed"
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
    "auth status")
        if [[ "${GH_AUTH_FAIL:-0}" == 1 ]]; then
            exit 1
        fi
        exit 0
        ;;
    "release view")
        if [[ "$*" == *"--json"* ]]; then
            if [[ -n "${GH_JSON_FAIL_FROM:-}" ]]; then
                json_n=0
                if [[ -f "$GH_STATE/json.count" ]]; then
                    json_n=$(cat "$GH_STATE/json.count")
                fi
                json_n=$((json_n + 1))
                printf '%s\n' "$json_n" > "$GH_STATE/json.count"
                if (( json_n >= GH_JSON_FAIL_FROM )); then
                    exit 1
                fi
            fi
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
        for arg in "${@:4}"; do
            if [[ -f "$arg" ]]; then
                basename "$arg" >> "$GH_LOG.actions"
            fi
        done
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
        export PATH="${RUN_PATH:-$stub:$PATH}"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$repo/aur/PKGBUILD"
        export SRCINFO="$repo/aur/.SRCINFO"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        export dry_run="${RUN_DRY:-0}"
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
        got_upload=$(grep -v -F '.tar.gz' "$GH_LOG.actions" | sort -u)
        if [[ "$got_upload" != "$expect" ]]; then
            fail "$label: upload tag should be $expect, got ${got_upload:-<none>}" "$GH_LOG.actions"
        fi
        if ! grep -qx 'demo-1.0.0.tar.gz' "$GH_LOG.actions"; then
            fail "$label: upload should include demo-1.0.0.tar.gz" "$GH_LOG.actions"
        fi
        if ! grep -qx 'demo-1.0.0.tar.gz.sig' "$GH_LOG.actions"; then
            fail "$label: upload should include demo-1.0.0.tar.gz.sig" "$GH_LOG.actions"
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
mark_release "v1.0.0" $'demo-1.0.0.tar.gz\ndemo-1.0.0.tar.gz.sig'
if ! run_aur; then
    fail "present-asset aur run failed" "$tmp/aur.err"
fi
assert_same_tag "v1.0.0" 0 "v-prefixed release that already has the tarball and signature"
if grep -F -q 'auth status' "$GH_LOG"; then
    fail "declining overwrite of a complete release should not check gh auth" "$GH_LOG"
fi
if ! grep -F -q 'Skipped uploading; using existing asset.' "$tmp/aur.out"; then
    fail "a present asset should prompt and keep the published file when overwrite is declined" "$tmp/aur.out"
fi

# stdin is /dev/null inside run_aur, so the overwrite prompt stays at its default.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" "demo-1.0.0.tar.gz"
if ! run_aur; then
    fail "missing-signature aur run failed" "$tmp/aur.err"
fi
if ! grep -F 'release upload' "$GH_LOG" | grep -F -q -- 'demo-1.0.0.tar.gz.sig'; then
    fail "missing signature should be uploaded" "$GH_LOG"
fi
if grep -F 'release upload' "$GH_LOG" | grep -E -q -- 'demo-1.0.0\.tar\.gz([^.]|$)'; then
    fail "existing tarball should not be uploaded" "$GH_LOG"
fi

# No release yet, so a real run would create one. Login is checked first.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
if CURL_STATUS=22 GH_AUTH_FAIL=1 run_aur; then
    fail "unauthenticated gh should stop the upload" "$tmp/aur.err"
fi
if ! grep -F -q 'gh auth login --hostname github.com' "$tmp/aur.err"; then
    fail "unauthenticated gh should name gh auth login" "$tmp/aur.err"
fi
if grep -E -q 'release (upload|create)' "$GH_LOG"; then
    fail "unauthenticated gh should not create or upload" "$GH_LOG"
fi
if ! grep -F -q 'auth status --hostname github.com' "$GH_LOG"; then
    fail "unauthenticated gh should check auth status" "$GH_LOG"
fi

rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
if ! CURL_STATUS=22 GH_AUTH_FAIL=0 run_aur; then
    fail "authenticated gh should upload a missing release" "$tmp/aur.err"
fi
if ! grep -F -q 'auth status --hostname github.com' "$GH_LOG"; then
    fail "authenticated gh should check auth status" "$GH_LOG"
fi
if [[ ! -s "$GH_LOG.actions" ]]; then
    fail "authenticated gh should create or upload" "$GH_LOG"
fi

# gh failed and the HEAD probe returned a non-HTTP status. Stop before create or upload.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
probe_status=0
CURL_STATUS=6 run_aur || probe_status=$?
if [[ "$probe_status" -eq 0 ]]; then
    fail "an unreachable asset probe should stop aur" "$tmp/aur.err"
fi
if ! grep -F -q 'GitHub could not be reached' "$tmp/aur.err"; then
    fail "an unreachable asset probe should say GitHub could not be reached" "$tmp/aur.err"
fi
if ! grep -F -q 'https://github.com/example/demo/releases/download/1.0.0/demo-1.0.0.tar.gz' "$tmp/aur.err"; then
    fail "an unreachable asset probe should name the asset URL" "$tmp/aur.err"
fi
if grep -E -q 'release (upload|create)' "$GH_LOG"; then
    fail "an unreachable asset probe should not create or upload" "$GH_LOG"
fi

# The same probe on a dry run warns and still writes the source URL.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
if ! CURL_STATUS=6 RUN_DRY=1 run_aur; then
    fail "a dry run should warn when the asset probe cannot reach GitHub" "$tmp/aur.err"
fi
if ! grep -F -q 'GitHub could not be reached' "$tmp/aur.out" "$tmp/aur.err"; then
    fail "a dry run should name the unreachable asset probe" "$tmp/aur.err"
fi
if ! grep -F -q 'https://github.com/example/demo/releases/download/1.0.0/demo-1.0.0.tar.gz' "$tmp/aur.out" "$tmp/aur.err"; then
    fail "a dry run should name the unreachable asset URL" "$tmp/aur.err"
fi
if grep -F -q 'Asset is missing. Would upload' "$tmp/aur.out" "$tmp/aur.err"; then
    fail "a dry run with an unreachable probe should not report that it would upload" "$tmp/aur.err"
fi
if grep -E -q 'release (upload|create)' "$GH_LOG"; then
    fail "a dry run with an unreachable probe should not create or upload" "$GH_LOG"
fi
if ! grep -q 'releases/download/[^/]*/demo-1.0.0.tar.gz"' "$repo/aur/PKGBUILD"; then
    fail "a dry run with an unreachable probe should still write the source URL" "$repo/aur/PKGBUILD"
fi

# The tarball is published, but the signature probe cannot reach GitHub.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" "demo-1.0.0.tar.gz"
sig_status=0
GH_JSON_FAIL_FROM=2 CURL_STATUS=6 run_aur || sig_status=$?
if [[ "$sig_status" -eq 0 ]]; then
    fail "an unreachable signature probe should stop aur" "$tmp/aur.err"
fi
if ! grep -F -q 'GitHub could not be reached' "$tmp/aur.err"; then
    fail "an unreachable signature probe should say GitHub could not be reached" "$tmp/aur.err"
fi
if ! grep -F -q 'https://github.com/example/demo/releases/download/v1.0.0/demo-1.0.0.tar.gz.sig' "$tmp/aur.err"; then
    fail "an unreachable signature probe should name the signature URL" "$tmp/aur.err"
fi
if grep -E -q 'release (upload|create)' "$GH_LOG"; then
    fail "an unreachable signature probe should not create or upload" "$GH_LOG"
fi

# gh is optional. Without it the asset check falls back to curl: an asset uploaded
# by hand is enough, a dry run only warns, and a real run without the asset stops.
nogh="$tmp/nogh"
mkdir -p "$nogh"
printf '#!/bin/bash\nexit 0\n' > "$nogh/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$nogh/updpkgsums"
printf '#!/bin/bash\nexit 1\n' > "$nogh/gpg"
printf '#!/bin/bash\nexit "${CURL_STATUS:-22}"\n' > "$nogh/curl"
chmod +x "$nogh/makepkg" "$nogh/updpkgsums" "$nogh/gpg" "$nogh/curl"
IFS=: read -r -a path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
    for tool in "$dir"/*; do
        name="${tool##*/}"
        [[ "$name" == gh || -e "$nogh/$name" || ! -x "$tool" ]] && continue
        ln -s "$tool" "$nogh/$name"
    done
done

if ! CURL_STATUS=0 RUN_PATH="$nogh" run_aur; then
    fail "an asset uploaded by hand should be enough without gh" "$tmp/aur.err"
fi
if ! grep -q 'releases/download/[^/]*/demo-1.0.0.tar.gz"' "$repo/aur/PKGBUILD"; then
    fail "without gh the source URL should still be written" "$repo/aur/PKGBUILD"
fi
if ! CURL_STATUS=22 RUN_DRY=1 RUN_PATH="$nogh" run_aur; then
    fail "a dry run without gh and without the asset should only warn" "$tmp/aur.err"
fi
if ! grep -q 'A real run stops here' "$tmp/aur.out" "$tmp/aur.err"; then
    fail "the dry run without gh should warn about the missing asset" "$tmp/aur.err"
fi
if CURL_STATUS=22 RUN_PATH="$nogh" run_aur; then
    fail "a real run without gh and without the asset should fail" "$tmp/aur.err"
fi
if CURL_STATUS=6 RUN_PATH="$nogh" run_aur; then
    fail "a real run without gh should stop when GitHub cannot be reached" "$tmp/aur.err"
fi
if ! grep -F -q 'GitHub could not be reached' "$tmp/aur.err"; then
    fail "a real run without gh should say GitHub could not be reached" "$tmp/aur.err"
fi
if ! grep -F -q 'https://github.com/example/demo/releases/download/' "$tmp/aur.err"; then
    fail "a real run without gh should name the asset URL" "$tmp/aur.err"
fi
if ! CURL_STATUS=6 RUN_DRY=1 RUN_PATH="$nogh" run_aur; then
    fail "a dry run without gh should warn when GitHub cannot be reached" "$tmp/aur.err"
fi
if ! grep -F -q 'GitHub could not be reached' "$tmp/aur.out" "$tmp/aur.err"; then
    fail "a dry run without gh should say GitHub could not be reached" "$tmp/aur.err"
fi
