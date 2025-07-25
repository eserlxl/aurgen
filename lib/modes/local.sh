#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen local mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_local() {
    log "${SILVER}[local] Build and install from local tarball.${RESET}"
    cp -f "$PROJECT_ROOT/aur/PKGBUILD.0" "$PROJECT_ROOT/aur/PKGBUILD"
    update_checksums
    generate_srcinfo
    install_pkg "local"
}
