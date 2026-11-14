#!/bin/bash
# Color setup for AURGen scripts
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

# Enable color output by default, unless overridden
color_enabled=${color_enabled:-1}

# --- Color Setup ---
init_colors() {
    # NO_COLOR (https://no-color.org/) and non-terminals never get escapes.
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
        color_enabled=0
    fi
    HAVE_TPUT=0
    if (( color_enabled )) \
        && command -v tput > /dev/null 2>&1 \
        && tput setaf 1 > /dev/null 2>&1 \
        && tput bold > /dev/null 2>&1 \
        && tput sgr0 > /dev/null 2>&1; then
        HAVE_TPUT=1
    fi
    if (( color_enabled )); then
        if (( HAVE_TPUT )); then
            RED="$(tput setaf 1)$(tput bold)"
            GREEN="$(tput setaf 2)$(tput bold)"
            YELLOW="$(tput setaf 3)$(tput bold)"
            SILVER="$(tput setaf 7)$(tput bold)"
            CYAN=$'\033[1;36m'
            RESET="$(tput sgr0)"
        else
            RED=$'\033[1;31m'
            GREEN=$'\033[1;32m'
            YELLOW=$'\033[1;33m'
            SILVER=$'\033[1;37m'
            CYAN=$'\033[1;36m'
            RESET=$'\033[0m'
        fi
    else
        RED=''
        GREEN=''
        YELLOW=''
        SILVER=''
        CYAN=''
        RESET=''
    fi
    # Export color variables for use in scripts that source this file
    export RED GREEN YELLOW SILVER CYAN RESET
} 