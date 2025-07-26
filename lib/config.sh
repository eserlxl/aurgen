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
# Using arrays to store YAML-like data structures (compatible with older bash)
DEFAULT_COPY_RULES_BIN="usr/bin:executable:"
DEFAULT_COPY_RULES_LIB="usr/lib/\$pkgname:read-only:"
DEFAULT_COPY_RULES_ETC="etc/\$pkgname:read-only:"
DEFAULT_COPY_RULES_SHARE="usr/share/\$pkgname:read-only:"
DEFAULT_COPY_RULES_INCLUDE="usr/include/\$pkgname:read-only:"
DEFAULT_COPY_RULES_LOCAL="usr/local/\$pkgname:read-only:"
DEFAULT_COPY_RULES_VAR="var/\$pkgname:read-only:"
DEFAULT_COPY_RULES_OPT="opt/\$pkgname:read-only:"

# Global variables to store parsed YAML configuration
COPY_RULES_BIN=""
COPY_RULES_LIB=""
COPY_RULES_ETC=""
COPY_RULES_SHARE=""
COPY_RULES_INCLUDE=""
COPY_RULES_LOCAL=""
COPY_RULES_VAR=""
COPY_RULES_OPT=""

# Load configuration from aurgen.install.yaml if it exists
# Usage: load_aurgen_config
load_aurgen_config() {
    local aur_config_file="$AUR_DIR/aurgen.install.yaml"
    
    # Initialize with defaults
    COPY_RULES_BIN="$DEFAULT_COPY_RULES_BIN"
    COPY_RULES_LIB="$DEFAULT_COPY_RULES_LIB"
    COPY_RULES_ETC="$DEFAULT_COPY_RULES_ETC"
    COPY_RULES_SHARE="$DEFAULT_COPY_RULES_SHARE"
    COPY_RULES_INCLUDE="$DEFAULT_COPY_RULES_INCLUDE"
    COPY_RULES_LOCAL="$DEFAULT_COPY_RULES_LOCAL"
    COPY_RULES_VAR="$DEFAULT_COPY_RULES_VAR"
    COPY_RULES_OPT="$DEFAULT_COPY_RULES_OPT"
    
    # Try to load from aur directory (project-specific location)
    if [[ -f "$aur_config_file" && -r "$aur_config_file" ]]; then
        debug "[config] Loading configuration from $aur_config_file"
        
        # Clear existing variables and reload from file
        COPY_RULES_BIN=""
        COPY_RULES_LIB=""
        COPY_RULES_ETC=""
        COPY_RULES_SHARE=""
        COPY_RULES_INCLUDE=""
        COPY_RULES_LOCAL=""
        COPY_RULES_VAR=""
        COPY_RULES_OPT=""
        
        # Parse YAML configuration
        parse_yaml_config "$aur_config_file"
    fi
}

# Parse YAML configuration file
# Usage: parse_yaml_config <config_file>
parse_yaml_config() {
    local config_file="$1"
    local current_section=""
    local source_dir=""
    local dest_dir=""
    local permissions=""
    local excludes=""
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check for section headers (e.g., "executables:")
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            # Save previous section if we have one
            if [[ -n "$current_section" && -n "$source_dir" && -n "$dest_dir" && -n "$permissions" ]]; then
                local rule="$dest_dir:$permissions:$excludes"
                case "$source_dir" in
                    bin) COPY_RULES_BIN="$rule" ;;
                    lib) COPY_RULES_LIB="$rule" ;;
                    etc) COPY_RULES_ETC="$rule" ;;
                    share) COPY_RULES_SHARE="$rule" ;;
                    include) COPY_RULES_INCLUDE="$rule" ;;
                    local) COPY_RULES_LOCAL="$rule" ;;
                    var) COPY_RULES_VAR="$rule" ;;
                    opt) COPY_RULES_OPT="$rule" ;;
                esac
                debug "[config] Added copy rule: $source_dir -> $rule"
            fi
            
            # Start new section
            current_section="${BASH_REMATCH[1]}"
            source_dir=""
            dest_dir=""
            permissions=""
            excludes=""
            continue
        fi
        
        # Parse key-value pairs
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            
            case "$key" in
                source)
                    source_dir="$value"
                    ;;
                destination)
                    dest_dir="$value"
                    ;;
                permissions)
                    permissions="$value"
                    ;;
                exclude)
                    # Handle array format [item1,item2] or empty []
                    if [[ "$value" == "[]" ]]; then
                        excludes=""
                    elif [[ "$value" =~ ^\[(.*)\]$ ]]; then
                        excludes="${BASH_REMATCH[1]}"
                    else
                        excludes="$value"
                    fi
                    ;;
            esac
        fi
    done < "$config_file"
    
    # Don't forget the last section
    if [[ -n "$current_section" && -n "$source_dir" && -n "$dest_dir" && -n "$permissions" ]]; then
        local rule="$dest_dir:$permissions:$excludes"
        case "$source_dir" in
            bin) COPY_RULES_BIN="$rule" ;;
            lib) COPY_RULES_LIB="$rule" ;;
            etc) COPY_RULES_ETC="$rule" ;;
            share) COPY_RULES_SHARE="$rule" ;;
            include) COPY_RULES_INCLUDE="$rule" ;;
            local) COPY_RULES_LOCAL="$rule" ;;
            var) COPY_RULES_VAR="$rule" ;;
            opt) COPY_RULES_OPT="$rule" ;;
        esac
        debug "[config] Added copy rule: $source_dir -> $rule"
    fi
}

