#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
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
        /^pkgname=/ {
            print "pkgname=vglog-filter-git"; next
        }
        /^source=/ {
            print "source=(\"git+https://github.com/" gh_user "/vglog-filter.git#branch=main\")";
            print sums;
            next
        }
        /^b2sums=/ || /^sha256sums=/ { next }
        { gsub(/\${pkgname}-\${pkgver}|\$pkgname-\$pkgver/, pkgname_short); print }
    ' "$PKGBUILD0" >| "$OUTDIR/PKGBUILD.git"
    # Insert pkgver() as before if missing
    if ! grep -q '^pkgver()' "$OUTDIR/PKGBUILD.git"; then
        awk '
            /^source=/ {
                print;
                print "";
                print "pkgver() {";
                print "    cd \"$srcdir/${pkgname%-git}\"";
                printf "    git describe --long --tags 2>/dev/null | sed \"s/^v//;s/-/./g\" || \\\n";
                print "        printf \"r%s.%s\" \"$(git rev-list --count HEAD)\" \"$(git rev-parse --short HEAD)\"";
                print "}";
                next
            }
            { print }
        ' "$OUTDIR/PKGBUILD.git" >| "$OUTDIR/PKGBUILD.git.tmp" && mv "$OUTDIR/PKGBUILD.git.tmp" "$OUTDIR/PKGBUILD.git"
    fi
    PKGBUILD_TEMPLATE="$OUTDIR/PKGBUILD.git"
    # Inject makedepends=(git) if missing or incomplete
    if ! grep -q '^makedepends=.*git' "$PKGBUILD_TEMPLATE"; then
        awk 'BEGIN{done=0} \
            /^pkgname=/ && !done {print; print "makedepends=(git)"; done=1; next} \
            {print}' "$PKGBUILD_TEMPLATE" >| "$PKGBUILD_TEMPLATE.tmp" && mv "$PKGBUILD_TEMPLATE.tmp" "$PKGBUILD_TEMPLATE"
        log "[aur-git] Injected makedepends=(git) into PKGBUILD.git."
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
