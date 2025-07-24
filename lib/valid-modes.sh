#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
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

# Only assign if not already set
if ! declare -p VALID_MODES &>/dev/null; then
    VALID_MODES=(local aur aur-git clean test lint golden)
fi

# Usage string for aurgen
AURGEN_USAGE="Usage: aurgen <mode> [options]\n\nModes:\n  local     Build and test locally\n  aur       Prepare and upload to AUR\n  aur-git   Prepare and upload to AUR (VCS)\n  clean     Clean build artifacts\n  test      Run tests\n  lint      Lint PKGBUILD and scripts\n  golden    Generate golden PKGBUILD\n\nUse 'aurgen <mode> --help' for mode-specific options."

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