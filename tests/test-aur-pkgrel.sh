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
    exit 1
}

pkgrel_of() {
    awk -F= '/^[[:space:]]*pkgrel[[:space:]]*=/ {print $2; exit}' "$1" | tr -d "\"'[:space:]"
}

stub="$tmp/bin"
mkdir -p "$stub"
for tool in gh curl gpg updpkgsums; do
    printf '#!/bin/bash\nexit 1\n' > "$stub/$tool"
    chmod +x "$stub/$tool"
done
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/makepkg"

repo="$tmp/repo"
mkdir -p "$repo/aur"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'x\n' > "$repo/payload.txt"
git -C "$repo" add payload.txt
git -C "$repo" commit -q -m init

write_pkgbuild() {
    local dest="$1"
    local ver="$2"
    local rel="$3"
    cat > "$dest" <<EOF
pkgname=demo
pkgver=${ver}
pkgrel=${rel}
pkgdesc='demo'
arch=('x86_64')
url='https://example.com'
license=('GPL-3.0-or-later')
source=("https://example.com/demo-${ver}.tar.gz")
b2sums=('SKIP')
EOF
}

write_pkgbuild "$repo/aur/PKGBUILD.0" 1.0.0 1
write_pkgbuild "$repo/aur/PKGBUILD" 1.0.0 4

export PATH="$stub:$PATH"
export PROJECT_ROOT="$repo"
export AUR_DIR="$repo/aur"
export PKGBUILD0="$repo/aur/PKGBUILD.0"
export PKGBUILD="$repo/aur/PKGBUILD"
export SRCINFO="$repo/aur/.SRCINFO"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/out.log"
export color_enabled=0
export dry_run=1
export no_wait=1
export PKGNAME=demo
export GH_USER=example
export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
export LIB_INSTALL_DIR="$tmp/nolib"
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"
mkdir -p "$LIB_INSTALL_DIR"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"
filter_pkgbuild_sources() { cat; }

got=$(aur_next_pkgrel 1.0.0 4 1.0.0)
if [[ "$got" != 5 ]]; then
    fail "same pkgver should bump pkgrel 4 to 5, got ${got}"
fi
got=$(aur_next_pkgrel 1.0.0 4 2.0.0)
if [[ "$got" != 1 ]]; then
    fail "new pkgver should reset pkgrel to 1, got ${got}"
fi
got=$(aur_next_pkgrel 1.0.0 1.1 1.0.0)
if [[ "$got" != 2 ]]; then
    fail "minor pkgrel 1.1 should bump to 2, got ${got}"
fi
got=$(aur_next_pkgrel 1.0.0 'a[$(touch "$tmp/evaluated")]' 1.0.0)
if [[ "$got" != 1 || -e "$tmp/evaluated" ]]; then
    fail "non-numeric pkgrel should fall back to 1 without being evaluated, got ${got}"
fi
got=$(aur_next_pkgrel "" "" 1.0.0)
if [[ "$got" != 1 ]]; then
    fail "missing published pkgrel should start at 1, got ${got}"
fi

run_aur() {
    local errfile="$1"
    (
        set +u
        mode_aur
    ) >"$tmp/aur.out" 2>"$errfile"
}

if ! run_aur "$tmp/aur.err"; then
    echo "first aur run failed"
    cat "$tmp/aur.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 5 ]]; then
    fail "republish of 1.0.0 should keep published pkgrel 4 and bump to 5, got ${got}"
fi

if ! run_aur "$tmp/aur.err"; then
    echo "second aur run failed"
    cat "$tmp/aur.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 6 ]]; then
    fail "second republish of 1.0.0 should bump pkgrel to 6, got ${got}"
fi

write_pkgbuild "$PKGBUILD0" 2.0.0 1
if ! run_aur "$tmp/aur.err"; then
    echo "version-change aur run failed"
    cat "$tmp/aur.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 1 ]]; then
    fail "new pkgver 2.0.0 should set pkgrel to 1, got ${got}"
fi

before=$(cat "$PKGBUILD")
exec 9>"$AUR_DIR/.aurgen.lock"
flock -n 9 || fail "test could not take the PKGBUILD lock"
if run_aur "$tmp/lock.err"; then
    flock -u 9
    echo "concurrent aur run should abort"
    cat "$tmp/lock.err"
    exit 1
fi
flock -u 9
if ! grep -F -q "Another process is already updating PKGBUILD" "$tmp/lock.err"; then
    echo "concurrent aur run did not report the lock"
    cat "$tmp/lock.err"
    exit 1
fi
after=$(cat "$PKGBUILD")
if [[ "$before" != "$after" ]]; then
    fail "concurrent aur run rewrote PKGBUILD"
fi

write_pkgbuild "$PKGBUILD0" 1.0.0 1
write_pkgbuild "$PKGBUILD" 1.0.0 4
export TEST_DIR="$tmp/test"
mkdir -p "$TEST_DIR"
printf 'held\n' > "$AUR_DIR/.aurgen.lock"
lock_inode=$(stat -c %i "$AUR_DIR/.aurgen.lock")

# shellcheck source=../lib/modes/clean.sh
source "$ROOT/lib/modes/clean.sh"
cleanup

if [[ ! -e "$AUR_DIR/.aurgen.lock" ]]; then
    fail "cleanup removed .aurgen.lock"
fi
got=$(stat -c %i "$AUR_DIR/.aurgen.lock")
if [[ "$got" != "$lock_inode" ]]; then
    fail "cleanup replaced .aurgen.lock"
fi
if ! run_aur "$tmp/cleanup.err"; then
    echo "aur run after cleanup failed"
    cat "$tmp/cleanup.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 5 ]]; then
    fail "same-version aur run after cleanup should bump published pkgrel 4 to 5, got ${got}"
fi

export GOLDEN_DIR="$tmp/golden"
export GREEN=""
export RESET=""
mkdir -p "$GOLDEN_DIR"
mode_clean >/dev/null
if [[ -e "$AUR_DIR/.aurgen.lock" ]]; then
    fail "mode_clean left .aurgen.lock in place"
fi

write_pkgbuild "$PKGBUILD0" 1.0.0 1
write_pkgbuild "$PKGBUILD" 1.0.0 "3 # rebuild"
if ! run_aur "$tmp/comment.err"; then
    echo "aur run over a commented pkgrel failed"
    cat "$tmp/comment.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 4 ]]; then
    fail "published pkgrel=3 # rebuild should bump to 4, got ${got}"
fi

# A child run inside aurgen test (AURGEN_KEEP_PREV=1) writes into a test log; its
# cleanup must not delete that log. A plain cleanup still removes old logs.
mkdir -p "$TEST_DIR"
printf 'child output\n' >| "$TEST_DIR/test-aur-1.log"
AURGEN_KEEP_PREV=1 cleanup
[[ -f "$TEST_DIR/test-aur-1.log" ]] || fail "cleanup inside aurgen test deleted the running test log"
cleanup
[[ ! -e "$TEST_DIR/test-aur-1.log" ]] || fail "plain cleanup kept an old test log"
