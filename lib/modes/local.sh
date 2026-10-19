#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
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
    
    # Extract version and package name for local mode
    extract_pkgbuild_data
    
    declare -r TARBALL="${PKGNAME}-${PKGVER}.tar.gz"
    
    # Create tarball for local mode (similar to aur mode but without GPG signing)
    cd "$PROJECT_ROOT" || exit 1
    
    # Use current HEAD for local mode
    GIT_REF="HEAD"
    log "[local] Using HEAD for local tarball creation"
    
    # Set mtime for reproducible builds
    if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
        ARCHIVE_MTIME="--mtime=@$SOURCE_DATE_EPOCH"
        log "[local] Using SOURCE_DATE_EPOCH=\"$SOURCE_DATE_EPOCH\" for tarball mtime."
    else
        COMMIT_EPOCH=$(git show -s --format=%ct "$GIT_REF")
        ARCHIVE_MTIME="--mtime=@$COMMIT_EPOCH"
        log "[local] Using commit date (epoch \"$COMMIT_EPOCH\") of \"$GIT_REF\" for tarball mtime."
    fi
    
    # Create tarball using filtered file list (same as aur mode)
    (
        set -euo pipefail
        unset CI
        trap '' ERR
        tar czf "$AUR_DIR/$TARBALL" "$ARCHIVE_MTIME" -C "$PROJECT_ROOT" -T <(git ls-files | filter_pkgbuild_sources)
    )
    log "Created $AUR_DIR/$TARBALL using filtered file list and reproducible mtime."
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Copy PKGBUILD.0 to PKGBUILD and update it for local mode
    cp -f "$PROJECT_ROOT/aur/PKGBUILD.0" "$PROJECT_ROOT/aur/PKGBUILD"
    
    # Update PKGBUILD to use the local tarball
    update_source_array_in_pkgbuild "$PROJECT_ROOT/aur/PKGBUILD" "$TARBALL"
    log "[local] Updated PKGBUILD to use local tarball: $TARBALL"
    
    # A local tarball is not a VCS source, so SKIP is not a finished checksum.
    update_checksums || exit 1

    generate_srcinfo
    install_pkg "local"
}
