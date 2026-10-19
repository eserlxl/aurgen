#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-description.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"

fail() {
    echo "$1"
    exit 1
}

write_gh() {
    local text="$1"
    cat > "$stub/gh" <<EOF
#!/bin/bash
printf '%s\n' '${text}'
exit 0
EOF
    chmod +x "$stub/gh"
}

new_repo() {
    local repo="$tmp/demo"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" remote add origin "https://example.com/testuser/demo.git"
    printf 'all:\n\t@true\n' > "$repo/Makefile"
    cat > "$repo/README.md" <<'EOF'
# Demo

[![ci](x)](y)

**A demo tool.**

## Usage

Run it.
EOF
    git -C "$repo" add Makefile README.md
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

run_gen() {
    local repo="$1"
    (
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=demo
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"
}

assert_pkgdesc() {
    local pkgbuild="$1"
    local expect="$2"
    [[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 was not written"
    if ! grep -F -x -q "pkgdesc='${expect}'" "$pkgbuild"; then
        echo "expected pkgdesc='${expect}'"
        grep '^pkgdesc=' "$pkgbuild" || true
        exit 1
    fi
}

repo="$(new_repo)"
pkgbuild="$repo/aur/PKGBUILD.0"
write_gh ""

if ! run_gen "$repo"; then
    echo "gen_pkgbuild0 failed for the README fallback"
    cat "$tmp/gen.err"
    exit 1
fi
assert_pkgdesc "$pkgbuild" "A demo tool."

write_gh "From GitHub."
if ! run_gen "$repo"; then
    echo "gen_pkgbuild0 failed for the GitHub description"
    cat "$tmp/gen.err"
    exit 1
fi
assert_pkgdesc "$pkgbuild" "From GitHub."

cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  description: "Configured summary."
EOF
if ! run_gen "$repo"; then
    echo "gen_pkgbuild0 failed for package.description"
    cat "$tmp/gen.err"
    exit 1
fi
assert_pkgdesc "$pkgbuild" "Configured summary."
