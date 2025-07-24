#!/bin/bash
# Check if aur/PKGBUILD.0 is a valid PKGBUILD.0 for aurgen
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

check_pkgbuild0() {
    # Check if aur/PKGBUILD.0 is a valid PKGBUILD.0 for aurgen
    # Returns 0 if valid, 1 if not
    set -euo pipefail
    PKGBUILD0="$AUR_DIR/PKGBUILD.0"

    local valid=1

    # Check existence
    if [[ ! -f "$PKGBUILD0" ]]; then
        warn "[check-pkgbuild0] $PKGBUILD0 does not exist." >&2
        return 1
    fi

    # Check for non-empty file
    if [[ ! -s "$PKGBUILD0" ]]; then
        warn "[check-pkgbuild0] $PKGBUILD0 is empty." >&2
        return 1
    fi

    # Required fields and their regexes
    declare -A fields=(
        [pkgname]="^pkgname=([^\"']+|\"[^\"]+\"|'[^']+')"
        [pkgver]="^pkgver=([^\"']+|\"[^\"]+\"|'[^']+')"
        [pkgrel]="^pkgrel=([^\"']+|\"[^\"]+\"|'[^']+')"
        [pkgdesc]="^pkgdesc=\"[^\"]+\""
        [url]="^url=\"https://github.com/[^/\"]+/[^/\"]+\""
        [license]="^license="
        [source]="^source="
    )

    for field in "${!fields[@]}"; do
        if ! grep -Eq "${fields[$field]}" "$PKGBUILD0"; then
            warn "[check-pkgbuild0] $PKGBUILD0 missing or invalid $field field." >&2
            valid=0
        fi
    done

    # Check that required fields are not empty (after =)
    for field in pkgname pkgver pkgrel pkgdesc url license source; do
        value=$(grep -E "^$field=" "$PKGBUILD0" | head -n1 | sed -E "s/^$field=//" | tr -d "'\"")
        if [[ -z "$value" ]]; then
            warn "[check-pkgbuild0] $PKGBUILD0 $field field is empty." >&2
            valid=0
        fi
    done

    if [[ $valid -eq 0 ]]; then
        return 1
    fi
    return 0
} 