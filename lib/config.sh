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

# Several libraries source this file; a second source would reset the loaded PKG_* values.
[[ -n "${AURGEN_CONFIG_SH_LOADED:-}" ]] && return 0
AURGEN_CONFIG_SH_LOADED=1

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

# Package metadata from a top-level package: section. Empty when the section is absent.
PKG_NAME=""
PKG_INSTALL=""
PKG_CHECK=""
PKG_ARCH=()
PKG_DEPENDS=()
PKG_OPTDEPENDS=()
PKG_MAKEDEPENDS=()
PKG_CONFLICTS=()
PKG_PROVIDES=()
PKG_BACKUP=()
PKG_INSTALL_VARS=()
# release (default), archive, or signed-tag. Empty means release.
PKG_SOURCE=""
# description replaces the detected pkgdesc. license replaces the detected license.
PKG_DESCRIPTION=""
PKG_LICENSE=()
# post_package lines are shell code appended to package(), not package metadata.
PKG_POST_PACKAGE=()

# Same quote stripping as copy-rule values: one leading and one trailing quote.
# Strip one matching pair of outer quotes only. A shell line such as
# echo "$v" > "$f" ends with a quote that belongs to the line.
_yaml_unquote() {
    local value="$1"
    if (( ${#value} >= 2 )); then
        case "$value" in
            \"*\"|\'*\') value="${value:1:${#value}-2}" ;;
        esac
    fi
    printf '%s' "$value"
}

_yaml_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

_reset_package_vars() {
    PKG_NAME=""
    PKG_INSTALL=""
    PKG_CHECK=""
    PKG_ARCH=()
    PKG_DEPENDS=()
    PKG_OPTDEPENDS=()
    PKG_MAKEDEPENDS=()
    PKG_CONFLICTS=()
    PKG_PROVIDES=()
    PKG_BACKUP=()
    PKG_INSTALL_VARS=()
    PKG_SOURCE=""
    PKG_DESCRIPTION=""
    PKG_LICENSE=()
    PKG_POST_PACKAGE=()
}

_pkg_add() {
    local key="$1"
    local item="$2"
    case "$key" in
        arch) PKG_ARCH+=("$item") ;;
        depends) PKG_DEPENDS+=("$item") ;;
        optdepends) PKG_OPTDEPENDS+=("$item") ;;
        makedepends) PKG_MAKEDEPENDS+=("$item") ;;
        conflicts) PKG_CONFLICTS+=("$item") ;;
        provides) PKG_PROVIDES+=("$item") ;;
        backup) PKG_BACKUP+=("$item") ;;
        install_vars) PKG_INSTALL_VARS+=("$item") ;;
        license) PKG_LICENSE+=("$item") ;;
        post_package) PKG_POST_PACKAGE+=("$item") ;;
    esac
}

# Inline form is "[a, b]" and only for items that do not contain commas.
_pkg_set_inline() {
    local key="$1"
    local raw part item
    local -a parts=()
    raw="$(_yaml_trim "$2")"
    [[ "$raw" =~ ^\[(.*)\]$ ]] || return 0
    local inner="${BASH_REMATCH[1]}"
    if [[ -z "${inner//[[:space:]]}" ]]; then
        return 0
    fi
    IFS=',' read -ra parts <<< "$inner"
    for part in "${parts[@]}"; do
        item="$(_yaml_trim "$part")"
        item="$(_yaml_unquote "$item")"
        item="$(_yaml_trim "$item")"
        if [[ -n "$item" ]]; then
            _pkg_add "$key" "$item"
        fi
    done
}

