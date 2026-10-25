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
# Repo-relative sources other than the eight names above. Each entry is
# "<source>:<destination>:<permissions>:<excludes>", in config order.
COPY_RULES_EXTRA=()

# Package metadata from a top-level package: section. Empty when the section is absent.
PKG_NAME=""
PKG_INSTALL=""
PKG_INSTALL_MESSAGES=0
PKG_POST_INSTALL=()
PKG_POST_UPGRADE=()
PKG_PRE_REMOVE=()
PKG_CHECK=""
PKG_ARCH=()
PKG_DEPENDS=()
PKG_OPTDEPENDS=()
PKG_MAKEDEPENDS=()
PKG_CHECKDEPENDS=()
PKG_CONFLICTS=()
PKG_PROVIDES=()
PKG_BACKUP=()
PKG_INSTALL_VARS=()
PKG_KEEP=()
# release (default), archive, or signed-tag. Empty means release.
PKG_SOURCE=""
# description replaces the detected pkgdesc. license replaces the detected license.
PKG_DESCRIPTION=""
# gpg_key names the signing key: a full fingerprint or a 16+ hex suffix of one.
PKG_GPG_KEY=""
PKG_LICENSE=()
# post_package lines are shell code appended to package(), not package metadata.
PKG_POST_PACKAGE=()

