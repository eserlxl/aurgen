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
    
    # 7. Look for specific tool mentions in installation sections
    local tool_deps
    tool_deps=$(echo "$content" | awk '
    BEGIN { in_install_section = 0; tools = "" }
    /^##?\s*(Installation|Install|Setup|Getting Started)/i { in_install_section = 1; next }
    /^##?\s*[^#]/ { in_install_section = 0 }
    in_install_section && /[[:space:]]*(bash|curl|jq|gpg|gh|shellcheck|getopt|makepkg|updpkgsums)[[:space:]]/ { 
        gsub(/[[:space:]]*(bash|curl|jq|gpg|gh|shellcheck|getopt|makepkg|updpkgsums)[[:space:]]/, " \\1 "); 
        split($0, arr, " "); 
        for (i in arr) { 
            if (arr[i] ~ /^(bash|curl|jq|gpg|gh|shellcheck|getopt|makepkg|updpkgsums)$/) 
                tools = tools " " arr[i] 
        }
    }
    END { print tools }
    ' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 8. Look for package manager hints and installation commands
    local pkg_hints
    pkg_hints=$(echo "$content" | grep -o -E 'pacman\s+-S\s+[a-zA-Z0-9_-]+' | sed 's/pacman\s+-S\s*//' | tr '\n' ' ' || true)
    
    # Combine all detected dependencies
    local all_deps
    all_deps=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' "$pacman_deps" "$apt_deps" "$yum_deps" "$brew_deps" "$section_deps" "$explicit_deps" "$tool_deps" "$pkg_hints" | tr ' ' '\n' | sort -u | grep -v '^$' || true)
    
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
    
    # Check for bash scripts (common in shell utilities)
    local bash_scripts
    bash_scripts=$(git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(sh|bash)$' | grep -v '^$' || true)
    if [[ -n "$bash_scripts" ]]; then
        local mapped_bash
        mapped_bash=$(map_tool_to_package "bash")
        makedepends+=("$mapped_bash")
        
        # Check if any bash scripts use specific tools
        local script_content
        script_content=$(cat $(echo "$bash_scripts" | head -5 | tr '\n' ' ') 2>/dev/null || true)
        
        # Check for common shell tools used in bash scripts
        if echo "$script_content" | grep -q -E '\bcurl\b'; then
            local mapped_curl
            mapped_curl=$(map_tool_to_package "curl")
            makedepends+=("$mapped_curl")
        fi
        if echo "$script_content" | grep -q -E '\bjq\b'; then
            local mapped_jq
            mapped_jq=$(map_tool_to_package "jq")
            makedepends+=("$mapped_jq")
        fi
        if echo "$script_content" | grep -q -E '\bgpg\b'; then
            local mapped_gpg
            mapped_gpg=$(map_tool_to_package "gpg")
            makedepends+=("$mapped_gpg")
        fi
        if echo "$script_content" | grep -q -E '\bgh\b'; then
            local mapped_gh
            mapped_gh=$(map_tool_to_package "gh")
            makedepends+=("$mapped_gh")
        fi
        if echo "$script_content" | grep -q -E '\bshellcheck\b'; then
            local mapped_shellcheck
            mapped_shellcheck=$(map_tool_to_package "shellcheck")
            makedepends+=("$mapped_shellcheck")
        fi
        if echo "$script_content" | grep -q -E '\bgetopt\b'; then
            local mapped_getopt
            mapped_getopt=$(map_tool_to_package "getopt")
            makedepends+=("$mapped_getopt")
        fi
        if echo "$script_content" | grep -q -E '\bmakepkg\b'; then
            local mapped_makepkg
            mapped_makepkg=$(map_tool_to_package "makepkg")
            makedepends+=("$mapped_makepkg")
        fi
        if echo "$script_content" | grep -q -E '\bupdpkgsums\b'; then
            local mapped_updpkgsums
            mapped_updpkgsums=$(map_tool_to_package "updpkgsums")
            makedepends+=("$mapped_updpkgsums")
        fi
    fi
    
    # Check for shellcheck usage (common in bash projects)
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(sh|bash)$' | grep -q .; then
        # Check if shellcheck is mentioned in any files
        local shellcheck_usage
        shellcheck_usage=$(git -C "$PROJECT_ROOT" grep -l -i "shellcheck" 2>/dev/null || true)
        if [[ -n "$shellcheck_usage" ]]; then
            local mapped_shellcheck
            mapped_shellcheck=$(map_tool_to_package "shellcheck")
            makedepends+=("$mapped_shellcheck")
        fi
    fi
    
    # Check for CMake
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]]; then
        local mapped_cmake
        mapped_cmake=$(map_tool_to_package "cmake")
        makedepends+=("$mapped_cmake")
        local mapped_make
        mapped_make=$(map_tool_to_package "make")
        makedepends+=("$mapped_make")
    fi
    
    # Check for Makefile
    if [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        local mapped_make
        mapped_make=$(map_tool_to_package "make")
        makedepends+=("$mapped_make")
    fi
    
    # Check for Python setup.py
    if [[ -f "$PROJECT_ROOT/setup.py" ]]; then
        local mapped_setuptools
        mapped_setuptools=$(map_tool_to_package "python-setuptools")
        makedepends+=("$mapped_setuptools")
    fi
    
    # Check for package.json (Node.js)
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        local mapped_npm
        mapped_npm=$(map_tool_to_package "npm")
        makedepends+=("$mapped_npm")
    fi
    
    # Check for C++ files using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(cpp|cc|cxx|c\+\+)$' | grep -q .; then
        local mapped_gcc
        mapped_gcc=$(map_tool_to_package "gcc")
        makedepends+=("$mapped_gcc")
    fi
    
    # Check for C files using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.c$' | grep -q .; then
        local mapped_gcc
        mapped_gcc=$(map_tool_to_package "gcc")
        makedepends+=("$mapped_gcc")
    fi
    
    # Check for Rust (Cargo.toml)
    if [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        local mapped_rust
        mapped_rust=$(map_tool_to_package "rust")
        makedepends+=("$mapped_rust")
        local mapped_cargo
        mapped_cargo=$(map_tool_to_package "cargo")
        makedepends+=("$mapped_cargo")
    fi
    
    # Check for Go (go.mod)
    if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
        local mapped_go
        mapped_go=$(map_tool_to_package "go")
        makedepends+=("$mapped_go")
    fi
    
    # Check for Java (pom.xml or build.gradle)
    if [[ -f "$PROJECT_ROOT/pom.xml" ]]; then
        local mapped_maven
        mapped_maven=$(map_tool_to_package "maven")
        makedepends+=("$mapped_maven")
        local mapped_jdk
        mapped_jdk=$(map_tool_to_package "jdk-openjdk")
        makedepends+=("$mapped_jdk")
    fi
    
    if [[ -f "$PROJECT_ROOT/build.gradle" ]]; then
        local mapped_gradle
        mapped_gradle=$(map_tool_to_package "gradle")
        makedepends+=("$mapped_gradle")
        local mapped_jdk
        mapped_jdk=$(map_tool_to_package "jdk-openjdk")
        makedepends+=("$mapped_jdk")
    fi
    
    # Check for Meson
    if [[ -f "$PROJECT_ROOT/meson.build" ]]; then
        local mapped_meson
        mapped_meson=$(map_tool_to_package "meson")
        makedepends+=("$mapped_meson")
        local mapped_ninja
        mapped_ninja=$(map_tool_to_package "ninja")
        makedepends+=("$mapped_ninja")
    fi
    
    # Check for Autotools
    if [[ -f "$PROJECT_ROOT/configure.ac" ]] || [[ -f "$PROJECT_ROOT/configure.in" ]]; then
        local mapped_autoconf
        mapped_autoconf=$(map_tool_to_package "autoconf")
        makedepends+=("$mapped_autoconf")
        local mapped_automake
        mapped_automake=$(map_tool_to_package "automake")
        makedepends+=("$mapped_automake")
        local mapped_libtool
        mapped_libtool=$(map_tool_to_package "libtool")
        makedepends+=("$mapped_libtool")
        local mapped_make
        mapped_make=$(map_tool_to_package "make")
        makedepends+=("$mapped_make")
    fi
    
    # Check for qmake
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] && grep -q "find_package(Qt" "$PROJECT_ROOT/CMakeLists.txt"; then
        local mapped_qt
        mapped_qt=$(map_tool_to_package "qt6-base")
        makedepends+=("$mapped_qt")
    elif git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.pro$' | grep -q .; then
        local mapped_qt
        mapped_qt=$(map_tool_to_package "qt6-base")
        makedepends+=("$mapped_qt")
    fi
    
    # Check for Vala using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.vala$' | grep -q .; then
        local mapped_vala
        mapped_vala=$(map_tool_to_package "vala")
        makedepends+=("$mapped_vala")
    fi
    
    # Check for TypeScript using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(ts|tsx)$' | grep -q .; then
        local mapped_typescript
        mapped_typescript=$(map_tool_to_package "typescript")
        makedepends+=("$mapped_typescript")
    fi
    
    # Check for SCSS/SASS using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(scss|sass)$' | grep -q .; then
        local mapped_sassc
        mapped_sassc=$(map_tool_to_package "sassc")
        makedepends+=("$mapped_sassc")
    fi
    
    # Check for YAML/JSON processing (common in modern projects)
    if [[ -f "$PROJECT_ROOT/package.json" ]] || git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(yaml|yml)$' | grep -q .; then
        local mapped_jq
        mapped_jq=$(map_tool_to_package "jq")
        makedepends+=("$mapped_jq")
    fi
    
    # Check for pkg-config (common dependency) using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.pc\.in$' | grep -q .; then
        local mapped_pkgconf
        mapped_pkgconf=$(map_tool_to_package "pkgconf")
        makedepends+=("$mapped_pkgconf")
    fi
    
    # Check for gettext (internationalization) using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(po|pot)$' | grep -q .; then
        local mapped_gettext
        mapped_gettext=$(map_tool_to_package "gettext")
        makedepends+=("$mapped_gettext")
    fi
    
    # Check for asciidoc documentation using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.adoc$' | grep -q .; then
        local mapped_asciidoc
        mapped_asciidoc=$(map_tool_to_package "asciidoc")
        makedepends+=("$mapped_asciidoc")
    fi
    
    # Check for GitHub CLI usage (common in AUR tools)
    if git -C "$PROJECT_ROOT" grep -l -i "github-cli\|gh " 2>/dev/null | grep -q .; then
        local mapped_gh
        mapped_gh=$(map_tool_to_package "gh")
        makedepends+=("$mapped_gh")
    fi
    
    # Check for AUR-specific tools
    if git -C "$PROJECT_ROOT" grep -l -i "aur\|PKGBUILD\|makepkg\|updpkgsums" 2>/dev/null | grep -q .; then
        local mapped_pacman
        mapped_pacman=$(map_tool_to_package "pacman")
        makedepends+=("$mapped_pacman")
        local mapped_pacman_contrib
        mapped_pacman_contrib=$(map_tool_to_package "pacman-contrib")
        makedepends+=("$mapped_pacman_contrib")
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${makedepends[@]}" | sort -u | tr '\n' ' '
} 