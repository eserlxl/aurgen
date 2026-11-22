#!/bin/bash
# Read-only project metadata, license, source-filter, and build-system detection for aurgen
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

_project_metadata_lib_dir="${LIB_INSTALL_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
if [[ ! -f "$_project_metadata_lib_dir/detect-deps.sh" ]]; then
    _project_metadata_lib_dir="$(dirname "${BASH_SOURCE[0]}")"
fi
if ! declare -F aurgen_ls_files >/dev/null 2>&1; then
    # Same as lib/helpers.sh, for callers that source this file alone.
    aurgen_ls_files() { local root="$1"; shift; git -C "$root" -c core.quotePath=off ls-files "$@"; }
fi
if ! declare -F pyproject_is_pep517 >/dev/null 2>&1; then
    # shellcheck source=lib/detect-deps.sh
    # shellcheck disable=SC1091
    . "$_project_metadata_lib_dir/detect-deps.sh"
fi
unset _project_metadata_lib_dir

# Map a license file to an SPDX id. An SPDX-License-Identifier line wins.
# Titles are ordered so AGPL/LGPL are not read as GPL, and BSD is not read as MIT
# (the BSD grant says "are permitted", which used to match a bare MIT search).
# Usage: detect_license_spdx <file>
detect_license_spdx() {
    local -x LC_ALL=C
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
    for name in ${PKG_KEEP[@]+"${PKG_KEEP[@]}"}; do
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
            go.mod|*/go.mod) ;;
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
    (( ${dry_run:-0} == 1 )) && return 0
    local GITATTR_FILE="$PROJECT_ROOT/.gitattributes"
    # Only a project that keeps a .gitattributes gets it updated. Creating one would add
    # an untracked file, and export-ignore lines would strip tests from the GitHub
    # archive an archive-source PKGBUILD builds and checks.
    [[ -f "$GITATTR_FILE" ]] || return 0
    local TMP_GITATTR
    TMP_GITATTR=$(mktemp)
    local all_files filtered_files
    mapfile -t all_files < <(aurgen_ls_files "$PROJECT_ROOT")
    mapfile -t filtered_files < <(aurgen_ls_files "$PROJECT_ROOT" | filter_pkgbuild_sources)
    # Compute files to ignore
    declare -A kept_files=()
    local f
    for f in "${filtered_files[@]}"; do
        [[ -n "$f" ]] && kept_files["$f"]=1
    done
    local block_lines=()
    declare -A block_set=()
    local line
    for f in "${all_files[@]}"; do
        if [[ -z "${kept_files[$f]+x}" ]]; then
            line="$f export-ignore"
            if [[ -z "${block_set[$line]+x}" ]]; then
                block_set["$line"]=1
                block_lines+=("$line")
            fi
        fi
    done
    # A leading slash anchors the override to the repository root, as the filter is.
    for f in ${PKG_KEEP[@]+"${PKG_KEEP[@]}"}; do
        f="/$f"
        [[ "$f" == */ ]] && f+='**'
        line="$f -export-ignore"
        if [[ -z "${block_set[$line]+x}" ]]; then
            block_set["$line"]=1
            block_lines+=("$line")
        fi
    done

    local begin_marker="# BEGIN aurgen export-ignore"
    local end_marker="# END aurgen export-ignore"
    local in_block=0 wrote_block=0
    # A BEGIN without its END would swallow the user's lines after it, so leave such a file alone.
    local n_begin n_end
    n_begin=$(grep -cFx -- "$begin_marker" "$GITATTR_FILE" || true)
    n_end=$(grep -cFx -- "$end_marker" "$GITATTR_FILE" || true)
    local first_begin first_end
    first_begin=$(grep -nFx -m1 -- "$begin_marker" "$GITATTR_FILE" | cut -d: -f1)
    first_end=$(grep -nFx -m1 -- "$end_marker" "$GITATTR_FILE" | cut -d: -f1)
    if [[ "$n_begin" != "$n_end" ]] || (( n_begin > 1 )) || (( n_begin == 1 && first_end < first_begin )); then
        echo -e "${YELLOW:-}[gitattributes] Warning: unbalanced '$begin_marker' markers in $GITATTR_FILE; leaving it unchanged.${RESET:-}" >&2
        rm -f "$TMP_GITATTR"
        return 0
    fi
    if [[ -f "$GITATTR_FILE" ]]; then
        # The copy replaces the tracked file, so an unterminated last line must not be lost.
        while IFS= read -r line || [[ -n "$line" ]]; do
            if (( in_block )); then
                if [[ "$line" == "$end_marker" ]]; then
                    in_block=0
                fi
                continue
            fi
            if [[ "$line" == "$begin_marker" ]]; then
                in_block=1
                if (( ! wrote_block )); then
                    printf '%s\n' "$begin_marker" >> "$TMP_GITATTR"
                    for f in ${block_lines[@]+"${block_lines[@]}"}; do
                        printf '%s\n' "$f" >> "$TMP_GITATTR"
                    done
                    printf '%s\n' "$end_marker" >> "$TMP_GITATTR"
                    wrote_block=1
                fi
                continue
            fi
            if [[ -n "${block_set[$line]+x}" ]]; then
                continue
            fi
            printf '%s\n' "$line" >> "$TMP_GITATTR"
        done < "$GITATTR_FILE"
    fi
    if (( ! wrote_block )); then
        printf '%s\n' "$begin_marker" >> "$TMP_GITATTR"
        for f in ${block_lines[@]+"${block_lines[@]}"}; do
            printf '%s\n' "$f" >> "$TMP_GITATTR"
        done
        printf '%s\n' "$end_marker" >> "$TMP_GITATTR"
    fi
    mv "$TMP_GITATTR" "$GITATTR_FILE"
}

