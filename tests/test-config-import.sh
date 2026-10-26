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

# A read-only config without package: must report a failed append.
readonly_dir="$tmp/readonly/aur"
mkdir -p "$readonly_dir" "$tmp/readonly-home" || exit 1
cp "$ROOT/tests/fixtures/cleaner/hand/PKGBUILD" "$readonly_dir/PKGBUILD" || exit 1
printf '# Existing config\n' >| "$readonly_dir/aurgen.install.yaml" || exit 1
chmod 444 "$readonly_dir/aurgen.install.yaml" || exit 1
if (
    export HOME="$tmp/readonly-home"
    export AUR_DIR="$readonly_dir"
    export PROJECT_ROOT="$tmp/readonly"
    set -o noclobber
    mode_config import
) >|"$tmp/readonly.out" 2>|"$tmp/readonly.err"; then
    echo "import accepted a read-only config"
    exit 1
fi
if ! grep -Fq "[config] Cannot write $readonly_dir/aurgen.install.yaml" "$tmp/readonly.err"; then
    echo "failed append did not explain the write failure"
    cat "$tmp/readonly.err"
    exit 1
fi
if grep -Fq 'Imported package metadata' "$tmp/readonly.out" "$tmp/readonly.err"; then
    echo "failed append reported import success"
    exit 1
fi

# A package() without make install must fail before creating a config.
install_dir="$tmp/install-only/aur"
mkdir -p "$install_dir" "$tmp/install-home" || exit 1
cat >| "$install_dir/PKGBUILD" <<'EOF'
pkgname=installonly

package() {
  install -Dm755 tool "$pkgdir/usr/bin/tool"
  install -Dm755 helper "$pkgdir/usr/bin/helper"
}
EOF
if (
    export HOME="$tmp/install-home"
    export AUR_DIR="$install_dir"
    export PROJECT_ROOT="$tmp/install-only"
    set -o noclobber
    mode_config import
) >|"$tmp/install-only.out" 2>|"$tmp/install-only.err"; then
    echo "import accepted package() without make install"
    exit 1
fi
if [[ -e "$install_dir/aurgen.install.yaml" ]]; then
    echo "failed import created a config"
    exit 1
fi
if ! grep -Fq "Cannot import $install_dir/PKGBUILD: package() has no make install line" "$tmp/install-only.err"; then
    echo "failed import did not explain the unsupported package() body"
    cat "$tmp/install-only.err"
    exit 1
fi

# A package() running a command other than cd before make install must fail
# before creating a config.
preinstall_dir="$tmp/preinstall/aur"
mkdir -p "$preinstall_dir" "$tmp/preinstall-home" || exit 1
cat >| "$preinstall_dir/PKGBUILD" <<'EOF'
pkgname=preinstallpkg

package() {
  cd "$srcdir/$pkgname"
  install -Dm644 extra.conf "$pkgdir/etc/extra.conf"
  make install DESTDIR="$pkgdir" PREFIX=/usr
}
EOF
if (
    export HOME="$tmp/preinstall-home"
    export AUR_DIR="$preinstall_dir"
    export PROJECT_ROOT="$tmp/preinstall"
    set -o noclobber
    mode_config import
) >|"$tmp/preinstall.out" 2>|"$tmp/preinstall.err"; then
    echo "import accepted a command before make install"
    exit 1
fi
if [[ -e "$preinstall_dir/aurgen.install.yaml" ]]; then
    echo "failed preinstall import created a config"
    exit 1
fi
if ! grep -Fq "Cannot import $preinstall_dir/PKGBUILD: package() runs install -Dm644 extra.conf \"\$pkgdir/etc/extra.conf\" before make install" "$tmp/preinstall.err"; then
    echo "failed import did not explain the pre-install command"
    cat "$tmp/preinstall.err"
    exit 1
fi

# A package() using a heredoc must fail before creating a config.
heredoc_dir="$tmp/heredoc/aur"
mkdir -p "$heredoc_dir" "$tmp/heredoc-home" || exit 1
cat >| "$heredoc_dir/PKGBUILD" <<'EOF'
pkgname=heredocpkg

