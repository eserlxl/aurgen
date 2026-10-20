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
    if [[ "${AURGEN_KEEP_PREV:-}" != 1 && -f "$AUR_DIR/PKGBUILD" ]]; then
        cp -f "$AUR_DIR/PKGBUILD" "$AUR_DIR/PKGBUILD.prev"
    fi
    rm -f "$AUR_DIR/PKGBUILD" "$AUR_DIR/PKGBUILD.git"
    if [[ "${AURGEN_KEEP_PREV:-}" != 1 && -f "$AUR_DIR/.SRCINFO" ]]; then
        cp -f "$AUR_DIR/.SRCINFO" "$AUR_DIR/.SRCINFO.prev"
    fi
    rm -f "$AUR_DIR/.SRCINFO"
    # Remove any test or diff logs
    rm -f "$TEST_DIR"/test-*.log
    rm -f "$TEST_DIR"/diff-*.log
    # Remove any generated tarballs and signatures
    rm -f "$AUR_DIR/${PKGNAME}-"*.tar.gz
    rm -f "$AUR_DIR/${PKGNAME}-"*.tar.gz.sig
    rm -f "$AUR_DIR/${PKGNAME}-"*.tar.gz.asc
    # Remove any generated package files
    rm -f "$AUR_DIR"/*.pkg.tar.*
}

mode_clean() {
    warn "[clean] Removing generated files and directories..."
    cleanup
    rm -f "$AUR_DIR/.aurgen.lock" "$AUR_DIR/PKGBUILD.prev" "$AUR_DIR/.SRCINFO.prev"
    find "$AUR_DIR" -maxdepth "${MAXDEPTH:-5}" -type d -name "${PKGNAME}-*" -exec rm -r {} +  # Uses MAXDEPTH if set, else defaults to 5
    rm -f "$GOLDEN_DIR"/PKGBUILD.*.golden
    log "${GREEN}[clean] Clean complete.${RESET}"
} 