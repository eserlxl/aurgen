#!/bin/bash
# Tool to package mapping for Arch Linux
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

set -euo pipefail

# Map tool names to their containing packages
# Usage: map_tool_to_package <tool_name>
# Returns: package name that contains the tool
map_tool_to_package() {
    local tool="$1"
    
    # Tool to package mapping for Arch Linux
    case "$tool" in
        # Core system tools
        getopt) echo "util-linux" ;;
        updpkgsums) echo "pacman-contrib" ;;
        makepkg) echo "pacman" ;;
        
        # Package managers
        cargo) echo "rust" ;;
        
        # Development tools
        node) echo "nodejs" ;;
        java) echo "jdk-openjdk" ;;
        
        # Utilities
        gpg) echo "gnupg" ;;
        gh) echo "github-cli" ;;
        
        # Languages and frameworks
        pkg-config) echo "pkgconf" ;;
        
        # Qt and GTK
        qt) echo "qt6-base" ;;
        gtk) echo "gtk3" ;;
        glib) echo "glib2" ;;
        
        # Default: return the tool name as-is if no mapping exists
        *) echo "$tool" ;;
    esac
} 