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
    if [[ -n "${PKGBUILD:-}" && -f "$PKGBUILD" ]]; then
        echo "--- PKGBUILD ---"
        cat "$PKGBUILD"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
for tool in gh curl gpg updpkgsums; do
    printf '#!/bin/bash\nexit 1\n' > "$stub/$tool"
    chmod +x "$stub/$tool"
done
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/makepkg"

export PATH="$stub:$PATH"
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
# shellcheck source=../lib/modes/git.sh
source "$ROOT/lib/modes/git.sh"

write_pkgbuild0() {
    local dest="$1"
    cat > "$dest" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
pkgdesc='demo'
arch=('x86_64')
url='https://github.com/example/demo'
license=('GPL-3.0-or-later')
depends=()
makedepends=('cmake')
source=(
  "https://example.com/demo-1.0.0.tar.gz"
)
b2sums=('SKIP')
EOF
}

prepare_repo() {
    local repo="$1"
    local branch="$2"
    local set_origin="$3"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q -b "$branch"
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" config commit.gpgsign false
    printf 'x\n' > "$repo/README"
    git -C "$repo" add README
    git -C "$repo" commit -q -m init
    if [[ "$set_origin" == origin ]]; then
        git -C "$repo" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/${branch}"
    fi
    write_pkgbuild0 "$repo/aur/PKGBUILD.0"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGBUILD0="$repo/aur/PKGBUILD.0"
    export PKGBUILD="$repo/aur/PKGBUILD"
    export SRCINFO="$repo/aur/.SRCINFO"
}

run_git() {
    (
        mode_git
    ) >"$tmp/git.out" 2>"$tmp/git.err"
}

check_pkg() {
    local branch="$1"
    local file="$PKGBUILD"
    grep -qx 'pkgname=demo-git' "$file" || fail "pkgname should be demo-git (branch ${branch})"
    grep -qx 'provides=(demo)' "$file" || fail "missing provides=(demo) (branch ${branch})"
    grep -qx 'conflicts=(demo)' "$file" || fail "missing conflicts=(demo) (branch ${branch})"
    grep -qE '^makedepends=.*git' "$file" || fail "git missing from makedepends (branch ${branch})"
    grep -qF "git+https://github.com/example/demo.git#branch=${branch}" "$file" || fail "source branch should be ${branch}"
    grep -qF 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g' "$file" || fail "pkgver sed does not match the standard transform"
    if grep -q 'AURGEN_' "$file"; then
        fail "PKGBUILD references an aurgen variable"
    fi
}

plain_pkgver() {
    local srcdir="$1"
    env -i PATH="$PATH" HOME="$tmp" bash --noprofile --norc -c '
        set -u
        srcdir=$1
        source "$2"
        pkgver
    ' bash "$srcdir" "$PKGBUILD"
}

prepare_repo "$tmp/with-origin" "release/1" origin
if ! run_git; then
    echo "mode_git failed for origin/HEAD branch"
    cat "$tmp/git.err"
    exit 1
fi
check_pkg "release/1"

srcdir="$tmp/src"
mkdir -p "$srcdir/demo"
git -C "$srcdir/demo" init -q -b master
git -C "$srcdir/demo" config user.email "t@example.com"
git -C "$srcdir/demo" config user.name "t"
git -C "$srcdir/demo" config commit.gpgsign false
git -C "$srcdir/demo" config tag.gpgsign false
printf 'a\n' > "$srcdir/demo/f"
git -C "$srcdir/demo" add f
git -C "$srcdir/demo" commit -q -m init

got=$(plain_pkgver "$srcdir") || fail "pkgver fallback failed under plain bash: ${got}"
count=$(git -C "$srcdir/demo" rev-list --count HEAD)
short=$(git -C "$srcdir/demo" rev-parse --short HEAD)
if [[ "$got" != "r${count}.${short}" ]]; then
    fail "pkgver fallback should be r${count}.${short}, got ${got}"
fi

git -C "$srcdir/demo" tag v1.2.3
printf 'b\n' >> "$srcdir/demo/f"
git -C "$srcdir/demo" add f
git -C "$srcdir/demo" commit -q -m more
got=$(plain_pkgver "$srcdir") || fail "pkgver describe failed under plain bash: ${got}"
expect=$(git -C "$srcdir/demo" describe --long --tags | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')
if [[ "$got" != "$expect" ]]; then
    fail "pkgver describe should be ${expect}, got ${got}"
fi

prepare_repo "$tmp/no-origin" devel no
if ! run_git; then
    echo "mode_git failed for current-branch fallback"
    cat "$tmp/git.err"
    exit 1
fi
check_pkg devel
