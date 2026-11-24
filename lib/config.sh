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
# Additional rules for repo-relative sources. Each entry is
# "<source>:<destination>:<permissions>:<excludes>", in config order.
COPY_RULES_EXTRA=()
# All copy rules in config order, using the same entry format.
COPY_RULES_ORDERED=()

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
PKG_GROUPS=()
PKG_PROVIDES=()
PKG_REPLACES=()
PKG_BACKUP=()
PKG_OPTIONS=()
PKG_INSTALL_VARS=()
PKG_CMAKE_ARGS=()
PKG_KEEP=()
PKG_EXCLUDE=()
PKG_URL=""
PKG_EPOCH=""
# release (default), archive, or signed-tag. Empty means release.
PKG_SOURCE=""
# description replaces the detected pkgdesc. license replaces the detected license.
PKG_DESCRIPTION=""
# gpg_key names the signing key: a full fingerprint or a 16+ hex suffix of one.
PKG_GPG_KEY=""
PKG_LICENSE=()
# post_package lines are shell code appended to package(), not package metadata.
PKG_POST_PACKAGE=()
PKG_PREPARE=()

# Same quote stripping as copy-rule values: one leading and one trailing quote.
# Strip one matching pair of outer quotes only. A shell line such as
# echo "$v" > "$f" ends with a quote that belongs to the line.
# Inside single quotes, '' is one apostrophe.
# Inside double quotes YAML reads \" as a quote and \\ as a backslash.
_yaml_dq_decode() {
    local value="$1" out="" c i
    for (( i = 0; i < ${#value}; i++ )); do
        c="${value:i:1}"
        if [[ "$c" == "\\" && ( "${value:i+1:1}" == "\\" || "${value:i+1:1}" == '"' ) ]]; then
            i=$((i + 1))
            c="${value:i:1}"
        fi
        out+="$c"
    done
    printf '%s' "$out"
}

_yaml_unquote() {
    local value="$1"
    if (( ${#value} >= 2 )); then
        case "$value" in
            \"*\") value="$(_yaml_dq_decode "${value:1:${#value}-2}")" ;;
            \'*\')
                value="${value:1:${#value}-2}"
                value="${value//\'\'/\'}"
                ;;
        esac
    fi
    printf '%s' "$value"
}

# For shell-code list items (prepare, post_package): only one whole quoted scalar
# is unquoted, since "a" "b" is two quoted words and stripping its ends joins them.
_yaml_unquote_whole() {
    local value="$1" inner rest
    if (( ${#value} >= 2 )); then
        case "$value" in
            \"*\")
                inner="${value:1:${#value}-2}"
                rest="${inner//\\\\/}"
                rest="${rest//\\\"/}"
                [[ "$rest" == *\"* ]] || value="$(_yaml_dq_decode "$inner")"
                ;;
            \'*\')
                inner="${value:1:${#value}-2}"
                rest="${inner//\'\'/}"
                [[ "$rest" == *\'* ]] || value="${inner//\'\'/\'}"
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
    PKG_URL=""
    PKG_EPOCH=""
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
    PKG_GROUPS=()
    PKG_PROVIDES=()
    PKG_REPLACES=()
    PKG_OPTIONS=()
    PKG_BACKUP=()
    PKG_INSTALL_VARS=()
    PKG_CMAKE_ARGS=()
    PKG_KEEP=()
    PKG_EXCLUDE=()
    PKG_SOURCE=""
    PKG_DESCRIPTION=""
    PKG_GPG_KEY=""
    PKG_LICENSE=()
    PKG_POST_PACKAGE=()
    PKG_PREPARE=()
}

_pkg_add() {
    local LC_ALL=C
    local key="$1"
    local item="$2"
    case "$key" in
        arch) PKG_ARCH+=("$item") ;;
        depends)
            if [[ "$item" == \!* && ! "${item#!}" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
                echo "[config] Invalid package.depends entry: $item" >&2
                return 1
            fi
            PKG_DEPENDS+=("$item")
            ;;
        optdepends) PKG_OPTDEPENDS+=("$item") ;;
        makedepends)
            if [[ "$item" == \!* && ! "${item#!}" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
                echo "[config] Invalid package.makedepends entry: $item" >&2
                return 1
            fi
            PKG_MAKEDEPENDS+=("$item")
            ;;
        checkdepends) PKG_CHECKDEPENDS+=("$item") ;;
        conflicts) PKG_CONFLICTS+=("$item") ;;
        groups) PKG_GROUPS+=("$item") ;;
        provides) PKG_PROVIDES+=("$item") ;;
        replaces) PKG_REPLACES+=("$item") ;;
        options) PKG_OPTIONS+=("$item") ;;
        backup) PKG_BACKUP+=("$item") ;;
        install_vars) PKG_INSTALL_VARS+=("$item") ;;
        cmake_args)
            if [[ ! "$item" =~ ^-D[A-Za-z0-9_]+(:[A-Z]+)?=[A-Za-z0-9_./+=,-]*$ ]]; then
                echo "[config] Invalid package.cmake_args entry: $item" >&2
                return 1
            fi
            PKG_CMAKE_ARGS+=("$item")
            ;;
        keep)
            case "$item" in
                /*|*..*|*'*'*|*'?'*|*'['*|*']'*)
                    echo "[config] Invalid package.keep entry: $item" >&2
                    return 1
                    ;;
            esac
            PKG_KEEP+=("$item")
            ;;
        exclude)
            case "$item" in
                /*|*..*|*'*'*|*'?'*|*'['*|*']'*)
                    echo "[config] Invalid package.exclude entry: $item" >&2
                    return 1
                    ;;
            esac
            PKG_EXCLUDE+=("$item")
            ;;
        license) PKG_LICENSE+=("$item") ;;
        post_package) PKG_POST_PACKAGE+=("$item") ;;
        prepare) PKG_PREPARE+=("$item") ;;
        install_messages_post_install) PKG_POST_INSTALL+=("$item") ;;
        install_messages_post_upgrade) PKG_POST_UPGRADE+=("$item") ;;
        install_messages_pre_remove) PKG_PRE_REMOVE+=("$item") ;;
    esac
}

# Split on commas that sit outside single or double quotes.
# A quote toggles until its match, so a comma inside an item stays put.
_yaml_split_commas() {
    local -n _split_out="$1"
    local s="$2" cur="" c q="" i
    _split_out=()
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        if [[ "$q" == '"' && "$c" == "\\" ]]; then
            # \" and \\ stay inside a double-quoted item; _yaml_dq_decode undoes them later.
            cur+="${s:i:2}"
            i=$((i + 1))
        elif [[ -n "$q" ]]; then
            cur+="$c"
            [[ "$c" == "$q" ]] && q=""
        elif [[ "$c" == '"' || "$c" == "'" ]]; then
            q="$c"
            cur+="$c"
        elif [[ "$c" == ',' ]]; then
            _split_out+=("$cur")
            cur=""
        else
            cur+="$c"
        fi
    done
    _split_out+=("$cur")
}

# Inline form is "[a, b]". A quoted item may contain commas.
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
    _yaml_split_commas parts "$inner"
    for part in "${parts[@]}"; do
        item="$(_yaml_trim "$part")"
        item="$(_yaml_unquote "$item")"
        item="$(_yaml_trim "$item")"
        if [[ -n "$item" ]]; then
            _pkg_add "$key" "$item" || return 1
        fi
    done
}

# Return the active configuration file path.
aurgen_config_file() {
    if [[ -n "${AURGEN_CONFIG_FILE:-}" ]]; then
        printf '%s\n' "$AURGEN_CONFIG_FILE"
    else
        printf '%s\n' "${AUR_DIR:-}/aurgen.install.yaml"
    fi
}

# Load configuration from aurgen.install.yaml if it exists
# Usage: load_aurgen_config [config_file]
load_aurgen_config() {
    local aur_config_file="${1:-$(aurgen_config_file)}"

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
    COPY_RULES_ORDERED=(
        "bin:$COPY_RULES_BIN"
        "lib:$COPY_RULES_LIB"
        "etc:$COPY_RULES_ETC"
        "share:$COPY_RULES_SHARE"
        "include:$COPY_RULES_INCLUDE"
        "local:$COPY_RULES_LOCAL"
        "var:$COPY_RULES_VAR"
        "opt:$COPY_RULES_OPT"
    )
    
    # Try to load from aur directory (project-specific location)
    if [[ -f "$aur_config_file" ]]; then
        if [[ ! -r "$aur_config_file" ]]; then
            echo "[config] Configuration file is not readable: $aur_config_file" >&2
            return 1
        fi
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
        COPY_RULES_ORDERED=()
        
        # Parse YAML configuration
        parse_yaml_config "$aur_config_file" || return 1
    fi
}

# Store an additional copy rule.
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

# Save a copy section, rejecting incomplete rules.
_save_copy_section() {
    local section="$1" source_dir="$2" dest_dir="$3" permissions="$4" excludes="$5"
    if [[ -z "$source_dir" ]]; then
        echo "[config] Copy section '$section': missing source" >&2
        return 1
    fi
    if [[ -z "$dest_dir" ]]; then
        echo "[config] Copy section '$section' (source '$source_dir'): missing destination" >&2
        return 1
    fi
    if [[ -z "$permissions" ]]; then
        echo "[config] Copy section '$section' (source '$source_dir'): missing permissions" >&2
        return 1
    fi

    local rule="$dest_dir:$permissions:$excludes" rule_var=""
    case "$source_dir" in
        bin) rule_var=COPY_RULES_BIN ;;
        lib) rule_var=COPY_RULES_LIB ;;
        etc) rule_var=COPY_RULES_ETC ;;
        share) rule_var=COPY_RULES_SHARE ;;
        include) rule_var=COPY_RULES_INCLUDE ;;
        local) rule_var=COPY_RULES_LOCAL ;;
        var) rule_var=COPY_RULES_VAR ;;
        opt) rule_var=COPY_RULES_OPT ;;
    esac
    if [[ -z "$rule_var" || -n "${!rule_var}" ]]; then
        _save_extra_copy_rule "$source_dir" "$rule" || return 1
    else
        printf -v "$rule_var" '%s' "$rule"
    fi
    COPY_RULES_ORDERED+=("$source_dir:$rule")
    debug "[config] Added copy rule: $source_dir -> $rule"
}

# Parse YAML configuration file
# Usage: parse_yaml_config <config_file>
# Report a line the parser cannot place, and name the usual cause when the previous line
# opened a flow list without closing it.
# Usage: _config_invalid_line <file> <line_no> <line> <previous line>
_config_invalid_line() {
    echo "[config] Invalid configuration line in ${1}:${2}: $(_yaml_trim "$3")" >&2
    if [[ "$4" =~ :[[:space:]]*\[[^]]*$ ]]; then
        echo "[config] A flow list ([a, b]) must fit on one line; for a long list write one '- item' per line." >&2
    fi
}

parse_yaml_config() {
    local LC_ALL=C
    local config_file="$1"
    local current_section=""
    local source_dir=""
    local dest_dir=""
    local permissions=""
    local excludes=""
    local in_package=0
    local in_aur=0
    local pkg_list_key=""
    local messages_indent=-1 indent
    local prev_line="" cur_line=""
    local key value item line_no=0 in_exclude_list=0
    local pkg_known_keys="name, description, url, epoch, gpg_key, install, check, source, install_messages, arch, depends, optdepends, makedepends, checkdepends, conflicts, groups, provides, replaces, options, backup, install_vars, cmake_args, keep, exclude, license, post_package, prepare"
    local copy_known_keys="source, destination, permissions, exclude"

    _reset_package_vars

    # shellcheck disable=SC2094 # _config_invalid_line only prints the file name
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        line="$(_yaml_strip_comment "$line")"
        [[ -z "${line//[[:space:]]}" ]] && continue
        prev_line="$cur_line"
        cur_line="$line"

        # Top-level section headers start at column 0 (e.g., "executables:")
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            # Snapshot before saving: an extra-source regex overwrites BASH_REMATCH.
            local next_section="${BASH_REMATCH[1]}"
            # Save previous section if we have one
            if [[ "$in_package" -eq 0 && "$in_aur" -eq 0 && -n "$current_section" ]]; then
                _save_copy_section "$current_section" "$source_dir" "$dest_dir" "$permissions" "$excludes" || return 1
            fi

            # Start new section. package: and aur_integration: are not copy rules.
            current_section="$next_section"
            source_dir=""
            dest_dir=""
            permissions=""
            excludes=""
            pkg_list_key=""
            messages_indent=-1
            in_exclude_list=0
            in_package=0
            in_aur=0
            if [[ "$current_section" == "package" ]]; then
                in_package=1
            elif [[ "$current_section" == "aur_integration" ]]; then
                in_aur=1
            fi
            continue
        fi

        if [[ "$line" != [[:space:]]* || -z "$current_section" ]]; then
            _config_invalid_line "$config_file" "$line_no" "$line" "$prev_line"
            return 1
        fi

        if [[ "$in_aur" -eq 1 ]]; then
            continue
        fi

        # Block-list items stay intact so optdepends can contain ": ".
        if [[ "$in_package" -eq 1 && "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
            if [[ -z "$pkg_list_key" ]]; then
                _config_invalid_line "$config_file" "$line_no" "$line" "$prev_line"
                return 1
            fi
            item="$(_yaml_trim "${BASH_REMATCH[1]}")"
            if [[ "$pkg_list_key" == post_package || "$pkg_list_key" == prepare ]]; then
                item="$(_yaml_unquote_whole "$item")"
            else
                item="$(_yaml_unquote "$item")"
            fi
            if [[ "$pkg_list_key" == install_messages_* ]]; then
                _pkg_add "$pkg_list_key" "$item" || return 1
                continue
            fi
            item="$(_yaml_trim "$item")"
            if [[ -n "$item" && ( "$pkg_list_key" == post_package || "$pkg_list_key" == prepare ) ]]; then
                # Shell code keeps the indentation after the one space that follows "-",
                # so nested loops stay readable in the generated package().
                local post_raw="${line#*-}" post_indent
                post_raw="${post_raw# }"
                post_indent="${post_raw%%[![:space:]]*}"
                item="$post_indent$item"
            fi
            if [[ -n "$item" ]]; then
                _pkg_add "$pkg_list_key" "$item" || return 1
            fi
            continue
        fi

        if [[ "$in_package" -eq 1 && "$line" =~ ^[[:space:]]*([^:]+): ]]; then
            key="$(_yaml_trim "${BASH_REMATCH[1]}")"
            if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[config] Unknown package key '$key' in ${config_file}:${line_no}; known keys: ${pkg_known_keys}" >&2
                return 1
            fi
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
                    name|description|url|epoch|gpg_key|install|check|source|arch|depends|optdepends|makedepends|checkdepends|conflicts|groups|provides|replaces|options|backup|install_vars|cmake_args|keep|exclude|license|post_package|prepare) ;;
                    *)
                        echo "[config] Unknown package key '$pkg_list_key' in ${config_file}:${line_no}; known keys: ${pkg_known_keys}" >&2
                        return 1
                        ;;
                esac
            fi
            continue
        fi

        # A block-list exclude in a copy section, stored like the inline [a, b] form.
        if [[ "$in_package" -eq 0 ]]; then
            if [[ "$line" =~ ^[[:space:]]+exclude:[[:space:]]*$ ]]; then
                excludes=""
                in_exclude_list=1
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]*-(|[[:space:]].*)$ ]]; then
                if (( ! in_exclude_list )); then
                    _config_invalid_line "$config_file" "$line_no" "$line" "$prev_line"
                    return 1
                fi
                item="$(_yaml_trim "${line#*-}")"
                excludes+="${excludes:+, }$item"
                continue
            fi
            in_exclude_list=0

            if [[ ! "$line" =~ ^[[:space:]]+([^:]+):[[:space:]]*(.*)$ ]]; then
                _config_invalid_line "$config_file" "$line_no" "$line" "$prev_line"
                return 1
            fi
            key="$(_yaml_trim "${BASH_REMATCH[1]}")"
            value="$(_yaml_trim "${BASH_REMATCH[2]}")"
            if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo "[config] Unknown copy key '$key' in ${config_file}:${line_no}; known keys: ${copy_known_keys}" >&2
                return 1
            fi

            value="$(_yaml_trim "$(_yaml_unquote "$value")")"

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
                *)
                    echo "[config] Unknown copy key '$key' in ${config_file}:${line_no}; known keys: ${copy_known_keys}" >&2
                    return 1
                    ;;
            esac
            continue
        fi

        # Parse key-value pairs in package:
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

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
                url) PKG_URL="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
                epoch) PKG_EPOCH="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "$value")")")" ;;
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
                arch|depends|optdepends|makedepends|checkdepends|conflicts|groups|provides|replaces|options|backup|install_vars|cmake_args|keep|exclude|license|post_package|prepare)
                    _pkg_set_inline "$key" "$value" || return 1
                    ;;
                *)
                    echo "[config] Unknown package key '$key' in ${config_file}:${line_no}; known keys: ${pkg_known_keys}" >&2
                    return 1
                    ;;
            esac
            continue
        fi

        _config_invalid_line "$config_file" "$line_no" "$line" "$prev_line"
        return 1
    done < "$config_file"

    # Don't forget the last section
    if [[ "$in_package" -eq 0 && "$in_aur" -eq 0 && -n "$current_section" ]]; then
        _save_copy_section "$current_section" "$source_dir" "$dest_dir" "$permissions" "$excludes" || return 1
    fi
}

# Write a configuration file from the shared template.
# Usage: _write_config_template <config_file> <mode>
_write_config_template() {
    local config_file="$1"
    local mode="$2"
    local config_dir title_suffix="" headers_note="" headers_prefix=""
    local exclusions_block="" custom_block=""
    config_dir=$(dirname "$config_file")

    # Create directory if it doesn't exist. Callers test the status, which turns
    # errexit off, so a failed mkdir or write must return 1 itself.
    if [[ ! -d "$config_dir" ]] && ! mkdir -p "$config_dir"; then
        err "[config] Cannot create $config_dir"
        return 1
    fi

    if [[ "$mode" == "example" ]]; then
        # Don't overwrite existing example file
        if [[ -f "$config_file" ]]; then
            debug "[config] Example configuration file already exists: $config_file"
            return 0
        fi
        title_suffix=" Example"
        headers_note=" (commented out - won't copy include/)"
        headers_prefix="# "
        # shellcheck disable=SC2016 # $pkgname is literal YAML text
        exclusions_block='
# Configuration files with exclusions (exclude test/ and temp/ subdirectories)
config_with_exclusions:
  source: etc
  destination: etc/$pkgname
  permissions: read-only
  exclude: [test, temp]
'
        # shellcheck disable=SC2016 # $pkgname is literal YAML text
        custom_block='

# Custom example - uncomment and modify as needed
# custom_data:
#   source: custom
#   destination: usr/share/$pkgname/custom
#   permissions: read-only
#   exclude: [backup, temp]'
    else
        # Don't overwrite existing configuration file
        if [[ -f "$config_file" ]]; then
            warn "[config] Configuration file already exists: $config_file"
            warn "[config] Use 'aurgen config edit' to modify it, or 'aurgen config reset' to regenerate."
            return 1
        fi
    fi

    mkdir -p "$(dirname "$config_file")" || { err "[config] Cannot create directory for $config_file"; return 1; }

    # Generate the YAML configuration file
    cat > "$config_file" <<EOF || { err "[config] Cannot write $config_file"; return 1; }
# AURGen Configuration File${title_suffix}
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
# url overrides the generated url= (defaults to the GitHub repository URL).
# epoch sets PKGBUILD epoch= (positive integer, omitted when unset).
# gpg_key is the signing key fingerprint (or a 16+ hex suffix); GPG_KEY_ID wins.
# post_package lines are shell code appended to the end of package().
# prepare lines are shell code for a prepare() run in the source tree before build().
# keep preserves exact repo-relative paths or directory prefixes ending in /.
# exclude drops exact repo-relative paths or directory prefixes ending in / from package sources.
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
#     - "!jq"   # drop a wrongly detected dependency
#   optdepends:
#     - "libnotify: desktop notifications"
#   makedepends: []
#   checkdepends: []
#   conflicts: [mytool]
#   groups: []
#   provides: []
#   replaces: []
#   options: []
#   backup:
#     - etc/mytool/mytool.conf
#   install_vars:
#     - UNITDIR=/usr/lib/systemd/system
#   cmake_args: [-DCMAKE_BUILD_TYPE=Release]   # CMake configure arguments
#   keep: [VERSION, share/help/]
#   exclude: [examples/, tests/fixtures/]
#   description: "what the package does"
#   url: https://example.org/mytool
#   epoch: 1
#   gpg_key: 0123456789ABCDEF0123456789ABCDEF01234567
#   license: [GPL-3.0-or-later]
#   post_package: []
#   prepare: []

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
${exclusions_block}
# Shared data files
shared_data:
  source: share
  destination: usr/share/\$pkgname
  permissions: read-only
  exclude: []

# Header files${headers_note}
${headers_prefix}headers:
${headers_prefix}  source: include
${headers_prefix}  destination: usr/include/\$pkgname
${headers_prefix}  permissions: read-only
${headers_prefix}  exclude: []

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
  validate_before_push: true${custom_block}
EOF

    if [[ "$mode" == "example" ]]; then
        debug "[config] Generated example configuration file: $config_file"
    else
        log "[config] Generated default configuration file: $config_file"
        echo -e "${YELLOW}[config] You can now edit $config_file to customize directory copying behavior.${RESET}" >&2
    fi
}

# Generate default configuration file
# Usage: generate_default_config [config_file_path]
generate_default_config() {
    local config_file="${1:-$(aurgen_config_file)}"
    _write_config_template "$config_file" default
}

# Generate example configuration file
# Usage: generate_example_config [config_file_path]
generate_example_config() {
    local config_file="${1:-$AUR_DIR/aurgen.install.yaml.example}"
    _write_config_template "$config_file" example
}

# Emit one standard FHS copy section for config init (commented when 1).
_write_init_copy_section() {
    local source_dir="$1" commented="${2:-0}" prefix=""
    local section="" dest="" perms="read-only"
    (( commented )) && prefix="# "
    case "$source_dir" in
        bin) section="executables"; dest="usr/bin"; perms="executable" ;;
        lib) section="libraries"; dest="usr/lib/\$pkgname" ;;
        etc) section="config"; dest="etc/\$pkgname" ;;
        share) section="shared_data"; dest="usr/share/\$pkgname" ;;
        include) section="headers"; dest="usr/include/\$pkgname" ;;
        local) section="local_data"; dest="usr/local/\$pkgname" ;;
        var) section="variable_data"; dest="var/\$pkgname" ;;
        opt) section="optional_data"; dest="opt/\$pkgname" ;;
        *) return 0 ;;
    esac
    printf '%s%s:\n' "$prefix" "$section"
    printf '%s  source: %s\n' "$prefix" "$source_dir"
    printf '%s  destination: %s\n' "$prefix" "$dest"
    printf '%s  permissions: %s\n' "$prefix" "$perms"
    printf '%s  exclude: []\n\n' "$prefix"
}

# Write a project-tailored starter configuration without overwriting existing files.
generate_init_config() {
    local config_file="$1"
    shift
    local pkgname="" version="1.0.0" description="" license="custom"
    local build_system="none" install_mode="copy-rules" arch="any"
    local check_cmd="" depends="" makedepends="" copy_dirs="" optdepends=""

    while (( $# > 0 )); do
        case "$1" in
            --pkgname) pkgname="${2:-}"; shift 2 ;;
            --version) version="${2:-1.0.0}"; shift 2 ;;
            --description) description="${2:-}"; shift 2 ;;
            --license) license="${2:-custom}"; shift 2 ;;
            --build-system) build_system="${2:-none}"; shift 2 ;;
            --install-mode) install_mode="${2:-copy-rules}"; shift 2 ;;
            --arch) arch="${2:-any}"; shift 2 ;;
            --check) check_cmd="${2:-}"; shift 2 ;;
            --depends) depends="${2:-}"; shift 2 ;;
            --makedepends) makedepends="${2:-}"; shift 2 ;;
            --copy-dirs) copy_dirs="${2:-}"; shift 2 ;;
            --optdepends) optdepends="${2:-}"; shift 2 ;;
            *)
                err "[config] Unknown option for generate_init_config: $1"
                return 1
                ;;
        esac
    done

    if [[ -f "$config_file" ]]; then
        warn "[config] Configuration file already exists: $config_file"
        return 1
    fi

    local config_dir
    config_dir="$(dirname "$config_file")"
    if ! mkdir -p "$config_dir" 2>/dev/null || [[ ! -w "$config_dir" ]]; then
        err "[config] Error: Cannot write to configuration directory: $config_dir"
        return 1
    fi

    local safe_desc safe_check safe_deps safe_md
    safe_desc="${description//$'\r'/ }"
    safe_desc="${safe_desc//$'\n'/ }"
    safe_desc="${safe_desc//\"/\'}"
    safe_check="${check_cmd//$'\r'/ }"
    safe_check="${safe_check//$'\n'/ }"
    safe_check="${safe_check//\"/\'}"
    safe_deps="${depends:-none}"
    safe_md="${makedepends:-none}"

    {
        printf '# AURGen Configuration File (project-tailored starter)\n'
        printf '# Detected defaults (applied automatically unless overridden under package:):\n'
        printf '#   version: %s\n' "$version"
        printf '#   build_system: %s (%s)\n' "$build_system" "$install_mode"
        printf '#   arch: %s\n' "$arch"
        printf '#   license: %s\n' "$license"
        printf '#   depends: %s\n' "$safe_deps"
        printf '#   makedepends: %s\n' "$safe_md"
        printf '#   check: %s\n\n' "${safe_check:-none}"

        printf 'package:\n'
        printf '  name: %s\n' "${pkgname:-package}"
        printf '  # source: release\n'
        if [[ -n "$safe_desc" ]]; then
            printf '  # description: "%s"\n' "$safe_desc"
        fi
        printf '  # license: [%s]\n' "$license"
        if [[ -n "$safe_check" ]]; then
            printf '  # check: "%s"\n' "$safe_check"
        fi
        printf '  # depends: []\n'
        # Detected optional tools, as "pkg (command)" lines, ready to uncomment.
        if [[ -n "$optdepends" ]]; then
            local opt_item opt_pkg opt_cmd
            printf '  # optdepends:\n'
            while IFS= read -r opt_item; do
                [[ -n "$opt_item" ]] || continue
                opt_pkg="${opt_item%% (*}"
                opt_cmd="${opt_item#"$opt_pkg"}"
                opt_cmd="${opt_cmd# (}"
                opt_cmd="${opt_cmd%)}"
                if [[ -n "$opt_cmd" && "$opt_cmd" != "$opt_pkg" ]]; then
                    printf '  #   - "%s: used by %s"\n' "$opt_pkg" "$opt_cmd"
                else
                    printf '  #   - "%s"\n' "$opt_pkg"
                fi
            done <<< "$optdepends"
            printf '\n'
        else
            printf '  # optdepends: []\n\n'
        fi

        if [[ "$install_mode" == "build-system" ]]; then
            printf '# Build system '\''%s'\'' handles installation; uncomment copy sections only for extra files.\n' "$build_system"
            _write_init_copy_section "bin" 1
        elif [[ -n "$copy_dirs" ]]; then
            local -a dir_list=()
            local d
            IFS=',' read -ra dir_list <<< "$copy_dirs"
            for d in "${dir_list[@]}"; do
                [[ -n "$d" ]] && _write_init_copy_section "$d" 0
            done
        else
            printf '# No standard copy directories found yet; uncomment and adjust when adding files.\n'
            _write_init_copy_section "bin" 1
        fi

        printf '# aur_integration:\n'
        printf '#   auto_push: true   # the default; false commits without pushing\n'
        printf '#   validate_before_push: true\n'
        printf '#   commit_message: "Update to version {version}"\n'
    } >| "$config_file"
}

# A destination lands inside double quotes in package(): $pkgname is the only
# expansion allowed, and a ".." component would install outside $pkgdir.
_valid_copy_destination() {
    local LC_ALL=C
    local dest_dir="$1"
    case "$dest_dir" in
        ''|..|../*|*/..|*/../*) return 1 ;;
    esac
    [[ "${dest_dir//\$pkgname/}" =~ ^[A-Za-z0-9._/+-]*$ ]]
}

# Validate configuration
# Usage: validate_config
validate_config() {
    local LC_ALL=C
    local valid=1
    local rule_pair source_dir dest_dir permissions excludes

    if [[ -n "$PKG_NAME" && ! "$PKG_NAME" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
        err "[config] Invalid package.name '$PKG_NAME' (lowercase letters, digits and @._+- only; no leading dot or hyphen)."
        valid=0
    fi

    if [[ -n "${PKG_URL:-}" && ! "$PKG_URL" =~ ^[[:alpha:]][[:alnum:]+.-]*://[^[:space:]\"\']+$ ]]; then
        err "[config] Invalid package.url '$PKG_URL' (expected a single-line URL with scheme://host and no whitespace or quotes)."
        valid=0
    fi

    if [[ -n "${PKG_EPOCH:-}" && ! "$PKG_EPOCH" =~ ^[1-9][0-9]*$ ]]; then
        err "[config] Invalid package.epoch '$PKG_EPOCH' (expected a positive integer)."
        valid=0
    fi

    local dep_item
    for dep_item in "${PKG_DEPENDS[@]}"; do
        if [[ "$dep_item" == \!* && ! "${dep_item#!}" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
            err "[config] Invalid package.depends entry '$dep_item'."
            valid=0
        fi
    done
    for dep_item in "${PKG_MAKEDEPENDS[@]}"; do
        if [[ "$dep_item" == \!* && ! "${dep_item#!}" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
            err "[config] Invalid package.makedepends entry '$dep_item'."
            valid=0
        fi
    done

    local group_item
    for group_item in "${PKG_GROUPS[@]}"; do
        if [[ ! "$group_item" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
            err "[config] Invalid package.groups entry '$group_item'."
            valid=0
        fi
    done

    local rep_item
    for rep_item in "${PKG_REPLACES[@]}"; do
        if [[ ! "$rep_item" =~ ^[a-z0-9@_+][a-z0-9@._+-]*((<=|>=|<|>|=)[A-Za-z0-9._+:~-]+)?$ ]]; then
            err "[config] Invalid package.replaces entry '$rep_item'."
            valid=0
        fi
    done

    local opt_item
    for opt_item in "${PKG_OPTIONS[@]}"; do
        if [[ ! "$opt_item" =~ ^!?[a-z][a-z0-9_-]*$ ]]; then
            err "[config] Invalid package.options entry '$opt_item' (expected makepkg option name, optionally prefixed with '!')."
            valid=0
        fi
    done

    if [[ -n "${PKG_INSTALL:-}" && ( "$PKG_INSTALL" == */* || "$PKG_INSTALL" == .* ) ]]; then
        err "[config] Invalid package.install '$PKG_INSTALL' (must name a file in aur/, without '/' or a leading '.')."
        valid=0
    fi

    local install_var
    for install_var in "${PKG_INSTALL_VARS[@]}"; do
        if [[ ! "$install_var" =~ ^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._/+-]+$ ]]; then
            err "[config] Unsafe install variable in package.install_vars: '$install_var' (expected VAR=value with safe path characters)."
            valid=0
        fi
    done

    local cmake_arg
    for cmake_arg in "${PKG_CMAKE_ARGS[@]}"; do
        if [[ ! "$cmake_arg" =~ ^-D[A-Za-z0-9_]+(:[A-Z]+)?=[A-Za-z0-9_./+=,-]*$ ]]; then
            err "[config] Invalid package.cmake_args entry: $cmake_arg"
            valid=0
        fi
    done

    if [[ -n "${PKG_GPG_KEY:-}" && ! "$PKG_GPG_KEY" =~ ^[[:xdigit:]]{16,40}$ ]]; then
        err "[config] Invalid package.gpg_key '$PKG_GPG_KEY' (expected 16 to 40 hexadecimal characters)."
        valid=0
    fi
    
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

        if ! _valid_copy_destination "$dest_dir"; then
            err "[config] Unsafe copy rule for $source_dir: '$dest_dir:$permissions'"
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
    local rule_pair source_dir dest_dir permissions excludes octal_perms output
    for rule_pair in "${COPY_RULES_ORDERED[@]}"; do
        IFS=':' read -r source_dir dest_dir permissions excludes <<< "$rule_pair"
        # Convert human-readable permissions to octal
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
        output="$source_dir:$dest_dir:$octal_perms"
        [[ -n "$excludes" ]] && output="$output:$excludes"
        printf '%s\n' "$output"
    done
}
