#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
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
    # Remove lock file
    rm -f "$AUR_DIR/.aurgen.lock"
    # Remove generated PKGBUILD files
    rm -f "$AUR_DIR/PKGBUILD" "$AUR_DIR/PKGBUILD.git"
    # Remove generated SRCINFO
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
    find "$AUR_DIR" -maxdepth 1 -type d -name "${PKGNAME}-*" -exec rm -r {} +
    rm -f "$GOLDEN_DIR"/PKGBUILD.*.golden
    log "${GREEN}[clean] Clean complete.${RESET}"
} 