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
    if [[ -f "$tmp/local.err" ]]; then
        echo "--- stderr ---"
        cat "$tmp/local.err"
    fi
    if [[ -f "$tmp/list" ]]; then
        echo "--- tar ---"
        cat "$tmp/list"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 1\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/updpkgsums" "$stub/makepkg"

export PATH="$stub:$PATH"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/out.log"
export color_enabled=0
export dry_run=1
export no_wait=1
export PKGNAME=demo
export DEBUG_LEVEL=0
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"

# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
export color_enabled=0
init_colors
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/local.sh
source "$ROOT/lib/modes/local.sh"

filter_pkgbuild_sources() { cat; }

write_pkgbuild0() {
    local dest="$1"
    local body="$2"
    cat > "$dest" <<EOF
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

build() {
${body}
}
EOF
}

prepare_repo() {
    local repo="$1"
    local body="$2"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" config commit.gpgsign false
    printf 'x\n' > "$repo/payload.txt"
    git -C "$repo" add payload.txt
    git -C "$repo" commit -q -m init
    write_pkgbuild0 "$repo/aur/PKGBUILD.0" "$body"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGBUILD0="$repo/aur/PKGBUILD.0"
    export PKGBUILD="$repo/aur/PKGBUILD"
    export SRCINFO="$repo/aur/.SRCINFO"
}

run_local() {
    (
        mode_local
    ) >"$tmp/local.out" 2>"$tmp/local.err"
}

list_tar() {
    local repo="$1"
    tar -tzf "$repo/aur/demo-1.0.0.tar.gz" > "$tmp/list"
}

prepare_repo "$tmp/archive" '    cd "$srcdir/demo-$pkgver"'
run_local || fail "archive mode_local failed"
list_tar "$tmp/archive" || fail "archive tar -tzf failed"
grep -qx 'demo-1.0.0/payload.txt' "$tmp/list" || fail "archive tarball should extract into demo-1.0.0"

prepare_repo "$tmp/signed" '    cd "$srcdir/$pkgname"'
run_local || fail "signed-tag mode_local failed"
list_tar "$tmp/signed" || fail "signed-tag tar -tzf failed"
grep -qx 'demo/payload.txt' "$tmp/list" || fail "signed-tag tarball should extract into demo"

prepare_repo "$tmp/release" '    true'
run_local || fail "release mode_local failed"
list_tar "$tmp/release" || fail "release tar -tzf failed"
grep -qx 'payload.txt' "$tmp/list" || fail "release tarball should list payload.txt"
if grep -q '/' "$tmp/list"; then
    fail "release tarball should stay flat"
fi

prepare_repo "$tmp/listfail" '    true'
real_git="$(command -v git)"
cat > "$stub/git" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "-C" && "\${3:-}" == "ls-files" ]]; then
    exit 1
fi
if [[ "\${1:-}" == "ls-files" ]]; then
    exit 1
fi
exec ${real_git@Q} "\$@"
EOF
chmod +x "$stub/git"
hash -r
if run_local; then
    fail "ls-files failure should stop mode_local"
fi
if grep -q 'Created' "$tmp/local.out"; then
    fail "ls-files failure should not log Created"
fi
