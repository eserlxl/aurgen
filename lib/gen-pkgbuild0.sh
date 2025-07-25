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
# Usage: gen_pkgbuild_header <USER_NAME> <GH_USER_EMAIL> <PROJECT_NAME> <LICENSE_TYPE>
gen_pkgbuild_header() {
    local USER_NAME="$1" GH_USER_EMAIL="$2" PROJECT_NAME="$3" LICENSE_TYPE="$4"
    local HEADER_FILE="$AUR_DIR/PKGBUILD.HEADER"
    if [[ -f "$HEADER_FILE" ]]; then
        return 0
    fi
    case "$LICENSE_TYPE" in
        GPL3|GPLv3|GPL-3.0|GPL-3.0-or-later)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of $PROJECT_NAME and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
        MIT)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: MIT
#
# This file is part of $PROJECT_NAME and is licensed under
# the MIT License. See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
        Apache*)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: Apache-2.0
#
# This file is part of $PROJECT_NAME and is licensed under
# the Apache License 2.0. See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
        *)
            cat > "$HEADER_FILE" <<EOF
# Copyright (C) $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: Custom
#
# This file is part of $PROJECT_NAME. See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
    esac
}

# Filter files for PKGBUILD source array, applying all recommended exclusions
filter_pkgbuild_sources() {
    while IFS= read -r file; do
        # Exclude directories
        if [[ "$file" == .git/* || "$file" == aur/* || "$file" == doc/* || "$file" == build/* || "$file" == dist/* || "$file" == out/* || "$file" == target/* || "$file" == node_modules/* || "$file" == coverage/* || "$file" == .tox/* || "$file" == .pytest_cache/* || "$file" == .mypy_cache/* || "$file" == .cache/* || "$file" == .eggs/* || "$file" == .gradle/* || "$file" == .idea/* || "$file" == .vscode/* || "$file" == docs/_build/* || "$file" == doc/_build/* ]]; then
            continue
        fi
        # Exclude dotfiles and files in dot-directories
        if [[ "$file" == .* || "$file" == */.* ]]; then
            continue
        fi
        # Exclude file patterns
        case "$file" in
            *.o|*.so|*.so.*|*.a|*.dll|*.exe|*.out|*.bin|*.class|*.jar|*.war|*.ear|*.pyo|*.pyc|*.pyd|*.egg-info|*.dist-info|*.log|*.tmp|*.temp|*~|*.bak|*.orig|*.sublime-*|*.iml|*.DS_Store|*.swo|*.mod|*.cmd|*.pdf|*.html|*.dSYM|*.key|*.pem|*.project|*.classpath|*.sublime-*|*.swp|*.md|*.csv|*.tsv|*.xlsx|*.xls|*.doc|*.docx|*.ppt|*.pptx|*.rtf|*.dmg|*.iso|*.img|*.zip|*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.7z|*.rar|*.gz|*.bz2|*.xz|*.lz|*.lzma|*.zst|*.rpm|*.deb|*.apk|*.app|*.msi|*.cab|*.psd|*.xcf|*.svgz|*.xcf|*.xcf.bz2|*.xcf.gz|*.xcf.xz|*.xcf.zst|*.xcf.lzma|*.xcf.lz|*.xcf.zip|*.xcf.7z|*.xcf.rar|*.xcf.tar|*.xcf.tar.gz|*.xcf.tgz|*.xcf.tar.bz2|*.xcf.tbz2|*.xcf.tar.xz|*.xcf.txz|*.xcf.tar.zst|*.xcf.tar.lzma|*.xcf.tar.lz|*.xcf.tar.zip|*.xcf.tar.7z|*.xcf.tar.rar|*.xcf.tar.img|*.xcf.tar.iso|*.xcf.tar.dmg|*.xcf.tar.app|*.xcf.tar.apk|*.xcf.tar.cab|*.xcf.tar.msi|*.xcf.tar.psd|*.xcf.tar.svgz|*.xcf.tar.xcf|*.xcf.tar.xcf.bz2|*.xcf.tar.xcf.gz|*.xcf.tar.xcf.xz|*.xcf.tar.xcf.zst|*.xcf.tar.xcf.lzma|*.xcf.tar.xcf.lz|*.xcf.tar.xcf.zip|*.xcf.tar.xcf.7z|*.xcf.tar.xcf.rar|*.xcf.tar.xcf.tar|*.xcf.tar.xcf.tar.gz|*.xcf.tar.xcf.tgz|*.xcf.tar.xcf.tar.bz2|*.xcf.tar.xcf.tbz2|*.xcf.tar.xcf.tar.xz|*.xcf.tar.xcf.txz|*.xcf.tar.xcf.tar.zst|*.xcf.tar.xcf.tar.lzma|*.xcf.tar.xcf.tar.lz|*.xcf.tar.xcf.tar.zip|*.xcf.tar.xcf.tar.7z|*.xcf.tar.xcf.tar.rar|*.xcf.tar.xcf.tar.img|*.xcf.tar.xcf.tar.iso|*.xcf.tar.xcf.tar.dmg|*.xcf.tar.xcf.tar.app|*.xcf.tar.xcf.tar.apk|*.xcf.tar.xcf.tar.cab|*.xcf.tar.xcf.tar.msi|*.xcf.tar.xcf.tar.psd|*.xcf.tar.xcf.tar.svgz) continue ;;
        esac
        # Exclude secret/config files
        case "$file" in
            .env|.env.*|secrets.*|*.token|*.secret|*.password|*.passwd|*.credentials|*.pem|*.crt|*.csr|*.pfx|*.p12|*.jks|*.keystore|*.asc|*.gpg|*.age|*.enc|*.dec) continue ;;
        esac
        echo "$file"
    done
}

