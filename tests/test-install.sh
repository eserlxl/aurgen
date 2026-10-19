#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-install.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"

fail() {
    echo "$1"
    exit 1
}

new_repo() {
    local repo="$tmp/$1"
    mkdir -p "$repo/aur" "$repo/bin"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
    printf '#!/bin/bash\n' > "$repo/bin/hello"
    printf 'hello\n' > "$repo/README.md"
    git -C "$repo" add bin/hello README.md
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

run_gen() {
    local repo="$1"
    if ! (
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
        load_aurgen_config
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
        return 1
    fi
}

repo="$(new_repo make-install)"
printf 'all:\n\t@true\ninstall:\n\t@true\n' > "$repo/Makefile"
cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  install_vars: [UNITDIR=/usr/lib/systemd/system]
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
if ! run_gen "$repo"; then
    echo "gen_pkgbuild0 failed for make-install"
    cat "$tmp/gen.err"
    exit 1
fi
pkgbuild="$repo/aur/PKGBUILD.0"
[[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 missing for make-install"
if ! bash -n "$pkgbuild"; then
    echo "bash -n failed for make-install"
    exit 1
fi
expected='    make install DESTDIR="$pkgdir" PREFIX=/usr UNITDIR=/usr/lib/systemd/system'
if ! grep -F -x -q -- "$expected" "$pkgbuild"; then
    echo "install line missing for make-install"
    cat "$pkgbuild"
    exit 1
fi
if grep -E -q '^    copy_tree "' "$pkgbuild"; then
    echo "copy rules must not run next to make install"
    cat "$pkgbuild"
    exit 1
fi

repo="$(new_repo make-copy)"
printf 'all:\n\t@true\n' > "$repo/Makefile"
if ! run_gen "$repo"; then
    echo "gen_pkgbuild0 failed for make-copy"
    cat "$tmp/gen.err"
    exit 1
fi
pkgbuild="$repo/aur/PKGBUILD.0"
[[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 missing for make-copy"
if ! grep -F -q 'copy_tree' "$pkgbuild"; then
    echo "copy_tree missing for make-copy"
    cat "$pkgbuild"
    exit 1
fi
if grep -F -q 'make install' "$pkgbuild"; then
    echo "make install was emitted without an install target"
    cat "$pkgbuild"
    exit 1
fi

repo="$(new_repo make-unsafe)"
printf 'all:\n\t@true\ninstall:\n\t@true\n' > "$repo/Makefile"
cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  install_vars: [UNITDIR=/usr/lib;touch]
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
if run_gen "$repo"; then
    echo "unsafe install variable was accepted"
    cat "$repo/aur/PKGBUILD.0"
    exit 1
fi
if [[ -f "$repo/aur/PKGBUILD.0" ]]; then
    echo "PKGBUILD.0 kept after refusing an unsafe install variable"
    exit 1
fi
if ! grep -F -q 'Unsafe install variable' "$tmp/gen.err"; then
    echo "unsafe install variable was not reported"
    cat "$tmp/gen.err"
    exit 1
fi