package() {
  make install DESTDIR="$pkgdir" PREFIX=/usr
  cat > "$pkgdir/x.conf" <<'END'
key=value
END
}
EOF
if (
    export HOME="$tmp/heredoc-home"
    export AUR_DIR="$heredoc_dir"
    export PROJECT_ROOT="$tmp/heredoc"
    set -o noclobber
    mode_config import
) >|"$tmp/heredoc.out" 2>|"$tmp/heredoc.err"; then
    echo "import accepted package() with a heredoc"
    exit 1
fi
if [[ -e "$heredoc_dir/aurgen.install.yaml" ]]; then
    echo "failed heredoc import created a config"
    exit 1
fi
if ! grep -Fq "Cannot import $heredoc_dir/PKGBUILD: package() uses a heredoc" "$tmp/heredoc.err"; then
    echo "failed import did not explain the heredoc rejection"
    cat "$tmp/heredoc.err"
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

# install_vars followed by find -exec with an escaped semicolon, both quote
# kinds, an inner brace group, and a top-level $CARCH (unset under set -u).
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
  find "$pkgdir" -name "*.sh" -exec chmod 755 {} \;
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
    find "$pkgdir" -name "*.sh" -exec chmod 755 {} \;
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
    bash -n "$quote_repo/aur/PKGBUILD.0" || exit 1
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
  case "$CARCH" in
    x86_64)
      make check
      ;;
    *)
      true
      ;;
  esac
}

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$compound_repo" init -q || exit 1
git -C "$compound_repo" config user.email "t@example.com" || exit 1
git -C "$compound_repo" config user.name "t" || exit 1
git -C "$compound_repo" config commit.gpgsign false || exit 1
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
    [[ "$PKG_CHECK" == *'in x86_64) make check;'* ]] || { echo "imported check lost the case statement: $PKG_CHECK"; exit 1; }
) >"$tmp/compound.out" 2>"$tmp/compound.err"; then
    echo "compound check import failed"
    cat "$tmp/compound.out" "$tmp/compound.err"
    exit 1
fi

# Case fallthrough and multiline subshells keep valid check() syntax.
for check_kind in fallthrough subshell; do
    check_dir="$tmp/check-$check_kind/aur"
    mkdir -p "$check_dir" || exit 1
    {
        printf 'pkgname=compoundpkg\npkgver=1.0.0\npkgrel=1\n'
        printf 'pkgdesc="compound check"\narch=(any)\n'
        printf 'url="https://example.com/compoundpkg"\nlicense=(MIT)\n'
        if [[ "$check_kind" == fallthrough ]]; then
            cat <<'EOF'
check() {
  case "$CARCH" in
    x86_64)
      make check
      ;&
    aarch64)
      true
      ;;&
    *)
      true
      ;;
  esac
}
EOF
        else
            cat <<'EOF'
check() {
  (
    cd tests && pytest
  )
  echo done
}
EOF
        fi
        printf 'package() {\n  make install DESTDIR="$pkgdir"\n}\n'
    } >| "$check_dir/PKGBUILD" || exit 1
    if ! (
        export AUR_DIR="$check_dir"
        export PROJECT_ROOT="$compound_repo"
        export PKGNAME=compoundpkg
        set -o noclobber
        mode_config import || exit 1
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config || exit 1
        if [[ "$check_kind" == fallthrough ]]; then
            [[ "$PKG_CHECK" == *';& aarch64)'* && "$PKG_CHECK" == *';;& *)'* ]] || exit 1
        else
            [[ "$PKG_CHECK" == '( cd tests && pytest ); echo done' ]] || exit 1
        fi
        gen_pkgbuild0 || exit 1
        bash -n "$check_dir/PKGBUILD.0" || exit 1
    ) >|"$tmp/check-$check_kind.out" 2>|"$tmp/check-$check_kind.err"; then
        echo "$check_kind check import failed"
        cat "$tmp/check-$check_kind.out" "$tmp/check-$check_kind.err"
        exit 1
    fi
done

# A package() with a case block after make install imports and keeps the case
# terminators intact so the generated PKGBUILD.0 passes bash -n.
case_repo="$tmp/repo-case"
mkdir -p "$case_repo/hand" "$case_repo/aur" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' > "$case_repo/Makefile" || exit 1
cat >| "$case_repo/hand/PKGBUILD" <<'EOF'
pkgname=casepkg
pkgver=1.0.0
pkgrel=1
pkgdesc='case block in package'
arch=('x86_64')
url='https://example.com/casepkg'
license=('MIT')

