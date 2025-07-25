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

# shellcheck source=lib/colors.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/colors.sh"
# shellcheck source=lib/helpers.sh
. "$LIB_INSTALL_DIR/helpers.sh"
init_colors

# Generate PKGBUILD.HEADER if it does not exist, using project metadata and license info
# Usage: gen_pkgbuild_header <GH_USER> <GH_USER_EMAIL> <PROJECT_NAME> <LICENSE_TYPE>
gen_pkgbuild_header() {
    local GH_USER="$1" GH_USER_EMAIL="$2" PROJECT_NAME="$3" LICENSE_TYPE="$4"
    local HEADER_FILE="$AUR_DIR/PKGBUILD.HEADER"
    if [[ -f "$HEADER_FILE" ]]; then
        return 0
    fi
    case "$LICENSE_TYPE" in
        GPL3|GPLv3|GPL-3.0|GPL-3.0-or-later)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $GH_USER <$GH_USER_EMAIL>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of $PROJECT_NAME and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Maintainer: $GH_USER <$GH_USER_EMAIL>
EOF
            ;;
        MIT)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $GH_USER <$GH_USER_EMAIL>
# SPDX-License-Identifier: MIT
#
# This file is part of $PROJECT_NAME and is licensed under
# the MIT License. See the LICENSE file in the project root for details.

# Maintainer: $GH_USER <$GH_USER_EMAIL>
EOF
            ;;
        Apache*)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $GH_USER <$GH_USER_EMAIL>
# SPDX-License-Identifier: Apache-2.0
#
# This file is part of $PROJECT_NAME and is licensed under
# the Apache License 2.0. See the LICENSE file in the project root for details.

# Maintainer: $GH_USER <$GH_USER_EMAIL>
EOF
            ;;
        *)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $GH_USER <$GH_USER_EMAIL>
# SPDX-License-Identifier: Custom
#
# This file is part of $PROJECT_NAME. See the LICENSE file in the project root for details.

# Maintainer: $GH_USER <$GH_USER_EMAIL>
EOF
            ;;
    esac
}

