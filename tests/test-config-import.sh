#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config-import.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_MODE=test
export DEBUG_LEVEL=0
export color_enabled=0
export LIB_INSTALL_DIR="$ROOT/lib"
# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
init_colors
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/modes/config.sh
source "$ROOT/lib/modes/config.sh"

# shellcheck disable=SC2329
emit_list() {
    local key="$1"
    shift
    local item
    printf '%s\n' "$key"
    for item in "$@"; do
        printf '%s\n' "$item"
    done
}

pkg_snapshot() {
    # shellcheck disable=SC2153 # PKG_NAME comes from load_aurgen_config
    printf 'NAME\n%s\n' "$PKG_NAME"
    printf 'DESCRIPTION\n%s\n' "$PKG_DESCRIPTION"
    # install is not compared: the fixtures replaced their hand .install with
    # install_messages, while import keeps the hand PKGBUILD's install= file name.
    printf 'CHECK\n%s\n' "$PKG_CHECK"
    printf 'SOURCE\n%s\n' "$PKG_SOURCE"
    emit_list ARCH "${PKG_ARCH[@]}"
    emit_list DEPENDS "${PKG_DEPENDS[@]}"
    emit_list OPTDEPENDS "${PKG_OPTDEPENDS[@]}"
    emit_list MAKEDEPENDS "${PKG_MAKEDEPENDS[@]}"
    emit_list CHECKDEPENDS "${PKG_CHECKDEPENDS[@]}"
    emit_list CONFLICTS "${PKG_CONFLICTS[@]}"
    emit_list PROVIDES "${PKG_PROVIDES[@]}"
    emit_list BACKUP "${PKG_BACKUP[@]}"
    emit_list INSTALL_VARS "${PKG_INSTALL_VARS[@]}"
    emit_list LICENSE "${PKG_LICENSE[@]}"
    emit_list POST_PACKAGE "${PKG_POST_PACKAGE[@]}"
}

prepare_repo() {
    local name="$1"
    local repo="$tmp/repo-$name"
    mkdir -p "$repo" || return 1
    cp -a "$ROOT/tests/fixtures/$name/." "$repo/" || return 1
    rm -f "$repo/aur/aurgen.install.yaml"
    git -C "$repo" init -q || return 1
    git -C "$repo" config user.email "t@example.com" || return 1
    git -C "$repo" config user.name "t" || return 1
    git -C "$repo" config commit.gpgsign false || return 1
    git -C "$repo" add -A || return 1
    git -C "$repo" commit -q -m init || return 1
    printf '%s\n' "$repo"
}

# A config that already has package: must come back byte for byte.
refuse_dir="$tmp/refuse/aur"
mkdir -p "$refuse_dir" || exit 1
cp "$ROOT/tests/fixtures/cleaner/aur/aurgen.install.yaml" "$refuse_dir/aurgen.install.yaml" || exit 1
cp "$ROOT/tests/fixtures/cleaner/hand/PKGBUILD" "$refuse_dir/PKGBUILD" || exit 1
before="$(cksum "$refuse_dir/aurgen.install.yaml")" || exit 1
if (
    export AUR_DIR="$refuse_dir"
    export PROJECT_ROOT="$tmp/refuse"
    set -o noclobber
    mode_config import
) >"$tmp/refuse.out" 2>"$tmp/refuse.err"; then
    echo "import overwrote an existing package: section"
    exit 1
fi
after="$(cksum "$refuse_dir/aurgen.install.yaml")" || exit 1
if [[ "$before" != "$after" ]]; then
    echo "existing package: section was modified"
    exit 1
fi

