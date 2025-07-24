#!/bin/bash
# Generate a basic PKGBUILD.0 for the current GitHub project
# Supports CMake, Make, Python, Node.js (auto-detects)
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen gen-pkgbuild0 mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# shellcheck source=/usr/lib/aurgen/colors.sh
. "$LIB_INSTALL_DIR/colors.sh"
init_colors

gen_pkgbuild0() {
    local AUR_DIR PKGBUILD0 REPO_URL PKGBUILD0 REPO_URL GH_USER PKGVER PKGREL DESC LICENSE BUILDSYS SRC_URL
    #PROJECT_ROOT="$(git rev-parse --show-toplevel 2>>"$AURGEN_ERROR_LOG")"
    AUR_DIR="$PROJECT_ROOT/aur"
    mkdir -p "$AUR_DIR"
    PKGBUILD0="$AUR_DIR/PKGBUILD.0"

    # Warn and remove existing PKGBUILD.0 if present
    if [[ -f "$PKGBUILD0" ]]; then
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: Existing $PKGBUILD0 found. Deleting before regeneration.${RESET}" >&2
        rm -f "$PKGBUILD0"
    fi

    # --- Detect project metadata ---
    REPO_URL=$(git config --get remote.origin.url || true)
    GH_USER=$(basename "$(dirname "$REPO_URL")")

    # Try to extract version from git tag or fallback
    PKGVER=$(git describe --tags --abbrev=0 2>>"$AURGEN_ERROR_LOG" | sed 's/^v//')
    if [[ -z "${PKGVER:-}" ]]; then
        PKGVER="1.0.0"
    fi
    PKGREL=1

    # Try to extract description from README
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        DESC=$(head -n 10 "$PROJECT_ROOT/README.md" | grep -m1 -E '^# ' | sed 's/^# //')
        DESC=${DESC:-"$PKGNAME"}
    else
        DESC="$PKGNAME"
    fi

    # Try to detect license
    LICENSE="custom"
    for f in LICENSE LICENSE.txt COPYING; do
        if [[ -f "$PROJECT_ROOT/$f" ]]; then
            if grep -qi 'MIT' "$PROJECT_ROOT/$f"; then LICENSE="MIT"; fi
            if grep -qi 'GPL' "$PROJECT_ROOT/$f"; then LICENSE="GPL3"; fi
            if grep -qi 'Apache' "$PROJECT_ROOT/$f"; then LICENSE="Apache"; fi
        fi
    done

    # Detect build system
    BUILDSYS=""
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]]; then
        BUILDSYS="cmake"
    elif [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        BUILDSYS="make"
    elif [[ -f "$PROJECT_ROOT/setup.py" ]]; then
        BUILDSYS="python"
    elif [[ -f "$PROJECT_ROOT/package.json" ]]; then
        BUILDSYS="node"
    fi

    # Set source URL
    SRC_URL="https://github.com/$GH_USER/$PKGNAME/archive/refs/tags/v$PKGVER.tar.gz"

    # --- Write PKGBUILD.0 ---
    cat > "$PKGBUILD0" <<EOF
# Maintainer: $GH_USER <>
pkgname=$PKGNAME
pkgver=$PKGVER
pkgrel=$PKGREL
desc="$DESC"
arch=(x86_64)
url="https://github.com/$GH_USER/$PKGNAME"
license=('$LICENSE')
depends=()
makedepends=()
source=("$SRC_URL")
b2sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
EOF

    case "$BUILDSYS" in
        cmake)
            cat >> "$PKGBUILD0" <<'EOB'
    cmake -B build -S .
    cmake --build build
EOB
            ;;
        make)
            cat >> "$PKGBUILD0" <<'EOB'
    make
EOB
            ;;
        python)
            cat >> "$PKGBUILD0" <<'EOB'
    python setup.py build
EOB
            ;;
        node)
            cat >> "$PKGBUILD0" <<'EOB'
    npm install
    npm run build || true
EOB
            ;;
        *)
            cat >> "$PKGBUILD0" <<'EOB'
    # Add your build steps here
EOB
            ;;
    esac

    cat >> "$PKGBUILD0" <<'EOF'
}

package() {
    cd "$pkgname-$pkgver"
EOF
    case "$BUILDSYS" in
        cmake)
            cat >> "$PKGBUILD0" <<'EOB'
    DESTDIR="$pkgdir" cmake --install build
EOB
            ;;
        make)
            cat >> "$PKGBUILD0" <<'EOB'
    make DESTDIR="$pkgdir" install
EOB
            ;;
        python)
            cat >> "$PKGBUILD0" <<'EOB'
    python setup.py install --root="$pkgdir" --optimize=1
EOB
            ;;
        node)
            cat >> "$PKGBUILD0" <<'EOB'
    mkdir -p "$pkgdir/usr/lib/aurgen/$pkgname"
    cp -r * "$pkgdir/usr/lib/aurgen/$pkgname/"
EOB
            ;;
        *)
            cat >> "$PKGBUILD0" <<'EOB'
    # Add your install steps here
EOB
            ;;
    esac
    cat >> "$PKGBUILD0" <<'EOF'
}
EOF

    printf "[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME ($BUILDSYS)\n"
} 