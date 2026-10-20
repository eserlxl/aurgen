#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-pkgbuild-prev.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export AUR_DIR="$tmp/aur"
export TEST_DIR="$tmp/test"
export GOLDEN_DIR="$tmp/golden"
export PKGNAME=example
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_MODE=test
export DEBUG_LEVEL=0
export color_enabled=0
export GREEN=""
export RESET=""
mkdir -p "$AUR_DIR" "$TEST_DIR" "$GOLDEN_DIR"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/clean.sh
source "$ROOT/lib/modes/clean.sh"

printf 'old pkgbuild\n' > "$AUR_DIR/PKGBUILD"
printf 'stale prev\n' > "$AUR_DIR/PKGBUILD.prev"
printf 'old srcinfo\n' > "$AUR_DIR/.SRCINFO"

cleanup

if [[ -f "$AUR_DIR/PKGBUILD" ]]; then
    echo "cleanup left PKGBUILD in place"
    exit 1
fi
if [[ ! -f "$AUR_DIR/PKGBUILD.prev" ]]; then
    echo "cleanup did not write PKGBUILD.prev"
    exit 1
fi
if ! cmp -s "$AUR_DIR/PKGBUILD.prev" <(printf 'old pkgbuild\n'); then
    echo "PKGBUILD.prev does not hold the replaced PKGBUILD"
    exit 1
fi
if [[ -f "$AUR_DIR/.SRCINFO" ]]; then
    echo "cleanup left .SRCINFO in place"
    exit 1
fi
if ! cmp -s "$AUR_DIR/.SRCINFO.prev" <(printf 'old srcinfo\n'); then
    echo ".SRCINFO.prev does not hold the replaced .SRCINFO"
    exit 1
fi

printf 'second pkgbuild\n' > "$AUR_DIR/PKGBUILD"
export AURGEN_KEEP_PREV=1
cleanup
unset AURGEN_KEEP_PREV

if [[ -f "$AUR_DIR/PKGBUILD" ]]; then
    echo "keep-prev cleanup left PKGBUILD in place"
    exit 1
fi
if ! cmp -s "$AUR_DIR/PKGBUILD.prev" <(printf 'old pkgbuild\n'); then
    echo "AURGEN_KEEP_PREV=1 changed PKGBUILD.prev"
    exit 1
fi

mode_clean >/dev/null

if [[ -e "$AUR_DIR/PKGBUILD.prev" || -e "$AUR_DIR/.SRCINFO.prev" ]]; then
    echo "mode_clean left .prev files behind"
    exit 1
fi