package() {
  make install DESTDIR="$pkgdir" PREFIX=/usr
  case "$CARCH" in
    x86_64)
      install -Dm644 a "$pkgdir/a"
      ;;
    *)
      install -Dm644 b "$pkgdir/b"
      ;;
  esac
}
EOF
git -C "$case_repo" init -q || exit 1
git -C "$case_repo" config user.email "t@example.com" || exit 1
git -C "$case_repo" config user.name "t" || exit 1
git -C "$case_repo" config commit.gpgsign false || exit 1
git -C "$case_repo" add Makefile || exit 1
git -C "$case_repo" commit -q -m init || exit 1
cat >| "$tmp/case.want" <<'EOF'
    make install DESTDIR="$pkgdir" PREFIX=/usr
    case "$CARCH" in
    x86_64)
    install -Dm644 a "$pkgdir/a"
    ;;
    *)
    install -Dm644 b "$pkgdir/b"
    ;;
    esac
EOF
if ! (
    export AUR_DIR="$case_repo/aur"
    export PROJECT_ROOT="$case_repo"
    export PKGNAME=casepkg
    set -o noclobber
    mode_config import "$case_repo/hand/PKGBUILD" || exit 1
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config || exit 1
    gen_pkgbuild0 || exit 1
    if ! bash -n "$case_repo/aur/PKGBUILD.0"; then
        echo "generated PKGBUILD is not valid bash"
        exit 1
    fi
    : >| "$tmp/case.got" || exit 1
    seen=0
    while IFS= read -r line; do
        if [[ "$seen" -eq 0 && "$line" == '    make install DESTDIR="$pkgdir" PREFIX=/usr'* ]]; then
            seen=1
        fi
        if [[ "$seen" -eq 1 ]]; then
            [[ "$line" == '}' ]] && break
            printf '%s\n' "$line" >> "$tmp/case.got" || exit 1
        fi
    done < "$case_repo/aur/PKGBUILD.0" || exit 1
    if ! cmp -s "$tmp/case.want" "$tmp/case.got"; then
        echo "package() case block was not reproduced"
        diff -u "$tmp/case.want" "$tmp/case.got" || true
        exit 1
    fi
) >|"$tmp/case.out" 2>|"$tmp/case.err"; then
    echo "case import failed"
    cat "$tmp/case.err"
    exit 1
fi

# A quoted VAR="VALUE" after make install is stored without the quotes.
quoted_repo="$tmp/repo-quoted"
mkdir -p "$quoted_repo/hand" "$quoted_repo/aur" "$tmp/quoted-home" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' >| "$quoted_repo/Makefile" || exit 1
cat >| "$quoted_repo/hand/PKGBUILD" <<'EOF'
pkgname=quotedpkg
pkgver=1.0.0
pkgrel=1
pkgdesc='quoted install var'
arch=('any')
url='https://example.com/quotedpkg'
license=('MIT')

package() {
  make install DESTDIR="$pkgdir" PREFIX=/usr UNITDIR="/usr/lib/systemd/system"
}
EOF
git -C "$quoted_repo" init -q || exit 1
git -C "$quoted_repo" config user.email "t@example.com" || exit 1
git -C "$quoted_repo" config user.name "t" || exit 1
git -C "$quoted_repo" config commit.gpgsign false || exit 1
git -C "$quoted_repo" add Makefile || exit 1
git -C "$quoted_repo" commit -q -m init || exit 1
if ! (
    export HOME="$tmp/quoted-home"
    export AUR_DIR="$quoted_repo/aur"
    export PROJECT_ROOT="$quoted_repo"
    export PKGNAME=quotedpkg
    set -o noclobber
    mode_config import "$quoted_repo/hand/PKGBUILD" || exit 1
    load_aurgen_config || exit 1
    if [[ "${#PKG_INSTALL_VARS[@]}" -ne 1 || "${PKG_INSTALL_VARS[0]}" != "UNITDIR=/usr/lib/systemd/system" ]]; then
        echo "quoted install_vars lost UNITDIR"
        printf '%s\n' "${PKG_INSTALL_VARS[@]}"
        exit 1
    fi
) >|"$tmp/quoted.out" 2>|"$tmp/quoted.err"; then
    echo "quoted install var import failed"
    cat "$tmp/quoted.err"
    exit 1
