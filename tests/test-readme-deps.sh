#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# README detection keeps Arch package names from pacman -S and from
# requirement lists. Flags and apt/yum/brew names are not makedepends.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-readme-deps.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    exit 1
}

# detect_readme_deps prints a trailing space. Compare the list, then reject flags.
assert_deps() {
    local got="$1"
    local expected="$2"
    local tok
    local -a toks=()
    if [[ "$got" != "$expected" ]]; then
        echo "expected [$expected], got [$got]"
        exit 1
    fi
    read -ra toks <<< "$got"
    for tok in "${toks[@]}"; do
        if [[ "$tok" == -* ]]; then
            echo "flag token: $tok"
            exit 1
        fi
    done
}

run_detect() {
    local repo="$1"
    if ! (
        export PROJECT_ROOT="$repo"
        export AURGEN_MODE=test
        export color_enabled=0
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/detect-deps.sh
        source "$ROOT/lib/detect-deps.sh"
        detect_readme_deps
    ) >"$tmp/out" 2>"$tmp/err"; then
        echo "detect_readme_deps failed"
        cat "$tmp/err"
        exit 1
    fi
}

repo="$tmp/pacman"
mkdir -p "$repo"
cat > "$repo/README.md" <<'EOF'
sudo pacman -S cmake qt6-base
sudo apt install libqt6-dev
sudo yum install qt6-qtbase-devel
brew install qt@6
EOF
run_detect "$repo"
assert_deps "$(cat "$tmp/out")" "cmake qt6-base "

repo="$tmp/requirements"
mkdir -p "$repo"
cat > "$repo/README.md" <<'EOF'
## Requirements
- meson
- ninja
EOF
run_detect "$repo"
assert_deps "$(cat "$tmp/out")" "meson ninja "

# Capitalized requirement words meet the lowercase exclusion list and package names.
repo="$tmp/capitalized"
mkdir -p "$repo"
cat > "$repo/README.md" <<'EOF'
## Requirements
- Linux
- Meson
- jq
EOF
run_detect "$repo"
assert_deps "$(cat "$tmp/out")" "jq meson "

repo="$tmp/flags"
mkdir -p "$repo"
cat > "$repo/README.md" <<'EOF'
sudo pacman -S --needed zlib
EOF
run_detect "$repo"
assert_deps "$(cat "$tmp/out")" "zlib "


# Presence checks read the whole file list: under pipefail an early-exiting
# grep -q made the producer die of SIGPIPE on a long list and hid the match.
repo="$tmp/many-ts"
mkdir -p "$repo/src"
git -C "$repo" init -q
for i in $(seq 1 600); do
    : > "$repo/src/component-with-a-fairly-long-file-name-$i.ts"
done
git -C "$repo" add src
git -C "$repo" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m init
if ! (
    export PROJECT_ROOT="$repo"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh"
    # gen-pkgbuild0.sh defines the real filter; every file here is a source.
    filter_pkgbuild_sources() { cat; }
    detect_makedepends
) >"$tmp/many.out" 2>"$tmp/many.err"; then
    echo "detect_makedepends failed"
    cat "$tmp/many.err"
    exit 1
fi
grep -qw typescript "$tmp/many.out" || fail "600 tracked .ts files did not give typescript: [$(cat "$tmp/many.out")]"

echo "ok"
