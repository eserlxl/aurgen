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
    cp -f "$PROJECT_ROOT/aur/PKGBUILD.0" "$PROJECT_ROOT/aur/PKGBUILD"
    
    # For local mode, we skip checksum updates since we're working with local files
    # Set b2sums to SKIP to avoid updpkgsums issues with missing files
    if ! grep -q '^b2sums=' "$PROJECT_ROOT/aur/PKGBUILD"; then
        printf "b2sums=('SKIP')\n" >> "$PROJECT_ROOT/aur/PKGBUILD"
        log "[local] Added b2sums=('SKIP') to PKGBUILD for local mode."
    fi
    
    # For local mode, use current HEAD instead of a specific tag to get all current files
    if grep -q 'git+' "$PROJECT_ROOT/aur/PKGBUILD"; then
        sed -i 's/#tag=1\.0\.0/#branch=main/' "$PROJECT_ROOT/aur/PKGBUILD"
        log "[local] Updated git source to use current HEAD instead of tag for local mode."
    fi
    
    # Ensure pkgver() function exists for git-based PKGBUILD
    if grep -q 'git+' "$PROJECT_ROOT/aur/PKGBUILD" && ! grep -q '^pkgver()' "$PROJECT_ROOT/aur/PKGBUILD"; then
        awk '
            /^source=/ {
                print;
                print "";
                print "pkgver() {";
                print "    cd \"$srcdir/${pkgname}\"";
                printf "    git describe --long --tags 2>>\"$AURGEN_ERROR_LOG\" | sed \"s/^v//;s/-/./g\" || \\\n";
                print "        printf \"r%s.%s\" \"$(git rev-list --count HEAD)\" \"$(git rev-parse --short HEAD)\"";
                print "}";
                next
            }
            { print }
        ' "$PROJECT_ROOT/aur/PKGBUILD" > "$PROJECT_ROOT/aur/PKGBUILD.tmp" && mv "$PROJECT_ROOT/aur/PKGBUILD.tmp" "$PROJECT_ROOT/aur/PKGBUILD"
        log "[local] Added pkgver() function to PKGBUILD for git-based source."
    fi
    
    # Fix package() function for git-based PKGBUILD (use $pkgname instead of $PKGNAME-$PKGVER)
    if grep -q 'git+' "$PROJECT_ROOT/aur/PKGBUILD"; then
        sed -i 's/cd "$PKGNAME-$PKGVER"/cd "$pkgname"/' "$PROJECT_ROOT/aur/PKGBUILD"
        log "[local] Fixed package() function for git-based source."
    fi
    
    generate_srcinfo
    install_pkg "local"
}
