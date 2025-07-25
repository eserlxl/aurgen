#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen initialization: color setup, env vars, traps, and early checks

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

# Source helpers for logging and info output
# shellcheck source=../lib/helpers.sh
. "$LIB_INSTALL_DIR/helpers.sh"
# Source color setup
# shellcheck source=../lib/colors.sh
. "$LIB_INSTALL_DIR/colors.sh"

# Call color initialization
init_colors

# --- Directory Setup ---
# Always require git repo for project root

aurgen_init() {
    if git_root=$(git rev-parse --show-toplevel 2>>"$AURGEN_ERROR_LOG"); then
        PROJECT_ROOT="$git_root"
    else
        echo "[aurgen] ERROR: This script must be run inside a git repository (no .git found)." >&2
        exit 1
    fi
    declare -gr PROJECT_ROOT
    declare -gr AUR_DIR="$PROJECT_ROOT/aur"
    GOLDEN_DIR="$PROJECT_ROOT/aur/golden"
    TEST_DIR="$PROJECT_ROOT/aur/test"
    mkdir -p "$AUR_DIR" "$GOLDEN_DIR" "$TEST_DIR"

    # --- Environment and Trap Setup ---
    declare -g PKGBUILD0="$AUR_DIR/PKGBUILD.0"
    declare -gr PKGBUILD="$AUR_DIR/PKGBUILD"
    declare -gr SRCINFO="$AUR_DIR/.SRCINFO"
    declare -gr GOLDEN_DIR
    export PKGBUILD0 PKGBUILD SRCINFO GOLDEN_DIR TEST_DIR AUR_DIR

    # Tool-to-package mapping for Arch Linux hints
    # shellcheck disable=SC2034 # Used externally by sourced scripts
    declare -gAr PKG_HINT=(
        [updpkgsums]=pacman-contrib
        [makepkg]=base-devel
        [curl]=curl
        [gpg]=gnupg
        [gh]=github-cli
        [flock]=util-linux
        [awk]=gawk
        [git]=git
        [jq]=jq
    )

    set -E
    set -o errtrace
    trap 'err "[FATAL] ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND"' ERR

    # --- Constants ---
    # --- PKGNAME Auto-detection from Git ---
    if git_root=$(git rev-parse --show-toplevel 2>>"$AURGEN_ERROR_LOG"); then
        # Try to get repo name from remote URL
        repo_url=$(git config --get remote.origin.url || true)
        if [[ -n "$repo_url" ]]; then
            PKGNAME=$(basename "${repo_url%.git}")
        else
            # Fallback: use git root directory name
            PKGNAME=$(basename "$git_root")
        fi
    else
        echo "[aurgen] ERROR: This script must be run inside a git repository (no .git found)." >&2
        exit 1
    fi
    declare -gr PKGNAME

    # Skip PKGBUILD.0 and GH_USER logic for lint and clean modes
    if [[ "${AURGEN_MODE:-}" != "lint" && "${AURGEN_MODE:-}" != "clean" ]]; then
        # Source PKGBUILD.0 checker
        # shellcheck source=../lib/check-pkgbuild0.sh
        . "$LIB_INSTALL_DIR/check-pkgbuild0.sh"
        # shellcheck source=../lib/gen-pkgbuild0.sh
        . "$LIB_INSTALL_DIR/gen-pkgbuild0.sh"

        # Ensure PKGBUILD.0 exists and is valid before GH_USER detection
        if ! check_pkgbuild0; then
            if [[ -f "$PKGBUILD0" ]]; then
                cp -f "$PKGBUILD0" "$AUR_DIR/PKGBUILD.0.bak"
                warn "[aurgen] PKGBUILD.0 is invalid and will be regenerated. The previous file has been backed up as PKGBUILD.0.bak."
            fi
            gen_pkgbuild0
            if ! check_pkgbuild0; then
                err "[aurgen] ERROR: Failed to generate a valid PKGBUILD.0.\n" >&2
                exit 1
            else
                log "[aurgen] Created new PKGBUILD.0 in $PKGBUILD0"
            fi
        fi

        # --- GH_USER detection and validation ---
        if [[ -z "${GH_USER:-}" ]]; then
            PKGBUILD0_URL=$(awk -F/ '/^url="https:\/\/github.com\// {print $4}' "$PKGBUILD0")
            if [[ -n "$PKGBUILD0_URL" ]]; then
                GH_USER="${PKGBUILD0_URL%\"}"
            else
                printf "[aurgen] ERROR: Could not parse GitHub user/org from PKGBUILD.0 url field.\n" >&2
                printf "[aurgen] Please set the url field in PKGBUILD.0 to your real GitHub repo, e.g.:\n" >&2
                printf '[aurgen]     url="https://github.com/<yourusername>/%s"\n' "$PKGNAME" >&2
                exit 1
            fi
        fi
        if [[ "$GH_USER" == "$PKGNAME" ]]; then
            echo "[aurgen] ERROR: Detected GH_USER='$GH_USER' (same as PKGNAME). This usually means the url field in PKGBUILD.0 is wrong." >&2
            echo "[aurgen] Please set the url field in PKGBUILD.0 to your real GitHub repo, e.g.:" >&2
            echo "[aurgen]     url=\"https://github.com/<yourusername>/$PKGNAME\"" >&2
            echo "[aurgen] Detected url line:" >&2
            grep '^url=' "$PKGBUILD0" >&2
            err "[aurgen] Aborting due to invalid GH_USER configuration."
            exit 1
        fi
        declare -gr GH_USER
    fi

    # Require Bash >= 4 early
    if ((BASH_VERSINFO[0] < 4)); then
        err "Bash ≥ 4 required" >&2
        exit 1
    fi

    # Enable debug tracing if DEBUG_LEVEL is set to a value greater than 1
    if (( ${DEBUG_LEVEL:-0} > 1 )); then
        set -x
    fi

    GPG_TTY=$(tty)
    export GPG_TTY

    set -euo pipefail
    # shellcheck disable=SC2034 # Used externally or for future extension
    color_enabled=${COLOR:-1}
    set -o noclobber
}
