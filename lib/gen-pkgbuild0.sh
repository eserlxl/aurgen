#!/bin/bash
# Generate a basic PKGBUILD.0 for the current GitHub project
# Supports CMake, Make, Python, Node.js (auto-detects)
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen PKGBUILD generation logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Global configuration
MAXDEPTH=${MAXDEPTH:-5}

# shellcheck source=lib/colors.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/colors.sh"
# shellcheck source=lib/helpers.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/helpers.sh"
# shellcheck source=lib/detect-deps.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/detect-deps.sh"
# shellcheck source=lib/config.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/config.sh"
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
# Copyright © $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
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
# Copyright © $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: MIT
#
# This file is part of $PROJECT_NAME and is licensed under
# the MIT License. See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
        Apache*)
            cat > "$HEADER_FILE" <<EOF
# Copyright © $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: Apache-2.0
#
# This file is part of $PROJECT_NAME and is licensed under
# the Apache License 2.0. See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
        *)
            cat > "$HEADER_FILE" <<EOF
# Copyright © $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
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
        if [[ "$file" == .git/* || "$file" == aur/* || "$file" == doc/* || "$file" == dev-bin/* || "$file" == build/* || "$file" == dist/* || "$file" == out/* || "$file" == target/* || "$file" == node_modules/* || "$file" == coverage/* || "$file" == .tox/* || "$file" == .pytest_cache/* || "$file" == .mypy_cache/* || "$file" == .cache/* || "$file" == .eggs/* || "$file" == .gradle/* || "$file" == .idea/* || "$file" == .vscode/* || "$file" == docs/_build/* || "$file" == doc/_build/* ]]; then
            continue
        fi
        # Exclude dotfiles and files in dot-directories
        if [[ "$file" == .* || "$file" == */.* ]]; then
            continue
        fi
        # Exclude file patterns
        case "$file" in
            *.o|*.so|*.so.*|*.a|*.dll|*.exe|*.out|*.bin|*.class|*.jar|*.war|*.ear|*.pyo|*.pyc|*.pyd|*.egg-info|*.dist-info|*.log|*.tmp|*.temp|*~|*.bak|*.orig|*.sublime-*|*.iml|*.DS_Store|*.swo|*.mod|*.cmd|*.pdf|*.html|*.dSYM|*.key|*.pem|*.project|*.classpath|*.swp|*.md|*.csv|*.tsv|*.xlsx|*.xls|*.doc|*.docx|*.ppt|*.pptx|*.rtf|*.dmg|*.iso|*.img|*.zip|*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.7z|*.rar|*.gz|*.bz2|*.xz|*.lz|*.lzma|*.zst|*.rpm|*.deb|*.apk|*.app|*.msi|*.cab|*.psd|*.xcf|*.svgz) continue ;;
        esac
        # Exclude secret/config files
        case "$file" in
            .env|.env.*|secrets.*|*.token|*.secret|*.password|*.passwd|*.credentials|*.pem|*.crt|*.csr|*.pfx|*.p12|*.jks|*.keystore|*.asc|*.gpg|*.age|*.enc|*.dec) continue ;;
        esac
        # Exclude version files
        case "$file" in
            VERSION|version|VERSION.txt|version.txt) continue ;;
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
    
    # Generate default configuration file if it doesn't exist
    if [[ ! -f "$AUR_DIR/aurgen.install.yaml" ]]; then
        generate_default_config
    fi
    
    # Generate example configuration file if it doesn't exist
    if [[ ! -f "$AUR_DIR/aurgen.install.yaml.example" ]]; then
        generate_example_config
    fi
    
    local PKGBUILD0 REPO_URL GH_USER PKGVER PKGREL DESC LICENSE BUILDSYS SRC_URL
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

    # Try to extract version from git tag, then VERSION file, then fallback
    PKGVER=$(git describe --tags --abbrev=0 2>>"$AURGEN_ERROR_LOG" | sed 's/^v//') || true
    if [[ -z "${PKGVER:-}" ]]; then
        # Check VERSION file as first fallback
        if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
            PKGVER=$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")
            if [[ -n "${PKGVER:-}" ]]; then
                PKGVER_FALLBACK=1
                debug "[gen-pkgbuild0] Success: Found version $PKGVER in VERSION file." >&2
            else
                PKGVER="1.0.0"
                PKGVER_FALLBACK=2
                echo -e "${YELLOW}[gen-pkgbuild0] Warning: VERSION file exists but is empty. Using fallback version $PKGVER.${RESET}" >&2
            fi
        else
            PKGVER="1.0.0"
            PKGVER_FALLBACK=2
            echo -e "${YELLOW}[gen-pkgbuild0] Warning: No git tag found and no VERSION file. Using fallback version $PKGVER.${RESET}" >&2
        fi
    else
        PKGVER_FALLBACK=0
        debug "[gen-pkgbuild0] Success: Found git tag $PKGVER." >&2
    fi
    PKGREL=1

    # Try to extract description from GitHub, then README, then fallback to PKGNAME
    DESC=""
    if command -v gh >/dev/null 2>&1; then
        GH_DESC=$(gh repo view --json description -q .description 2>>"$AURGEN_ERROR_LOG" || true)
        if [[ -n "${GH_DESC// }" ]]; then
            DESC="$GH_DESC"
        fi
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: GitHub CLI (gh) is required for fetching repo description but not found. Falling back to README or PKGNAME.${RESET}" >&2
    fi
    if [[ -z "${DESC// }" ]]; then
        if [[ -f "$PROJECT_ROOT/README.md" ]]; then
            # Try to extract the first bold or italic line (excluding headings)
            DESC=$(grep -m1 -E '^( *[^*]+ *| *[^_]+_)' "$PROJECT_ROOT/README.md" | sed 's/^\*//;s/\*$//;s/^_//;s/_$//')
            # If not found, try to extract the first non-title, non-empty, non-heading line
            if [[ -z "${DESC// }" ]]; then
                DESC=$(grep -v -E '^(#|\s*$)' "$PROJECT_ROOT/README.md" | head -n1 | sed 's/^\s*//;s/\s*$//')
            fi
            DESC=${DESC:-"$PKGNAME"}
        else
            DESC="$PKGNAME"
        fi
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

    # Select GPG key for validpgpkeys
    # Temporarily disable set -e to handle GPG key selection gracefully
    set +e
    select_gpg_key
    select_gpg_key_status=$?
    set -e
    if [[ $select_gpg_key_status -ne 0 ]]; then
        if [[ "${AURGEN_MODE:-}" == "test" ]]; then
            warn "[gen-pkgbuild0] No GPG key found, but running in test mode. Forcing dry_run=1 and using test GPG key."
            dry_run=1
            GPG_KEY_ID="TEST_KEY_FOR_DRY_RUN"
            export dry_run
            export GPG_KEY_ID
        else
            err "[gen-pkgbuild0] Error: No GPG key found and not in test mode. Aborting."
            exit 1
        fi
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
    elif [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        BUILDSYS="rust"
    elif [[ -f "$PROJECT_ROOT/go.mod" ]]; then
        BUILDSYS="go"
    elif [[ -f "$PROJECT_ROOT/meson.build" ]]; then
        BUILDSYS="meson"
    else
        # Check if this is a no-build project (scripts, configs, etc.)
        # Look for common patterns that indicate no build is needed
        local has_scripts=0 has_configs=0 has_docs=0 has_data=0
        
        # Check for executable scripts
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f -executable -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" -o -name "*.js" | grep -q .; then
            has_scripts=1
        fi
        
        # Check for configuration files
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f \( -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" \) | grep -q .; then
            has_configs=1
        fi
        
        # Check for documentation
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.rst" -o -name "*.html" \) | grep -q .; then
            has_docs=1
        fi
        
        # Check for data files
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f \( -name "*.dat" -o -name "*.csv" -o -name "*.xml" -o -name "*.sql" \) | grep -q .; then
            has_data=1
        fi
        
        # If we have scripts, configs, docs, or data but no build system, it's likely a no-build project
        if [[ $has_scripts -eq 1 || $has_configs -eq 1 || $has_docs -eq 1 || $has_data -eq 1 ]]; then
            BUILDSYS="none"
        else
            # Default to unknown build system (will use placeholder)
            BUILDSYS="unknown"
        fi
    fi

    # Log build system detection
    if [[ "$BUILDSYS" == "none" ]]; then
        log "[gen-pkgbuild0] Detected no-build project (scripts/configs/data)"
    elif [[ "$BUILDSYS" == "unknown" ]]; then
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: Could not detect build system. Using placeholder build steps.${RESET}" >&2
    else
        log "[gen-pkgbuild0] Detected build system: $BUILDSYS"
    fi

    # Detect makedepends
    MAKEDEPENDS=$(detect_makedepends)
    if [[ -n "${MAKEDEPENDS// }" ]]; then
        log "[gen-pkgbuild0] Detected makedepends: $MAKEDEPENDS"
    else
        log "[gen-pkgbuild0] No specific makedepends detected"
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
            echo -e "${YELLOW}[gen-pkgbuild0] Warning: Could not find a GitHub release tarball for version $PKGVER.${RESET}" >&2
            echo -e "${YELLOW}[gen-pkgbuild0] This is normal for new projects that haven't created their first release yet.${RESET}" >&2
            echo -e "${YELLOW}[gen-pkgbuild0] You can either:${RESET}" >&2
            echo -e "${YELLOW}[gen-pkgbuild0]   1. Create a GitHub release for tag $PKGVER, or${RESET}" >&2
            echo -e "${YELLOW}[gen-pkgbuild0]   2. Continue without a release (for development/testing)${RESET}" >&2
            echo -e "${YELLOW}[gen-pkgbuild0]   3. Use 'aur-git' mode instead which doesn't require releases${RESET}" >&2
            echo -e "${YELLOW}[gen-pkgbuild0] Proceeding without release tarball URL...${RESET}" >&2
            SRC_URL=""
        fi
    elif [[ "$PKGVER_FALLBACK" -eq 1 ]]; then
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: Using version from VERSION file ($PKGVER). No GitHub release tarball will be set in source array. Please update manually if needed.${RESET}" >&2
        SRC_URL=""
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: No git tag found and no VERSION file, using fallback version $PKGVER. No GitHub release tarball will be set in source array. Please update manually if needed.${RESET}" >&2
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
EOF
    # Insert validpgpkeys if provided
    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        echo "validpgpkeys=('$GPG_KEY_ID')" >> "$PKGBUILD0"
    fi
    # Convert space-separated makedepends to properly quoted array format
    MAKEDEPENDS_ARRAY=""
    if [[ -n "${MAKEDEPENDS// }" ]]; then
        MAKEDEPENDS_ARRAY="("
        for dep in $MAKEDEPENDS; do
            MAKEDEPENDS_ARRAY="${MAKEDEPENDS_ARRAY}'${dep}' "
        done
        MAKEDEPENDS_ARRAY="${MAKEDEPENDS_ARRAY% })"
    else
        MAKEDEPENDS_ARRAY="()"
    fi
    
    cat >> "$PKGBUILD0" <<EOF
depends=()
makedepends=${MAKEDEPENDS_ARRAY}
EOF

    if [[ $USE_VCS_SOURCE -eq 1 ]]; then
        echo "source=(\"git+$VCS_URL.git#tag=v$PKGVER\")" >> "$PKGBUILD0"
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

EOF

    # Handle build function based on build system
    if [[ "$BUILDSYS" == "none" ]]; then
        # For no-build projects, create a build function with a no-op command
        cat >> "$PKGBUILD0" <<'EOF'
build() {
    # No build steps required
    :
}

EOF
    else
        # For projects that need building, create the standard build function
        # Note: Tarball is created without subdirectory prefix, so no cd needed
        cat >> "$PKGBUILD0" <<'EOF'
build() {
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
            rust)
                cat >> "$PKGBUILD0" <<'EOB'
    cargo build --release
EOB
                ;;
            go)
                cat >> "$PKGBUILD0" <<'EOB'
    go build -o "$PKGNAME" .
EOB
                ;;
            meson)
                cat >> "$PKGBUILD0" <<'EOB'
    meson setup build
    meson compile -C build
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
EOF
    fi

    # Generate package() function based on build system
    cat >> "$PKGBUILD0" <<EOF
