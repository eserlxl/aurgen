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
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unset RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    AURGEN_NON_INTERACTIVE AURGEN_OVERWRITE_ASSETS DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
export XDG_DATA_HOME="$tmp/data"
export XDG_CONFIG_HOME="$tmp/config"
export GNUPGHOME="$tmp/gnupg"
export TMPDIR="$tmp/tmpdir"
mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$TMPDIR"
mkdir -m 700 "$GNUPGHOME"

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

export UPD_LOG="$tmp/updpkgsums.log"
export GPG_LOG="$tmp/gpg.log"
export CURL_LOG="$tmp/curl.log"
export GH_LOG="$tmp/gh.log"
export GH_STATE="$tmp/gh-state"
export PUBLISHED_TARBALL="$tmp/published-tarball.tar.gz"
export PUBLISHED_SIG="$tmp/published-tarball.tar.gz.sig"
mkdir -p "$GH_STATE"
printf 'fake-sig\n' >| "$PUBLISHED_SIG"

cat > "$stub/makepkg" << 'EOF'
#!/bin/bash
exit 0
EOF

cat > "$stub/updpkgsums" << 'EOF'
#!/bin/bash
printf 'updpkgsums %s\n' "$*" >> "$UPD_LOG"
if [[ -f PKGBUILD ]]; then
    sed -i "s/^b2sums=.*/b2sums=('pinned' 'SKIP')/" PKGBUILD
fi
exit 0
EOF

cat > "$stub/gpg" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GPG_LOG"
exit "${GPG_STATUS:-0}"
EOF

cat > "$stub/curl" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
out=""
url=""
head_only=0
while (( $# > 0 )); do
    case "$1" in
        -o|--output)
            out="${2:-}"
            shift 2
            ;;
        -I|--head)
            head_only=1
            shift
            ;;
        -*)
            if [[ "$1" == "--max-time" ]]; then
                shift 2
            else
                shift
            fi
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done
if (( head_only )); then
    exit "${CURL_HEAD_STATUS:-0}"
fi
case "${CURL_FAIL_ON:-}" in
    all)
        exit "${CURL_STATUS:-22}"
        ;;
    tarball)
        if [[ "$url" != *.sig && "$url" != *.asc ]]; then
            exit "${CURL_STATUS:-22}"
        fi
        ;;
    sig)
        if [[ "$url" == *.sig || "$url" == *.asc ]]; then
            exit "${CURL_STATUS:-22}"
        fi
        ;;
esac
if [[ -n "$out" ]]; then
    if [[ "$url" == *.sig || "$url" == *.asc ]]; then
        cp -f "$PUBLISHED_SIG" "$out" || exit 1
    else
        cp -f "$PUBLISHED_TARBALL" "$out" || exit 1
    fi
fi
# A download that was served succeeded; CURL_STATUS only applies to the URLs failed above.
exit 0
EOF

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
        exit 0
        ;;
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

chmod +x "$stub/makepkg" "$stub/updpkgsums" "$stub/gpg" "$stub/curl" "$stub/gh"

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

mark_release() {
    local tag="$1"
    local assets="$2"
    touch "$GH_STATE/$tag.exists"
    printf '%s\n' "$assets" > "$GH_STATE/$tag.assets"
}

reset_pkgbuild() {
    cp -f "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD"
}

assert_tmpdir_clean() {
    local label="$1"
    local leftover
    leftover="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 2>/dev/null || true)"
    if [[ -n "$leftover" ]]; then
        fail "$label: mktemp dir was not cleaned up: $leftover"
    fi
}

