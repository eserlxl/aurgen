#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen valid modes library

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

declare -gar VALID_MODES=(local aur git aur-init aur-deploy aur-status clean test lint golden config)

# Usage string for aurgen
AURGEN_USAGE="Usage: aurgen <mode> [options]\n\nModes:\n  local     Build and test locally\n  aur       Prepare and upload to AUR\n  git       Prepare and upload to AUR (VCS)\n  aur-init  Initialize AUR repository\n  aur-deploy Deploy package to AUR\n  aur-status Check AUR repository status\n  clean     Clean build artifacts\n  test      Run tests\n  lint      Lint PKGBUILD and scripts\n  golden    Generate golden PKGBUILD\n  config    Manage install configuration files\n\nOptions:\n  -n, --no-color      Disable colored output\n  -a, --ascii-armor   Use ASCII-armored GPG signatures (.asc)\n  -d, --dry-run       Dry run (no changes, for testing)\n  --no-wait           Skip post-upload wait for asset availability\n  --maxdepth N        Set maximum search depth for lint and clean modes\n  -h, --help          Show detailed help and exit\n  -v, --version       Show version and exit\n  --usage             Show minimal usage and exit\n\nUse 'aurgen <mode> --help' for mode-specific options.\n\nFor complete documentation, see doc/USAGE.md and doc/AUR-INTEGRATION.md."

# Print usage helper
usage() {
    echo -e "$AURGEN_USAGE"
}

# Check if a mode is valid
is_valid_mode() {
    local mode="$1"
    for m in "${VALID_MODES[@]}"; do
        [[ "$m" == "$mode" ]] && return 0
    done
    return 1
} 