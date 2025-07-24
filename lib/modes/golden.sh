#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
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

mode_golden() {
    extract_pkgbuild_data

    log ${YELLOW}"[golden] Regenerating golden PKGBUILD files in $GOLDEN_DIR."${RESET}
    GOLDEN_MODES=(local aur aur-git)
    mkdir -p "$GOLDEN_DIR"
    any_failed=0
    for mode in "${GOLDEN_MODES[@]}"; do
        log ${YELLOW}"[golden] Generating PKGBUILD for $mode..."${RESET}
        aurgen clean 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG" || warn "[golden] Clean failed for $mode, continuing..."
        _old_ci=${CI:-}
        export CI=1
        export GPG_KEY_ID="TEST_KEY_FOR_DRY_RUN"
        if aurgen --dry-run "$mode" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"; then
            GOLDEN_FILE="$GOLDEN_DIR/PKGBUILD.$mode.golden"
            cp -f "$PKGBUILD" "$GOLDEN_FILE"
            warn "# This is a golden file for test comparison only. Do not use for actual builds or releases." > "$GOLDEN_FILE.tmp"
            cat "$GOLDEN_FILE" >> "$GOLDEN_FILE.tmp"
            mv "$GOLDEN_FILE.tmp" "$GOLDEN_FILE"
            log ${YELLOW}"[golden]"${GREEN}" Updated $GOLDEN_FILE"${RESET}
        else
            err ${YELLOW}"[golden]${RED} Failed to generate PKGBUILD for $mode. Golden file not updated."${RESET}
            any_failed=1
        fi
        if [[ -n $_old_ci ]]; then
            export CI="$_old_ci"
        else
            unset CI
        fi
    done
    if [[ $any_failed -eq 0 ]]; then
        log ${YELLOW}"[golden]"${GREEN}" ✓ All golden files updated."${RESET}
    else
        warn ${YELLOW}"[golden] Some golden files failed to update. Check logs for details."${RESET}
    fi
    exit 0
} 