fi

# A value outside the install-variable alphabet stops the import.
unsafe_repo="$tmp/repo-unsafe"
mkdir -p "$unsafe_repo/hand" "$unsafe_repo/aur" "$tmp/unsafe-home" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' >| "$unsafe_repo/Makefile" || exit 1
cat >| "$unsafe_repo/hand/PKGBUILD" <<'EOF'
pkgname=unsafepkg
pkgver=1.0.0
pkgrel=1
pkgdesc='unsafe install var'
arch=('any')
url='https://example.com/unsafepkg'
license=('MIT')

package() {
  make install DESTDIR="$pkgdir" PREFIX=/usr EVIL='$(reboot)'
}
EOF
git -C "$unsafe_repo" init -q || exit 1
git -C "$unsafe_repo" config user.email "t@example.com" || exit 1
git -C "$unsafe_repo" config user.name "t" || exit 1
git -C "$unsafe_repo" config commit.gpgsign false || exit 1
git -C "$unsafe_repo" add Makefile || exit 1
git -C "$unsafe_repo" commit -q -m init || exit 1
if (
    export HOME="$tmp/unsafe-home"
    export AUR_DIR="$unsafe_repo/aur"
    export PROJECT_ROOT="$unsafe_repo"
    export PKGNAME=unsafepkg
    set -o noclobber
    mode_config import "$unsafe_repo/hand/PKGBUILD"
) >|"$tmp/unsafe.out" 2>|"$tmp/unsafe.err"; then
    echo "import accepted an unsafe install variable"
    exit 1
fi
if [[ -e "$unsafe_repo/aur/aurgen.install.yaml" ]]; then
    echo "unsafe import created a config"
    exit 1
fi
if ! grep -Fq "[config] Cannot import" "$tmp/unsafe.err"; then
    echo "unsafe import did not explain the rejected install word"
    cat "$tmp/unsafe.err"
    exit 1
fi

# An apostrophe before " #" must stay in the scalar and reach PKGBUILD.0.
apos_repo="$tmp/repo-apos"
mkdir -p "$apos_repo/hand" "$apos_repo/aur" "$tmp/apos-home" "$tmp/apos-bin" || exit 1
printf '#!/bin/bash\nexit 0\n' >| "$tmp/apos-bin/gh" || exit 1
chmod +x "$tmp/apos-bin/gh" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' >| "$apos_repo/Makefile" || exit 1
cat >| "$apos_repo/hand/PKGBUILD" <<'EOF'
pkgname=apospkg
pkgver=1.0.0
pkgrel=1
pkgdesc="Don't fail on #1"
arch=('any')
url='https://example.com/apospkg'
license=('MIT')

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$apos_repo" init -q || exit 1
git -C "$apos_repo" config user.email "t@example.com" || exit 1
git -C "$apos_repo" config user.name "t" || exit 1
git -C "$apos_repo" config commit.gpgsign false || exit 1
git -C "$apos_repo" add Makefile || exit 1
git -C "$apos_repo" commit -q -m init || exit 1
if ! (
    export HOME="$tmp/apos-home"
    export PATH="$tmp/apos-bin:$PATH"
    export AUR_DIR="$apos_repo/aur"
    export PROJECT_ROOT="$apos_repo"
    export PKGNAME=apospkg
    set -o noclobber
    mode_config import "$apos_repo/hand/PKGBUILD" || exit 1
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config || exit 1
    [[ "$PKG_DESCRIPTION" == "Don't fail on #1" ]] || { echo "description: [$PKG_DESCRIPTION]"; exit 1; }
    gen_pkgbuild0 || exit 1
    if ! grep -Fxq "pkgdesc='Don'\\''t fail on #1'" "$apos_repo/aur/PKGBUILD.0"; then
        echo "generated pkgdesc lost the apostrophe or the hash"
        grep -n '^pkgdesc=' "$apos_repo/aur/PKGBUILD.0" || true
        exit 1
    fi
) >|"$tmp/apos.out" 2>|"$tmp/apos.err"; then
    echo "apostrophe import failed"
    cat "$tmp/apos.err"
    exit 1
fi

