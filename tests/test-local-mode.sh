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
    if [[ -f "$tmp/verbose" ]]; then
        echo "--- tar -tv ---"
        cat "$tmp/verbose"
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
    printf 'cafe\n' > "$repo/café.txt"
    git -C "$repo" add payload.txt café.txt
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
printf 'real\n' > "$tmp/archive/real.sh"
ln -s real.sh "$tmp/archive/link.sh"
git -C "$tmp/archive" add real.sh link.sh
git -C "$tmp/archive" commit -q -m link
run_local || fail "archive mode_local failed"
list_tar "$tmp/archive" || fail "archive tar -tzf failed"
grep -qx 'demo-1.0.0/payload.txt' "$tmp/list" || fail "archive tarball should extract into demo-1.0.0"
grep -qx 'demo-1.0.0/café.txt' "$tmp/list" || fail "archive tarball should include café.txt"
tar -tvzf "$tmp/archive/aur/demo-1.0.0.tar.gz" > "$tmp/verbose" || fail "archive tar -tvzf failed"
grep -q 'demo-1.0.0/link.sh -> real.sh' "$tmp/verbose" || fail "archive symlink should keep relative target real.sh"

prepare_repo "$tmp/signed" '    cd "$srcdir/$pkgname"'
run_local || fail "signed-tag mode_local failed"
list_tar "$tmp/signed" || fail "signed-tag tar -tzf failed"
grep -qx 'demo/payload.txt' "$tmp/list" || fail "signed-tag tarball should extract into demo"
grep -qx 'demo/café.txt' "$tmp/list" || fail "signed-tag tarball should include café.txt"

prepare_repo "$tmp/release" '    true'
run_local || fail "release mode_local failed"
list_tar "$tmp/release" || fail "release tar -tzf failed"
grep -qx 'payload.txt' "$tmp/list" || fail "release tarball should list payload.txt"
grep -qx 'café.txt' "$tmp/list" || fail "release tarball should include café.txt"
if grep -q '/' "$tmp/list"; then
    fail "release tarball should stay flat"
fi

prepare_repo "$tmp/leading-dash" '    true'
printf '#!/bin/bash\n' >| "$tmp/leading-dash/-n.sh"
git -C "$tmp/leading-dash" add -- -n.sh
run_local || fail "leading-dash mode_local failed"
tar tzf "$tmp/leading-dash/aur/demo-1.0.0.tar.gz" | grep -Fx -- '-n.sh' || fail "local tarball should include -n.sh"

prepare_repo "$tmp/deleted" '    true'
rm -f -- "$tmp/deleted/payload.txt"
printf 'working-tree edit\n' >| "$tmp/deleted/café.txt"
run_local || fail "unstaged deletion mode_local failed"
list_tar "$tmp/deleted" || fail "unstaged deletion tar -tzf failed"
if grep -qx 'payload.txt' "$tmp/list"; then
    fail "unstaged deletion payload.txt should not be in local tarball"
fi
grep -qx 'café.txt' "$tmp/list" || fail "unstaged deletion tarball should still include café.txt"
tar -xzOf "$tmp/deleted/aur/demo-1.0.0.tar.gz" café.txt >| "$tmp/extracted-cafe" || fail "failed to extract café.txt"
grep -qx 'working-tree edit' "$tmp/extracted-cafe" || fail "local tarball should include working-tree edits"

prepare_repo "$tmp/replaced" '    true'
rm -f -- "$tmp/replaced/payload.txt"
mkdir -p "$tmp/replaced/payload.txt"
printf 'secret\n' >| "$tmp/replaced/payload.txt/secret.txt"
run_local || fail "directory replacing tracked file mode_local failed"
list_tar "$tmp/replaced" || fail "directory replacing tracked file tar -tzf failed"
if grep -q 'payload.txt' "$tmp/list"; then
    fail "directory replacing tracked file should not be in local tarball"
fi
if grep -q 'secret.txt' "$tmp/list"; then
    fail "untracked file inside replaced directory should not be in local tarball"
fi
grep -qx 'café.txt' "$tmp/list" || fail "directory replacing tracked file tarball should still include café.txt"

prepare_repo "$tmp/tarfail" '    true'
mkdir -p "$tmp/tarfail-tmp"
printf '#!/bin/bash\nexit 1\n' >| "$stub/tar"
chmod +x "$stub/tar"
hash -r
if TMPDIR="$tmp/tarfail-tmp" run_local; then
    fail "tar failure should stop mode_local"
fi
if compgen -G "$tmp/tarfail-tmp/*" > /dev/null; then
    fail "tar failure should remove the temporary file list"
fi
[[ ! -e "$PKGBUILD" ]] || fail "tar failure should not write PKGBUILD"
rm -f -- "$stub/tar"
hash -r

prepare_repo "$tmp/listfail" '    true'
real_git="$(command -v git)"
cat > "$stub/git" <<EOF
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == "ls-files" ]]; then
        exit 1
    fi
done
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
