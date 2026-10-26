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
            local LC_ALL=C HEADER_LICENSE=Custom
            if [[ "$LICENSE_TYPE" != custom && "$LICENSE_TYPE" =~ ^[A-Za-z0-9.+-]+$ ]]; then
                HEADER_LICENSE="$LICENSE_TYPE"
            fi
            cat > "$HEADER_FILE" <<EOF
# Copyright © $(date +%Y) $USER_NAME <$GH_USER_EMAIL>
# SPDX-License-Identifier: $HEADER_LICENSE
#
# This file is part of $PROJECT_NAME. See the LICENSE file in the project root for details.

# Maintainer: $USER_NAME <$GH_USER_EMAIL>
EOF
            ;;
    esac
}

# Map a license file to an SPDX id. An SPDX-License-Identifier line wins.
# Titles are ordered so AGPL/LGPL are not read as GPL, and BSD is not read as MIT
# (the BSD grant says "are permitted", which used to match a bare MIT search).
# Usage: detect_license_spdx <file>
detect_license_spdx() {
    local file="$1"
    local line id

    if line=$(grep -m1 -ioE 'SPDX-License-Identifier:[[:space:]]*[^[:space:]]+' "$file"); then
        id="${line#*:}"
        id="${id#"${id%%[![:space:]]*}"}"
        printf '%s\n' "$id"
        return 0
    fi
    if grep -qF 'GNU AFFERO' "$file"; then
        printf '%s\n' 'AGPL-3.0-or-later'
        return 0
    fi
    if grep -qF 'GNU LESSER' "$file"; then
        if grep -qF 'Version 3' "$file"; then
            printf '%s\n' 'LGPL-3.0-or-later'
        elif grep -qF 'Version 2.1' "$file"; then
            printf '%s\n' 'LGPL-2.1-or-later'
        else
            printf '%s\n' 'custom'
        fi
        return 0
    fi
    if grep -qF 'GNU GENERAL PUBLIC LICENSE' "$file"; then
        if grep -qF 'Version 3' "$file"; then
            printf '%s\n' 'GPL-3.0-or-later'
        elif grep -qF 'Version 2' "$file"; then
            printf '%s\n' 'GPL-2.0-or-later'
        else
            printf '%s\n' 'custom'
        fi
        return 0
    fi
    if grep -qF 'Apache License' "$file" && grep -qF 'Version 2.0' "$file"; then
        printf '%s\n' 'Apache-2.0'
        return 0
    fi
    if grep -qF 'MIT License' "$file" || grep -qF 'Permission is hereby granted, free of charge' "$file"; then
        printf '%s\n' 'MIT'
        return 0
    fi
    if grep -qF 'Redistribution and use in source and binary forms' "$file"; then
        if grep -qF 'Neither the name' "$file"; then
            printf '%s\n' 'BSD-3-Clause'
        else
            printf '%s\n' 'BSD-2-Clause'
        fi
        return 0
    fi
    printf '%s\n' 'custom'
}

# Root-level license file names, in the order detection and package() try them.
# GitHub projects often use LICENSE.md, which the *.md exclusion below would drop.
LICENSE_FILE_NAMES=(LICENSE LICENSE.txt LICENSE.md LICENCE COPYING COPYING.md)

# Match exact kept paths or directory prefixes ending in a slash.
pkg_path_is_kept() {
    local file="$1"
    local name
    for name in "${PKG_KEEP[@]}"; do
        if [[ "$file" == "$name" || ( "$name" == */ && "$file" == "$name"* ) ]]; then
            return 0
        fi
    done
    return 1
}

# Filter files for PKGBUILD source array, applying all recommended exclusions
filter_pkgbuild_sources() {
    local name
    while IFS= read -r file; do
        if pkg_path_is_kept "$file"; then
            printf '%s\n' "$file"
            continue
        fi
        for name in "${LICENSE_FILE_NAMES[@]}"; do
            [[ "$file" == "$name" ]] && { echo "$file"; continue 2; }
        done
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
    # Only a project that keeps a .gitattributes gets it updated. Creating one would add
    # an untracked file, and export-ignore lines would strip tests from the GitHub
    # archive an archive-source PKGBUILD builds and checks.
    [[ -f "$GITATTR_FILE" ]] || return 0
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
        # The copy replaces the tracked file, so an unterminated last line must not be lost.
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Only process lines with export-ignore
            if [[ "$line" =~ ^([^[:space:]]+)\ export-ignore([[:space:]]|$) ]]; then
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
    # A leading slash anchors the override to the repository root, as the filter is.
    for f in "${PKG_KEEP[@]}"; do
        f="/$f"
        [[ "$f" == */ ]] && f+='**'
        if ! grep -Fxq -- "$f -export-ignore" "$TMP_GITATTR"; then
            echo "$f -export-ignore" >> "$TMP_GITATTR"
        fi
    done
    mv "$TMP_GITATTR" "$GITATTR_FILE"
}