# Helper function to copy and rebase paths with optional exclusions
copy_tree() {
    local src="\$1" destbase="\$2" mode="\$3" excludes="\$4"
    [[ -d "\$src" ]] || return 0

    local abs_src
    abs_src="\$(realpath "\$src" 2>/dev/null)" || return 0

    # Build find command with exclusions
    local find_cmd="find \"\$abs_src\" -maxdepth 5 -type f"
    
    # Add exclusion patterns if provided
    if [[ -n "\$excludes" ]]; then
        IFS=',' read -ra exclude_array <<< "\$excludes"
        for exclude in "\${exclude_array[@]}"; do
            # Trim whitespace
            exclude="\${exclude#" \${exclude%%[! ]*}"}"
            exclude="\${exclude%" \${exclude##*[! ]}"}"
            if [[ -n "\$exclude" ]]; then
                find_cmd="\$find_cmd -not -path \"\$abs_src/\$exclude/*\""
            fi
        done
    fi
    
    find_cmd="\$find_cmd -print0"
    
    mapfile -d '' -t files < <(eval "\$find_cmd") || return 0

    for file in "\${files[@]}"; do
        local relpath
        relpath="\$(realpath --relative-to="\$abs_src" "\$file")"
        install -Dm"\$mode" "\$file" "\$pkgdir/\$destbase/\$relpath"
    done
}

package() {
    # Note: Tarball is created without subdirectory prefix, so no cd needed
    # Install license file
    for name in LICENSE LICENSE.txt COPYING; do
        [[ -f "\$name" ]] && install -Dm644 "\$name" "\$pkgdir/usr/share/licenses/\$pkgname/LICENSE" && break
    done

    # Copy sections based on configuration
EOF

    # Load configuration and generate copy commands
    while IFS= read -r dir_rule; do
        [[ -z "$dir_rule" ]] && continue
        IFS=':' read -r src_dir dest_dir permissions excludes <<< "$dir_rule"
        echo "    copy_tree \"$src_dir\" \"$dest_dir\" \"$permissions\" \"$excludes\"" >> "$PKGBUILD0"
    done < <(get_copy_directories)

    cat >> "$PKGBUILD0" <<'EOF'
EOF

    # Add build system specific installation
    case "$BUILDSYS" in
        cmake)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install CMake build artifacts
    DESTDIR="\$pkgdir" cmake --install build
EOB
            ;;
        make)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Make build artifacts
    make DESTDIR="\$pkgdir" install