# want_check: the check command the import must write when the hand PKGBUILD
# ran a suite other than the Makefile default (make check).
import_one() {
    local name="$1" want_check="${2:-}"
    local repo config before after
    repo="$(prepare_repo "$name")" || {
        echo "could not prepare $name"
        exit 1
    }
    # set -e is off inside if ! ( ); every check has to exit itself.
    if ! (
        export AUR_DIR="$repo/aur"
        export PROJECT_ROOT="$repo"
        set -o noclobber
        mode_config import "$repo/hand/PKGBUILD" || exit 1
        load_aurgen_config || exit 1
        pkg_snapshot >"$tmp/$name.got" || exit 1
        AUR_DIR="$ROOT/tests/fixtures/$name/aur"
        load_aurgen_config || exit 1
        [[ -z "$want_check" ]] || PKG_CHECK="$want_check"
        pkg_snapshot >"$tmp/$name.want" || exit 1
        # The second import must hit the config the first one wrote, not the tracked fixture.
        AUR_DIR="$repo/aur"
        config="$repo/aur/aurgen.install.yaml"
        before="$(cksum "$config")" || exit 1
        if mode_config import "$repo/hand/PKGBUILD"; then
            echo "second import overwrote package: for $name"
            exit 1
        fi
        after="$(cksum "$config")" || exit 1
        if [[ "$before" != "$after" ]]; then
            echo "second import changed $name"
            exit 1
        fi
    ) >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        echo "import failed for $name"
        cat "$tmp/$name.err"
        exit 1
    fi
    if ! cmp -s "$tmp/$name.got" "$tmp/$name.want"; then
        echo "package fields differ for $name"
        diff -u "$tmp/$name.want" "$tmp/$name.got" || true
        exit 1
    fi
}

# The hand tmpcleaner and ramcleaner PKGBUILDs ran the developer suite; the
# hand cleaner PKGBUILD had no check(), which must survive a check: target.
import_one tmpcleaner 'make test' || exit 1
import_one cleaner false || exit 1
import_one ramcleaner 'make test' || exit 1

# install_vars followed by another command, both quote kinds, an inner brace
# group, and a top-level $CARCH (unset under set -u unless the importer exports it).
quote_repo="$tmp/repo-quote"
mkdir -p "$quote_repo/hand" "$quote_repo/aur" "$tmp/quote-bin" || exit 1
printf '#!/bin/bash\nexit 0\n' > "$tmp/quote-bin/gh" || exit 1
chmod +x "$tmp/quote-bin/gh" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' > "$quote_repo/Makefile" || exit 1
cat > "$quote_repo/hand/PKGBUILD" <<'EOF'
pkgname=quotepkg
pkgver=1.0.0
pkgrel=1
pkgdesc='quote round trip'
arch=('any')
url='https://example.com/quotepkg'
license=('GPL-3.0-or-later')
checkdepends=('bats' 'python-pytest>=8')
_arch=$CARCH

package() {
  make install DESTDIR="$pkgdir" PREFIX=/usr UNITDIR=/usr/lib/systemd/system
  python -c "print('x')"
  { echo a; echo b; }
}
EOF
git -C "$quote_repo" init -q || exit 1
git -C "$quote_repo" config user.email "t@example.com" || exit 1
git -C "$quote_repo" config user.name "t" || exit 1
git -C "$quote_repo" config commit.gpgsign false || exit 1
git -C "$quote_repo" add Makefile || exit 1
git -C "$quote_repo" commit -q -m init || exit 1
cat > "$tmp/quote.want" <<'EOF'
    make install DESTDIR="$pkgdir" PREFIX=/usr UNITDIR=/usr/lib/systemd/system
    python -c "print('x')"
    {
    echo a
    echo b
    }
EOF
if ! (
    export PATH="$tmp/quote-bin:$PATH"
    export AUR_DIR="$quote_repo/aur"
    export PROJECT_ROOT="$quote_repo"
    export PKGNAME=quotepkg
    set -o noclobber
    mode_config import "$quote_repo/hand/PKGBUILD" || exit 1
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config || exit 1
    if [[ "${#PKG_CHECKDEPENDS[@]}" -ne 2 || "${PKG_CHECKDEPENDS[0]}" != bats || "${PKG_CHECKDEPENDS[1]}" != 'python-pytest>=8' ]]; then
        echo "import lost checkdepends"
        exit 1
    fi
    if [[ "${#PKG_INSTALL_VARS[@]}" -ne 1 || "${PKG_INSTALL_VARS[0]}" != "UNITDIR=/usr/lib/systemd/system" ]]; then
        echo "install_vars lost UNITDIR"
        printf '%s\n' "${PKG_INSTALL_VARS[@]}"
        exit 1
    fi
    gen_pkgbuild0 || exit 1
    if ! grep -Fxq "checkdepends=('bats' 'python-pytest>=8')" "$quote_repo/aur/PKGBUILD.0"; then
        echo "generated PKGBUILD lost checkdepends"
        exit 1
    fi
    : > "$tmp/quote.got" || exit 1
    seen=0
    while IFS= read -r line; do
        if [[ "$seen" -eq 0 && "$line" == '    make install DESTDIR="$pkgdir" PREFIX=/usr UNITDIR=/usr/lib/systemd/system' ]]; then
            seen=1
        fi
        if [[ "$seen" -eq 1 ]]; then
            [[ "$line" == '}' ]] && break
            printf '%s\n' "$line" >> "$tmp/quote.got" || exit 1
        fi
    done < "$quote_repo/aur/PKGBUILD.0" || exit 1
    if ! cmp -s "$tmp/quote.want" "$tmp/quote.got"; then
        echo "package() body was not reproduced"
        diff -u "$tmp/quote.want" "$tmp/quote.got" || true
        exit 1
    fi
) >"$tmp/quote.out" 2>"$tmp/quote.err"; then
    echo "quote import failed"
    cat "$tmp/quote.err"
    exit 1