# Same quote stripping as copy-rule values: one leading and one trailing quote.
# Strip one matching pair of outer quotes only. A shell line such as
# echo "$v" > "$f" ends with a quote that belongs to the line.
# Inside single quotes, '' is one apostrophe.
_yaml_unquote() {
    local value="$1"
    if (( ${#value} >= 2 )); then
        case "$value" in
            \"*\") value="${value:1:${#value}-2}" ;;
            \'*\')
                value="${value:1:${#value}-2}"
                value="${value//\'\'/\'}"
                ;;
        esac
    fi
    printf '%s' "$value"
}

# Drop a trailing comment the way YAML does: a # outside quotes that follows
# whitespace. A quote opens only at the start of a token, so don't stays a word.
_yaml_strip_comment() {
    local s="$1" out="" c q="" prev=" " i
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        if [[ "$q" == '"' && "$c" == "\\" ]]; then
            # \" and \\ stay inside a double-quoted scalar.
            out+="${s:i:2}"
            prev="${s:i+1:1}"
            i=$((i + 1))
            continue
        elif [[ "$q" == "'" && "$c" == "'" && "${s:i+1:1}" == "'" ]]; then
            # '' is a quote inside a single-quoted scalar.
            out+="''"
            i=$((i + 1))
            continue
        elif [[ -n "$q" ]]; then
            [[ "$c" == "$q" ]] && q=""
        elif [[ ( "$c" == '"' || "$c" == "'" ) && "$prev" =~ [[:space:]:,\[\-] ]]; then
            q="$c"
        elif [[ "$c" == '#' && "$prev" =~ [[:space:]] ]]; then
            break
        fi
        out+="$c"
        prev="$c"
    done
    printf '%s' "${out%"${out##*[![:space:]]}"}"
}

_yaml_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# A spaceless quoted token is YAML quoting; other quotes are pattern text and
# must survive inside pkgbuild_squote.
_unquote_excludes() {
    local raw="$1" part="" out=""
    local -a parts=()
    [[ -n "$raw" ]] || return 0
    IFS=',' read -ra parts <<< "$raw"
    for part in "${parts[@]}"; do
        part="$(_yaml_trim "$part")"
        if [[ "$part" =~ ^\"[^\"[:space:]]*\"$ || "$part" =~ ^\'[^\'[:space:]]*\'$ ]]; then
            part="$(_yaml_unquote "$part")"
            part="$(_yaml_trim "$part")"
        fi
        [[ -z "$part" ]] && continue
        out+="${out:+, }$part"
    done
    printf '%s' "$out"
}

_reset_package_vars() {
    PKG_NAME=""
    PKG_INSTALL=""
    PKG_INSTALL_MESSAGES=0
    PKG_POST_INSTALL=()
    PKG_POST_UPGRADE=()
    PKG_PRE_REMOVE=()
    PKG_CHECK=""
    PKG_ARCH=()
    PKG_DEPENDS=()
    PKG_OPTDEPENDS=()
    PKG_MAKEDEPENDS=()
    PKG_CHECKDEPENDS=()
    PKG_CONFLICTS=()
    PKG_PROVIDES=()
    PKG_BACKUP=()
    PKG_INSTALL_VARS=()
    PKG_KEEP=()
    PKG_SOURCE=""
    PKG_DESCRIPTION=""
    PKG_GPG_KEY=""
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
        checkdepends) PKG_CHECKDEPENDS+=("$item") ;;
        conflicts) PKG_CONFLICTS+=("$item") ;;
        provides) PKG_PROVIDES+=("$item") ;;
        backup) PKG_BACKUP+=("$item") ;;
        install_vars) PKG_INSTALL_VARS+=("$item") ;;
        keep)
            case "$item" in
                /*|*..*|*'*'*|*'?'*|*'['*|*']'*)
                    echo "[config] Invalid package.keep entry: $item" >&2
                    return 1
                    ;;
            esac
            PKG_KEEP+=("$item")
            ;;
        license) PKG_LICENSE+=("$item") ;;
        post_package) PKG_POST_PACKAGE+=("$item") ;;
        install_messages_post_install) PKG_POST_INSTALL+=("$item") ;;
        install_messages_post_upgrade) PKG_POST_UPGRADE+=("$item") ;;
        install_messages_pre_remove) PKG_PRE_REMOVE+=("$item") ;;
    esac
}

# Inline form is "[a, b]" and only for items that do not contain commas.
# A bare scalar is one item.
_pkg_set_inline() {
    local key="$1"
    local raw part item
    local -a parts=()
    raw="$(_yaml_trim "$2")"
    if [[ ! "$raw" =~ ^\[(.*)\]$ ]]; then
        # A scalar (license: MIT) is a one-item list; an empty value starts a block list.
        raw="$(_yaml_trim "$(_yaml_unquote "$raw")")"
        if [[ -n "$raw" ]]; then
            _pkg_add "$key" "$raw" || return 1
        fi
        return 0
    fi
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
            _pkg_add "$key" "$item" || return 1
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
    COPY_RULES_EXTRA=()
    
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
        COPY_RULES_EXTRA=()
        
        # Parse YAML configuration
        parse_yaml_config "$aur_config_file" || return 1
    fi
}

# Store a copy source that is not one of the eight fixed directory names.
# A safe source is a repo-relative path: components of [A-Za-z0-9._-],
# separated by "/", never "." or "..". Anything else is a config error.
_save_extra_copy_rule() {
    local source_dir="$1"
    local rule="$2"
    local part="" rest=""
    # LC_ALL overrides LC_COLLATE. A Turkish LC_ALL makes [A-Za-z] miss i/I.
    local LC_ALL=
    local LC_COLLATE=C

    if [[ ! "$source_dir" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]]; then
        echo "[config] Invalid copy source: $source_dir" >&2
        return 1
    fi
    # "." is a legal character, so "." and ".." still match the class.
    rest="$source_dir"
    while [[ -n "$rest" ]]; do
        part="${rest%%/*}"
        if [[ "$part" == "." || "$part" == ".." ]]; then
            echo "[config] Invalid copy source: $source_dir" >&2
            return 1
        fi
        if [[ "$rest" == */* ]]; then
            rest="${rest#*/}"
        else
            rest=""
        fi
    done
    COPY_RULES_EXTRA+=("${source_dir}:${rule}")
}

# Save a copy section, rejecting incomplete rules that name a source.
_save_copy_section() {
    local section="$1" source_dir="$2" dest_dir="$3" permissions="$4" excludes="$5"
    [[ -n "$source_dir" ]] || return 0
    if [[ -z "$dest_dir" ]]; then
        echo "[config] Copy section '$section' (source '$source_dir'): missing destination" >&2
        return 1
    fi
    if [[ -z "$permissions" ]]; then
        echo "[config] Copy section '$section' (source '$source_dir'): missing permissions" >&2
        return 1
    fi

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
        *) _save_extra_copy_rule "$source_dir" "$rule" || return 1 ;;
    esac
    debug "[config] Added copy rule: $source_dir -> $rule"
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
    local messages_indent=-1 indent
    local key value item line_no=0 in_exclude_list=0
    local pkg_known_keys="name, description, gpg_key, install, check, source, install_messages, arch, depends, optdepends, makedepends, checkdepends, conflicts, provides, backup, install_vars, keep, license, post_package"

    _reset_package_vars

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        line="$(_yaml_strip_comment "$line")"
        [[ -z "${line// }" ]] && continue

        # Block-list items stay intact so optdepends can contain ": ".
        if [[ "$in_package" -eq 1 && "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
            item="$(_yaml_trim "${BASH_REMATCH[1]}")"
            item="$(_yaml_unquote "$item")"
            if [[ "$pkg_list_key" == install_messages_* ]]; then
                _pkg_add "$pkg_list_key" "$item" || return 1
                continue
            fi
            item="$(_yaml_trim "$item")"
            if [[ -n "$pkg_list_key" && -n "$item" ]]; then
                _pkg_add "$pkg_list_key" "$item" || return 1
            fi
            continue
        fi

        # Indented bare keys inside package: are list headers, not copy-rule sections.
        if [[ "$in_package" -eq 1 && "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            pkg_list_key="${BASH_REMATCH[1]}"
            indent="${line%%[![:space:]]*}"
            if (( ${#indent} <= messages_indent )); then
                messages_indent=-1
            fi
            if [[ "$pkg_list_key" == install_messages ]]; then
                # shellcheck disable=SC2034 # consumed by scriptlet generation
                PKG_INSTALL_MESSAGES=1
                messages_indent=${#indent}
                pkg_list_key=""
            elif (( messages_indent >= 0 )); then
                case "$pkg_list_key" in
                    post_install|post_upgrade|pre_remove) pkg_list_key="install_messages_$pkg_list_key" ;;
                    *) echo "[config] Unknown install_messages hook: $pkg_list_key" >&2; return 1 ;;
                esac
            else
                case "$pkg_list_key" in
                    name|description|gpg_key|install|check|source|arch|depends|optdepends|makedepends|checkdepends|conflicts|provides|backup|install_vars|keep|license|post_package) ;;
                    *)
                        echo "[config] Unknown package key '$pkg_list_key' in ${config_file}:${line_no}; known keys: ${pkg_known_keys}" >&2
                        return 1
                        ;;
                esac
            fi
            continue
        fi

        # A block-list exclude in a copy section, stored like the inline [a, b] form.
        if [[ "$in_package" -eq 0 && -n "$current_section" ]]; then
            if [[ "$line" =~ ^[[:space:]]+exclude:[[:space:]]*$ ]]; then
                excludes=""
                in_exclude_list=1
                continue
            fi
            if (( in_exclude_list )) && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
                item="$(_yaml_trim "${BASH_REMATCH[1]}")"
                excludes+="${excludes:+, }$item"
                continue
            fi
            in_exclude_list=0
        fi

        # Check for section headers (e.g., "executables:")
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            # Snapshot before saving: an extra-source regex overwrites BASH_REMATCH.
            local next_section="${BASH_REMATCH[1]}"
            # Save previous section if we have one
            if [[ "$in_package" -eq 0 && -n "$current_section" ]]; then
                _save_copy_section "$current_section" "$source_dir" "$dest_dir" "$permissions" "$excludes" || return 1
            fi
            
            # Start new section. package: is metadata, not a copy rule.
            current_section="$next_section"
            source_dir=""
            dest_dir=""
            permissions=""
            excludes=""
            pkg_list_key=""
            messages_indent=-1
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
                indent="${line%%[![:space:]]*}"
                if (( ${#indent} <= messages_indent )); then
                    messages_indent=-1
                fi
                if (( messages_indent >= 0 )); then
                    echo "[config] install_messages hooks require block lists" >&2
                    return 1
                fi
                # shellcheck disable=SC2034 # package fields are consumed by later generators
                case "$key" in
                    install_messages)
                        echo "[config] install_messages requires a block mapping" >&2
                        return 1
                        ;;
                    name) PKG_NAME="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                    description) PKG_DESCRIPTION="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                    gpg_key) PKG_GPG_KEY="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
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
                    arch|depends|optdepends|makedepends|checkdepends|conflicts|provides|backup|install_vars|keep|license|post_package)
                        _pkg_set_inline "$key" "$value" || return 1
                        ;;
                    *)
                        echo "[config] Unknown package key '$key' in ${config_file}:${line_no}; known keys: ${pkg_known_keys}" >&2
                        return 1
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
    if [[ "$in_package" -eq 0 && -n "$current_section" ]]; then
        _save_copy_section "$current_section" "$source_dir" "$dest_dir" "$permissions" "$excludes" || return 1
    fi
}

# Generate default configuration file
# Usage: generate_default_config [config_file_path]
generate_default_config() {
    local config_file="${1:-$AUR_DIR/aurgen.install.yaml}"
    local config_dir
    config_dir=$(dirname "$config_file")

    # Create directory if it doesn't exist. Callers test the status, which turns
    # errexit off, so a failed mkdir or write must return 1 itself.
    if [[ ! -d "$config_dir" ]] && ! mkdir -p "$config_dir"; then
        err "[config] Cannot create $config_dir"
        return 1
    fi

    # Don't overwrite existing configuration file
    if [[ -f "$config_file" ]]; then
        warn "[config] Configuration file already exists: $config_file"
        warn "[config] Use 'aurgen config edit' to modify it, or 'aurgen config reset' to regenerate."
        return 1
    fi
    
    # Generate the YAML configuration file
    cat > "$config_file" <<EOF || { err "[config] Cannot write $config_file"; return 1; }
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
# gpg_key is the signing key fingerprint (or a 16+ hex suffix); GPG_KEY_ID wins.
# post_package lines are shell code appended to the end of package().
# keep preserves exact repo-relative paths or directory prefixes ending in /.
# package:
#   name: linux-mytool
#   install: mytool.install
#   install_messages:
#     post_install:
#       - "Review /etc/mytool/mytool.conf before enabling the timer."
#     pre_remove:
#       - "Disable the timer before removing the package."
#   check: true
#   source: release
#   arch: [any]
#   depends:
#     - systemd>=249
#   optdepends:
#     - "libnotify: desktop notifications"
#   makedepends: []
#   checkdepends: []
#   conflicts: [mytool]
#   provides: []
#   backup:
#     - etc/mytool/mytool.conf
#   install_vars:
#     - UNITDIR=/usr/lib/systemd/system
#   keep: [VERSION, share/help/]
#   description: "what the package does"
#   gpg_key: 0123456789ABCDEF0123456789ABCDEF01234567
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
  aur_repo_dir: ~/.local/share/aurgen/aur
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template (use {version} for version placeholder)
  commit_message: "Update to version {version}"
  # Git user for AUR commits; leave commented so the clone uses the user's git config
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # SSH key for AUR authentication. When unset, ~/.ssh/config is used.
  # ssh_key: ~/.ssh/aur
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
# gpg_key is the signing key fingerprint (or a 16+ hex suffix); GPG_KEY_ID wins.
# post_package lines are shell code appended to the end of package().
# keep preserves exact repo-relative paths or directory prefixes ending in /.
# package:
#   name: linux-mytool
#   install: mytool.install
#   install_messages:
#     post_install:
#       - "Review /etc/mytool/mytool.conf before enabling the timer."
#     pre_remove:
#       - "Disable the timer before removing the package."
#   check: true
#   source: release
#   arch: [any]
#   depends:
#     - systemd>=249
#   optdepends:
#     - "libnotify: desktop notifications"
#   makedepends: []
#   checkdepends: []
#   conflicts: [mytool]
#   provides: []
#   backup:
#     - etc/mytool/mytool.conf
#   install_vars:
#     - UNITDIR=/usr/lib/systemd/system
#   keep: [VERSION, share/help/]
#   description: "what the package does"
#   gpg_key: 0123456789ABCDEF0123456789ABCDEF01234567
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
  aur_repo_dir: ~/.local/share/aurgen/aur
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template (use {version} for version placeholder)
  commit_message: "Update to version {version}"
  # Git user for AUR commits; leave commented so the clone uses the user's git config
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # SSH key for AUR authentication. When unset, ~/.ssh/config is used.
  # ssh_key: ~/.ssh/aur
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
    local rule_pair source_dir dest_dir permissions excludes
    
    # Empty fixed rules are disabled; every extra entry must be valid.
    local rules=(
        "${COPY_RULES_BIN:+bin:$COPY_RULES_BIN}"
        "${COPY_RULES_LIB:+lib:$COPY_RULES_LIB}"
        "${COPY_RULES_ETC:+etc:$COPY_RULES_ETC}"
        "${COPY_RULES_SHARE:+share:$COPY_RULES_SHARE}"
        "${COPY_RULES_INCLUDE:+include:$COPY_RULES_INCLUDE}"
        "${COPY_RULES_LOCAL:+local:$COPY_RULES_LOCAL}"
        "${COPY_RULES_VAR:+var:$COPY_RULES_VAR}"
        "${COPY_RULES_OPT:+opt:$COPY_RULES_OPT}"
    )
    local active_rules=()
    for rule_pair in "${rules[@]}"; do
        [[ -n "$rule_pair" ]] && active_rules+=("$rule_pair")
    done
    
    for rule_pair in "${active_rules[@]}" "${COPY_RULES_EXTRA[@]}"; do
        IFS=':' read -r source_dir dest_dir permissions excludes <<< "$rule_pair"

        # Validate required fields
        if [[ -z "$dest_dir" || -z "$permissions" ]]; then
            err "[config] Invalid configuration rule for $source_dir: missing destination or permissions"
            valid=0
            continue
        fi

        # Validate permissions format
        case "$permissions" in
            executable|read-only|readonly)
                # Valid human-readable permissions
                ;;
            [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7])
                # Valid octal permissions (gen-pkgbuild0 accepts 3 or 4 digits)
                ;;
            *)
                err "[config] Invalid permissions '$permissions' for $source_dir"
                valid=0
                ;;
        esac
    done
    return $((1 - valid))
}