# A Makefile plus a tracked C source is compiled, so arch=('any') is explicit
# and must stay any through import and generation.
cany_repo="$tmp/repo-cany"
mkdir -p "$cany_repo/hand" "$cany_repo/aur" "$tmp/cany-home" "$tmp/cany-bin" || exit 1
printf '#!/bin/bash\nexit 0\n' >| "$tmp/cany-bin/gh" || exit 1
chmod +x "$tmp/cany-bin/gh" || exit 1
printf 'all:\n\tcc -o main main.c\ninstall:\n\t@true\n' >| "$cany_repo/Makefile" || exit 1
printf 'int main(void){return 0;}\n' >| "$cany_repo/main.c" || exit 1
cat >| "$cany_repo/hand/PKGBUILD" <<'EOF'
pkgname=canypkg
pkgver=1.0.0
pkgrel=1
pkgdesc='explicit arch any'
arch=('any')
url='https://example.com/canypkg'
license=('MIT')

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$cany_repo" init -q || exit 1
git -C "$cany_repo" config user.email "t@example.com" || exit 1
git -C "$cany_repo" config user.name "t" || exit 1
git -C "$cany_repo" config commit.gpgsign false || exit 1
git -C "$cany_repo" add Makefile main.c || exit 1
git -C "$cany_repo" commit -q -m init || exit 1
if ! (
    export HOME="$tmp/cany-home"
    export PATH="$tmp/cany-bin:$PATH"
    export AUR_DIR="$cany_repo/aur"
    export PROJECT_ROOT="$cany_repo"
    export PKGNAME=canypkg
    set -o noclobber
    mode_config import "$cany_repo/hand/PKGBUILD" || exit 1
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config || exit 1
    if [[ "${#PKG_ARCH[@]}" -ne 1 || "${PKG_ARCH[0]}" != any ]]; then
        echo "import dropped explicit arch any"
        printf '%s\n' "${PKG_ARCH[@]}"
        exit 1
    fi
    gen_pkgbuild0 || exit 1
    if ! grep -Fxq "arch=('any')" "$cany_repo/aur/PKGBUILD.0"; then
        echo "generation replaced explicit arch any"
        grep -n '^arch=' "$cany_repo/aur/PKGBUILD.0" || true
        exit 1
    fi
) >|"$tmp/cany.out" 2>|"$tmp/cany.err"; then
    echo "compiled arch any import failed"
    cat "$tmp/cany.err"
    exit 1
fi

# A cd into $srcdir is dropped; a cd into another directory stays in check.
cdsub_repo="$tmp/repo-cdsub"
mkdir -p "$cdsub_repo/hand" "$cdsub_repo/aur" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' >| "$cdsub_repo/Makefile" || exit 1
cat >| "$cdsub_repo/hand/PKGBUILD" <<'EOF'
pkgname=cdsubpkg
pkgver=1.0.0
pkgrel=1
pkgdesc='cd into a subdirectory'
arch=('any')
url='https://example.com/cdsubpkg'
license=('MIT')

check() {
  cd "$srcdir"
  cd tests
  bash smoke.sh
}

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$cdsub_repo" init -q || exit 1
git -C "$cdsub_repo" config user.email "t@example.com" || exit 1
git -C "$cdsub_repo" config user.name "t" || exit 1
git -C "$cdsub_repo" config commit.gpgsign false || exit 1
git -C "$cdsub_repo" add Makefile || exit 1
git -C "$cdsub_repo" commit -q -m init || exit 1
if ! (
    export AUR_DIR="$cdsub_repo/aur"
    export PROJECT_ROOT="$cdsub_repo"
    export PKGNAME=cdsubpkg
    set -o noclobber
    mode_config import "$cdsub_repo/hand/PKGBUILD" || exit 1
    load_aurgen_config || exit 1
    if ! grep -Fq "check: 'cd tests; bash smoke.sh'" "$cdsub_repo/aur/aurgen.install.yaml"; then
        echo "subdirectory cd was dropped from check"
        cat "$cdsub_repo/aur/aurgen.install.yaml"
        exit 1
    fi
    if [[ "$PKG_CHECK" != 'cd tests; bash smoke.sh' ]]; then
        echo "imported check: '$PKG_CHECK'"
        exit 1
    fi
) >|"$tmp/cdsub.out" 2>|"$tmp/cdsub.err"; then
    echo "subdirectory cd import failed"
    cat "$tmp/cdsub.out" "$tmp/cdsub.err"
    exit 1