fi

# A CMake project's hand PKGBUILD without check() keeps no check: generation
# would otherwise add ctest.
cmake_repo="$tmp/repo-cmake"
mkdir -p "$cmake_repo/hand" "$cmake_repo/aur" || exit 1
printf 'cmake_minimum_required(VERSION 3.20)\nproject(demo)\n' > "$cmake_repo/CMakeLists.txt" || exit 1
cat > "$cmake_repo/hand/PKGBUILD" <<'EOF'
pkgname=cmakepkg
pkgver=1.0.0
pkgrel=1
pkgdesc='cmake without check'
arch=('x86_64')
url='https://example.com/cmakepkg'
license=('MIT')

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$cmake_repo" init -q || exit 1
git -C "$cmake_repo" config user.email "t@example.com" || exit 1
git -C "$cmake_repo" config user.name "t" || exit 1
git -C "$cmake_repo" config commit.gpgsign false || exit 1
git -C "$cmake_repo" add CMakeLists.txt || exit 1
git -C "$cmake_repo" commit -q -m init || exit 1
if ! (
    export AUR_DIR="$cmake_repo/aur"
    export PROJECT_ROOT="$cmake_repo"
    export PKGNAME=cmakepkg
    set -o noclobber
    mode_config import "$cmake_repo/hand/PKGBUILD" || exit 1
    load_aurgen_config || exit 1
    if [[ "$PKG_CHECK" != "false" ]]; then
        echo "a CMake import without check() wrote check: '$PKG_CHECK', want false"
        exit 1
    fi
) >"$tmp/cmake.out" 2>"$tmp/cmake.err"; then
    echo "cmake import failed"
    cat "$tmp/cmake.out" "$tmp/cmake.err"
    exit 1
fi

# A check() with if/then and a loop imports as one valid command.
compound_repo="$tmp/repo-compound"
mkdir -p "$compound_repo/hand" "$compound_repo/aur" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' > "$compound_repo/Makefile" || exit 1
cat > "$compound_repo/hand/PKGBUILD" <<'EOF'
pkgname=compoundpkg
pkgver=1.0.0
pkgrel=1
pkgdesc='compound check'
arch=('any')
url='https://example.com/compoundpkg'
license=('MIT')

check() {
  if [ -f Makefile ]; then
    make check
  fi
  for t in a b; do
    echo "$t"
  done
}

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$compound_repo" init -q || exit 1
git -C "$compound_repo" config user.email "t@example.com" || exit 1
git -C "$compound_repo" config user.name "t" || exit 1
git -C "$compound_repo" add Makefile || exit 1
git -C "$compound_repo" commit -q -m init || exit 1
if ! (
    export AUR_DIR="$compound_repo/aur"
    export PROJECT_ROOT="$compound_repo"
    export PKGNAME=compoundpkg
    set -o noclobber
    mode_config import "$compound_repo/hand/PKGBUILD" || exit 1
    load_aurgen_config || exit 1
    if ! bash -n <<< "$PKG_CHECK"; then
        echo "imported check is not valid bash: $PKG_CHECK"
        exit 1
    fi
    [[ "$PKG_CHECK" == *'then make check; fi'* && "$PKG_CHECK" == *'do echo "$t"; done'* ]] || { echo "imported check lost its structure: $PKG_CHECK"; exit 1; }
) >"$tmp/compound.out" 2>"$tmp/compound.err"; then
    echo "compound check import failed"
    cat "$tmp/compound.out" "$tmp/compound.err"
    exit 1
fi
