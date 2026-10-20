#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-aur-package-name.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export color_enabled=0
export DEBUG_LEVEL=0
export SILVER=""
export RESET=""
export YELLOW=""
export PKGNAME="demopkg"
export LIB_INSTALL_DIR="$ROOT/lib"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

export SRCINFO="$tmp/both.SRCINFO"
printf 'pkgbase = demopkg-git\n\tpkgname = othername\n' >|"$SRCINFO"
got=$(aur_package_name) || exit 1
if [[ "$got" != "demopkg-git" ]]; then
    echo "pkgbase did not win: $got"
    exit 1
fi

export SRCINFO="$tmp/pkgname.SRCINFO"
printf '\tpkgname = demopkg\n' >|"$SRCINFO"
got=$(aur_package_name) || exit 1
if [[ "$got" != "demopkg" ]]; then
    echo "pkgname fallback failed: $got"
    exit 1
fi

export SRCINFO="$tmp/missing.SRCINFO"
got=$(aur_package_name) || exit 1
if [[ "$got" != "demopkg" ]]; then
    echo "missing .SRCINFO did not use PKGNAME: $got"
    exit 1
fi

export AUR_DIR="$tmp/aurdir"
mkdir -p "$AUR_DIR"
printf '%s\n' 'aur_integration:' "  aur_repo_dir: $tmp/aur" >|"$AUR_DIR/aurgen.install.yaml"
export SRCINFO="$tmp/git.SRCINFO"
printf 'pkgbase = demopkg-git\n' >|"$SRCINFO"

stub="$tmp/bin"
mkdir -p "$stub"
printf '%s\n' '#!/bin/bash' 'exit 1' >|"$stub/curl"
chmod +x "$stub/curl"
export PATH="$stub:$PATH"

# shellcheck source=../lib/modes/aur-status.sh
source "$ROOT/lib/modes/aur-status.sh"

if ! mode_aur_status >|"$tmp/status.out" 2>|"$tmp/status.err"; then
    echo "mode_aur_status failed"
    cat "$tmp/status.out"
    cat "$tmp/status.err"
    exit 1
fi
if ! grep -F -q '=== AUR Repository Status: demopkg-git ===' "$tmp/status.out"; then
    echo "status did not name demopkg-git"
    cat "$tmp/status.out"
    exit 1
fi
if ! grep -F -q 'Checking AUR repository status for package: demopkg-git' "$tmp/status.out"; then
    echo "status log did not name demopkg-git"
    cat "$tmp/status.out"
    exit 1
fi
