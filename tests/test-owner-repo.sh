#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-owner-repo.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub" || exit 1
printf '#!/bin/bash\nexit 0\n' > "$stub/gh" || exit 1
chmod +x "$stub/gh" || exit 1

export PATH="$stub:$PATH"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_STATE_HOME" || exit 1

init_repo() {
    local repo="$1"
    local origin="$2"
    mkdir -p "$repo" || exit 1
    cp -a "$ROOT/tests/fixtures/tmpcleaner/." "$repo/" || exit 1
    git -C "$repo" init -q -b master || exit 1
    git -C "$repo" config user.email "t@example.com" || exit 1
    git -C "$repo" config user.name "t" || exit 1
    git -C "$repo" config commit.gpgsign false || exit 1
    git -C "$repo" remote add origin "$origin" || exit 1
    git -C "$repo" add -A || exit 1
    git -C "$repo" commit -q -m init || exit 1
}

repo="$tmp/src"
init_repo "$repo" "https://github.com/tmux/tmux.git"

if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n --dry-run git
) >"$tmp/git.out" 2>"$tmp/git.err"; then
    fail "aurgen git failed for owner==repo" "$tmp/git.err"
fi
grep -qx "url='https://github.com/tmux/tmux'" "$repo/aur/PKGBUILD.0" || fail "url should be the tmux repository" "$repo/aur/PKGBUILD.0"

bad="$tmp/bad"
init_repo "$bad" "https://github.com/someone/tmux.git"
cat > "$bad/aur/PKGBUILD.0" <<'EOF'
pkgname=tmux
pkgver=1.0.0
pkgrel=1
pkgdesc='terminal multiplexer'
arch=('x86_64')
url='https://github.com/tmux/tmux'
license=('GPL-3.0-or-later')
source=('https://github.com/tmux/tmux/archive/refs/tags/1.0.0.tar.gz')
EOF
rm -f "$bad/aur/.PKGBUILD.0.stamp"

if (
    cd "$bad" || exit 1
    "$ROOT/bin/aurgen" -n --dry-run git
) >"$tmp/bad.out" 2>"$tmp/bad.err"; then
    fail "PKGBUILD.0 owner that disagrees with origin should be refused" "$tmp/bad.err"
fi
grep -F -q 'Aborting due to invalid GH_USER configuration' "$tmp/bad.err" || fail "missing GH_USER abort" "$tmp/bad.err"
