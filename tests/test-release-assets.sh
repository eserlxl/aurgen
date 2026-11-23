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
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unset RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    AURGEN_NON_INTERACTIVE AURGEN_OVERWRITE_ASSETS DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

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
    "release view"|"release upload"|"release create")
        args=("$@")
        repo=""
        for (( i=3; i<${#args[@]}; i++ )); do
            if [[ "${args[i]}" == --repo ]]; then
                repo="${args[i+1]:-}"
            fi
        done
        if [[ "$repo" != example/demo ]]; then
            echo "Expected --repo example/demo" >&2
            exit 2
        fi
        ;;
esac
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
        export no_wait="${RUN_NO_WAIT:-1}"
        export PKGNAME=demo
        export GH_USER=example
        if [[ -n "${RUN_GPG_KEY_ID+x}" ]]; then
            if [[ -n "$RUN_GPG_KEY_ID" ]]; then
                export GPG_KEY_ID="$RUN_GPG_KEY_ID"
            else
                unset GPG_KEY_ID PKG_GPG_KEY
            fi
        else
            export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        fi
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
grep -F -q 'No upload was performed.' "$tmp/aur.err" || fail "a declined overwrite should say no upload was performed" "$tmp/aur.err"

# With no_wait=0, declining overwrite on a complete release must skip the CDN wait and after-upload note.
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\nexit "${CURL_STATUS:-22}"\n' "$tmp/curl.log" >| "$stub/curl"
chmod +x "$stub/curl"
: >| "$tmp/curl.log"
if ! RUN_NO_WAIT=0 CURL_STATUS=22 run_aur; then
    fail "declined-overwrite aur run with no_wait=0 failed" "$tmp/aur.err"
fi
if grep -F -q 'Waiting for GitHub to propagate' "$tmp/aur.err" "$tmp/aur.out"; then
    fail "declining overwrite should not wait for GitHub CDN propagation" "$tmp/aur.err"
fi
if grep -F -q 'Note: After upload' "$tmp/aur.err" "$tmp/aur.out"; then
    fail "declining overwrite should not print the post-upload note" "$tmp/aur.err"
fi
if [[ -s "$tmp/curl.log" ]]; then
    fail "declining overwrite when gh listed both assets should not poll curl" "$tmp/curl.log"
fi

# Signature-only upload with no_wait=0 probes the uploaded signature URL on the CDN.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" "demo-1.0.0.tar.gz"
: >| "$tmp/curl.log"
if ! RUN_NO_WAIT=0 CURL_STATUS=0 run_aur; then
    fail "signature-only upload with no_wait=0 failed" "$tmp/aur.err"
fi
grep -F -q 'demo-1.0.0.tar.gz.sig' "$tmp/curl.log" || fail "signature-only upload should probe the signature URL during CDN wait" "$tmp/curl.log"

# Failed GPG key selection or failed detached signing must abort mode_aur before any GitHub upload.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
if RUN_GPG_KEY_ID="" run_aur; then
    fail "missing GPG signing key should abort mode_aur" "$tmp/aur.err"
fi
if [[ -s "$GH_LOG.actions" ]]; then
    fail "missing GPG signing key should stop before gh create/upload" "$GH_LOG.actions"
fi
if RUN_GPG_KEY_ID="0123456789ABCDEF0123456789ABCDEF01234567" run_aur; then
    fail "failed gpg --detach-sign should abort mode_aur" "$tmp/aur.err"
fi
grep -F -q 'Failed to create GPG signature' "$tmp/aur.err" || fail "failed gpg --detach-sign should report signing failure" "$tmp/aur.err"
if [[ -s "$GH_LOG.actions" ]]; then
    fail "failed gpg --detach-sign should stop before gh create/upload" "$GH_LOG.actions"
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
grep -F -q 'Uploaded to existing GitHub release v1.0.0.' "$tmp/aur.err" || fail "a signature-only upload should be reported in the summary" "$tmp/aur.err"
if grep -F -q 'No upload was performed.' "$tmp/aur.err"; then
    fail "a signature-only upload should not claim no upload was performed" "$tmp/aur.err"
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
if ! grep -F -q 'Assets have been automatically uploaded to GitHub release' "$tmp/aur.out"; then
    fail "a real upload should say the assets were uploaded" "$tmp/aur.out"
fi
grep -E -q '^release create .*--generate-notes' "$GH_LOG" || fail "a new release without AURGEN_RELEASE_NOTES_FILE should use --generate-notes" "$GH_LOG"

# AURGEN_RELEASE_NOTES_FILE replaces --generate-notes; a missing file stops before gh is used.
printf 'Release notes from a changelog tool\n' > "$tmp/notes.md"
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
if ! CURL_STATUS=22 GH_AUTH_FAIL=0 AURGEN_RELEASE_NOTES_FILE="$tmp/notes.md" run_aur; then
    fail "a release with AURGEN_RELEASE_NOTES_FILE failed" "$tmp/aur.err"
fi
grep -F -q -- "--notes-file $tmp/notes.md" "$GH_LOG" || fail "gh release create should get --notes-file" "$GH_LOG"
if grep -F -q -- '--generate-notes' "$GH_LOG"; then
    fail "--notes-file should replace --generate-notes" "$GH_LOG"
fi
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
if CURL_STATUS=22 GH_AUTH_FAIL=0 AURGEN_RELEASE_NOTES_FILE="$tmp/no-such-notes.md" run_aur; then
    fail "a missing AURGEN_RELEASE_NOTES_FILE should stop aur mode" "$tmp/aur.err"
fi
grep -F -q 'AURGEN_RELEASE_NOTES_FILE is not a readable file' "$tmp/aur.err" || fail "a missing notes file should be named" "$tmp/aur.err"
if [[ -s "$GH_LOG" ]]; then
    fail "a missing notes file should stop before gh is used" "$GH_LOG"
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

# A dry run never uploads, so its summary must not say it did.
for dry_curl in 6 22; do
    rm -rf "$GH_STATE"
    mkdir -p "$GH_STATE"
    if ! CURL_STATUS="$dry_curl" RUN_DRY=1 run_aur; then
        fail "dry run with HEAD status $dry_curl failed" "$tmp/aur.err"
    fi
    if grep -F -q 'automatically uploaded' "$tmp/aur.out" "$tmp/aur.err"; then
        fail "a dry run (HEAD status $dry_curl) claimed an automatic upload" "$tmp/aur.out"
    fi
    if ! grep -F -q '(dry run) No upload was performed.' "$tmp/aur.out"; then
        fail "a dry run (HEAD status $dry_curl) should say no upload was performed" "$tmp/aur.out"
    fi
done

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

# Exhausting post-upload CDN availability retries in non-interactive execution aborts cleanly instead of ignoring missing assets.
mkdir -p "$tmp/fastsleep"
printf '#!/bin/bash\nexit 0\n' >| "$tmp/fastsleep/sleep"
chmod +x "$tmp/fastsleep/sleep"
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" "other.zip"
if (
    export PATH="$tmp/fastsleep:$PATH"
    export AURGEN_NON_INTERACTIVE=1
    RUN_NO_WAIT=0 CURL_STATUS=22 run_aur
); then
    fail "exhausting CDN retries in non-interactive mode unexpectedly succeeded" "$tmp/aur.err"
fi
grep -F -q -- 'still unavailable in non-interactive mode' "$tmp/aur.err" || fail "CDN exhaustion error missing non-interactive message" "$tmp/aur.err"
grep -F -q -- '--no-wait' "$tmp/aur.err" || fail "CDN exhaustion error did not mention --no-wait" "$tmp/aur.err"

# Overwrite mode: AURGEN_OVERWRITE_ASSETS=1 and --overwrite-assets replace existing assets unattended (including under --non-interactive) and report accurately on --dry-run.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" $'demo-1.0.0.tar.gz\ndemo-1.0.0.tar.gz.sig'
if ! RUN_DRY=1 run_aur; then
    fail "default dry-run with existing release assets failed" "$tmp/aur.err"
fi
grep -F -q 'Would prompt to overwrite and upload demo-1.0.0.tar.gz and demo-1.0.0.tar.gz.sig to GitHub release v1.0.0.' "$tmp/aur.out" "$tmp/aur.err" \
    || fail "default dry-run should report it would prompt to overwrite" "$tmp/aur.out"
[[ ! -s "$GH_LOG.actions" ]] || fail "default dry-run should not upload assets" "$GH_LOG.actions"

if ! AURGEN_OVERWRITE_ASSETS=1 RUN_DRY=1 run_aur; then
    fail "overwrite dry-run with existing release assets failed" "$tmp/aur.err"
fi
grep -F -q 'Would overwrite and upload demo-1.0.0.tar.gz and demo-1.0.0.tar.gz.sig to GitHub release v1.0.0 without prompting.' "$tmp/aur.out" "$tmp/aur.err" \
    || fail "overwrite dry-run should report it would overwrite and upload without prompting" "$tmp/aur.out"
if grep -F -q 'Would prompt to overwrite' "$tmp/aur.out" "$tmp/aur.err"; then
    fail "overwrite dry-run still reported that it would prompt" "$tmp/aur.out"
fi
[[ ! -s "$GH_LOG.actions" ]] || fail "overwrite dry-run should not upload assets" "$GH_LOG.actions"

if ! AURGEN_OVERWRITE_ASSETS=0 AURGEN_NON_INTERACTIVE=1 run_aur; then
    fail "AURGEN_OVERWRITE_ASSETS=0 run with existing release assets failed" "$tmp/aur.err"
fi
assert_same_tag "v1.0.0" 0 "AURGEN_OVERWRITE_ASSETS=0 keeps existing assets"
grep -F -q 'Skipped uploading; using existing asset.' "$tmp/aur.out" \
    || fail "AURGEN_OVERWRITE_ASSETS=0 should keep existing asset" "$tmp/aur.out"

if ! AURGEN_OVERWRITE_ASSETS=1 AURGEN_NON_INTERACTIVE=1 run_aur; then
    fail "AURGEN_OVERWRITE_ASSETS=1 unattended overwrite run failed" "$tmp/aur.err"
fi
assert_same_tag "v1.0.0" 1 "AURGEN_OVERWRITE_ASSETS=1 unattended overwrite uploads replacement tarball and signature"
grep -F -q 'Overwrite requested (--overwrite-assets / AURGEN_OVERWRITE_ASSETS=1); replacing existing asset without prompting.' "$tmp/aur.out" \
    || fail "AURGEN_OVERWRITE_ASSETS=1 should log explicit overwrite notice" "$tmp/aur.out"
grep -F -q 'Asset(s) overwritten.' "$tmp/aur.out" \
    || fail "AURGEN_OVERWRITE_ASSETS=1 should log asset(s) overwritten" "$tmp/aur.out"
grep -F -q 'Uploaded to existing GitHub release v1.0.0.' "$tmp/aur.err" \
    || fail "AURGEN_OVERWRITE_ASSETS=1 should report upload to existing GitHub release" "$tmp/aur.err"
if grep -F -q 'Skipped uploading; using existing asset.' "$tmp/aur.out" || grep -F -q 'No upload was performed.' "$tmp/aur.err"; then
    fail "AURGEN_OVERWRITE_ASSETS=1 should not report skipped upload" "$tmp/aur.out"
fi

# End-to-end CLI invocation with --overwrite-assets --non-interactive --no-wait aur
git -C "$repo" remote remove origin >/dev/null 2>&1 || true
git -C "$repo" remote add origin "https://github.com/example/demo.git"
: > "$GH_LOG"
: > "$GH_LOG.actions"
if ! (
    cd "$repo" || exit 1
    export PATH="$stub:$PATH"
    export HOME="$tmp/cli-home" XDG_STATE_HOME="$tmp/cli-state" XDG_DATA_HOME="$tmp/cli-data" XDG_CONFIG_HOME="$tmp/cli-config"
    mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN AURGEN_OVERWRITE_ASSETS=0
    "$ROOT/bin/aurgen" -n --overwrite-assets --non-interactive --no-wait aur
) >"$tmp/cli-ow.out" 2>"$tmp/cli-ow.err" < /dev/null; then
    fail "CLI --overwrite-assets --non-interactive --no-wait aur failed" "$tmp/cli-ow.err"
fi
assert_same_tag "v1.0.0" 1 "CLI --overwrite-assets overrides AURGEN_OVERWRITE_ASSETS=0 and uploads replacement assets"
grep -F -q 'Overwrite requested (--overwrite-assets / AURGEN_OVERWRITE_ASSETS=1); replacing existing asset without prompting.' "$tmp/cli-ow.out" \
    || fail "CLI --overwrite-assets did not log overwrite notice" "$tmp/cli-ow.out"
grep -F -q 'Uploaded to existing GitHub release v1.0.0.' "$tmp/cli-ow.err" \
    || fail "CLI --overwrite-assets did not report upload to existing release" "$tmp/cli-ow.err"

# Release creation with a local tag must target the resolved local tag's commit sha.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
tag_commit="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag -a v1.0.0 -m "release v1.0.0"
printf 'y\n' >> "$repo/payload.txt"
git -C "$repo" commit -q -am "advance branch tip"
branch_tip="$(git -C "$repo" rev-parse HEAD)"
if ! CURL_STATUS=22 GH_AUTH_FAIL=0 run_aur; then
    fail "release creation with local tag failed" "$tmp/aur.err"
fi
if ! grep -F 'release create' "$GH_LOG" | grep -F -q -- "--target $tag_commit"; then
    fail "release create should target the local tag's commit $tag_commit" "$GH_LOG"
fi
if grep -F 'release create' "$GH_LOG" | grep -F -q -- "--target $branch_tip"; then
    fail "release create should not target the default branch tip $branch_tip" "$GH_LOG"
fi
