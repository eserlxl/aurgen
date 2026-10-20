#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen clean mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

# --- Cleanup lingering lock and generated files at script start or before modes ---
cleanup() {
    # Leave .aurgen.lock. Unlinking it lets a second run flock a new inode.
    # Snapshot the files the next run is about to replace.
    # aurgen test sets AURGEN_KEEP_PREV so later cleanups keep that first snapshot.
    # OUT_DIR is aur/dry-run during a dry run, so published files stay put.
    local out="${OUT_DIR:-$AUR_DIR}"
    if [[ "${AURGEN_KEEP_PREV:-}" != 1 && -f "$out/PKGBUILD" ]]; then
        cp -f "$out/PKGBUILD" "$out/PKGBUILD.prev"
    fi
    rm -f "$out/PKGBUILD" "$out/PKGBUILD.git"
    if [[ "${AURGEN_KEEP_PREV:-}" != 1 && -f "$out/.SRCINFO" ]]; then
        cp -f "$out/.SRCINFO" "$out/.SRCINFO.prev"
    fi
    rm -f "$out/.SRCINFO"
    # Remove any test or diff logs
    # Inside aurgen test (AURGEN_KEEP_PREV=1) a child run writes into these logs.
    if [[ "${AURGEN_KEEP_PREV:-}" != 1 ]]; then
        rm -f "$TEST_DIR"/test-*.log
        rm -f "$TEST_DIR"/diff-*.log
    fi
    # Remove any generated tarballs and signatures
    rm -f "$out/${PKGNAME}-"*.tar.gz
    rm -f "$out/${PKGNAME}-"*.tar.gz.sig
    rm -f "$out/${PKGNAME}-"*.tar.gz.asc
    # Remove any generated package files
    rm -f "$out"/*.pkg.tar.*
}

mode_clean() {
    warn "[clean] Removing generated files and directories..."
    cleanup
    local out="${OUT_DIR:-$AUR_DIR}"
    rm -f "$out/.aurgen.lock" "$out/PKGBUILD.prev" "$out/.SRCINFO.prev"
    find "$AUR_DIR" -maxdepth "${MAXDEPTH:-5}" -type d -name "${PKGNAME}-*" -exec rm -r {} +  # Uses MAXDEPTH if set, else defaults to 5
    rm -f "$GOLDEN_DIR"/PKGBUILD.*.golden
    log "${GREEN}[clean] Clean complete.${RESET}"
} 