#!/bin/bash
# Detect build dependencies based on project files
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

# Configuration
# Note: Using git ls-files with filter_pkgbuild_sources instead of find for better performance

# Detect makedepends based on project files
# Usage: detect_makedepends
# Returns: space-separated list of makedepends
detect_makedepends() {
    local makedepends=()
    
    # Check for CMake
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]]; then
        makedepends+=("cmake")
        makedepends+=("make")
    fi
    
    # Check for Makefile
    if [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        makedepends+=("make")
    fi
    
    # Check for Python setup.py
    if [[ -f "$PROJECT_ROOT/setup.py" ]]; then
        makedepends+=("python-setuptools")
    fi
    
    # Check for package.json (Node.js)
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        makedepends+=("npm")
    fi
    
    # Check for C++ files using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(cpp|cc|cxx|c\+\+)$' | grep -q .; then
        makedepends+=("gcc")
    fi
    
    # Check for C files using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.c$' | grep -q .; then
        makedepends+=("gcc")
    fi
    
    # Check for Rust (Cargo.toml)
    if [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        makedepends+=("rust")
        makedepends+=("cargo")
    fi
    
    # Check for Go (go.mod)
    if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
        makedepends+=("go")
    fi
    
    # Check for Java (pom.xml or build.gradle)
    if [[ -f "$PROJECT_ROOT/pom.xml" ]]; then
        makedepends+=("maven")
        makedepends+=("jdk-openjdk")
    fi
    
    if [[ -f "$PROJECT_ROOT/build.gradle" ]]; then
        makedepends+=("gradle")
        makedepends+=("jdk-openjdk")
    fi
    
    # Check for Meson
    if [[ -f "$PROJECT_ROOT/meson.build" ]]; then
        makedepends+=("meson")
        makedepends+=("ninja")
    fi
    
    # Check for Autotools
    if [[ -f "$PROJECT_ROOT/configure.ac" ]] || [[ -f "$PROJECT_ROOT/configure.in" ]]; then
        makedepends+=("autoconf")
        makedepends+=("automake")
        makedepends+=("libtool")
        makedepends+=("make")
    fi
    
    # Check for qmake
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] && grep -q "find_package(Qt" "$PROJECT_ROOT/CMakeLists.txt"; then
        makedepends+=("qt6-base")
    elif git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.pro$' | grep -q .; then
        makedepends+=("qt6-base")
    fi
    
    # Check for Vala using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.vala$' | grep -q .; then
        makedepends+=("vala")
    fi
    
    # Check for TypeScript using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(ts|tsx)$' | grep -q .; then
        makedepends+=("typescript")
    fi
    
    # Check for SCSS/SASS using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(scss|sass)$' | grep -q .; then
        makedepends+=("sassc")
    fi
    
    # Check for YAML/JSON processing (common in modern projects)
    if [[ -f "$PROJECT_ROOT/package.json" ]] || git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(yaml|yml)$' | grep -q .; then
        makedepends+=("jq")
    fi
    
    # Check for pkg-config (common dependency) using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.pc\.in$' | grep -q .; then
        makedepends+=("pkgconf")
    fi
    
    # Check for gettext (internationalization) using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(po|pot)$' | grep -q .; then
        makedepends+=("gettext")
    fi
    
    # Check for asciidoc documentation using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.adoc$' | grep -q .; then
        makedepends+=("asciidoc")
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${makedepends[@]}" | sort -u | tr '\n' ' '
} 