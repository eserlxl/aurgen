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

# A branch name holding $() must not reach the PKGBUILD git makepkg sources.
prepare_repo "$tmp/hostile" 'x$(touch${IFS}pwned)' origin
if run_git; then
    fail "mode_git accepted a branch name with \$()"
fi
if grep -qF 'touch' "$PKGBUILD" 2>/dev/null; then
    fail "hostile branch name was written into PKGBUILD"
fi

# A single-line source array must not swallow build/check/package.
write_single_line_pkgbuild0() {
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
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
b2sums=('SKIP')

build() {
    cd "$srcdir/demo-$pkgver"
    cmake -B build -S .
}

check() {
    ctest --test-dir build
}

package() {
    cd "$srcdir/demo-$pkgver"
    DESTDIR="$pkgdir" cmake --install build
}
EOF
}

assert_repo_cd() {
    local fn="$1"
    local line
    grep -q "^${fn}()" "$PKGBUILD" || fail "${fn}() was dropped"
    line="$(awk -v fn="$fn" '
        $0 ~ "^" fn "\\(\\)" { capture = 1; next }
        capture && /^\{/ { next }
        capture && /^}/ { exit }
        capture && /[^[:space:]]/ { print; exit }
    ' "$PKGBUILD")"
    [[ "$line" == '    cd "$srcdir/demo"' ]] || fail "${fn}() should cd into the repo clone, got: ${line:-<none>}"
}

prepare_repo "$tmp/single-line" master origin
write_single_line_pkgbuild0 "$PKGBUILD0"
if ! run_git; then
    echo "mode_git failed for a single-line source"
    cat "$tmp/git.err"
    exit 1
fi
check_pkg master
assert_repo_cd build
assert_repo_cd check
assert_repo_cd package
grep -qF 'cmake -B build -S .' "$PKGBUILD" || fail "build() body was dropped"
grep -qF 'ctest --test-dir build' "$PKGBUILD" || fail "check() body was dropped"
grep -qF 'cmake --install build' "$PKGBUILD" || fail "package() body was dropped"
if grep -qF 'cd "$srcdir/demo-$pkgver"' "$PKGBUILD"; then
    fail "archive cd survived in the git PKGBUILD"
fi

# A configured conflicts array must keep its entries and also name the release package.
write_conflicts_pkgbuild0() {
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
conflicts=('other')
source=(
  "https://example.com/demo-1.0.0.tar.gz"
)
b2sums=('SKIP')
EOF
}

prepare_repo "$tmp/merge-conflicts" master origin
write_conflicts_pkgbuild0 "$PKGBUILD0"
if ! run_git; then
    echo "mode_git failed when conflicts is already set"
    cat "$tmp/git.err"
    exit 1
fi
[[ "$(grep -c '^provides=' "$PKGBUILD")" -eq 1 ]] || fail "provides assigned more than once"
[[ "$(grep -c '^conflicts=' "$PKGBUILD")" -eq 1 ]] || fail "conflicts assigned more than once"
sourced=$(bash --noprofile --norc -c '
    source "$1"
    printf "conflicts=%s\n" "${conflicts[*]}"
    printf "provides=%s\n" "${provides[*]}"
' bash "$PKGBUILD") || fail "sourcing the git PKGBUILD failed: ${sourced}"
[[ "$sourced" == *'conflicts=other demo'* ]] || fail "conflicts should contain other and demo, got: ${sourced}"
[[ "$sourced" == *'provides=demo'* ]] || fail "provides should contain demo, got: ${sourced}"

# libgit2 contains the letters git but is not the VCS package makepkg needs.
write_libgit2_pkgbuild0() {
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
makedepends=(libgit2)
source=(
  "https://example.com/demo-1.0.0.tar.gz"
)
b2sums=('SKIP')
EOF
}

prepare_repo "$tmp/libgit2" master origin
write_libgit2_pkgbuild0 "$PKGBUILD0"
if ! run_git; then
    echo "mode_git failed when makedepends names libgit2"
    cat "$tmp/git.err"
    exit 1
fi
grep -qx 'makedepends=(libgit2 git)' "$AUR_DIR/PKGBUILD.git" || fail "makedepends should be (libgit2 git)"

# An existing git token must stay a single entry.
write_git_pkgbuild0() {
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
makedepends=(git)
source=(
  "https://example.com/demo-1.0.0.tar.gz"
)
b2sums=('SKIP')
EOF
}

prepare_repo "$tmp/already-git" master origin
write_git_pkgbuild0 "$PKGBUILD0"
if ! run_git; then
    echo "mode_git failed when makedepends already lists git"
    cat "$tmp/git.err"
    exit 1
fi
grep -qx 'makedepends=(git)' "$AUR_DIR/PKGBUILD.git" || fail "git should not be duplicated in makedepends"

# A source array closed by an indented ")" must not swallow the functions after it.
write_indented_source_pkgbuild0() {
    local dest="$1"
    cat > "$dest" <<'PKG'
pkgname=demo
pkgver=1.0.0
pkgrel=1
pkgdesc='demo'
arch=('x86_64')
url='https://github.com/example/demo'
license=('GPL-3.0-or-later')
depends=()
makedepends=()
source=(
  "https://example.com/demo-1.0.0.tar.gz"
  )
b2sums=('SKIP')

package() {
    install -Dm644 README "$pkgdir/usr/share/doc/demo/README"
}
PKG
}

prepare_repo "$tmp/indented-source" master origin
write_indented_source_pkgbuild0 "$PKGBUILD0"
if ! run_git; then
    echo "mode_git failed for an indented source closing parenthesis"
    cat "$tmp/git.err"
    exit 1
fi
grep -q '^package() {' "$AUR_DIR/PKGBUILD.git" || fail "package() was dropped after an indented source closing parenthesis"
