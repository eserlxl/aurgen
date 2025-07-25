#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen helpers library: error handling, logging, prompts, validation, and utility functions

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

# --- Error and Logging Helpers ---
# Set color_enabled=1 by default if not set
: "${color_enabled:=1}"
err() {
    # Print error message in red to stderr
    echo -e "${RED:-}[ERROR] $*${RESET:-}" >&2
}
init_error_trap() {
    set -E
    set -o errtrace
    trap 'if (( ${DEBUG_LEVEL:-0} > 0 )); then err "[FATAL] ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND"; else err "[FATAL] ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND"; exit 1; fi' ERR
}
warn() {
    (( color_enabled )) && printf '%b%s%b\n' "${YELLOW:-}" "$*" "${RESET:-}" || printf '%s\n' "$*"
}
log() {
    printf '%b\n' "$*"
}
debug() {
    if (( ${DEBUG_LEVEL:-0} > 0 )); then
        (( color_enabled )) && printf '%b[DEBUG] %s%b\n' "${CYAN:-}" "$*" "${RESET:-}" || printf '[DEBUG] %s\n' "$*"
    fi
}

# --- Tool Hint and Requirement Helpers ---
hint() {
    local tool="$1"
    local pkg="${PKG_HINT[$tool]:-}"
    if [[ -n "$pkg" ]]; then
        warn "[aurgen] Hint: Install '$tool' with: sudo pacman -S $pkg"
    else
        warn "[aurgen] Hint: Install '$tool' (no package hint available)"
    fi
}
require() {
    local missing=()
    for tool in "$@"; do
        if ! command -v "$tool" > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
            missing+=("$tool")
        fi
    done
    if (( ${#missing[@]} )); then
        for tool in "${missing[@]}"; do
            hint "$tool"
        done
        err "Missing required tool(s): ${missing[*]}"
    fi
}

# --- Prompt and Validation Helpers ---
prompt() {
    local msg="$1"; local __resultvar="$2"; local default="$3"
    if have_tty; then
        read -r -p "$msg" input
        if [[ -z "$input" && -n "$default" ]]; then
            input="$default"
        fi
        eval "$__resultvar=\"$input\""
    else
        eval "$__resultvar=\"$default\""
    fi
}
have_tty() {
    [[ -t 0 ]]
}
is_valid_mode() {
    local mode="$1"
    for valid_mode_name in "${VALID_MODES[@]}"; do
        if [[ "$mode" == "$valid_mode_name" ]]; then
            return 0
        fi
    done
    return 1
}

# --- Usage and Help ---
usage() {
    printf 'Usage: aurgen [OPTIONS] MODE\n'
    printf 'Modes: local | aur | aur-git | clean | test | lint | golden\n'
}
help() {
    usage
    printf '\n'
    printf 'Options:\n'
    printf '  -n, --no-color      Disable color output\n'
    printf '  -a, --ascii-armor   Use ASCII-armored GPG signatures (.asc)\n'
    printf '  -d, --dry-run       Dry run (no changes, for testing)\n'
    printf '  --no-wait           Skip post-upload wait for asset availability (for CI/advanced users, or set NO_WAIT=1)\n'
    printf '  --maxdepth N        Set maximum search depth for lint mode only (default: 5)\n'
    printf '  -h, --help          Show detailed help and exit\n'
    printf '  --usage             Show minimal usage and exit\n'
    printf '\n'
    printf 'All options must appear before the mode.\n'
    printf 'For full documentation, see doc/AUR.md.\n'
    printf '\n'
    printf 'If a required tool is missing, a hint will be printed with an installation suggestion (e.g., pacman -S pacman-contrib for updpkgsums).\n'
    printf '\n'
    printf 'The lint mode runs shellcheck and bash -n on this script for quick CI/self-test.\n'
    printf '\n'
    printf 'The golden mode regenerates golden PKGBUILD files for test/fixtures/.\n'
}

# --- PKGBUILD and Install Helpers ---
set_signature_ext() {
    if [[ ${ascii_armor:-0} -eq 1 ]]; then
        SIGNATURE_EXT=".asc"
        GPG_ARMOR_OPT="--armor"
    else
        SIGNATURE_EXT=".sig"
        GPG_ARMOR_OPT=""
    fi
    export SIGNATURE_EXT
    export GPG_ARMOR_OPT
}

asset_exists() {
    local url="$1"
    curl -I -L -f --silent "$url" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"
}
update_checksums() {
    cd "$PROJECT_ROOT/aur" || exit 1
    if ! updpkgsums; then
        err "[aurgen] updpkgsums failed."
    fi
}
generate_srcinfo() {
    cd "$PROJECT_ROOT/aur" || exit 1
    rm -f "$SRCINFO" || exit 1
    if ! makepkg --printsrcinfo > "$SRCINFO"; then
        err "[aurgen] makepkg --printsrcinfo failed."
    fi
}
install_pkg() {
    local mode="$1"
    : "${dry_run:=0}"
    if (( dry_run )); then
        warn "[install_pkg] Dry run: skipping install for mode $mode."
        return
    fi
    case "$mode" in
        local)
            warn "[install_pkg] Running makepkg -si for local install."
            makepkg -si
            ;;
        aur|aur-git)
            log "${GREEN}[install_pkg] PKGBUILD and .SRCINFO are ready for AUR upload.${RESET}"
            ;;
        *)
            err "[install_pkg] Unknown mode: $mode"
            ;;
    esac
}