# Load configuration from aurgen.install.yaml if it exists
# Usage: load_aurgen_config
load_aurgen_config() {
    local aur_config_file="$AUR_DIR/aurgen.install.yaml"

    _reset_package_vars

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
    local in_package=0
    local pkg_list_key=""
    local key value item

    _reset_package_vars

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Block-list items stay intact so optdepends can contain ": ".
        if [[ "$in_package" -eq 1 && "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
            item="$(_yaml_trim "${BASH_REMATCH[1]}")"
            item="$(_yaml_unquote "$item")"
            item="$(_yaml_trim "$item")"
            if [[ -n "$pkg_list_key" && -n "$item" ]]; then
                _pkg_add "$pkg_list_key" "$item"
            fi
            continue
        fi

        # Indented bare keys inside package: are list headers, not copy-rule sections.
        if [[ "$in_package" -eq 1 && "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            pkg_list_key="${BASH_REMATCH[1]}"
            continue
        fi

        # Check for section headers (e.g., "executables:")
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            # Save previous section if we have one
            if [[ "$in_package" -eq 0 && -n "$current_section" && -n "$source_dir" && -n "$dest_dir" && -n "$permissions" ]]; then
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
            
            # Start new section. package: is metadata, not a copy rule.
            current_section="${BASH_REMATCH[1]}"
            source_dir=""
            dest_dir=""
            permissions=""
            excludes=""
            pkg_list_key=""
            if [[ "$current_section" == "package" ]]; then
                in_package=1
            else
                in_package=0
            fi
            continue
        fi
        
        # Parse key-value pairs
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            if [[ "$in_package" -eq 1 ]]; then
                pkg_list_key=""
                # shellcheck disable=SC2034 # package fields are consumed by later generators
                case "$key" in
                    name) PKG_NAME="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                    description) PKG_DESCRIPTION="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                    install) PKG_INSTALL="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                    check) PKG_CHECK="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                    source)
                        PKG_SOURCE="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")"
                        case "$PKG_SOURCE" in
                            release|archive|signed-tag) ;;
                            *)
                                echo "[config] package.source must be release, archive, or signed-tag (got '$PKG_SOURCE')" >&2
                                return 1
                                ;;
                        esac
                        ;;
                    arch|depends|optdepends|makedepends|conflicts|provides|backup|install_vars|license|post_package)
                        _pkg_set_inline "$key" "$value"
                        ;;
                esac
                continue
            fi

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
    if [[ "$in_package" -eq 0 && -n "$current_section" && -n "$source_dir" && -n "$dest_dir" && -n "$permissions" ]]; then
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
# AURGen Configuration File
# This file contains two main sections:
# 1. Package Installation: Controls which directories are copied during package installation
# 2. AUR Integration: Controls AUR repository deployment behavior
# 
# Package Installation Section:
# Each section below defines what gets installed and where

# Package metadata the generator cannot infer. Uncomment what applies.
# Detected values are kept; entries here are added or win over them.
# name defaults to the repository name, lowercased; install names a file
# next to this config in aur/; check is true, false, or a test command;
# arch defaults to any unless the project compiles; install_vars are extra
# variables passed to make install. source is release (default), archive, or signed-tag.
# description replaces the detected pkgdesc. license replaces the detected license.
# post_package lines are shell code appended to the end of package().
# package:
#   name: linux-mytool
#   install: mytool.install
#   check: true
#   source: release
#   arch: [any]
#   depends:
#     - systemd>=249
#   optdepends:
#     - "libnotify: desktop notifications"
#   makedepends: []
#   conflicts: [mytool]
#   provides: []
#   backup:
#     - etc/mytool/mytool.conf
#   install_vars:
#     - UNITDIR=/usr/lib/systemd/system
#   description: "what the package does"
#   license: [GPL-3.0-or-later]
#   post_package: []

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

# AUR Integration Configuration
# This section controls AUR repository deployment behavior
aur_integration:
  # Local AUR repositories directory
  aur_repo_dir: /opt/AUR
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template (use {version} for version placeholder)
  commit_message: "Update to version {version}"
  # Git user for AUR commits; leave commented so the clone uses the user's git config
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # SSH key for AUR authentication (optional)
  ssh_key: ~/.ssh/aur_key
  # Backup existing files before overwriting
  backup_existing: true
  # Validate AUR repository before pushing
  validate_before_push: true
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
# AURGen Configuration File Example
# This file contains two main sections:
# 1. Package Installation: Controls which directories are copied during package installation
# 2. AUR Integration: Controls AUR repository deployment behavior
# 
# Package Installation Section:
# Each section below defines what gets installed and where

# Package metadata the generator cannot infer. Uncomment what applies.
# Detected values are kept; entries here are added or win over them.
# name defaults to the repository name, lowercased; install names a file
# next to this config in aur/; check is true, false, or a test command;
# arch defaults to any unless the project compiles; install_vars are extra
# variables passed to make install. source is release (default), archive, or signed-tag.
# description replaces the detected pkgdesc. license replaces the detected license.
# post_package lines are shell code appended to the end of package().
# package:
#   name: linux-mytool
#   install: mytool.install
#   check: true
#   source: release
#   arch: [any]
#   depends:
#     - systemd>=249
#   optdepends:
#     - "libnotify: desktop notifications"
#   makedepends: []
#   conflicts: [mytool]
#   provides: []
#   backup:
#     - etc/mytool/mytool.conf
#   install_vars:
#     - UNITDIR=/usr/lib/systemd/system
#   description: "what the package does"
#   license: [GPL-3.0-or-later]
#   post_package: []

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

# AUR Integration Configuration
# This section controls AUR repository deployment behavior
aur_integration:
  # Local AUR repositories directory
  aur_repo_dir: /opt/AUR
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template (use {version} for version placeholder)
  commit_message: "Update to version {version}"
  # Git user for AUR commits; leave commented so the clone uses the user's git config
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # SSH key for AUR authentication (optional)
  ssh_key: ~/.ssh/aur_key
  # Backup existing files before overwriting
  backup_existing: true
  # Validate AUR repository before pushing
  validate_before_push: true

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