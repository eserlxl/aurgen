#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen golden mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

# Put the published aur/PKGBUILD and .SRCINFO back after mode_golden's children ran.
_golden_restore_published() {
    local dir="${_GOLDEN_PUBLISHED:-}" published_file
    [[ -n "$dir" && -d "$dir" ]] || return 0
    for published_file in PKGBUILD .SRCINFO; do
        if [[ -f "$dir/$published_file" ]]; then
            mv -f -- "$dir/$published_file" "$AUR_DIR/$published_file"
        fi
    done
    rmdir -- "$dir" 2>/dev/null || true
    _GOLDEN_PUBLISHED=""
}

mode_golden() {
    if [[ "${dry_run:-0}" -eq 1 ]]; then
        err "[golden] golden has no dry run: it regenerates the files in aur/golden/"
        exit 1
    fi
    extract_pkgbuild_data || exit 1

    log "${YELLOW}[golden] Regenerating golden PKGBUILD files in $GOLDEN_DIR.${RESET}"
    GOLDEN_MODES=(local aur git)
    mkdir -p "$GOLDEN_DIR"
    any_failed=0
    # No clean here: each golden comes from a --dry-run child that writes only aur/dry-run/,
    # and a real clean would delete the published aur/PKGBUILD, .SRCINFO and their .prev copies.
    # A mode that fails below keeps its previous golden because nothing removes it.
    # A dry-run aur child would read the published aur/PKGBUILD as the previous version and
    # bump pkgrel, so the published files sit in a temp dir while the children run.
    _GOLDEN_PUBLISHED="$(mktemp -d)"
    local published_file
    for published_file in PKGBUILD .SRCINFO; do
        if [[ -f "$AUR_DIR/$published_file" ]]; then
            mv -- "$AUR_DIR/$published_file" "$_GOLDEN_PUBLISHED/$published_file"
        fi
    done
    trap _golden_restore_published EXIT
    for mode in "${GOLDEN_MODES[@]}"; do
        log "${YELLOW}[golden] Generating PKGBUILD for $mode...${RESET}"
        _old_ci=${CI:-}
        export CI=1
        export GPG_KEY_ID="TEST_KEY_FOR_DRY_RUN"
        if "$AURGEN_BIN" --dry-run "$mode" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"; then
            GOLDEN_FILE="$GOLDEN_DIR/PKGBUILD.$mode.golden"
            # The --dry-run child writes its PKGBUILD under aur/dry-run/, not to $PKGBUILD.
            cp -f "$AUR_DIR/dry-run/PKGBUILD" "$GOLDEN_FILE"
            echo "# This is a golden file for test comparison only. Do not use for actual builds or releases." >| "$GOLDEN_FILE.tmp"
            cat "$GOLDEN_FILE" >> "$GOLDEN_FILE.tmp"
            mv "$GOLDEN_FILE.tmp" "$GOLDEN_FILE"
            log "${YELLOW}[golden]${GREEN} Updated $GOLDEN_FILE${RESET}"
        else
            err "${YELLOW}[golden]${RED} Failed to generate PKGBUILD for $mode. Golden file not updated.${RESET}"
            any_failed=1
        fi
        if [[ -n $_old_ci ]]; then
            export CI="$_old_ci"
        else
            unset CI
        fi
    done
    if [[ $any_failed -eq 0 ]]; then
        log "${YELLOW}[golden]${GREEN} ✓ All golden files updated.${RESET}"
    else
        warn "${YELLOW}[golden] Some golden files failed to update. Check logs for details.${RESET}"
        exit 1
    fi
    exit 0
}