# --- PKGBUILD Source Array Helper ---
# Replace the entire source array in a PKGBUILD file with a new tarball URL, preserving extra sources
update_source_array_in_pkgbuild() {
    local pkgbuild_file="$1"
    local tarball_url="$2"
    awk -v newurl="$tarball_url" '
        BEGIN { in_source=0 }
        /^source=\(/ {
            in_source=1; print "source=(\"" newurl "\")"; next
        }
        in_source && /\)/ {
            in_source=0; next
        }
        in_source { next }
        { print $0 }
    ' "$pkgbuild_file" > "$pkgbuild_file.tmp" && mv "$pkgbuild_file.tmp" "$pkgbuild_file"
}

# --- PKGBUILD Data Extraction Helper ---
extract_pkgbuild_data() {
    # 1. Extract pkgver from PKGBUILD.0
    if [[ ! -f "$PKGBUILD0" ]]; then
        err "Error: $PKGBUILD0 not found. Please create it from your original PKGBUILD."
        return 0
    fi
    PKGVER_LINE=$(awk -F= '/^[[:space:]]*pkgver[[:space:]]*=/ {print $2}' "$PKGBUILD0")
    if [[ -z "$PKGVER_LINE" ]]; then
        warn "[aur] Could not find a static pkgver assignment in $PKGBUILD0. Printing file contents for debugging:"
        cat "$PKGBUILD0" >&2
        err "Error: Could not extract pkgver line from $PKGBUILD0. Ensure it contains a line like 'pkgver=1.2.3' with no shell expansion."
        return 0
    fi
    if [[ "$PKGVER_LINE" =~ [\$\`\(\)] ]]; then
        warn "[aur] Extracted pkgver line: '$PKGVER_LINE'"
        cat "$PKGBUILD0" >&2
        err "Dynamic pkgver assignment detected in $PKGBUILD0. Only static assignments are supported."
        return 0
    fi
    PKGVER=$(echo "$PKGVER_LINE" | tr -d "\"'[:space:]")
    if [[ -z "$PKGVER" ]]; then
        warn "[aur] PKGVER_LINE was: '$PKGVER_LINE'"
        cat "$PKGBUILD0" >&2
        err "Error: Could not extract static pkgver from $PKGBUILD0"
        return 0
    fi
    declare -r PKGVER
}

# --- GPG Key Selection Helper ---
select_gpg_key() {
    # If GPG_KEY_ID is already set and non-empty, do not prompt again
    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        # Handle test/dry-run case where GPG_KEY_ID is set to a test value
        if [[ "$GPG_KEY_ID" == "TEST_KEY_FOR_DRY_RUN" ]]; then
            warn "Test mode detected: using test GPG key for dry-run" >&2
            return 0
        fi
        return 0
    fi
    
    # For dry-run mode, always use test key to avoid GPG-related issues
    if [[ "${dry_run:-0}" -eq 1 ]]; then
        warn "Dry-run mode detected: using test GPG key to avoid signing issues" >&2
        GPG_KEY_ID="TEST_KEY_FOR_DRY_RUN"
        export GPG_KEY_ID
        return 0
    fi
    
    mapfile -t KEYS < <(gpg --list-secret-keys --with-colons | awk -F: '/^sec/ {print $5}')
    if [[ ${#KEYS[@]} -eq 0 ]]; then
        err "No GPG secret keys found. Please generate or import a GPG key."
        GPG_KEY_ID=""
        return 1
    fi
    
    # Auto-selection logic: if only one key is available, wait 10 seconds then auto-select
    if [[ ${#KEYS[@]} -eq 1 ]]; then
        warn "Available GPG secret keys:" >&2
        USER=$(gpg --list-secret-keys "${KEYS[0]}" | grep uid | head -n1 | sed 's/.*] //')
        warn "1. ${KEYS[0]} ($USER)" >&2
        warn "Only one GPG key found. Auto-selecting in 10 seconds..." >&2
        sleep 10
        GPG_KEY_ID="${KEYS[0]}"
        warn "Auto-selected GPG key: ${KEYS[0]} ($USER)" >&2
        export GPG_KEY_ID
        return 0
    fi
    
    # Multiple keys: show all and prompt with timeout
    warn "Available GPG secret keys:" >&2
    for i in "${!KEYS[@]}"; do
        USER=$(gpg --list-secret-keys "${KEYS[$i]}" | grep uid | head -n1 | sed 's/.*] //')
        warn "$((i+1)). ${KEYS[$i]} ($USER)" >&2
    done
    if ! have_tty; then
        err "No interactive terminal: please set GPG_KEY_ID in headless mode."
        GPG_KEY_ID=""
        return 1
    fi
    
    warn "Multiple GPG keys found. Auto-selecting the first key in 15 seconds..." >&2
    warn "Press Enter to select now, or wait for auto-selection." >&2
    
    # Use read with timeout for user input
    if read -t 15 -r choice; then
        # User provided input
        if [[ -z "$choice" ]]; then
            # User just pressed Enter, select first key
            choice=1
        fi
    else
        # Timeout occurred, auto-select first key
        choice=1
        warn "Timeout reached. Auto-selecting the first GPG key." >&2
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#KEYS[@]} )); then
        err "Invalid selection."
        GPG_KEY_ID=""
        return 1
    fi
    
    USER=$(gpg --list-secret-keys "${KEYS[$((choice-1))]}" | grep uid | head -n1 | sed 's/.*] //')
    GPG_KEY_ID="${KEYS[$((choice-1))]}"
    warn "Selected GPG key: ${KEYS[$((choice-1))]} ($USER)" >&2
    export GPG_KEY_ID
}