# Generate default configuration file
# Usage: generate_default_config [config_file_path]
generate_default_config() {
    local config_file="${1:-$AUR_DIR/aurgen.install.yaml}"
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
    
    # Generate the YAML configuration file
    cat > "$config_file" <<EOF
# AURGen Install Configuration File
# This file controls which directories are copied during package installation
# Each section defines what gets installed and where

# Executable files
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []

# Library files
libraries:
  source: lib
  destination: usr/lib/\$pkgname
  permissions: read-only
  exclude: []

# Configuration files
config:
  source: etc
  destination: etc/\$pkgname
  permissions: read-only
  exclude: []

# Shared data files
shared_data:
  source: share
  destination: usr/share/\$pkgname
  permissions: read-only
  exclude: []

# Header files
headers:
  source: include
  destination: usr/include/\$pkgname
  permissions: read-only
  exclude: []

# Local data files
local_data:
  source: local
  destination: usr/local/\$pkgname
  permissions: read-only
  exclude: []

# Variable data files
variable_data:
  source: var
  destination: var/\$pkgname
  permissions: read-only
  exclude: []

# Optional data files
optional_data:
  source: opt
  destination: opt/\$pkgname
  permissions: read-only
  exclude: []
EOF
    
    log "[config] Generated default configuration file: $config_file"
    echo -e "${YELLOW}[config] You can now edit $config_file to customize directory copying behavior.${RESET}" >&2
}

# Generate example configuration file
# Usage: generate_example_config [config_file_path]
generate_example_config() {
    local config_file="${1:-$AUR_DIR/aurgen.install.yaml.example}"
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
    
    # Generate the example YAML configuration file
    cat > "$config_file" <<EOF
# AURGen Install Configuration File Example
# This file controls which directories are copied during package installation
# Each section defines what gets installed and where

# Executable files
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []

# Library files
libraries:
  source: lib
  destination: usr/lib/\$pkgname
  permissions: read-only
  exclude: []

# Configuration files
config:
  source: etc
  destination: etc/\$pkgname
  permissions: read-only
  exclude: []

# Configuration files with exclusions (exclude test/ and temp/ subdirectories)
config_with_exclusions:
  source: etc
  destination: etc/\$pkgname
  permissions: read-only
  exclude: [test, temp]

# Shared data files
shared_data:
  source: share
  destination: usr/share/\$pkgname
  permissions: read-only
  exclude: []

# Header files (commented out - won't copy include/)
# headers:
#   source: include
#   destination: usr/include/\$pkgname
#   permissions: read-only
#   exclude: []

# Local data files
local_data:
  source: local
  destination: usr/local/\$pkgname
  permissions: read-only
  exclude: []

# Variable data files
variable_data:
  source: var
  destination: var/\$pkgname
  permissions: read-only
  exclude: []

# Optional data files
optional_data:
  source: opt
  destination: opt/\$pkgname
  permissions: read-only
  exclude: []

# Custom example - uncomment and modify as needed
# custom_data:
#   source: custom
#   destination: usr/share/\$pkgname/custom
#   permissions: read-only
#   exclude: [backup, temp]
EOF
    
    debug "[config] Generated example configuration file: $config_file"
}

