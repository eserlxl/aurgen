#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# Quoted recipe heredocs must emit makepkg's $pkgname and $pkgdir, not \$ or PKGNAME.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-recipes.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$stub" "$repo"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"
printf 'int main(void){return 0;}\n' > "$repo/main.c"

git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" add main.c
git -C "$repo" commit -q -m init

generate() {
    local marker="$1"
    rm -f "$repo/CMakeLists.txt" "$repo/Makefile" "$repo/setup.py" \
        "$repo/package.json" "$repo/Cargo.toml" "$repo/go.mod" \
        "$repo/meson.build" "$repo/README.md"
    rm -rf "$repo/aur"
    if [[ "$marker" == Makefile ]]; then
        # The make recipe installs through the project's own install target.
        printf 'install:\n\ttrue\n' > "$repo/$marker"
    elif [[ -n "$marker" ]]; then
        printf 'x\n' > "$repo/$marker"
    fi
    if ! (
        cd "$repo" || exit 1
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=testpkg
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
        echo "gen_pkgbuild0 failed for ${marker:-unknown}"
        cat "$tmp/gen.err"
        exit 1
    fi
}

check_pkgbuild() {
    local label="$1"
    local expect="${2:-}"
    local pkgbuild="$repo/aur/PKGBUILD.0"
    if [[ ! -f "$pkgbuild" ]]; then
        echo "PKGBUILD.0 missing for $label"
        exit 1
    fi
    if grep -F '\$' "$pkgbuild" >/dev/null; then
        echo "PKGBUILD.0 for $label contains a stray backslash"
        cat "$pkgbuild"
        exit 1
    fi
    if grep -F 'PKGNAME' "$pkgbuild" >/dev/null; then
        echo "PKGBUILD.0 for $label contains PKGNAME"
        cat "$pkgbuild"
        exit 1
    fi
    if [[ -n "$expect" ]] && ! grep -F -q -- "$expect" "$pkgbuild"; then
        echo "PKGBUILD.0 for $label is missing: $expect"
        cat "$pkgbuild"
        exit 1
    fi
    if ! bash -n "$pkgbuild"; then
        echo "bash -n failed for $label"
        cat "$pkgbuild"
        exit 1
    fi
}

generate CMakeLists.txt
check_pkgbuild cmake 'DESTDIR="$pkgdir" cmake --install build'
generate Makefile
check_pkgbuild make 'make install DESTDIR="$pkgdir" PREFIX=/usr'
generate setup.py
check_pkgbuild python 'python setup.py install --root="$pkgdir" --optimize=1 --skip-build'
generate package.json
check_pkgbuild node 'npm install -g --prefix "$pkgdir/usr" .'
generate Cargo.toml
check_pkgbuild rust 'install -Dm755 target/release/$pkgname "$pkgdir/usr/bin/$pkgname"'
generate go.mod
check_pkgbuild go 'go build -o "$pkgname" .'
check_pkgbuild go 'install -Dm755 $pkgname "$pkgdir/usr/bin/$pkgname"'
generate meson.build
check_pkgbuild meson 'DESTDIR="$pkgdir" meson install -C build'
generate README.md
check_pkgbuild none