fi

# A cd into $srcdir or $srcdir/<one component> is still dropped. A deeper cd
# stays in check, relative to that source root (quoted $srcdir and ${srcdir}).
cddeep_repo="$tmp/repo-cddeep"
mkdir -p "$cddeep_repo/hand" "$cddeep_repo/aur" || exit 1
printf 'all:\n\t@true\ninstall:\n\t@true\n' >| "$cddeep_repo/Makefile" || exit 1
cat >| "$cddeep_repo/hand/PKGBUILD" <<'EOF'
pkgname=cddeeppkg
pkgver=1.0.0
pkgrel=1
pkgdesc='cd below the source root'
arch=('any')
url='https://example.com/cddeeppkg'
license=('MIT')

check() {
  cd "$srcdir"
  cd "${srcdir}/${pkgname}-${pkgver}"
  cd "$srcdir/${pkgname}-${pkgver}/t"
  cd "${srcdir}/${pkgname}-${pkgver}/src"
  cd $srcdir/${pkgname}-${pkgver}/extra
  bash smoke.sh
}

package() {
  make install DESTDIR="$pkgdir"
}
EOF
git -C "$cddeep_repo" init -q || exit 1
git -C "$cddeep_repo" config user.email "t@example.com" || exit 1
git -C "$cddeep_repo" config user.name "t" || exit 1
git -C "$cddeep_repo" config commit.gpgsign false || exit 1
git -C "$cddeep_repo" add Makefile || exit 1
git -C "$cddeep_repo" commit -q -m init || exit 1
if ! (
    export AUR_DIR="$cddeep_repo/aur"
    export PROJECT_ROOT="$cddeep_repo"
    export PKGNAME=cddeeppkg
    set -o noclobber
    mode_config import "$cddeep_repo/hand/PKGBUILD" || exit 1
    load_aurgen_config || exit 1
    if ! grep -Fq "check: 'cd \"t\"; cd \"src\"; cd extra; bash smoke.sh'" "$cddeep_repo/aur/aurgen.install.yaml"; then
        echo "deeper cd was not kept relative to the source root"
        cat "$cddeep_repo/aur/aurgen.install.yaml"
        exit 1
    fi
    if [[ "$PKG_CHECK" != 'cd "t"; cd "src"; cd extra; bash smoke.sh' ]]; then
        echo "imported check: '$PKG_CHECK'"
        exit 1
    fi
) >|"$tmp/cddeep.out" 2>|"$tmp/cddeep.err"; then
    echo "deeper source cd import failed"
    cat "$tmp/cddeep.out" "$tmp/cddeep.err"
    exit 1
fi

# A cd with another command or word is not a standalone source-root change.
while IFS= read -r cd_line; do
    if [[ "$(_import_cd_place "$cd_line")" != other ]]; then
        echo "non-standalone cd was classified as a source directory: $cd_line"
        exit 1
    fi
done <<'EOF'
cd $srcdir/demo-1.0 && pytest
cd "$srcdir/demo-1.0" && pytest
cd $srcdir/demo-1.0 || pytest
cd $srcdir/demo-1.0; pytest
cd $srcdir/demo-1.0 | pytest
cd $srcdir/demo-1.0 extra
cd "$srcdir/demo-1.0" "extra"
cd "$srcdir/.."
cd "$srcdir/."
cd "$srcdir/demo/../tests"
cd "$srcdir/demo/./tests"
EOF
for cd_line in 'cd "$srcdir/a && b"' 'cd "$srcdir/a || b"' 'cd "$srcdir/a; b"' 'cd "$srcdir/a | b"'; do
    if [[ "$(_import_cd_place "$cd_line")" != root ]]; then
        echo "quoted source-root target was rejected: $cd_line"
        exit 1
    fi
done
for cd_line in 'cd $srcdir/demo-1.0 && pytest' 'cd "$srcdir/demo-1.0" && pytest'; do
    check_fn="$(printf 'check ()\n{\n    %s\n}\n' "$cd_line")" || exit 1
    if [[ "$(_import_check_command "$check_fn")" != pytest ]]; then
        echo "chained source-root cd lost its check command: $cd_line"
        exit 1
    fi
done