# Generate or merge .gitattributes to mark excluded files as export-ignore
# Usage: generate_gitattributes_from_filter
# This ensures that only filtered files are included in source tarballs and VCS-based AUR packages

generate_gitattributes_from_filter() {
    local GITATTR_FILE="$PROJECT_ROOT/.gitattributes"
    local TMP_GITATTR
    TMP_GITATTR=$(mktemp)
    local all_files filtered_files
    mapfile -t all_files < <(git -C "$PROJECT_ROOT" ls-files)
    mapfile -t filtered_files < <(git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources)
    # Compute files to ignore
    local ignore_files=()
    for f in "${all_files[@]}"; do
        if ! printf '%s\n' "${filtered_files[@]}" | grep -qx -- "$f"; then
            ignore_files+=("$f")
        fi
    done
    # Read existing .gitattributes if present
    declare -A existing
    if [[ -f "$GITATTR_FILE" ]]; then
        while IFS= read -r line; do
            # Only process lines with export-ignore
            if [[ "$line" =~ ^([^[:space:]]+)\ export-ignore ]]; then
                existing["${BASH_REMATCH[1]}"]=1
            fi
            echo "$line" >> "$TMP_GITATTR"
        done < "$GITATTR_FILE"
    fi
    # Add new export-ignore lines for files not already present
    for f in "${ignore_files[@]}"; do
        if [[ -z "${existing[$f]:-}" ]]; then
            echo "$f export-ignore" >> "$TMP_GITATTR"
        fi
    done
    mv "$TMP_GITATTR" "$GITATTR_FILE"
}

