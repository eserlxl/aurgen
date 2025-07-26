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

# Source tool mapping functions
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"

# Configuration
# Note: Using git ls-files with filter_pkgbuild_sources instead of find for better performance

# Detect dependencies from README.md files
# Usage: detect_readme_deps
# Returns: space-separated list of dependencies found in README
detect_readme_deps() {
    local readme_deps=()
    local readme_file=""
    
    # Look for README files (case-insensitive)
    for readme in README.md README.txt README.rst README; do
        if [[ -f "$PROJECT_ROOT/$readme" ]]; then
            readme_file="$PROJECT_ROOT/$readme"
            break
        fi
    done
    
    if [[ -z "$readme_file" ]]; then
        return 0
    fi
    
    debug "[detect_readme_deps] Found README file: $readme_file"
    
    # Extract dependencies from README content
    local content
    content=$(cat "$readme_file" 2>/dev/null || true)
    
    if [[ -z "$content" ]]; then
        return 0
    fi
    
    # Look for specific dependency patterns in the content
    # Focus on installation/requirements sections and package manager commands
    
    # 1. Look for pacman install commands (most precise)
    local pacman_deps
    pacman_deps=$(echo "$content" | grep -o -E 'pacman\s+-S\s+[a-zA-Z0-9_-]+(\s+[a-zA-Z0-9_-]+)*' | sed 's/pacman\s+-S\s*//' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 2. Look for apt install commands
    local apt_deps
    apt_deps=$(echo "$content" | grep -o -E 'apt\s+(install|get\s+install)\s+[a-zA-Z0-9_-]+(\s+[a-zA-Z0-9_-]+)*' | sed 's/apt\s\+\(install\|get\s\+install\)\s*//' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 3. Look for yum install commands
    local yum_deps
    yum_deps=$(echo "$content" | grep -o -E 'yum\s+install\s+[a-zA-Z0-9_-]+(\s+[a-zA-Z0-9_-]+)*' | sed 's/yum\s\+install\s*//' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 4. Look for brew install commands
    local brew_deps
    brew_deps=$(echo "$content" | grep -o -E 'brew\s+install\s+[a-zA-Z0-9_-]+(\s+[a-zA-Z0-9_-]+)*' | sed 's/brew\s\+install\s*//' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 5. Look for specific dependency sections with package lists
    # Focus on sections that explicitly list packages
    local section_deps
    section_deps=$(echo "$content" | awk '
    BEGIN { in_deps_section = 0; deps = "" }
    /^##?\s*(Installation|Requirements|Dependencies|Prerequisites|Build Dependencies|Make Dependencies)/i { in_deps_section = 1; next }
    /^##?\s*[^#]/ { in_deps_section = 0 }
    in_deps_section && /^\s*[-*+]\s*[a-zA-Z0-9_-]+/ { 
        gsub(/^\s*[-*+]\s*/, ""); 
        gsub(/\s*[:;].*$/, ""); 
        if ($0 ~ /^[a-zA-Z0-9_-]+$/) deps = deps " " $0 
    }
    in_deps_section && /^\s*[a-zA-Z0-9_-]+\s*[:;]/ { 
        gsub(/\s*[:;].*$/, ""); 
        if ($0 ~ /^[a-zA-Z0-9_-]+$/) deps = deps " " $0 
    }
    END { print deps }
    ' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 6. Look for explicit dependency declarations in markdown lists
    # This is the most precise method - look for "Required:" and "Optional:" sections
    local explicit_deps
    explicit_deps=$(echo "$content" | grep -A1 -B1 "Required\|Optional" | sed -n "s/.*\`\([a-zA-Z0-9_-]*\)\`.*/\1/p" | tr '\n' ' ' || true)
    
    # Combine all detected dependencies
    local all_deps
    all_deps=$(printf '%s\n%s\n%s\n%s\n%s\n%s' "$pacman_deps" "$apt_deps" "$yum_deps" "$brew_deps" "$section_deps" "$explicit_deps" | tr ' ' '\n' | sort -u | grep -v '^$' || true)
    
    # Filter for valid package names and add to dependencies
    while IFS= read -r dep; do
        if [[ -n "$dep" && "$dep" =~ ^[a-zA-Z0-9_-]+$ && ${#dep} -gt 1 ]]; then
            # Skip common false positives
            if [[ ! "$dep" =~ ^(install|require|depend|prerequisite|build|the|and|or|with|from|to|for|in|on|at|by|of|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|could|should|may|might|can|must|shall|package|version|latest|stable|dev|master|main|branch|commit|tag|release|download|clone|git|repo|url|https|http|www|com|org|net|io|github|gitlab|bitbucket|pacman|apt|yum|brew|sudo)$ ]]; then
                # Map tool names to their containing packages
                local mapped_dep
                mapped_dep=$(map_tool_to_package "$dep")
                readme_deps+=("$mapped_dep")
            fi
        fi
    done <<< "$all_deps"
    
    # Remove duplicates and return
    if (( ${#readme_deps[@]} > 0 )); then
        printf '%s\n' "${readme_deps[@]}" | sort -u | tr '\n' ' '
        debug "[detect_readme_deps] Found dependencies in README: ${readme_deps[*]}"
    fi
}

# Detect makedepends based on project files
# Usage: detect_makedepends
# Returns: space-separated list of makedepends
detect_makedepends() {
    local makedepends=()
    
    # First, detect dependencies from README.md
    local readme_deps
    readme_deps=$(detect_readme_deps)
    if [[ -n "${readme_deps// }" ]]; then
        # Convert space-separated string to array
        readarray -t readme_deps_array <<< "$(echo "$readme_deps" | tr ' ' '\n')"
        makedepends+=("${readme_deps_array[@]}")
        debug "[detect_makedepends] Added README dependencies: $readme_deps"
    fi
    
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