# Get copy directories for use in PKGBUILD generation
# Usage: get_copy_directories
get_copy_directories() {
    # Callers read stdout as copy rules, so every diagnostic goes to stderr.
    # Load configuration if not already loaded. Extra rules count: a file that
    # only names a directory such as data/ must not be replaced by the defaults.
    if [[ -z "$COPY_RULES_BIN$COPY_RULES_LIB$COPY_RULES_ETC$COPY_RULES_SHARE$COPY_RULES_INCLUDE$COPY_RULES_LOCAL$COPY_RULES_VAR$COPY_RULES_OPT" && ${#COPY_RULES_EXTRA[@]} -eq 0 ]]; then
        load_aurgen_config >&2 || return 1
    fi
    
    # Validate configuration
    if ! validate_config >&2; then
        err "[config] Configuration validation failed" >&2
        return 1
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
            
            excludes="$(_unquote_excludes "$excludes")"
            local output="$source_dir:$dest_dir:$octal_perms"
            [[ -n "$excludes" ]] && output="$output:$excludes"
            printf '%s\n' "$output"
        fi
    done

    local extra_entry="" extra_source="" extra_rule=""
    local extra_dest="" extra_perms="" extra_excludes="" extra_octal="" extra_output=""
    for extra_entry in "${COPY_RULES_EXTRA[@]}"; do
        extra_source="${extra_entry%%:*}"
        extra_rule="${extra_entry#*:}"
        IFS=':' read -r extra_dest extra_perms extra_excludes <<< "$extra_rule"
        case "$extra_perms" in
            executable)
                extra_octal="755"
                ;;
            read-only|readonly)
                extra_octal="644"
                ;;
            *)
                extra_octal="$extra_perms"
                ;;
        esac
        extra_excludes="$(_unquote_excludes "$extra_excludes")"
        extra_output="$extra_source:$extra_dest:$extra_octal"
        [[ -n "$extra_excludes" ]] && extra_output="$extra_output:$extra_excludes"
        printf '%s\n' "$extra_output"
    done
}