# The build system a project's marker file names, first match wins. Prints
# nothing when none exists; gen_pkgbuild0 then tells no-build from unknown.
detect_buildsys() {
    local root="$1"
    local pyproject="$root/pyproject.toml"
    local pyproject_pep517=0 pyproject_compiled=0
    if pyproject_is_pep517 "$pyproject"; then
        pyproject_pep517=1
        if pyproject_is_compiled "$pyproject"; then
            pyproject_compiled=1
        fi
    fi
    if [[ -f "$root/CMakeLists.txt" ]]; then
        if (( pyproject_compiled )); then
            echo python-pep517
        else
            echo cmake
        fi
    elif [[ -f "$root/Makefile" ]]; then
        echo make
    elif (( pyproject_pep517 )); then
        echo python-pep517
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
        python-pep517) pyproject_is_compiled "$root/pyproject.toml" && return 0 ;;
    esac
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    while IFS= read -r tracked; do
        case "$tracked" in
            *.c|*.cc|*.cpp|*.cxx|*.c++|*.rs|*.go|*.vala) return 0 ;;
        esac
    done < <(aurgen_ls_files "$root" | filter_pkgbuild_sources)
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
            if [[ -f "$root/Cargo.lock" ]]; then
                echo 'cargo test --release --locked'
            else
                echo 'cargo test --release'
            fi
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
# Usage: pkgbuild0_input_stamp [config_file] [header_file]
pkgbuild0_input_stamp() {
    local config_file="${1:-}" header_file="${2:-}"
    if [[ -z "$config_file" ]]; then
        if [[ -n "${AURGEN_CONFIG_FILE:-}" ]]; then
            config_file="$AURGEN_CONFIG_FILE"
        else
            config_file="$AUR_DIR/aurgen.install.yaml"
            if [[ ! -f "$config_file" ]] && (( ${dry_run:-0} == 1 )) && [[ -n "${OUT_DIR:-}" && "$OUT_DIR" != "$AUR_DIR" && -f "$OUT_DIR/aurgen.install.yaml" ]]; then
                config_file="$OUT_DIR/aurgen.install.yaml"
            fi
        fi
    fi
    if [[ -z "$header_file" ]]; then
        header_file="$AUR_DIR/PKGBUILD.HEADER"
        if [[ ! -f "$header_file" ]] && (( ${dry_run:-0} == 1 )) && [[ -n "${OUT_DIR:-}" && "$OUT_DIR" != "$AUR_DIR" && -f "$OUT_DIR/PKGBUILD.HEADER" ]]; then
            header_file="$OUT_DIR/PKGBUILD.HEADER"
        fi
    fi
    local file sum scanned=""
    for file in "$config_file" "$header_file" "$PROJECT_ROOT/VERSION" "$PROJECT_ROOT/Makefile" "$PROJECT_ROOT/README.md"; do
        if [[ -f "$file" ]]; then
            sum=$(sha256sum -- "$file")
            printf '%s\n' "${sum%% *}"
        else
            printf '\n'
        fi
    done
    # Outside a git work tree there are no index records; the stamp then hashes an empty list.
    # core.quotePath=off: a quoted non-ASCII name would match nothing in the second call.
    scanned=$(aurgen_ls_files "$PROJECT_ROOT" 2>/dev/null | filter_pkgbuild_sources \
        | xargs -r -d '\n' git -c core.quotePath=off --literal-pathspecs -C "$PROJECT_ROOT" ls-files -s -- 2>/dev/null) || scanned=""
    sum=$(printf '%s' "$scanned" | sha256sum)
    printf '%s\n' "${sum%% *}"
    printf '%s\n' "$(git -C "${PROJECT_ROOT:-.}" describe --tags --abbrev=0 2>/dev/null || true)"
    printf '%s\n' "${AURGEN_VERSION:-}"
    if [[ -n "${AUR_DIR:-}" && -n "${PKG_INSTALL:-}" && "$PKG_INSTALL" != */* && "$PKG_INSTALL" != .* && -f "$AUR_DIR/$PKG_INSTALL" ]]; then
        printf '1\n'
    else
        printf '0\n'
    fi
}

# Goal a bare `make` would run. .DEFAULT_GOAL wins; otherwise the first rule
# target that does not start with "." and contains neither % nor =.
# Make is not executed: an install-only Makefile must not be run in build().
makefile_default_goal() {
    local LC_ALL=C
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

# Read-only metadata helpers shared by gen_pkgbuild0 and doctor mode.
# Usage: detect_project_version [project_root]
# Prints "<source>\t<pkgver>" where source is tag|version-file|empty-version-file|fallback.
detect_project_version() {
    local root="${1:-${PROJECT_ROOT:-}}"
    local pkgver="" ver_src="fallback"
    pkgver=$(git -C "$root" describe --tags --abbrev=0 2>>"${AURGEN_ERROR_LOG:-/dev/null}" | sed 's/^v//') || true
    if [[ -n "${pkgver:-}" ]]; then
        ver_src="tag"
    elif [[ -f "$root/VERSION" ]]; then
        pkgver=$(tr -d '[:space:]' < "$root/VERSION")
        if [[ -n "${pkgver:-}" ]]; then
            ver_src="version-file"
        else
            pkgver="1.0.0"
            ver_src="empty-version-file"
        fi
    else
        pkgver="1.0.0"
    fi
    printf '%s\t%s\n' "$ver_src" "$pkgver"
}

# Usage: detect_project_description [project_root] [fallback_pkgname] [online=1]
# Prints two lines: "<source>" then "<description>".
detect_project_description() {
    local root="${1:-${PROJECT_ROOT:-}}"
    local fallback="${2:-${PKGNAME:-}}"
    local online="${3:-1}"
    local desc="" desc_src="" gh_desc=""
    if (( online )) && command -v gh >/dev/null 2>&1 && [[ -n "$root" && -d "$root" ]]; then
        # gh resolves the repository from the working directory, so stay in "$root".
        gh_desc=$(cd "$root" && gh repo view --json description -q .description 2>>"${AURGEN_ERROR_LOG:-/dev/null}" || true)
        if [[ -n "${gh_desc// }" ]]; then
            desc="$gh_desc"
            desc_src="github"
        fi
    fi
    if [[ -z "${desc// }" ]] && pyproject_is_pep517 "$root/pyproject.toml"; then
        desc="$(_toml_extract "$root/pyproject.toml" "project" "description" "scalar" || true)"
        [[ -n "${desc// }" ]] && desc_src="pyproject.toml"
    fi
    if [[ -z "${desc// }" && -f "$root/Cargo.toml" ]]; then
        desc="$(_toml_extract "$root/Cargo.toml" "package" "description" "scalar" || true)"
        [[ -n "${desc// }" ]] && desc_src="Cargo.toml"
    fi
    if [[ -z "${desc// }" && -f "$root/package.json" ]]; then
        desc="$(_package_json_description "$root/package.json" || true)"
        [[ -n "${desc// }" ]] && desc_src="package.json"
    fi
    if [[ -z "${desc// }" && -f "$root/README.md" ]]; then
        # First prose line. A setext title is held until the next line proves it is not an underline.
        desc=$(awk '
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
        ' "$root/README.md")
        [[ -n "${desc// }" ]] && desc_src="README.md"
    fi
    if [[ -z "${desc// }" ]]; then
        desc="$fallback"
        desc_src="fallback"
    fi
    printf '%s\n%s\n' "$desc_src" "${desc//$'\n'/}"
}

# Usage: detect_project_license [project_root]
# Prints "<found>\t<spdx_id>\t<filename>".
detect_project_license() {
    local root="${1:-${PROJECT_ROOT:-}}"
    local license="custom" found=0 found_file="" detected="" f
    for f in "${LICENSE_FILE_NAMES[@]}"; do
        if [[ -f "$root/$f" ]]; then
            detected=$(detect_license_spdx "$root/$f")
            found=1
            found_file="$f"
            if [[ "$detected" != custom ]]; then
                license="$detected"
            fi
        fi
    done
    printf '%s\t%s\t%s\n' "$found" "$license" "$found_file"
}

# Check if a package name belongs to Arch's base-devel group.
# makepkg assumes base-devel is present, and Arch guidelines omit its members from makedepends.
is_base_devel_package() {
    case "${1:-}" in
        archlinux-keyring|autoconf|automake|binutils|bison|debugedit|fakeroot|file|findutils|flex|gawk|gcc|gettext|grep|groff|gzip|libtool|m4|make|pacman|patch|pkgconf|sed|sudo|texinfo|which)
            return 0
            ;;
    esac
    return 1
}
