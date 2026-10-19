#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-release-tarball.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config tag.gpgsign false
printf 'tagged\n' > "$repo/src.txt"
printf 'readme\n' > "$repo/README.md"
git -C "$repo" add src.txt README.md
git -C "$repo" commit -q -m init
git -C "$repo" tag v1.0.0
printf 'later\n' > "$repo/src.txt"
printf 'extra\n' > "$repo/extra.txt"
git -C "$repo" add src.txt extra.txt
git -C "$repo" commit -q -m later
printf 'dirty\n' > "$repo/src.txt"

export PROJECT_ROOT="$repo"
export LIB_INSTALL_DIR="$ROOT/lib"
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
: > "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/gen-pkgbuild0.sh
source "$ROOT/lib/gen-pkgbuild0.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"
# gen-pkgbuild0.sh enables set -e; this file reports failures itself.
set +e

epoch=$(git -C "$repo" show -s --format=%ct v1.0.0)
export ARCHIVE_MTIME="--mtime=@${epoch}"

out1="$tmp/a.tar.gz"
out2="$tmp/b.tar.gz"
if ! aur_create_tarball v1.0.0 "$out1"; then
    fail "first archive failed" "$AURGEN_ERROR_LOG"
fi
if ! aur_create_tarball v1.0.0 "$out2"; then
    fail "second archive failed" "$AURGEN_ERROR_LOG"
fi
if ! cmp -s "$out1" "$out2"; then
    fail "two runs of the same ref differ"
fi

listing=$(tar -tzf "$out1")
if [[ "$listing" != "src.txt" ]]; then
    fail "tarball should be the flat filtered tag, got: ${listing}"
fi

extract="$tmp/extract"
mkdir -p "$extract"
tar -xzf "$out1" -C "$extract"
if [[ "$(cat "$extract/src.txt")" != "tagged" ]]; then
    fail "extracted file is not the tagged content" "$extract/src.txt"
fi

filter_pkgbuild_sources() { cat >/dev/null; }
empty="$tmp/empty.tar.gz"
if ! aur_create_tarball v1.0.0 "$empty"; then
    fail "empty filtered archive failed" "$AURGEN_ERROR_LOG"
fi
empty_listing=$(tar -tzf "$empty" || true)
if [[ -n "$empty_listing" ]]; then
    fail "filtered-out tree should not be archived, got: ${empty_listing}"
fi
