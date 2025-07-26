#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen aur-git mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_aur_git() {
    log "[aur-git] Prepare PKGBUILD for VCS (git) package. No tarball is created."
    awk -v gh_user="$GH_USER" -v pkgname_short="${PKGNAME%-git}" '
        BEGIN { sums = "b2sums=(\"SKIP\")" }
        # When we see the start of the source array, replace it and enter skip mode
        /^source=\(/ {
            print "source=(\"git+https://github.com/" gh_user "/" pkgname_short ".git#branch=main\")";
            print sums;
            in_source=1;
            next
        }
        # Skip all lines until we see the closing parenthesis of the array
        in_source && /^\)/ { in_source=0; next }
        # While in skip mode, skip lines
        in_source { next }
        # Remove b2sums and sha256sums lines
        /^b2sums=/ || /^sha256sums=/ { next }
        # Otherwise, print lines as-is, with variable substitution
        { gsub(/\${pkgname}-\${pkgver}|\$pkgname-\$pkgver/, pkgname_short); print }
    ' "$PKGBUILD0" >| "$AUR_DIR/PKGBUILD.git"
    # Insert pkgver() as before if missing
    if ! grep -q '^pkgver()' "$AUR_DIR/PKGBUILD.git"; then
        awk '
            /^source=/ {
                print;
                print "";
                print "pkgver() {";
                print "    cd \"$srcdir/${pkgname%-git}\"";
                printf "    git describe --long --tags 2>>\"$AURGEN_ERROR_LOG\" | sed \"s/^v//;s/-/./g\" || \\\n";
                print "        printf \"r%s.%s\" \"$(git rev-list --count HEAD)\" \"$(git rev-parse --short HEAD)\"";
                print "}";
                next
            }
            { print }
        ' "$AUR_DIR/PKGBUILD.git" >| "$AUR_DIR/PKGBUILD.git.tmp" && mv "$AUR_DIR/PKGBUILD.git.tmp" "$AUR_DIR/PKGBUILD.git"
    fi
    PKGBUILD_TEMPLATE="$AUR_DIR/PKGBUILD.git"
    # Inject git to makedepends if missing
    if ! grep -q '^makedepends=.*git' "$PKGBUILD_TEMPLATE"; then
        # Check if makedepends already exists
        if grep -q '^makedepends=' "$PKGBUILD_TEMPLATE"; then
            # Append git to existing makedepends
            sed -i 's/^makedepends=(\([^)]*\))/makedepends=(\1 git)/' "$PKGBUILD_TEMPLATE"
            log "[aur-git] Added git to existing makedepends in PKGBUILD.git."
        else
            # Insert new makedepends line after pkgname
            awk 'BEGIN{done=0} \
                /^pkgname=/ && !done {print; print "makedepends=(git)"; done=1; next} \
                {print}' "$PKGBUILD_TEMPLATE" >| "$PKGBUILD_TEMPLATE.tmp" && mv "$PKGBUILD_TEMPLATE.tmp" "$PKGBUILD_TEMPLATE"
            log "[aur-git] Injected makedepends=(git) into PKGBUILD.git."
        fi
    fi
    cp -f "$PKGBUILD_TEMPLATE" "$PKGBUILD"
    log "[aur-git] PKGBUILD.git generated and copied to PKGBUILD."
    # Set validpgpkeys if missing
    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        grep -q "^validpgpkeys=('${GPG_KEY_ID}')" "$PKGBUILD" || printf "validpgpkeys=('%s')\n" "$GPG_KEY_ID" >> "$PKGBUILD"
    fi
    generate_srcinfo
    install_pkg "aur-git"
}
