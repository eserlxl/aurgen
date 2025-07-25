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
        
        # Build tools
        cmake) echo "cmake" ;;
        make) echo "make" ;;
        gcc) echo "gcc" ;;
        clang) echo "clang" ;;
        
        # Package managers
        npm) echo "npm" ;;
        cargo) echo "rust" ;;
        maven) echo "maven" ;;
        gradle) echo "gradle" ;;
        
        # Development tools
        python) echo "python" ;;
        node) echo "nodejs" ;;
        rust) echo "rust" ;;
        go) echo "go" ;;
        java) echo "jdk-openjdk" ;;
        
        # Build systems
        meson) echo "meson" ;;
        ninja) echo "ninja" ;;
        autoconf) echo "autoconf" ;;
        automake) echo "automake" ;;
        libtool) echo "libtool" ;;
        
        # Utilities
        curl) echo "curl" ;;
        jq) echo "jq" ;;
        gpg) echo "gnupg" ;;
        gh) echo "github-cli" ;;
        shellcheck) echo "shellcheck" ;;
        bash) echo "bash" ;;
        
        # Documentation
        asciidoc) echo "asciidoc" ;;
        sassc) echo "sassc" ;;
        
        # Languages and frameworks
        typescript) echo "typescript" ;;
        vala) echo "vala" ;;
        pkg-config) echo "pkgconf" ;;
        pkgconf) echo "pkgconf" ;;
        gettext) echo "gettext" ;;
        
        # Qt and GTK
        qt) echo "qt6-base" ;;
        gtk) echo "gtk3" ;;
        glib) echo "glib2" ;;
        
        # Git
        git) echo "git" ;;
        
        # Default: return the tool name as-is if no mapping exists
        *) echo "$tool" ;;
    esac
} 