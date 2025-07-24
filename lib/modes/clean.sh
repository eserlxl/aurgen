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

mode_clean() {
    warn "[clean] Removing generated files and directories..."
    rm -f "$OUTDIR/.aurgen.lock"
    rm -f "$OUTDIR/PKGBUILD" "$OUTDIR/PKGBUILD.git"
    rm -f "$OUTDIR/.SRCINFO"
    rm -f "$TEST_DIR"/*.log
    rm -f "$TEST_DIR"/diff-*.log
    rm -f "$OUTDIR"/${PKGNAME}-*.tar.gz*
    rm -f "$OUTDIR"/*.pkg.tar.*
    find "$OUTDIR" -maxdepth 1 -type d -name "${PKGNAME}-*" -exec rm -r {} +
    rm -f "$GOLDEN_DIR"/PKGBUILD.*.golden
    log ${GREEN}"[clean] Clean complete."${RESET}
} 