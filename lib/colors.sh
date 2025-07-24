#!/bin/bash
# Color setup for aurgen scripts
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

# Enable color output by default, unless overridden
color_enabled=1

# --- Color Setup ---
init_colors() {
    HAVE_TPUT=0
    if command -v tput > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        HAVE_TPUT=1
    fi
    if (( color_enabled )); then
        if (( HAVE_TPUT )) && [[ -t 1 ]]; then
            RED="$(tput setaf 1)$(tput bold)"
            GREEN="$(tput setaf 2)$(tput bold)"
            YELLOW="$(tput setaf 3)$(tput bold)"
            SILVER="$(tput setaf 7)$(tput bold)"
            RESET="$(tput sgr0)"
        else
            if [[ -n "${BASH_VERSION:-}" ]]; then
                RED='\e[1;31m'
                GREEN='\e[1;32m'
                YELLOW='\e[1;33m'
                SILVER='\e[1;37m'
                RESET='\e[0m'
            else
                RED='\033[1;31m'
                GREEN='\033[1;32m'
                YELLOW='\033[1;33m'
                SILVER='\033[1;37m'
                RESET='\033[0m'
            fi
        fi
    else
        RED=''
        GREEN=''
        YELLOW=''
        SILVER=''
        RESET=''
    fi
} 