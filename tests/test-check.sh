#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-check.XXXXXX)"
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
        echo "gen_pkgbuild0 failed for $repo"
        cat "$tmp/gen.err"
        exit 1
    fi
}

assert_check() {
    local repo="$1"
    local expected="$2"
    local pkgbuild="$repo/aur/PKGBUILD.0"
    local line
    [[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 missing for $repo"
    if ! bash -n "$pkgbuild"; then
        echo "bash -n failed for $repo"
        exit 1
    fi
    line="$(awk '/^check\(\) \{/{getline; print; exit}' "$pkgbuild")"
    if [[ "$line" != "    $expected" ]]; then
        echo "check() for ${repo##*/}: expected '$expected', got '${line:-<none>}'"
        exit 1
    fi
}

assert_no_check() {
    local repo="$1"
    local pkgbuild="$repo/aur/PKGBUILD.0"
    [[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 missing for $repo"
    if grep -q '^check()' "$pkgbuild"; then
        echo "check() was emitted for ${repo##*/}"
        cat "$pkgbuild"
        exit 1
    fi
}

repo="$(new_repo make-test)"
printf 'all:\n\t@true\ntest:\n\t@true\n' > "$repo/Makefile"
run_gen "$repo"
assert_no_check "$repo"

repo="$(new_repo make-check)"
printf 'all:\n\t@true\ncheck:\n\t@true\n' > "$repo/Makefile"
run_gen "$repo"
assert_check "$repo" "make check"

repo="$(new_repo make-both)"
printf 'all:\n\t@true\ntest:\n\t@true\ncheck:\n\t@true\n' > "$repo/Makefile"
run_gen "$repo"
assert_check "$repo" "make check"

repo="$(new_repo make-none)"
printf 'all:\n\t@true\n' > "$repo/Makefile"
run_gen "$repo"
assert_no_check "$repo"

repo="$(new_repo cmake)"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(testpkg)\n' > "$repo/CMakeLists.txt"
run_gen "$repo"
assert_check "$repo" "ctest --test-dir build"

repo="$(new_repo rust)"
printf '[package]\nname = "testpkg"\nversion = "0.1.0"\n' > "$repo/Cargo.toml"
run_gen "$repo"
assert_check "$repo" "cargo test --release"

repo="$(new_repo go)"
printf 'module example.com/testpkg\n\ngo 1.22\n' > "$repo/go.mod"
run_gen "$repo"
assert_check "$repo" "go test ./..."

repo="$(new_repo meson)"
printf 'project(%s)\n' "'testpkg'" > "$repo/meson.build"
run_gen "$repo"
assert_check "$repo" "meson test -C build"

repo="$(new_repo custom)"
printf 'all:\n\t@true\n' > "$repo/Makefile"
cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  check: pytest -q
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
run_gen "$repo"
assert_check "$repo" "pytest -q"

repo="$(new_repo disabled)"
printf 'all:\n\t@true\ntest:\n\t@true\n' > "$repo/Makefile"
cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  check: false
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
run_gen "$repo"
assert_no_check "$repo"
