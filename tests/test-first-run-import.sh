#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-first-run-import.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -f "$tmp/git.err" ]]; then
        echo "--- git stderr ---"
        cat "$tmp/git.err"
    fi
    if [[ -f "$tmp/git.out" ]]; then
        echo "--- git stdout ---"
        cat "$tmp/git.out"
    fi
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub" || exit 1
printf '#!/bin/bash\nexit 0\n' > "$stub/gh" || exit 1
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg" || exit 1
chmod +x "$stub/gh" "$stub/makepkg" || exit 1

repo="$tmp/src"
mkdir -p "$repo" || exit 1
cp -a "$ROOT/tests/fixtures/tmpcleaner/." "$repo/" || exit 1
rm -f "$repo/aur/aurgen.install.yaml" || exit 1
cp "$ROOT/tests/fixtures/tmpcleaner/hand/PKGBUILD" "$repo/aur/PKGBUILD" || exit 1
# A project before migration keeps its hand-written install file next to the PKGBUILD.
cp "$ROOT/tests/fixtures/tmpcleaner/hand/tmpcleaner.install" "$repo/aur/" || exit 1

git -C "$repo" init -q -b master || exit 1
git -C "$repo" config user.email "t@example.com" || exit 1
git -C "$repo" config user.name "t" || exit 1
git -C "$repo" config commit.gpgsign false || exit 1
git -C "$repo" remote add origin "https://github.com/eserlxl/tmpCleaner.git" || exit 1
git -C "$repo" add -A || exit 1
git -C "$repo" commit -q -m init || exit 1

export PATH="$stub:$PATH"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_STATE_HOME" || exit 1

if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n --dry-run git
) >"$tmp/git.out" 2>"$tmp/git.err"; then
    fail "aurgen git failed"
fi

pkg="$repo/aur/PKGBUILD.0"
[[ -f "$pkg" ]] || fail "PKGBUILD.0 was not written"
grep -qx 'pkgname=linux-tmpcleaner' "$pkg" || fail "pkgname should be linux-tmpcleaner" "$pkg"
grep -qx "pkgdesc='Systemd timer that deletes old /tmp entries while protecting files in use'" "$pkg" || fail "pkgdesc should keep the hand-written text" "$pkg"
grep -qx "conflicts=('tmpcleaner')" "$pkg" || fail "conflicts should keep tmpcleaner" "$pkg"
grep -qx "backup=('etc/tmpcleaner/tmpcleaner.conf')" "$pkg" || fail "backup should keep the hand-written path" "$pkg"
grep -qx "install='tmpcleaner.install'" "$pkg" || fail "install should keep tmpcleaner.install" "$pkg"