# Single-quote a value for a PKGBUILD field. Embedded quotes use the '\'' form
# so makepkg sources the text as data.
pkgbuild_squote() {
    local value="$1"
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

# Write name=( 'a' 'b' ). An empty list is omitted so unset metadata stays out of the PKGBUILD.
pkgbuild_write_array() {
    local name="$1"
    shift
    (( $# )) || return 0
    local item line="$name=("
    for item in "$@"; do
        line+="$(pkgbuild_squote "$item") "
    done
    printf '%s)\n' "${line% }"
}

# Archive extracts to <repo>-<pkgver> (GitHub drops the leading v). A named git
# source clones into $srcdir/$pkgname. Release tarballs are flat, so this prints nothing.
# shellcheck disable=SC2016 # $srcdir, $pkgver and $pkgname are for makepkg
write_source_cd() {
    local kind="$1"
    local repo="${2:-}"
    case "$kind" in
        archive)
            printf '    cd "$srcdir/%s-$pkgver"\n' "$repo"
            ;;
        signed-tag)
            printf '    cd "$srcdir/$pkgname"\n'
            ;;
    esac
}

# The build system a project's marker file names, first match wins. Prints
# nothing when none exists; gen_pkgbuild0 then tells no-build from unknown.
detect_buildsys() {
    local root="$1"
    if [[ -f "$root/CMakeLists.txt" ]]; then
        echo cmake
    elif [[ -f "$root/Makefile" ]]; then
        echo make
    elif [[ -f "$root/setup.py" ]]; then
        echo python
    elif [[ -f "$root/package.json" ]]; then
        echo node
    elif [[ -f "$root/Cargo.toml" ]]; then
        echo rust
    elif [[ -f "$root/go.mod" ]]; then
        echo go
    elif [[ -f "$root/meson.build" ]]; then
        echo meson
    fi
}

# A Makefile can drive a shell project. arch=any unless a compiler is involved:
# a compiled build system, or a tracked C, C++, Rust, Go or Vala source.
project_compiles() {
    local root="${1:-${PROJECT_ROOT:-}}"
    local buildsys tracked
    [[ -n "$root" ]] || return 1
    buildsys="$(detect_buildsys "$root")"
    case "$buildsys" in
        cmake|rust|go|meson) return 0 ;;
    esac
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    while IFS= read -r tracked; do
        case "$tracked" in
            *.c|*.cc|*.cpp|*.cxx|*.c++|*.rs|*.go|*.vala) return 0 ;;
        esac
    done < <(git -C "$root" ls-files | filter_pkgbuild_sources)
    return 1
}

# The check() command generation writes when package.check is empty or true.
# For Make only a ^check: rule counts: check is the GNU self-test target, while
# test is not standard and often a developer suite that needs git, network or
# the host. make itself is not run to discover the target.
default_check_command() {
    local buildsys="$1" root="$2"
    case "$buildsys" in
        make)
            if [[ -f "$root/Makefile" ]] && grep -E -q '^check:' "$root/Makefile"; then
                echo 'make check'
            fi
            ;;
        cmake)
            echo 'ctest --test-dir build'
            ;;
        rust)
            echo 'cargo test --release'
            ;;
        go)
            echo 'go test ./...'
            ;;
        meson)
            echo 'meson test -C build'
            ;;
    esac
    return 0
}

# Checksums of the files baked into PKGBUILD.0, one per line.
# A missing file is a blank line so creating it later still mismatches.
# VERSION is included because, without a tag, it is pkgver.
# The filtered index records cover staged or committed changes to scanned source files.
# The latest tag (pkgver) and the aurgen version (generator output) follow,
# so a new release tag or an aurgen upgrade regenerates PKGBUILD.0.
pkgbuild0_input_stamp() {
    local file sum scanned=""
    for file in "$AUR_DIR/aurgen.install.yaml" "$AUR_DIR/PKGBUILD.HEADER" "$PROJECT_ROOT/VERSION" "$PROJECT_ROOT/Makefile"; do
        if [[ -f "$file" ]]; then
            sum=$(sha256sum -- "$file")
            printf '%s\n' "${sum%% *}"
        else
            printf '\n'
        fi
    done
    # Outside a git work tree there are no index records; the stamp then hashes an empty list.
    scanned=$(git -C "$PROJECT_ROOT" ls-files 2>/dev/null | filter_pkgbuild_sources \
        | xargs -r -d '\n' git --literal-pathspecs -C "$PROJECT_ROOT" ls-files -s -- 2>/dev/null) || scanned=""
    sum=$(printf '%s' "$scanned" | sha256sum)
    printf '%s\n' "${sum%% *}"
    printf '%s\n' "$(git -C "${PROJECT_ROOT:-.}" describe --tags --abbrev=0 2>/dev/null)"
    printf '%s\n' "${AURGEN_VERSION:-}"
}

