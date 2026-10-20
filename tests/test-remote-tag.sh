#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-remote-tag.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

bare="$tmp/origin.git"
repo="$tmp/repo"
git init -q --bare "$bare"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'x\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
git -C "$repo" remote add origin "$bare"
git -C "$repo" tag v1.0.0

export PROJECT_ROOT="$repo"
export PKGVER=1.0.0
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
: >| "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"

if ( aur_require_remote_tag ) >"$tmp/before.out" 2>"$tmp/before.err"; then
    echo "expected failure before the tag is pushed"
    exit 1
fi
grep -F -q "[aur] Tag v1.0.0 is not on origin; push it first: git push origin v1.0.0" "$tmp/before.err" || exit 1

if ! git -C "$repo" push origin v1.0.0 >"$tmp/push.out" 2>"$tmp/push.err"; then
    echo "git push origin v1.0.0 failed"
    cat "$tmp/push.err"
    exit 1
fi

if ! ( aur_require_remote_tag ) >"$tmp/after.out" 2>"$tmp/after.err"; then
    echo "expected success after the tag is on origin"
    cat "$tmp/after.err"
    exit 1
fi