run_aur() {
    : > "$GH_LOG"
    : > "$GH_LOG.actions"
    : > "$UPD_LOG"
    : > "$GPG_LOG"
    : > "$CURL_LOG"
    : > "$tmp/err.log"
    : > "$tmp/out.log"
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
        export ascii_armor="${RUN_ASCII_ARMOR:-0}"
        export PKGNAME=demo
        export GH_USER=example
        export GPG_KEY_ID="${RUN_GPG_KEY_ID:-TEST_KEY_FOR_DRY_RUN}"
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

# Build the reference local tarball once by running an initial upload when no release exists.
reset_pkgbuild
# No release yet: the HEAD probe must say the asset is missing, so this run uploads.
if ! CURL_HEAD_STATUS=22 run_aur; then
    fail "initial aur upload run failed" "$tmp/aur.err"
fi
[[ -s "$repo/aur/demo-1.0.0.tar.gz" ]] || fail "initial aur run did not create demo-1.0.0.tar.gz"
cp -f "$repo/aur/demo-1.0.0.tar.gz" "$tmp/exact-local.tar.gz"

# 1. Published tarball differs from local $out/$TARBALL: exit non-zero before updpkgsums,
# print "differs from the local ... rerun with --overwrite-assets", and leave PKGBUILD unwritten.
rm -rf "$GH_STATE"
mkdir -p "$GH_STATE"
mark_release "v1.0.0" $'demo-1.0.0.tar.gz\ndemo-1.0.0.tar.gz.sig'
printf 'different-published-tarball-bytes\n' >| "$PUBLISHED_TARBALL"
reset_pkgbuild
if GPG_STATUS=0 run_aur; then
    fail "aur mode should fail when published tarball differs from local tarball" "$tmp/aur.out"
fi
if [[ -s "$UPD_LOG" ]]; then
    fail "updpkgsums should not run when published tarball differs" "$UPD_LOG"
fi
grep -E -q 'differs from the local .*rerun with --overwrite-assets' "$tmp/aur.err" \
    || fail "tarball mismatch should print 'differs from the local ... rerun with --overwrite-assets'" "$tmp/aur.err"
grep -F -q 'demo-1.0.0.tar.gz' "$tmp/aur.err" \
    || fail "tarball mismatch should name demo-1.0.0.tar.gz" "$tmp/aur.err"
if grep -F -q 'releases/download/' "$repo/aur/PKGBUILD" || grep -F -q "b2sums=('pinned'" "$repo/aur/PKGBUILD"; then
    fail "tarball mismatch should leave PKGBUILD release source and checksums unwritten" "$repo/aur/PKGBUILD"
fi
grep -F -q -- '--max-time' "$CURL_LOG" || fail "curl should be called with --max-time" "$CURL_LOG"
assert_tmpdir_clean "tarball mismatch"

# 2. Published tarball has identical bytes and gpg stub exits 0: aur mode continues and updates PKGBUILD.
cp -f "$tmp/exact-local.tar.gz" "$PUBLISHED_TARBALL"
reset_pkgbuild
if ! GPG_STATUS=0 run_aur; then
    fail "aur mode should succeed when published tarball matches and gpg --verify exits 0" "$tmp/aur.err"
fi
grep -F -q -- '--verify' "$GPG_LOG" || fail "aur mode should run gpg --verify on the published signature" "$GPG_LOG"
[[ -s "$UPD_LOG" ]] || fail "updpkgsums should run after published assets verify" "$tmp/aur.out"
grep -F -q 'https://github.com/example/demo/releases/download/v1.0.0/demo-1.0.0.tar.gz' "$repo/aur/PKGBUILD" \
    || fail "PKGBUILD should contain the verified release tarball URL" "$repo/aur/PKGBUILD"
grep -F -q "b2sums=('pinned' 'SKIP')" "$repo/aur/PKGBUILD" \
    || fail "PKGBUILD should contain the pinned checksums after verification" "$repo/aur/PKGBUILD"
assert_tmpdir_clean "verified asset reuse"

# 3. Published tarball matches, but gpg stub exits 1 (old/mismatched signature): stop before updpkgsums and name the signature file.
cp -f "$tmp/exact-local.tar.gz" "$PUBLISHED_TARBALL"
reset_pkgbuild
if GPG_STATUS=1 run_aur; then
    fail "aur mode should fail when gpg --verify rejects the published signature" "$tmp/aur.out"
fi
if [[ -s "$UPD_LOG" ]]; then
    fail "updpkgsums should not run when published signature verification fails" "$UPD_LOG"
fi
grep -F -q 'demo-1.0.0.tar.gz.sig' "$tmp/aur.err" \
    || fail "signature mismatch should name demo-1.0.0.tar.gz.sig" "$tmp/aur.err"
grep -F -q -- '--overwrite-assets' "$tmp/aur.err" \
    || fail "signature mismatch should mention --overwrite-assets" "$tmp/aur.err"
if grep -F -q 'releases/download/' "$repo/aur/PKGBUILD" || grep -F -q "b2sums=('pinned'" "$repo/aur/PKGBUILD"; then
    fail "signature mismatch should leave PKGBUILD release source and checksums unwritten" "$repo/aur/PKGBUILD"
fi
assert_tmpdir_clean "signature verification failure"

# 4. Download failure on tarball or signature exits the same way as "GitHub could not be reached" and cleans mktemp dir.
reset_pkgbuild
if CURL_FAIL_ON=tarball CURL_STATUS=22 GPG_STATUS=0 run_aur; then
    fail "aur mode should fail when downloading published tarball fails" "$tmp/aur.out"
fi
[[ ! -s "$UPD_LOG" ]] || fail "updpkgsums should not run when tarball download fails" "$UPD_LOG"
grep -F -q 'GitHub could not be reached for https://github.com/example/demo/releases/download/v1.0.0/demo-1.0.0.tar.gz.' "$tmp/aur.err" \
    || fail "tarball download failure should report GitHub could not be reached" "$tmp/aur.err"
assert_tmpdir_clean "tarball download failure"

reset_pkgbuild
if CURL_FAIL_ON=sig CURL_STATUS=22 GPG_STATUS=0 run_aur; then
    fail "aur mode should fail when downloading published signature fails" "$tmp/aur.out"
fi
[[ ! -s "$UPD_LOG" ]] || fail "updpkgsums should not run when signature download fails" "$UPD_LOG"
grep -F -q 'GitHub could not be reached for https://github.com/example/demo/releases/download/v1.0.0/demo-1.0.0.tar.gz.sig.' "$tmp/aur.err" \
    || fail "signature download failure should report GitHub could not be reached" "$tmp/aur.err"
assert_tmpdir_clean "signature download failure"

# 5. Dry run and --overwrite-assets skip aur_verify_published_assets.
printf 'stale-tarball-bytes\n' >| "$PUBLISHED_TARBALL"
reset_pkgbuild
if ! RUN_DRY=1 GPG_STATUS=1 run_aur; then
    fail "dry-run should skip published asset download/verification" "$tmp/aur.err"
fi
[[ ! -s "$CURL_LOG" ]] || fail "dry-run should not download published assets with curl" "$CURL_LOG"

reset_pkgbuild
if ! AURGEN_OVERWRITE_ASSETS=1 GPG_STATUS=1 run_aur; then
    fail "AURGEN_OVERWRITE_ASSETS=1 should upload replacement assets without failing on old published bytes" "$tmp/aur.err"
fi
[[ ! -s "$CURL_LOG" ]] || fail "overwriting assets with no_wait=1 should not download old published assets" "$CURL_LOG"
