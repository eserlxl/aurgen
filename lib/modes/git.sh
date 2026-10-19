#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen git mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_git() {
    log "[git] Prepare PKGBUILD for VCS (git) package. No tarball is created."
    # Select GPG key for validpgpkeys
    select_gpg_key
    # origin/HEAD is the clone default; a local checkout may be on another branch.
    local default_branch pkgname_short pkgver_inserted line
    pkgname_short="${PKGNAME%-git}"
    if default_branch=$(git -C "$PROJECT_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
        default_branch="${default_branch#refs/remotes/origin/}"
    else
        default_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)
    fi
    # These land inside source=("...") in a file makepkg sources; git allows $() in ref names.
    if [[ ! "$default_branch" =~ ^[A-Za-z0-9._/+-]+$ || ! "$GH_USER" =~ ^[A-Za-z0-9._-]+$ || ! "$pkgname_short" =~ ^[a-z0-9@._+-]+$ ]]; then
        err "[git] Refusing unsafe source URL parts: user '$GH_USER', repo '$pkgname_short', branch '$default_branch'"
        exit 1
    fi
    awk -v gh_user="$GH_USER" -v pkgname_short="$pkgname_short" -v branch="$default_branch" '
        BEGIN { sums = "b2sums=(\"SKIP\")" }
        /^pkgname=/ {
            print "pkgname=" pkgname_short "-git"
            print "provides=(" pkgname_short ")"
            print "conflicts=(" pkgname_short ")"
            next
        }
        # When we see the start of the source array, replace it and enter skip mode
        /^source=\(/ {
            print "source=(\"git+https://github.com/" gh_user "/" pkgname_short ".git#branch=" branch "\")";
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
    # Insert pkgver() as before if missing. No aurgen variables: makepkg does not set them.
    if ! grep -q '^pkgver()' "$AUR_DIR/PKGBUILD.git"; then
        pkgver_inserted=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "$line"
            if [[ "$pkgver_inserted" -eq 0 && "$line" == source=* ]]; then
                printf '\n'
                cat <<'EOF'
pkgver() {
    cd "$srcdir/${pkgname%-git}"
    if ver=$(git describe --long --tags 2>/dev/null); then
        printf '%s\n' "$ver" | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
    else
        printf 'r%s.%s\n' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
    fi
}
EOF
                pkgver_inserted=1
            fi
        done < "$AUR_DIR/PKGBUILD.git" >| "$AUR_DIR/PKGBUILD.git.tmp"
        mv "$AUR_DIR/PKGBUILD.git.tmp" "$AUR_DIR/PKGBUILD.git"
    fi
    PKGBUILD_TEMPLATE="$AUR_DIR/PKGBUILD.git"
    # Inject git to makedepends if missing
    if ! grep -q '^makedepends=.*git' "$PKGBUILD_TEMPLATE"; then
        # Check if makedepends already exists
        if grep -q '^makedepends=' "$PKGBUILD_TEMPLATE"; then
            # Append git to existing makedepends
            sed -i 's/^makedepends=(\([^)]*\))/makedepends=(\1 git)/' "$PKGBUILD_TEMPLATE"
            log "[git] Added git to existing makedepends in PKGBUILD.git."
        else
            # Insert new makedepends line after pkgname
            awk 'BEGIN{done=0} \
                /^pkgname=/ && !done {print; print "makedepends=(git)"; done=1; next} \
                {print}' "$PKGBUILD_TEMPLATE" >| "$PKGBUILD_TEMPLATE.tmp" && mv "$PKGBUILD_TEMPLATE.tmp" "$PKGBUILD_TEMPLATE"
            log "[git] Injected makedepends=(git) into PKGBUILD.git."
        fi
    fi
    cp -f "$PKGBUILD_TEMPLATE" "$PKGBUILD"
    log "[git] PKGBUILD.git generated and copied to PKGBUILD."
    # Set validpgpkeys if missing
    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        grep -q "^validpgpkeys=('${GPG_KEY_ID}')" "$PKGBUILD" || printf "validpgpkeys=('%s')\n" "$GPG_KEY_ID" >> "$PKGBUILD"
    fi
    generate_srcinfo
    install_pkg "git"
}