gen_pkgbuild0() {
    generate_gitattributes_from_filter
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
        USER_NAME=$(git config user.name || echo "Unknown User")
        gen_pkgbuild_header "$USER_NAME" "$GH_USER_EMAIL" "$PKGNAME" "$LICENSE"
        if [[ -f "$AUR_DIR/PKGBUILD.HEADER" && -r "$AUR_DIR/PKGBUILD.HEADER" ]]; then
            cat "$AUR_DIR/PKGBUILD.HEADER" > "$PKGBUILD0" || { echo -e "${YELLOW}[gen-pkgbuild0] Error: Failed to write generated header to $PKGBUILD0 (write error).${RESET}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        else
            echo "# Maintainer: $USER_NAME <$GH_USER_EMAIL>" > "$PKGBUILD0" || { echo -e "${YELLOW}[gen-pkgbuild0] Error: Failed to write default header to $PKGBUILD0 (write error).${RESET}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        fi
    fi

    # --- Collect source files using git ls-files, with exclusions ---
    # Always filter files for PKGBUILD source array using filter_pkgbuild_sources
    SOURCE_FILES=()
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Use filter_pkgbuild_sources to ensure only allowed files are included
        while IFS= read -r file; do
            SOURCE_FILES+=("$file")
        done < <(git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources)
        if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW}[gen-pkgbuild0] Warning: git ls-files returned no files after exclusions. The source array will be empty.${RESET}" >&2
        fi
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: Not a git repository. The source array will be empty.${RESET}" >&2
    fi

    # --- Decide on source array: VCS source (for aur-git) or fallback ---
    USE_VCS_SOURCE=0
    VCS_URL=""

    # Only allow VCS source for aur-git or similar modes, never for aur mode
    if [[ -n "$PKGVER" && -n "$REPO_URL" ]]; then
        # Only try for GitHub HTTPS/SSH URLs
        if [[ "$REPO_URL" =~ github.com[:/][^/]+/[^/]+(.git)?$ ]]; then
            # Normalize to HTTPS URL
            VCS_URL="https://github.com/$(echo "$REPO_URL" | sed -E 's#.*github.com[:/]([^/]+/[^/.]+).*#\1#')"
            # Check if the tag exists remotely
            if git ls-remote --tags "$REPO_URL" "refs/tags/v$PKGVER" | grep -q .; then
                USE_VCS_SOURCE=1
            elif git ls-remote --tags "$REPO_URL" "refs/tags/$PKGVER" | grep -q .; then
                USE_VCS_SOURCE=1
            fi
        fi
    fi
    # Explicitly disallow VCS source for aur mode
    if [[ "${AURGEN_MODE:-}" == "aur" ]]; then
        USE_VCS_SOURCE=0
    fi

    # Write PKGBUILD.0 main fields
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
EOF

    if [[ $USE_VCS_SOURCE -eq 1 ]]; then
        echo "source=(\"git+$VCS_URL.git#tag=$PKGVER\")" >> "$PKGBUILD0"
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: Could not use VCS source for source array. Falling back to explicit file list.${RESET}" >&2
        echo "source=(" >> "$PKGBUILD0"
        for f in "${SOURCE_FILES[@]}"; do
            echo "  \"$f\"" >> "$PKGBUILD0"
        done
        echo ")" >> "$PKGBUILD0"
    fi
    cat >> "$PKGBUILD0" <<'EOF'
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
    # --- Begin auto-generated install logic ---
    # Scan filtered files for installable targets
    INSTALL_CMDS=()
    LICENSE_INSTALLED=0
    # For CMake, scan build/ for executables
    if [[ "$BUILDSYS" == "cmake" ]]; then
        if [[ -d build ]]; then
            while IFS= read -r exe; do
                if [[ -x "build/$exe" && ! -d "build/$exe" ]]; then
                    INSTALL_CMDS+=("install -Dm755 build/$exe \"$pkgdir/usr/bin/$exe\"")
                fi
            done < <(cd build && find . -maxdepth 1 -type f -executable | sed 's|^./||')
        fi
    fi
    # Scan filtered source files
    for f in "${SOURCE_FILES[@]}"; do
        case "$f" in
            bin/*)
                if [[ -x "$f" && ! -d "$f" ]]; then
                    INSTALL_CMDS+=("install -Dm755 $f \"$pkgdir/usr/bin/$(basename "$f")\"")
                fi
                ;;
            lib/*)
                if [[ -f "$f" ]]; then
                    INSTALL_CMDS+=("install -Dm644 $f \"$pkgdir/usr/lib/$(basename "$f")\"")
                fi
                ;;
            share/*)
                if [[ -f "$f" ]]; then
                    INSTALL_CMDS+=("install -Dm644 $f \"$pkgdir/usr/share/${f#share/}\"")
                fi
                ;;
            LICENSE|LICENSE.txt|COPYING)
                if [[ $LICENSE_INSTALLED -eq 0 && -f "$f" ]]; then
                    INSTALL_CMDS+=("install -Dm644 $f \"$pkgdir/usr/share/licenses/$PKGNAME/$(basename "$f")\"")
                    LICENSE_INSTALLED=1
                fi
                ;;
        esac
    done
    # Write install commands to PKGBUILD0
    if [[ ${#INSTALL_CMDS[@]} -gt 0 ]]; then
        for cmd in "${INSTALL_CMDS[@]}"; do
            echo "    $cmd" >> "$PKGBUILD0"
        done
    else
        echo "    # Add your install steps here" >> "$PKGBUILD0"
    fi
    cat >> "$PKGBUILD0" <<'EOF'
}
EOF

    set -u
    log "${GREEN}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME ($BUILDSYS)${RESET}"
} 