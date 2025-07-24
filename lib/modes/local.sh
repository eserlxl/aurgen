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
    debug "[local] Build and install from local tarball."
    debug "PROJECT_ROOT: $PROJECT_ROOT"
    debug "AUR_DIR: $AUR_DIR"
    debug "PKGBUILD.0: $PROJECT_ROOT/aur/PKGBUILD.0"
    debug "PKGBUILD: $PROJECT_ROOT/aur/PKGBUILD"
    debug "Current working directory: $(pwd)"
    debug "Listing aur dir before copy:"
    ls -l "$PROJECT_ROOT/aur"
    debug "Copying PKGBUILD.0 to PKGBUILD..."
    cp -f "$PROJECT_ROOT/aur/PKGBUILD.0" "$PROJECT_ROOT/aur/PKGBUILD"
    debug "Listing aur dir after copy:"
    ls -l "$PROJECT_ROOT/aur"
    debug "Running update_checksums..."
    update_checksums
    debug "update_checksums completed. Running generate_srcinfo..."
    generate_srcinfo
    debug "generate_srcinfo completed. Running install_pkg..."
    install_pkg "local"
    debug "install_pkg completed."
}