EOB
            ;;
        python)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Python package
    python setup.py install --root="\$pkgdir" --optimize=1 --skip-build
EOB
            ;;
        node)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Node.js package
    npm install -g --prefix "\$pkgdir/usr" .
EOB
            ;;
        rust)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Rust binary
    install -Dm755 target/release/\$PKGNAME "\$pkgdir/usr/bin/\$PKGNAME"
EOB
            ;;
        go)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Go binary
    install -Dm755 \$PKGNAME "\$pkgdir/usr/bin/\$PKGNAME"
EOB
            ;;
        meson)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Meson build artifacts
    DESTDIR="\$pkgdir" meson install -C build
EOB
            ;;
        none)
            cat >> "$PKGBUILD0" <<EOB
EOB
            ;;
        *)
            cat >> "$PKGBUILD0" <<'EOB'
    # Add your installation steps here
    # Example:
    # install -Dm755 \$PKGNAME "\$pkgdir/usr/bin/\$PKGNAME"
    # install -Dm644 README.md "\$pkgdir/usr/share/doc/\$PKGNAME/README.md"
EOB
            ;;
    esac

    cat >> "$PKGBUILD0" <<'EOF'
}
EOF

    set -u
    if [[ "$BUILDSYS" == "none" ]]; then
        log "${GREEN}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME (no-build project)${RESET}"
    else
        log "${GREEN}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME ($BUILDSYS)${RESET}"
    fi
} 
