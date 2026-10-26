#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/makepkg" << 'EOF'
#!/bin/bash
printf '%s\n' 'pkgbase = demopkg' 'pkgver = 1.0.0'
EOF
chmod +x "$stub/makepkg"

export PATH="$stub:$PATH"
export color_enabled=0

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

log() { :; }

export AUR_REPO_DIR="$tmp/aur"
repo="$AUR_REPO_DIR/demopkg"
mkdir -p "$repo"
printf 'pkgname=demopkg\n' > "$repo/PKGBUILD"
printf '%s\n' 'pkgbase = demopkg' 'pkgver = 1.0.0' > "$repo/.SRCINFO"

if ! validate_aur_repo demopkg; then
    echo "matching .SRCINFO was rejected"
    exit 1
fi

printf '%s\n' 'pkgbase = demopkg' 'pkgver = 9.9.9' > "$repo/.SRCINFO"
if validate_aur_repo demopkg >"$tmp/out" 2>"$tmp/err"; then
    echo "stale .SRCINFO was accepted"
    exit 1
fi
if ! grep -F -q "[aur-integration] .SRCINFO is out of date; run (cd $(printf '%q' "$repo") && makepkg --printsrcinfo >| .SRCINFO)" "$tmp/err"; then
    echo "stale .SRCINFO did not report it was out of date"
    cat "$tmp/err"
    exit 1
fi
