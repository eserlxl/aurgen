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
    local mode="${2:-}"
    
    # Try to get package from comprehensive tool mapping first
    local package
    if command -v map_tool_to_package >/dev/null 2>&1; then
        package=$(map_tool_to_package "$tool")
    fi
    
    # Fallback to PKG_HINT if available and mapping didn't find anything useful
    if [[ -z "$package" || "$package" == "$tool" ]]; then
        if [[ -n "${PKG_HINT:-}" ]]; then
            package="${PKG_HINT[$tool]:-}"
        fi
    fi
    
    # Provide mode-specific context
    local mode_context=""
    case "$mode" in
        local)
            mode_context=" (required for local package building and testing)"
            ;;
        aur)
            mode_context=" (required for AUR package creation and signing)"
            ;;
        aur-git)
            mode_context=" (required for AUR git package creation)"
            ;;
        lint)
            mode_context=" (required for code linting and validation)"
            ;;
        golden)
            mode_context=" (required for golden file generation)"
            ;;
    esac
    
    # Generate installation hint with colors
    if [[ -n "$package" && "$package" != "$tool" ]]; then
        if (( color_enabled )); then
            printf '%b[aurgen] Hint: Install %b%s%b with: %bsudo pacman -S %s%b%s%b%b\n' \
                "${YELLOW:-}" "${CYAN:-}" "$tool" "${YELLOW:-}" "${GREEN:-}" "$package" "${YELLOW:-}" "${SILVER:-}" "$mode_context" "${RESET:-}"
        else
            warn "[aurgen] Hint: Install '$tool' with: sudo pacman -S $package$mode_context"
        fi
    else
        # Try to provide a more helpful message based on common patterns
        local suggestion=""
        case "$tool" in
            getopt)
                suggestion=" (GNU getopt from util-linux package)"
                ;;
            updpkgsums)
                suggestion=" (from pacman-contrib package)"
                ;;
            makepkg)
                suggestion=" (from base-devel package group)"
                ;;
            gpg)
                suggestion=" (from gnupg package)"
                ;;
            gh)
                suggestion=" (from github-cli package)"
                ;;
            shellcheck)
                suggestion=" (from shellcheck package)"
                ;;
            jq)
                suggestion=" (from jq package)"
                ;;
            curl)
                suggestion=" (from curl package)"
                ;;
            *)
                suggestion=" (package name may be the same as tool name)"
                ;;
        esac
        if (( color_enabled )); then
            printf '%b[aurgen] Hint: Install %b%s%b%s%s%b\n' \
                "${YELLOW:-}" "${CYAN:-}" "$tool" "${YELLOW:-}" "${SILVER:-}" "$suggestion$mode_context" "${RESET:-}"
        else
            warn "[aurgen] Hint: Install '$tool'$suggestion$mode_context"
        fi
    fi
}

require() {
    local missing=()
    local mode="${AURGEN_MODE:-}"
    
    for tool in "$@"; do
        if ! command -v "$tool" > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
            missing+=("$tool")
        fi
    done
    
    if (( ${#missing[@]} )); then
        if (( color_enabled )); then
            printf '%bMissing required tool(s) for %b%s%b mode: %b%s%b\n' \
                "${RED:-}" "${CYAN:-}" "$mode" "${RED:-}" "${CYAN:-}" "${missing[*]}" "${RESET:-}" >&2
            printf '%b\n' "${RED:-}" >&2
        else
            err "Missing required tool(s) for '$mode' mode: ${missing[*]}"
            err ""
        fi
        
        for tool in "${missing[@]}"; do
            hint "$tool" "$mode"
        done
        
        if (( color_enabled )); then
            printf '%b\n' "${RED:-}" >&2
            printf '%bPlease install the missing tools and try again.%b\n' "${RED:-}" "${RESET:-}" >&2
            printf '%bFor more information, see the documentation at %b%s%b\n' "${RED:-}" "${CYAN:-}" "doc/AUR.md" "${RESET:-}" >&2
        else
            err ""
            err "Please install the missing tools and try again."
            err "For more information, see the documentation at doc/AUR.md"
        fi
    fi
}

# --- Prompt and Validation Helpers ---
prompt() {
    local msg="$1"; local __resultvar="$2"; local default="${3-}"
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
# --- Usage and Help ---
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
    local pkgver="$2"
    local tarball="$3"
    
    # Extract repo info from URL
    local repo_info
    if [[ "$url" =~ https://github\.com/([^/]+/[^/]+)/releases/download ]]; then
        repo_info="${BASH_REMATCH[1]}"
    else
        # Fallback to curl check if we can't parse the URL
        curl -I -L -f --silent "$url" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"
        return $?
    fi
    
    # Use GitHub API to check if the asset exists (more reliable than CDN)
    if command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        # Check if the release exists first
        if ! gh release view "$pkgver" --repo "$repo_info" &>/dev/null; then
            return 1  # Release doesn't exist
        fi
        
        # Check if the specific asset exists in the release
        if gh release view "$pkgver" --repo "$repo_info" --json assets --jq ".assets[] | select(.name == \"$tarball\")" &>/dev/null; then
            return 0  # Asset exists
        else
            return 1  # Asset doesn't exist
        fi
    else
        # Fallback to curl check if gh is not available
        curl -I -L -f --silent "$url" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"
        return $?
    fi
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
    
    # Create a backup
    cp "$pkgbuild_file" "$pkgbuild_file.backup"
    
    # Use a more robust awk script that properly handles multi-line arrays
    awk -v newurl="$tarball_url" '
        BEGIN { 
            in_source = 0
            source_started = 0
        }
        /^[[:space:]]*source[[:space:]]*=[[:space:]]*\(/ {
            in_source = 1
            source_started = 1
            print "source=(\"" newurl "\")"
            next
        }
        in_source && /^[[:space:]]*\)/ {
            in_source = 0
            next
        }
        in_source {
            next
        }
        { 
            print $0 
        }
    ' "$pkgbuild_file" > "$pkgbuild_file.tmp" && mv "$pkgbuild_file.tmp" "$pkgbuild_file"
    
    # Verify the file is still valid using makepkg --printsrcinfo
    local pkgbuild_dir=$(dirname "$pkgbuild_file")
    local pkgbuild_name=$(basename "$pkgbuild_file")
    if ! (cd "$pkgbuild_dir" && makepkg --printsrcinfo -p "$pkgbuild_name" &>/dev/null); then
        # Restore from backup if makepkg check fails
        mv "$pkgbuild_file.backup" "$pkgbuild_file"
        err "Error: Failed to update source array in PKGBUILD (makepkg check failed). File restored from backup."
        return 1
    fi
    
    # Remove backup if successful
    rm -f "$pkgbuild_file.backup"
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
    
    # Auto-selection logic: if only one key is available, auto-select immediately
    if [[ ${#KEYS[@]} -eq 1 ]]; then
        USER=$(gpg --list-secret-keys "${KEYS[0]}" | grep uid | head -n1 | sed 's/.*] //')
        warn "Only one GPG key found. Auto-selecting: ${KEYS[0]} ($USER)" >&2
        GPG_KEY_ID="${KEYS[0]}"
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
    
    warn "Multiple GPG keys found. Auto-selecting the first key in 10 seconds..." >&2
    warn "Press Enter to select now, or wait for auto-selection." >&2
    
    # Use read with timeout for user input
    if read -t 10 -r choice; then
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