for cd_line in 'cd "$srcdir/$pkgname/tests" && pytest' 'cd $srcdir/$pkgname/tests && pytest'; do
    check_fn="$(printf 'check ()\n{\n    %s\n}\n' "$cd_line")" || exit 1
    expected='cd tests && pytest'
    [[ "$cd_line" == *'"'* ]] && expected='cd "tests" && pytest'
    if [[ "$(_import_check_command "$check_fn")" != "$expected" ]]; then
        echo "chained subdirectory cd was not relative to the source root: $cd_line"
        exit 1
    fi
done
cd_line='cd "$srcdir/../tests" && pytest'
check_fn="$(printf 'check ()\n{\n    %s\n}\n' "$cd_line")" || exit 1
if [[ "$(_import_check_command "$check_fn")" != "$cd_line" ]]; then
    echo "unrecognized chained cd was changed: $cd_line"
    exit 1
fi

# Only a package() cd into the source root may be dropped.
deeppkg_dir="$tmp/deeppkg/aur"
mkdir -p "$deeppkg_dir" "$tmp/deeppkg-home" || exit 1
for cd_line in 'cd "$srcdir/${pkgname}-${pkgver}/src"' 'cd src' 'cd -- "$srcdir/demo-1.0/src"' 'cd' 'cd "$srcdir/.."' 'cd "$srcdir/demo-1.0" && pytest'; do
    {
        printf 'pkgname=deeppkg\n\npackage() {\n  %s\n' "$cd_line"
        printf '  make install DESTDIR="$pkgdir" PREFIX=/usr\n}\n'
    } >| "$deeppkg_dir/PKGBUILD" || exit 1
    if (
        export HOME="$tmp/deeppkg-home"
        export AUR_DIR="$deeppkg_dir"
        export PROJECT_ROOT="$tmp/deeppkg"
        set -o noclobber
        mode_config import
    ) >|"$tmp/deeppkg.out" 2>|"$tmp/deeppkg.err"; then
        echo "import accepted package() $cd_line"
        exit 1
    fi
    if [[ -e "$deeppkg_dir/aurgen.install.yaml" ]]; then
        echo "refused package cd created a config"
        exit 1
    fi
    if ! grep -Fq "Cannot import $deeppkg_dir/PKGBUILD: package() changes directory with $cd_line" "$tmp/deeppkg.err"; then
        echo "failed import did not explain the package() cd"
        cat "$tmp/deeppkg.err"
        exit 1
    fi
done

# Source-root cds accept trailing slashes, a failure guard, and --.
rootcd_index=0
for cd_line in 'cd "$srcdir/demo-1.0/"' 'cd "$srcdir/demo-1.0" || return' 'cd "$srcdir/demo-1.0" || exit' 'cd "$srcdir/demo-1.0" || return 1' 'cd -- "$srcdir/demo-1.0///" || exit 2'; do
    rootcd_index=$((rootcd_index + 1))
    rootcd_dir="$tmp/rootcd-$rootcd_index/aur"
    mkdir -p "$rootcd_dir" || exit 1
    {
        printf 'pkgname=demo\npkgver=1.0\npkgrel=1\npkgdesc="root cd"\n'
        printf 'arch=(any)\nurl="https://example.com/demo"\nlicense=(MIT)\n'
        printf 'check() {\n  cd "$srcdir/demo-1.0" && pytest\n}\n'
        printf 'package() {\n  %s\n' "$cd_line"
        printf '  make install DESTDIR="$pkgdir" PREFIX=/usr\n}\n'
    } >| "$rootcd_dir/PKGBUILD" || exit 1
    if ! (
        export HOME="$tmp/deeppkg-home"
        export AUR_DIR="$rootcd_dir"
        export PROJECT_ROOT="$quote_repo"
        set -o noclobber
        mode_config import || exit 1
        load_aurgen_config || exit 1
        [[ "$PKG_NAME" == demo ]] || exit 1
        [[ "$PKG_CHECK" == pytest ]] || exit 1
        [[ "${#PKG_POST_PACKAGE[@]}" -eq 0 ]] || exit 1
    ) >|"$tmp/rootcd.out" 2>|"$tmp/rootcd.err"; then
        echo "source-root package() $cd_line did not import"
        cat "$tmp/rootcd.out" "$tmp/rootcd.err"
        exit 1
    fi
done