gen_pkgbuild0() {
    local PKGBUILD0 REPO_URL PKGBUILD0 REPO_URL GH_USER PKGVER PKGREL DESC LICENSE BUILDSYS SRC_URL
    #PROJECT_ROOT="$(git rev-parse --show-toplevel 2>>"$AURGEN_ERROR_LOG")"
    mkdir -p "$AUR_DIR"
    PKGBUILD0="$AUR_DIR/PKGBUILD.0"

    # Warn and remove existing PKGBUILD.0 if present
    if [[ -f "$PKGBUILD0" ]]; then
        echo -e "${YELLOW}[gen-pkgbuild0] Existing $PKGBUILD0 found. Deleting before regeneration.${RESET}" >&2
        rm -f "$PKGBUILD0"
    fi

    # --- Detect project metadata ---
    REPO_URL=$(git config --get remote.origin.url || true)
    GH_USER=$(basename "$(dirname "$REPO_URL")")

    # Try to extract version from git tag or fallback
    PKGVER=$(git describe --tags --abbrev=0 2>>"$AURGEN_ERROR_LOG" | sed 's/^v//') || true
    if [[ -z "${PKGVER:-}" ]]; then
        PKGVER="1.0.0"
        PKGVER_FALLBACK=1
    else
        PKGVER_FALLBACK=0
        debug "[gen-pkgbuild0] Success: Found git tag $PKGVER." >&2
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
    LICENSE_FOUND=0
    for f in LICENSE LICENSE.txt COPYING; do
        if [[ -f "$PROJECT_ROOT/$f" ]]; then
            if grep -qi 'MIT' "$PROJECT_ROOT/$f"; then LICENSE="MIT"; LICENSE_FOUND=1; fi
            if grep -qi 'GPL' "$PROJECT_ROOT/$f"; then LICENSE="GPL3"; LICENSE_FOUND=1; fi
            if grep -qi 'Apache' "$PROJECT_ROOT/$f"; then LICENSE="Apache"; LICENSE_FOUND=1; fi
        fi
    done
    if [[ $LICENSE_FOUND -eq 1 ]]; then
        log "[gen-pkgbuild0] Detected license: $LICENSE"
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: No license file found in project root. Setting license to 'custom'. Please add a LICENSE file for proper packaging.${RESET}" >&2
    fi

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

    set +u
    # Set source URL using GitHub CLI
    if ! command -v gh >/dev/null 2>&1; then
        echo -e "${YELLOW}[gen-pkgbuild0] Error: GitHub CLI (gh) is required but not found. Please install gh and authenticate before running this script.${RESET}" >&2
        exit 1
    fi

    if [[ "$PKGVER_FALLBACK" -eq 0 ]]; then
        # Try to get the tarball URL for the tag
        SRC_URL=$(gh release view "v$PKGVER" --json tarballUrl -q .tarballUrl 2>>"$AURGEN_ERROR_LOG" || true)
        if [[ -z "$SRC_URL" ]]; then
            # Try without 'v' prefix
            SRC_URL=$(gh release view "$PKGVER" --json tarballUrl -q .tarballUrl 2>>"$AURGEN_ERROR_LOG" || true)
        fi
        if [[ -z "$SRC_URL" ]]; then
            echo -e "${YELLOW}[gen-pkgbuild0] Error: Could not find a GitHub release tarball for version $PKGVER. Please ensure the release exists and try again.${RESET}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: No git tag found, using fallback version $PKGVER. No GitHub release tarball will be set in source array. Please update manually if needed.${RESET}" >&2
        SRC_URL=""
    fi
    rm -f "$PKGBUILD0" || exit 1
    # --- Write PKGBUILD.0 ---
    # Use PKGBUILD.HEADER if it exists and is readable. If it exists but cannot be read (e.g., permission denied), warn and continue with empty header. If it does not exist, try to generate it from project metadata.
    if [[ -f "$AUR_DIR/PKGBUILD.HEADER" ]]; then
        if [[ ! -r "$AUR_DIR/PKGBUILD.HEADER" ]]; then
            warn "[gen-pkgbuild0] Warning: $AUR_DIR/PKGBUILD.HEADER exists but cannot be read (permission denied or unreadable). Continuing with empty header."
            : > "$PKGBUILD0" || { echo -e "${YELLOW}[gen-pkgbuild0] Error: Failed to write empty header to $PKGBUILD0 (write error).${RESET}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        else
            cat "$AUR_DIR/PKGBUILD.HEADER" > "$PKGBUILD0" || { echo -e "${YELLOW}[gen-pkgbuild0] Error: Failed to write header to $PKGBUILD0 (write error).${RESET}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        fi
    else
        # Try to generate PKGBUILD.HEADER from project metadata
        GH_USER_EMAIL=$(git config user.email || echo "nobody@example.com")
        gen_pkgbuild_header "$GH_USER" "$GH_USER_EMAIL" "$PKGNAME" "$LICENSE"
        if [[ -f "$AUR_DIR/PKGBUILD.HEADER" && -r "$AUR_DIR/PKGBUILD.HEADER" ]]; then
            cat "$AUR_DIR/PKGBUILD.HEADER" > "$PKGBUILD0" || { echo -e "${YELLOW}[gen-pkgbuild0] Error: Failed to write generated header to $PKGBUILD0 (write error).${RESET}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        else
            echo "# Maintainer: $GH_USER <$GH_USER_EMAIL>" > "$PKGBUILD0" || { echo -e "${YELLOW}[gen-pkgbuild0] Error: Failed to write default header to $PKGBUILD0 (write error).${RESET}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        fi
    fi
    cat >> "$PKGBUILD0" <<EOF
pkgname=$PKGNAME
pkgver=$PKGVER
pkgrel=$PKGREL
pkgdesc="$DESC"
arch=(x86_64)
url="https://github.com/$GH_USER/$PKGNAME"
license=('$LICENSE')
depends=()
makedepends=()
source=("$SRC_URL")
b2sums=('SKIP')

build() {
    cd "$PKGNAME-$PKGVER"
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
    cd "$PKGNAME-$PKGVER"
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

    set -u
    log "${GREEN}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME ($BUILDSYS)${RESET}"
} 