# Validate configuration
# Usage: validate_config
validate_config() {
    local valid=1
    
    # Check each rule variable
    local rules=(
        "bin:COPY_RULES_BIN"
        "lib:COPY_RULES_LIB"
        "etc:COPY_RULES_ETC"
        "share:COPY_RULES_SHARE"
        "include:COPY_RULES_INCLUDE"
        "local:COPY_RULES_LOCAL"
        "var:COPY_RULES_VAR"
        "opt:COPY_RULES_OPT"
    )
    
    for rule_pair in "${rules[@]}"; do
        IFS=':' read -r source_dir var_name <<< "$rule_pair"
        local rule
        case "$var_name" in
            COPY_RULES_BIN) rule="$COPY_RULES_BIN" ;;
            COPY_RULES_LIB) rule="$COPY_RULES_LIB" ;;
            COPY_RULES_ETC) rule="$COPY_RULES_ETC" ;;
            COPY_RULES_SHARE) rule="$COPY_RULES_SHARE" ;;
            COPY_RULES_INCLUDE) rule="$COPY_RULES_INCLUDE" ;;
            COPY_RULES_LOCAL) rule="$COPY_RULES_LOCAL" ;;
            COPY_RULES_VAR) rule="$COPY_RULES_VAR" ;;
            COPY_RULES_OPT) rule="$COPY_RULES_OPT" ;;
        esac
        
        if [[ -n "$rule" ]]; then
            IFS=':' read -r dest_dir permissions excludes <<< "$rule"
            
            # Validate required fields
            if [[ -z "$dest_dir" || -z "$permissions" ]]; then
                warn "[config] Invalid configuration rule for $source_dir: missing destination or permissions"
                valid=0
                continue
            fi
            
            # Validate permissions format
            case "$permissions" in
                executable|read-only|readonly)
                    # Valid human-readable permissions
                    ;;
                [0-7][0-7][0-7])
                    # Valid octal permissions
                    ;;
                *)
                    warn "[config] Invalid permissions '$permissions' for $source_dir"
                    valid=0
                    ;;
            esac
        fi
    done
    return $((1 - valid))
}

# Get copy directories for use in PKGBUILD generation
# Usage: get_copy_directories
get_copy_directories() {
    # Load configuration if not already loaded
    if [[ -z "$COPY_RULES_BIN$COPY_RULES_LIB$COPY_RULES_ETC$COPY_RULES_SHARE$COPY_RULES_INCLUDE$COPY_RULES_LOCAL$COPY_RULES_VAR$COPY_RULES_OPT" ]]; then
        load_aurgen_config
    fi
    
    # Validate configuration
    if ! validate_config; then
        warn "[config] Configuration validation failed, using defaults"
        COPY_RULES_BIN="$DEFAULT_COPY_RULES_BIN"
        COPY_RULES_LIB="$DEFAULT_COPY_RULES_LIB"
        COPY_RULES_ETC="$DEFAULT_COPY_RULES_ETC"
        COPY_RULES_SHARE="$DEFAULT_COPY_RULES_SHARE"
        COPY_RULES_INCLUDE="$DEFAULT_COPY_RULES_INCLUDE"
        COPY_RULES_LOCAL="$DEFAULT_COPY_RULES_LOCAL"
        COPY_RULES_VAR="$DEFAULT_COPY_RULES_VAR"
        COPY_RULES_OPT="$DEFAULT_COPY_RULES_OPT"
    fi
    
    # Convert to the format expected by gen-pkgbuild0.sh
    local rules=(
        "bin:COPY_RULES_BIN"
        "lib:COPY_RULES_LIB"
        "etc:COPY_RULES_ETC"
        "share:COPY_RULES_SHARE"
        "include:COPY_RULES_INCLUDE"
        "local:COPY_RULES_LOCAL"
        "var:COPY_RULES_VAR"
        "opt:COPY_RULES_OPT"
    )
    
    for rule_pair in "${rules[@]}"; do
        IFS=':' read -r source_dir var_name <<< "$rule_pair"
        local rule
        case "$var_name" in
            COPY_RULES_BIN) rule="$COPY_RULES_BIN" ;;
            COPY_RULES_LIB) rule="$COPY_RULES_LIB" ;;
            COPY_RULES_ETC) rule="$COPY_RULES_ETC" ;;
            COPY_RULES_SHARE) rule="$COPY_RULES_SHARE" ;;
            COPY_RULES_INCLUDE) rule="$COPY_RULES_INCLUDE" ;;
            COPY_RULES_LOCAL) rule="$COPY_RULES_LOCAL" ;;
            COPY_RULES_VAR) rule="$COPY_RULES_VAR" ;;
            COPY_RULES_OPT) rule="$COPY_RULES_OPT" ;;
        esac
        
        if [[ -n "$rule" ]]; then
            IFS=':' read -r dest_dir permissions excludes <<< "$rule"
            
            # Convert human-readable permissions to octal
            local octal_perms
            case "$permissions" in
                executable)
                    octal_perms="755"
                    ;;
                read-only|readonly)
                    octal_perms="644"
                    ;;
                *)
                    octal_perms="$permissions"
                    ;;
            esac
            
            local output="$source_dir:$dest_dir:$octal_perms"
            [[ -n "$excludes" ]] && output="$output:$excludes"
            printf '%s\n' "$output"
        fi
    done
} 