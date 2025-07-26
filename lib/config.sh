#!/bin/bash
# Configuration system for AURGen
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Configuration file handling for AURGen

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Default directory configuration for PKGBUILD package() function
# Format: "source_dir:dest_dir:permissions"
# Example: "bin:usr/bin:755"
declare -a DEFAULT_COPY_DIRS=(
    "bin:usr/bin:755"
    "lib:usr/lib/\$pkgname:644"
    "etc:etc/\$pkgname:644"
    "share:usr/share/\$pkgname:644"
    "include:usr/include/\$pkgname:644"
    "local:usr/local/\$pkgname:644"
    "var:var/\$pkgname:644"
    "opt:opt/\$pkgname:644"
)

# Load configuration from aurgen.install.conf if it exists
# Usage: load_aurgen_config
load_aurgen_config() {
    local aur_config_file="$AUR_DIR/aurgen.install.conf"
    
    # Initialize with defaults
    COPY_DIRS=("${DEFAULT_COPY_DIRS[@]}")
    
    # Try to load from aur directory (project-specific location)
    if [[ -f "$aur_config_file" && -r "$aur_config_file" ]]; then
        debug "[config] Loading configuration from $aur_config_file"
        
        # Clear existing array and reload from file
        COPY_DIRS=()
        
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Validate format: source:dest:permissions
            if [[ "$line" =~ ^[^:]+:[^:]+:[0-7]{3}$ ]]; then
                COPY_DIRS+=("$line")
                debug "[config] Added copy rule: $line"
            else
                warn "[config] Invalid format in $aur_config_file: $line (expected: source:dest:permissions)"
            fi
        done < "$aur_config_file"
    fi
    

}

# Generate default configuration file
# Usage: generate_default_config [config_file_path]
generate_default_config() {
    local config_file="${1:-$AUR_DIR/aurgen.install.conf}"
    local config_dir
    config_dir=$(dirname "$config_file")
    
    # Create directory if it doesn't exist
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
    fi
    
    # Don't overwrite existing configuration file
    if [[ -f "$config_file" ]]; then
        warn "[config] Configuration file already exists: $config_file"
        warn "[config] Use 'aurgen config edit' to modify it, or 'aurgen config reset' to regenerate."
        return 1
    fi
    
    # Generate the configuration file
    cat > "$config_file" <<EOF
# AURGen Install Configuration File
# This file controls which directories are copied during package installation
# Format: source_dir:dest_dir:permissions
# 
# Examples:
# bin:usr/bin:755          # Copy bin/ to usr/bin/ with executable permissions
# lib:usr/lib/\$pkgname:644 # Copy lib/ to usr/lib/\$pkgname/ with read permissions
# etc:etc/\$pkgname:644     # Copy etc/ to etc/\$pkgname/ with read permissions
#
# To disable copying a directory, comment out or remove its line
# To add custom directories, add new lines following the same format

EOF
    
    # Add default rules with comments
    for dir_rule in "${DEFAULT_COPY_DIRS[@]}"; do
        IFS=':' read -r src dest perms <<< "$dir_rule"
        case "$src" in
            bin)
                echo "# Executable files" >> "$config_file"
                ;;
            lib)
                echo "# Library files" >> "$config_file"
                ;;
            etc)
                echo "# Configuration files" >> "$config_file"
                ;;
            share)
                echo "# Shared data files" >> "$config_file"
                ;;
            include)
                echo "# Header files" >> "$config_file"
                ;;
            local)
                echo "# Local data files" >> "$config_file"
                ;;
            var)
                echo "# Variable data files" >> "$config_file"
                ;;
            opt)
                echo "# Optional data files" >> "$config_file"
                ;;
        esac
        echo "$dir_rule" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    log "[config] Generated default configuration file: $config_file"
    echo -e "${YELLOW}[config] You can now edit $config_file to customize directory copying behavior.${RESET}" >&2
}

# Generate example configuration file
# Usage: generate_example_config [config_file_path]
generate_example_config() {
    local config_file="${1:-$AUR_DIR/aurgen.install.conf.example}"
    local config_dir
    config_dir=$(dirname "$config_file")
    
    # Create directory if it doesn't exist
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
    fi
    
    # Don't overwrite existing example file
    if [[ -f "$config_file" ]]; then
        debug "[config] Example configuration file already exists: $config_file"
        return 0
    fi
    
    # Generate the example configuration file
    cat > "$config_file" <<EOF
# AURGen Install Configuration File Example
# This file controls which directories are copied during package installation
# Format: source_dir:dest_dir:permissions
# 
# Examples:
# bin:usr/bin:755          # Copy bin/ to usr/bin/ with executable permissions
# lib:usr/lib/\$pkgname:644 # Copy lib/ to usr/lib/\$pkgname/ with read permissions
# etc:etc/\$pkgname:644     # Copy etc/ to etc/\$pkgname/ with read permissions
#
# To disable copying a directory, comment out or remove its line
# To add custom directories, add new lines following the same format

# Executable files
bin:usr/bin:755

# Library files
lib:usr/lib/\$pkgname:644

# Configuration files
etc:etc/\$pkgname:644

# Shared data files
share:usr/share/\$pkgname:644

# Header files (commented out - won't copy include/)
# include:usr/include/\$pkgname:644

# Local data files
local:usr/local/\$pkgname:644

# Variable data files
var:var/\$pkgname:644

# Optional data files
opt:opt/\$pkgname:644

# Custom example - uncomment and modify as needed
# custom:usr/share/\$pkgname/custom:644
EOF
    
    debug "[config] Generated example configuration file: $config_file"
}

# Validate configuration
# Usage: validate_config
validate_config() {
    local valid=1
    
    for dir_rule in "${COPY_DIRS[@]}"; do
        if [[ ! "$dir_rule" =~ ^[^:]+:[^:]+:[0-7]{3}$ ]]; then
            warn "[config] Invalid configuration rule: $dir_rule"
            valid=0
            continue
        fi
        
        # Check permissions are reasonable
        IFS=':' read -r src dest perms <<< "$dir_rule"
        if [[ ! "$perms" =~ ^[0-7]{3}$ ]]; then
            warn "[config] Invalid permissions in rule: $dir_rule"
            valid=0
        fi
    done
    return $((1 - valid))
}

# Get copy directories for use in PKGBUILD generation
# Usage: get_copy_directories
get_copy_directories() {
    # Load configuration if not already loaded
    if [[ -z "${COPY_DIRS:-}" ]]; then
        load_aurgen_config
    fi
    
    # Validate configuration
    if ! validate_config; then
        warn "[config] Configuration validation failed, using defaults"
        COPY_DIRS=("${DEFAULT_COPY_DIRS[@]}")
    fi
    
    printf '%s\n' "${COPY_DIRS[@]}"
} 