# Goal a bare `make` would run. .DEFAULT_GOAL wins; otherwise the first rule
# target that does not start with "." and contains neither % nor =.
# Make is not executed: an install-only Makefile must not be run in build().
makefile_default_goal() {
    local file="$1"
    local line target default_goal="" first_goal=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == $'\t'* ]] && continue
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        while [[ "$line" =~ ^(export|override|private)[[:space:]]+(.*)$ ]]; do
            line="${BASH_REMATCH[2]}"
        done
        if [[ "$line" =~ ^\.DEFAULT_GOAL[[:space:]]*[:?+!]*=[[:space:]]*([^[:space:]]+) ]]; then
            default_goal="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ -n "$first_goal" ]]; then
            continue
        fi
        # Assignments (PREFIX ?= /usr) are not rules. := ?= += != ::= included.
        if [[ "$line" =~ ^[A-Za-z0-9_.-]+[[:space:]]*[:?+!]*= ]]; then
            continue
        fi
        if [[ "$line" =~ ^([^:]+)[[:space:]]*: ]]; then
            # `all install:` — only the first target is the default goal.
            target="${BASH_REMATCH[1]}"
            target="${target%%[[:space:]]*}"
            if [[ "$target" == .* || "$target" == *%* || "$target" == *=* ]]; then
                continue
            fi
            first_goal="$target"
        fi
    done < "$file"
    if [[ -n "$default_goal" ]]; then
        printf '%s\n' "$default_goal"
    else
        printf '%s\n' "$first_goal"
    fi
}

write_install_messages() {
    local hook="$1" delimiter=AURGEN_MESSAGES line collision=1
    shift
    # A message may itself contain the delimiter, including shell-looking text after it.
    while (( collision )); do
        collision=0
        for line in "$@"; do
            if [[ "$line" == "$delimiter" ]]; then
                delimiter+=_
                collision=1
                break
            fi
        done
    done
    printf "%s() {\n    cat <<'%s'\n" "$hook" "$delimiter"
    printf '%s\n' "$@"
    printf '%s\n}\n\n' "$delimiter"
}

