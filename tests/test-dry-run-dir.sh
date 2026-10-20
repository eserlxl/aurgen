#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# A dry run writes under aur/dry-run/ and leaves published files byte-identical.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-dry-run.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 0\n' > "$stub/curl"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/makepkg" "$stub/updpkgsums" "$stub/curl" "$stub/gh"

repo="$tmp/repo"
mkdir -p "$repo"
cp -a "$ROOT/tests/fixtures/tmpcleaner/." "$repo/"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
git -C "$repo" add -A
git -C "$repo" commit -q -m init
git -C "$repo" remote add origin "https://github.com/eserlxl/tmpCleaner.git"

printf 'published pkgbuild\n' > "$repo/aur/PKGBUILD"
printf 'published srcinfo\n' > "$repo/aur/.SRCINFO"
cp "$repo/aur/PKGBUILD" "$tmp/PKGBUILD.orig"
cp "$repo/aur/.SRCINFO" "$tmp/SRCINFO.orig"

export PATH="$stub:$PATH"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_STATE_HOME"

run_dry() {
    local name="$1"
    shift
    if ! (cd "$repo" && "$ROOT/bin/aurgen" -n "$@") >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail "dry-run $name failed" "$tmp/$name.err"
    fi
}

assert_published() {
    cmp -s "$tmp/PKGBUILD.orig" "$repo/aur/PKGBUILD" || fail "published PKGBUILD changed" "$repo/aur/PKGBUILD"
    cmp -s "$tmp/SRCINFO.orig" "$repo/aur/.SRCINFO" || fail "published .SRCINFO changed" "$repo/aur/.SRCINFO"
    [[ -f "$repo/aur/dry-run/PKGBUILD" ]] || fail "aur/dry-run/PKGBUILD was not written"
    local stray
    stray=$(find "$repo" -path "$repo/aur/dry-run" -prune -o -type f \( -name '*.tar.gz' -o -name '*.tar.gz.sig' -o -name '*.tar.gz.asc' -o -name '*.pkg.tar.*' \) -print)
    [[ -z "$stray" ]] || fail "generated archive outside aur/dry-run/: $stray"
}

run_dry local --dry-run local
assert_published
run_dry git --dry-run git
assert_published