generate_install_scriptlet() {
    local output="$1" name="$2" unit command
    shift 2
    local -a enable=() disable=() post=() pre=()
    (( $# || PKG_INSTALL_MESSAGES )) || return 0
    for unit in "$@"; do
        case "$unit" in
            system:*) command='sudo systemctl' ;;
            user:*) command='systemctl --user' ;;
            *) continue ;;
        esac
        unit="${unit#*:}"
        enable+=("$command enable --now $unit")
        disable+=("$command disable --now $unit")
    done
    # Configured lines are printed verbatim; without them the hint is built from the units.
    post=("${PKG_POST_INSTALL[@]}")
    pre=("${PKG_PRE_REMOVE[@]}")
    if (( ! ${#post[@]} && ${#enable[@]} )); then
        post=("==> $name: nothing was enabled." "${enable[@]}")
    fi
    if (( ! ${#pre[@]} && ${#disable[@]} )); then
        pre=("==> $name: disable the units you enabled before removing:" "${disable[@]}")
    fi
    mkdir -p "$(dirname "$output")"
    {
        if (( ${#post[@]} )); then
            write_install_messages post_install "${post[@]}"
        fi
        if (( ${#PKG_POST_UPGRADE[@]} )); then
            write_install_messages post_upgrade "${PKG_POST_UPGRADE[@]}"
        fi
        if (( ${#pre[@]} )); then
            write_install_messages pre_remove "${pre[@]}"
        fi
    } >| "$output"
}

gen_pkgbuild0() {
    generate_gitattributes_from_filter
    
    # Generate default configuration file if it doesn't exist
    if [[ ! -f "$AUR_DIR/aurgen.install.yaml" ]]; then
        generate_default_config "$@"
    fi
    
    # Generate example configuration file if it doesn't exist
    if [[ ! -f "$AUR_DIR/aurgen.install.yaml.example" ]]; then
        generate_example_config "$@"
    fi
    
    local PKGBUILD0 REPO_URL GH_USER GH_REPO PKGVER PKGREL DESC LICENSE BUILDSYS
    mkdir -p "$AUR_DIR"
    PKGBUILD0="$AUR_DIR/PKGBUILD.0"

    # Warn and remove existing PKGBUILD.0 if present
    if [[ -f "$PKGBUILD0" ]]; then
        echo -e "${YELLOW}[gen-pkgbuild0] Existing $PKGBUILD0 found. Deleting before regeneration.${RESET}" >&2
        rm -f "$PKGBUILD0"
    fi

    # --- Detect project metadata ---
    REPO_URL=$(git -C "$PROJECT_ROOT" config --get remote.origin.url || true)
    # basename(dirname) is the owner only for https://github.com/owner/repo.
    # SSH is git@github.com:owner/repo.git, so the same github.com[:/] split
    # used for the VCS URL supplies both owner and repo.
    GH_USER=$(basename "$(dirname "$REPO_URL")")
    GH_REPO=""
    # Dots belong to the repository name (my.tool). Only a trailing .git is the VCS suffix.
    if [[ "$REPO_URL" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        GH_USER="${BASH_REMATCH[1]}"
        GH_REPO="${BASH_REMATCH[2]%.git}"
    fi

    # Try to extract version from git tag, then VERSION file, then fallback
    PKGVER=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>>"$AURGEN_ERROR_LOG" | sed 's/^v//') || true
    if [[ -z "${PKGVER:-}" ]]; then
        # Check VERSION file as first fallback
        if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
            PKGVER=$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")
            if [[ -n "${PKGVER:-}" ]]; then
                debug "[gen-pkgbuild0] Success: Found version $PKGVER in VERSION file." >&2
            else
                PKGVER="1.0.0"
                echo -e "${YELLOW}[gen-pkgbuild0] Warning: VERSION file exists but is empty. Using fallback version $PKGVER.${RESET}" >&2
            fi
        else
            PKGVER="1.0.0"
            echo -e "${YELLOW}[gen-pkgbuild0] Warning: No git tag found and no VERSION file. Using fallback version $PKGVER.${RESET}" >&2
        fi
    else
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
            # First prose line. A setext title is held until the next line proves it is not an underline.
            DESC=$(awk '
                function trim(s) {
                    gsub(/^[ \t\r]+|[ \t\r]+$/, "", s)
                    return s
                }
                function prose(s) {
                    s = trim(s)
                    gsub(/^[*_]+|[*_]+$/, "", s)
                    return trim(s)
                }
                function emit() {
                    if (hold != "") {
                        print hold
                        # exit still runs END, which must not print it again.
                        hold = ""
                        exit
                    }
                }
                BEGIN { fence = 0; hold = "" }
                {
                    line = trim($0)
                    if (line ~ /^```/ || line ~ /^~~~/) {
                        emit()
                        fence = !fence
                        next
                    }
                    if (fence) next
                    if (line ~ /^={3,}$/ || line ~ /^-{3,}$/) {
                        hold = ""
                        next
                    }
                    if (line == "" || line ~ /^#/ || line ~ /^\[!/ || line ~ /^!\[/ || line ~ /^</) {
                        emit()
                        next
                    }
                    text = prose(line)
                    if (text == "") {
                        emit()
                        next
                    }
                    if (hold != "") emit()
                    hold = text
                }
                END { if (hold != "") print hold }
            ' "$PROJECT_ROOT/README.md")
            DESC=${DESC:-"$PKGNAME"}
        else
            DESC="$PKGNAME"
        fi
    fi

    # Try to detect license. A later recognized file replaces an earlier one;
    # an unrecognized file does not wipe a license already found.
    LICENSE="custom"
    LICENSE_FOUND=0
    local detected
    for f in "${LICENSE_FILE_NAMES[@]}"; do
        if [[ -f "$PROJECT_ROOT/$f" ]]; then
            detected=$(detect_license_spdx "$PROJECT_ROOT/$f")
            LICENSE_FOUND=1
            if [[ "$detected" != custom ]]; then
                LICENSE="$detected"
            fi
        fi
    done
    if [[ $LICENSE_FOUND -eq 1 ]]; then
        log "[gen-pkgbuild0] Detected license: $LICENSE"
    else
        echo -e "${YELLOW}[gen-pkgbuild0] Warning: No license file found in project root. Setting license to 'custom'. Please add a LICENSE file for proper packaging.${RESET}" >&2
    fi
    # Configured text replaces detection. The header template takes one license id.
    if [[ -n "${PKG_DESCRIPTION:-}" ]]; then
        DESC="$PKG_DESCRIPTION"
    fi
    if (( ${#PKG_LICENSE[@]} )); then
        LICENSE="${PKG_LICENSE[0]}"
    fi

    # Empty package.source is today's release asset. archive and signed-tag are opt-in.
    local source_kind archive_repo source_tag="v\$pkgver"
    source_kind="${PKG_SOURCE:-}"
    if [[ -z "$source_kind" ]]; then
        source_kind=release
    fi
    case "$source_kind" in
        release|archive|signed-tag) ;;
        *)
            err "[gen-pkgbuild0] Unknown package.source: $source_kind"
            return 1
            ;;
    esac
    archive_repo="${GH_REPO:-${REPO_NAME:-$PKGNAME}}"
    if [[ "$source_kind" == "archive" && ! "$archive_repo" =~ ^[A-Za-z0-9._+-]+$ ]]; then
        err "[gen-pkgbuild0] Invalid repository name for archive source: $archive_repo"
        return 1
    fi
    if [[ "$source_kind" == "archive" || "$source_kind" == "signed-tag" ]] && [[ "$(version_tag_name)" == "$PKGVER" ]]; then
        source_tag="\$pkgver"
        log "[gen-pkgbuild0] Using bare version tag ${PKGVER}"
    fi

    # A signed release needs a key only in aur mode. test mode keeps its dry-run
    # key. Other modes omit validpgpkeys unless the caller already chose one.
    # Signed-tag aur mode writes the verified tag signer later.
    if [[ "$source_kind" == "release" && ( "${AURGEN_MODE:-}" == "aur" || "${AURGEN_MODE:-}" == "test" || -n "${GPG_KEY_ID:-}" ) ]]; then
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
    fi

    # Detect build system
    BUILDSYS="$(detect_buildsys "$PROJECT_ROOT")"
    if [[ -z "$BUILDSYS" ]]; then
        # Check if this is a no-build project (scripts, configs, etc.)
        # Look for common patterns that indicate no build is needed
        local has_scripts=0 has_configs=0 has_docs=0 has_data=0
        
        # Check for executable scripts
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f -executable -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" -o -name "*.js" | grep . >/dev/null; then
            has_scripts=1
        fi
        
        # Check for configuration files
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f \( -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" \) | grep . >/dev/null; then
            has_configs=1
        fi
        
        # Check for documentation
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.rst" -o -name "*.html" \) | grep . >/dev/null; then
            has_docs=1
        fi
        
        # Check for data files
        if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" -type f \( -name "*.dat" -o -name "*.csv" -o -name "*.xml" -o -name "*.sql" \) | grep . >/dev/null; then
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

    local runtime_scan
    local -a scan_lines=()
    runtime_scan=$(detect_runtime_deps --units)
    mapfile -t scan_lines <<< "$runtime_scan"
    RUNTIME_DEPENDS="${scan_lines[0]}"
    if [[ -n "${RUNTIME_DEPENDS// }" ]]; then
        log "[gen-pkgbuild0] Detected depends: $RUNTIME_DEPENDS"
    fi

    set +u
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
        GH_USER_EMAIL=$(git -C "$PROJECT_ROOT" config user.email || echo "nobody@example.com")
        USER_NAME=$(git -C "$PROJECT_ROOT" config user.name || echo "Unknown User")
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

    # A Makefile can drive a shell project. arch=any unless a compiler is involved.
    local compiled=0 arch_item arch_field
    if project_compiles "$PROJECT_ROOT"; then
        compiled=1
    fi
    arch_field="arch=('any')"
    if (( ${#PKG_ARCH[@]} )); then
        arch_field="arch=("
        for arch_item in "${PKG_ARCH[@]}"; do
            arch_field+="$(pkgbuild_squote "$arch_item") "
        done
        arch_field="${arch_field% })"
    elif (( compiled )); then
        arch_field="arch=('x86_64' 'aarch64')"
    fi

    # Write PKGBUILD.0 main fields. printf, not an unquoted heredoc: the quoted
    # text may itself contain $() or backticks and must not be expanded again.
    DESC=${DESC//$'\n'/}
    # pkgname/pkgver are written unquoted, so allow only the characters makepkg accepts.
    if [[ ! "$PKGNAME" =~ ^[a-z0-9@._+-]+$ ]]; then
        err "[gen-pkgbuild0] Invalid pkgname: $PKGNAME"
        rm -f "$PKGBUILD0"
        return 1
    fi
    if [[ ! "$PKGVER" =~ ^[A-Za-z0-9._+]+$ ]]; then
        err "[gen-pkgbuild0] Invalid pkgver: $PKGVER"
        rm -f "$PKGBUILD0"
        return 1
    fi
    {
        printf 'pkgname=%s\n' "$PKGNAME"
        printf 'pkgver=%s\n' "$PKGVER"
        printf 'pkgrel=%s\n' "$PKGREL"
        printf 'pkgdesc=%s\n' "$(pkgbuild_squote "$DESC")"
        printf '%s\n' "$arch_field"
        # Callers that only set PKGNAME (tests, older entry points) still name the remote.
        printf 'url=%s\n' "$(pkgbuild_squote "https://github.com/${GH_USER}/${REPO_NAME:-$PKGNAME}")"
        if (( ${#PKG_LICENSE[@]} )); then
            pkgbuild_write_array license "${PKG_LICENSE[@]}"
        else
            printf 'license=(%s)\n' "$(pkgbuild_squote "$LICENSE")"
        fi
    } >> "$PKGBUILD0"
    # Only release sources use the selected signing key.
    if [[ -n "${GPG_KEY_ID:-}" && "$source_kind" == "release" ]]; then
        printf 'validpgpkeys=(%s)\n' "$(pkgbuild_squote "$GPG_KEY_ID")" >> "$PKGBUILD0"
    fi
    # install= is a filename, not a path the PKGBUILD looks up later.
    local install_file="${PKG_INSTALL:-}"
    if [[ -n "$install_file" && ( "$install_file" == */* || "$install_file" == .* ) ]]; then
        err "[gen-pkgbuild0] install must name a file in $AUR_DIR: $PKG_INSTALL"
        rm -f "$PKGBUILD0"
        return 1
    fi
    if [[ -z "$install_file" || ! -f "$AUR_DIR/$install_file" ]]; then
        if (( ${#scan_lines[@]} > 1 || PKG_INSTALL_MESSAGES )); then
            install_file="$PKGNAME.install"
            # Generated next to PKGBUILD.0 and cached with it; a dry run copies it to aur/dry-run/.
            generate_install_scriptlet "$AUR_DIR/$install_file" "$PKGNAME" "${scan_lines[@]:1}" || return 1
        elif [[ -n "$install_file" ]]; then
            err "[gen-pkgbuild0] install file not found: $AUR_DIR/$install_file"
            rm -f "$PKGBUILD0"
            return 1
        fi
    fi

    # Detected makedepends stay first; configured names are added once.
    # Runtime packages cover unversioned build requirements, but not constraints.
    local -a md_items=()
    local -a dep_items=()
    local -a md_kept=()
    local -A md_seen=()
    local -A runtime_bases=()
    local -A optional_bases=()
    local dep rt base index
    # A tool the config lists in optdepends is optional at run time; a script that
    # mentions it does not make it a build dependency.
    for dep in "${PKG_OPTDEPENDS[@]}"; do
        [[ -n "$dep" ]] && optional_bases["$(pkg_dep_base "${dep%%:*}")"]=1
    done
    if [[ -n "${MAKEDEPENDS// }" ]]; then
        local -a detected=()
        read -ra detected <<< "$MAKEDEPENDS"
        for dep in "${detected[@]}"; do
            [[ -z "$dep" ]] && continue
            # makepkg assumes base-devel, and Arch guidelines say not to list its members.
            case "$dep" in
                archlinux-keyring|autoconf|automake|binutils|bison|debugedit|fakeroot|file|findutils|flex|gawk|gcc|gettext|grep|groff|gzip|libtool|m4|make|pacman|patch|pkgconf|sed|sudo|texinfo|which)
                    continue
                    ;;
            esac
            [[ -n "${optional_bases[$(pkg_dep_base "$dep")]:-}" ]] && continue
            md_items+=("$dep")
        done
    fi
    for dep in "${md_items[@]}" "${PKG_MAKEDEPENDS[@]}"; do
        [[ -z "$dep" ]] && continue
        base="$(pkg_dep_base "$dep")"
        if [[ -n "${md_seen[$base]:-}" ]]; then
            index=$((${md_seen[$base]} - 1))
            if [[ "${md_kept[$index]}" == "$base" && "$dep" != "$base" ]]; then
                md_kept[index]="$dep"
            fi
            continue
        fi
        md_kept+=("$dep")
        md_seen[$base]=${#md_kept[@]}
    done
    md_items=("${md_kept[@]}")
    md_kept=()
    # makepkg clones a signed tag with git, which has to be a makedepend.
    if [[ "$source_kind" == "signed-tag" && -z "${md_seen[git]:-}" ]]; then
        md_seen[git]=1
        md_items+=("git")
    fi
    if [[ -n "${RUNTIME_DEPENDS// }" ]]; then
        local -a detected_rt=()
        read -ra detected_rt <<< "$RUNTIME_DEPENDS"
        for rt in "${detected_rt[@]}"; do
            [[ -z "$rt" ]] && continue
            dep_items+=("$rt")
            runtime_bases["$(pkg_dep_base "$rt")"]=1
        done
    fi
    if (( ${#md_items[@]} && ${#runtime_bases[@]} )); then
        for dep in "${md_items[@]}"; do
            [[ -n "${runtime_bases[$dep]:-}" ]] && continue
            md_kept+=("$dep")
        done
        md_items=()
        if (( ${#md_kept[@]} )); then
            md_items=("${md_kept[@]}")
        fi
    fi

    {
        pkgbuild_write_array depends "${dep_items[@]}"
        pkgbuild_write_array makedepends "${md_items[@]}"
        pkgbuild_write_array checkdepends "${PKG_CHECKDEPENDS[@]}"
        pkgbuild_write_array optdepends "${PKG_OPTDEPENDS[@]}"
        pkgbuild_write_array conflicts "${PKG_CONFLICTS[@]}"
        pkgbuild_write_array provides "${PKG_PROVIDES[@]}"
        pkgbuild_write_array backup "${PKG_BACKUP[@]}"
        if [[ -n "$install_file" ]]; then
            printf 'install=%s\n' "$(pkgbuild_squote "$install_file")"
        fi
    } >> "$PKGBUILD0"

    # shellcheck disable=SC2016 # the source lines hold makepkg variables
    if [[ "$source_kind" == "archive" ]]; then
        printf 'source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/%s.tar.gz")\n' "$source_tag" >> "$PKGBUILD0"
    elif [[ "$source_kind" == "signed-tag" ]]; then
        printf 'source=("$pkgname::git+$url.git#tag=%s?signed")\n' "$source_tag" >> "$PKGBUILD0"
    else
        echo "source=(" >> "$PKGBUILD0"
        for f in "${SOURCE_FILES[@]}"; do
            echo "  $(pkgbuild_squote "$f")" >> "$PKGBUILD0"
        done
        echo ")" >> "$PKGBUILD0"
    fi
    cat >> "$PKGBUILD0" <<'EOF'
b2sums=('SKIP')

EOF

    # Handle build function based on build system
    if [[ "$BUILDSYS" == "none" ]]; then
        # For no-build projects, create a build function with a no-op command
        {
            printf 'build() {\n'
            write_source_cd "$source_kind" "$archive_repo"
            printf '    # No build steps required\n    :\n}\n\n'
        } >> "$PKGBUILD0"
    else
        # For projects that need building, create the standard build function
        # Note: Tarball is created without subdirectory prefix, so no cd needed
        cat >> "$PKGBUILD0" <<'EOF'
build() {
EOF
        write_source_cd "$source_kind" "$archive_repo" >> "$PKGBUILD0"

        case "$BUILDSYS" in
            cmake)
                cat >> "$PKGBUILD0" <<'EOB'
    cmake -B build -S .
    cmake --build build
EOB
                ;;
            make)
                # install/test/clean as the default goal builds nothing; package()
                # runs make install. Any other goal (all, a binary) still builds.
                local goal
                goal="$(makefile_default_goal "$PROJECT_ROOT/Makefile")"
                case "$goal" in
                    ""|install|uninstall|test|check|clean|help|lint)
                        printf '    # No build steps required\n    :\n' >> "$PKGBUILD0"
                        ;;
                    *)
                        printf '    make\n' >> "$PKGBUILD0"
                        ;;
                esac
                ;;
            python)
                cat >> "$PKGBUILD0" <<'EOB'
    python setup.py build
EOB
                ;;
            node)
                cat >> "$PKGBUILD0" <<'EOB'
    npm install
    npm run build --if-present
EOB
                ;;
            rust)
                cat >> "$PKGBUILD0" <<'EOB'
    cargo build --release
EOB
                ;;
            go)
                cat >> "$PKGBUILD0" <<'EOB'
    go build -o "${pkgname%-git}" .
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
    :
EOB
                ;;
        esac

        cat >> "$PKGBUILD0" <<'EOF'
}
EOF
    fi

    # PKG_CHECK=false skips tests. Any other command is used as written.
    # true and empty follow the build system (default_check_command). A project
    # whose check is not hermetic names a package target in package.check.
    if [[ "${PKG_CHECK:-}" != "false" ]]; then
        local check_cmd=""
        if [[ -n "${PKG_CHECK:-}" && "${PKG_CHECK}" != "true" ]]; then
            check_cmd="$PKG_CHECK"
        else
            check_cmd="$(default_check_command "$BUILDSYS" "$PROJECT_ROOT")"
        fi
        if [[ -n "$check_cmd" ]]; then
            {
                printf '\ncheck() {\n'
                write_source_cd "$source_kind" "$archive_repo"
                printf '    %s\n}\n' "$check_cmd"
            } >> "$PKGBUILD0"
        fi
    fi

    # A Makefile install target owns the layout; copy rules would install the same files twice.
    local use_make_install=0
    if [[ "$BUILDSYS" == make && -f "$PROJECT_ROOT/Makefile" ]] && grep -E -q '^install:' "$PROJECT_ROOT/Makefile"; then
        use_make_install=1
    fi

    # Load configuration and generate copy commands.
    # Destinations stay double-quoted so $pkgname still expands at package time.
    local dir_rule src_dir dest_dir permissions excludes pattern
    local copy_rules_output
    local -a exclude_array copy_rules
    if ! copy_rules_output=$(get_copy_directories); then
        rm -f "$PKGBUILD0"
        return 1
    fi
    mapfile -t copy_rules <<< "$copy_rules_output"
    local copy_calls=""
    (( use_make_install )) || for dir_rule in "${copy_rules[@]}"; do
        [[ -z "$dir_rule" ]] && continue
        IFS=':' read -r src_dir dest_dir permissions excludes <<< "$dir_rule"
        if ! _valid_copy_destination "$dest_dir" || [[ ! "$permissions" =~ ^[0-7]{3,4}$ ]]; then
            err "[gen-pkgbuild0] Unsafe copy rule for $src_dir: '$dest_dir:$permissions'"
            rm -f "$PKGBUILD0"
            return 1
        fi
        copy_calls+="$({
            printf '    copy_tree "%s" "%s" "%s"' "$src_dir" "$dest_dir" "$permissions"
            if [[ -n "$excludes" ]]; then
                exclude_array=()
                IFS=',' read -ra exclude_array <<< "$excludes"
                for pattern in "${exclude_array[@]}"; do
                    pattern="$(_yaml_trim "$pattern")"
                    [[ -z "$pattern" ]] && continue
                    printf ' %s' "$(pkgbuild_squote "$pattern")"
                done
            fi
        })"$'\n'
    done

    # Generate package() function based on build system.
    # copy_tree() is emitted only when a copy rule calls it.
    if [[ -n "$copy_calls" ]]; then
        cat >> "$PKGBUILD0" <<'EOF'
# Helper function to copy and rebase paths with optional exclusions
copy_tree() {
    local src="$1" destbase="$2" mode="$3"
    shift 3
    [[ -d "$src" ]] || return 0

    local abs_src
    abs_src="$(realpath "$src" 2>/dev/null)" || return 0

    # Patterns stay find arguments so install-YAML metacharacters are not executed.
    local -a find_cmd=(find "$abs_src" \( -type f -o -type l \))
    local exclude
    for exclude in "$@"; do
        # Trim whitespace
        exclude="${exclude#"${exclude%%[! ]*}"}"
        exclude="${exclude%"${exclude##*[! ]}"}"
        if [[ -n "$exclude" ]]; then
            find_cmd+=(-not -path "$abs_src/$exclude/*")
        fi
    done
    find_cmd+=(-print0)

    mapfile -d '' -t files < <("${find_cmd[@]}") || return 0

    for file in "${files[@]}"; do
        local relpath
        relpath="$(realpath -s --relative-to="$abs_src" "$file")"
        if [[ -L "$file" ]]; then
            mkdir -p "$(dirname "$pkgdir/$destbase/$relpath")"
            ln -s "$(readlink "$file")" "$pkgdir/$destbase/$relpath"
        else
            install -Dm"$mode" "$file" "$pkgdir/$destbase/$relpath"
        fi
    done
}
EOF
    fi
    printf '\npackage() {\n' >> "$PKGBUILD0"
    if [[ "$source_kind" == "release" ]]; then
        printf '    # Note: Tarball is created without subdirectory prefix, so no cd needed\n' >> "$PKGBUILD0"
    else
        write_source_cd "$source_kind" "$archive_repo" >> "$PKGBUILD0"
    fi
    # shellcheck disable=SC2016 # $name and $pkgdir are for makepkg
    printf '    # Install license file\n    for name in %s; do\n        [[ -f "$name" ]] && install -Dm644 "$name" "$pkgdir/usr/share/licenses/$pkgname/LICENSE" && break\n    done\n' \
        "${LICENSE_FILE_NAMES[*]}" >> "$PKGBUILD0"
    if [[ -n "$copy_calls" ]]; then
        printf '\n    # Copy sections based on configuration\n%s' "$copy_calls" >> "$PKGBUILD0"
    fi

    # Add build system specific installation
    case "$BUILDSYS" in
        cmake)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install CMake build artifacts
    DESTDIR="$pkgdir" cmake --install build
EOB
            ;;
        make)
            # Makefiles default PREFIX to /usr/local. Arch packages install under
            # /usr, with install_vars appended. No install target means the
            # copy_tree rules above are the install step; make is not run to
            # discover the target (a ^install: rule).
            if (( use_make_install )); then
                # shellcheck disable=SC2016 # $pkgdir is for makepkg, not this shell
                local make_install='make install DESTDIR="$pkgdir" PREFIX=/usr'
                local install_var
                for install_var in "${PKG_INSTALL_VARS[@]}"; do
                    if [[ ! "$install_var" =~ ^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._/+-]+$ ]]; then
                        err "[gen-pkgbuild0] Unsafe install variable: '$install_var'"
                        rm -f "$PKGBUILD0"
                        return 1
                    fi
                    make_install+=" $install_var"
                done
                printf '    # Install Make build artifacts\n    %s\n' "$make_install" >> "$PKGBUILD0"
            fi
            ;;
        python)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Python package
    python setup.py install --root="$pkgdir" --optimize=1 --skip-build
EOB
            ;;
        node)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Node.js package
    npm install -g --prefix "$pkgdir/usr" .
EOB
            ;;
        rust)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Rust binary; a -git package still ships the crate's binary name
    install -Dm755 "target/release/${pkgname%-git}" "$pkgdir/usr/bin/${pkgname%-git}"
EOB
            ;;
        go)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Go binary
    install -Dm755 "${pkgname%-git}" "$pkgdir/usr/bin/${pkgname%-git}"
EOB
            ;;
        meson)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Meson build artifacts
    DESTDIR="$pkgdir" meson install -C build
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
    # install -Dm755 $pkgname "$pkgdir/usr/bin/$pkgname"
    # install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    :
EOB
            ;;
    esac

    # post_package is shell code, written like a custom check command.
    if (( ${#PKG_POST_PACKAGE[@]} )); then
        local post_line
        for post_line in "${PKG_POST_PACKAGE[@]}"; do
            printf '    %s\n' "$post_line" >> "$PKGBUILD0"
        done
    fi

    cat >> "$PKGBUILD0" <<'EOF'
}
EOF

    set -u
    if [[ "$BUILDSYS" == "none" ]]; then
        log "${GREEN}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME (no-build project)${RESET}"
    else
        log "${GREEN}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME ($BUILDSYS)${RESET}"
    fi
    pkgbuild0_input_stamp >| "$AUR_DIR/.PKGBUILD.0.stamp"
} 
