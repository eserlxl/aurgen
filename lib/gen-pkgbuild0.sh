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
_gen_pkgbuild0_dir="${LIB_INSTALL_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
if [[ ! -f "$_gen_pkgbuild0_dir/project-metadata.sh" ]]; then
    _gen_pkgbuild0_dir="$(dirname "${BASH_SOURCE[0]}")"
fi
# shellcheck source=lib/project-metadata.sh
# shellcheck disable=SC1091
. "$_gen_pkgbuild0_dir/project-metadata.sh"
unset _gen_pkgbuild0_dir
init_colors

# Generate PKGBUILD.HEADER if it does not exist, using project metadata and license info
# Usage: gen_pkgbuild_header <USER_NAME> <GH_USER_EMAIL> <PROJECT_NAME> <LICENSE_TYPE> [header_file]
gen_pkgbuild_header() {
    local USER_NAME="$1" GH_USER_EMAIL="$2" PROJECT_NAME="$3" LICENSE_TYPE="$4"
    local HEADER_FILE="${5:-$AUR_DIR/PKGBUILD.HEADER}"
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
    (( $# || ${PKG_INSTALL_MESSAGES:-0} )) || return 0
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

# Resolve repository, version, description, license, source mode, GPG key, build system,
# and dependency metadata into gen_pkgbuild0's caller locals.
_pkgbuild0_resolve_metadata() {
    local REPO_URL _ver_src="" LICENSE_FOUND=0 select_gpg_key_status=0
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
    IFS=$'\t' read -r _ver_src PKGVER < <(detect_project_version "$PROJECT_ROOT")
    case "$_ver_src" in
        tag)
            debug "[gen-pkgbuild0] Success: Found git tag $PKGVER." >&2
            ;;
        version-file)
            debug "[gen-pkgbuild0] Success: Found version $PKGVER in VERSION file." >&2
            ;;
        empty-version-file)
            echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: VERSION file exists but is empty. Using fallback version $PKGVER.${RESET:-}" >&2
            ;;
        *)
            echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: No git tag found and no VERSION file. Using fallback version $PKGVER.${RESET:-}" >&2
            ;;
    esac
    PKGREL=1

    # Try to extract description from GitHub, then manifest/README, then fallback to PKGNAME
    DESC=""
    # test and golden mark their dry-run children offline; bin/aurgen refuses the marker on a real run.
    local desc_online=1
    if [[ "${dry_run:-0}" == 1 && "${_AURGEN_OFFLINE_DRY_RUN:-0}" == 1 ]]; then
        desc_online=0
    elif ! command -v gh >/dev/null 2>&1; then
        echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: GitHub CLI (gh) is required for fetching repo description but not found. Falling back to README or PKGNAME.${RESET:-}" >&2
    fi
    {
        IFS= read -r _ || true
        IFS= read -r DESC || true
    } < <(detect_project_description "$PROJECT_ROOT" "$PKGNAME" "$desc_online")
    DESC=${DESC:-"$PKGNAME"}

    # Detect the license from the first recognized license file; package()
    # installs that same file (LICENSE_FILE_DETECTED).
    LICENSE="custom"
    IFS=$'\t' read -r LICENSE_FOUND LICENSE LICENSE_FILE_DETECTED < <(detect_project_license "$PROJECT_ROOT")
    if [[ $LICENSE_FOUND -eq 1 ]]; then
        log "[gen-pkgbuild0] Detected license: $LICENSE"
    else
        echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: No license file found in project root. Setting license to 'custom'. Please add a LICENSE file for proper packaging.${RESET:-}" >&2
    fi
    # Configured text replaces detection. The header template takes one license id.
    if [[ -n "${PKG_DESCRIPTION:-}" ]]; then
        DESC="$PKG_DESCRIPTION"
    fi
    if (( ${#PKG_LICENSE[@]} )); then
        LICENSE="${PKG_LICENSE[0]}"
    fi

    # Empty package.source is today's release asset. archive and signed-tag are opt-in.
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
        # Scripts, configs, docs or data and no compiled sources: no build. doctor asks the same.
        BUILDSYS="$(nobuild_kind "$PROJECT_ROOT" "$AUR_DIR")"
    fi

    # Log build system detection
    if [[ "$BUILDSYS" == "none" ]]; then
        log "[gen-pkgbuild0] Detected no-build project (scripts/configs/data)"
    elif [[ "$BUILDSYS" == "unknown" ]]; then
        echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: Could not detect build system. Using placeholder build steps.${RESET:-}" >&2
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
    runtime_scan=$(detect_runtime_deps --units)
    mapfile -t scan_lines <<< "$runtime_scan"
    RUNTIME_DEPENDS="${scan_lines[0]:-}"
    if [[ -n "${RUNTIME_DEPENDS// }" ]]; then
        log "[gen-pkgbuild0] Detected depends: $RUNTIME_DEPENDS"
    fi
}

# Write PKGBUILD.HEADER, collect filtered sources, validate pkgname/pkgver, and emit core fields.
_pkgbuild0_emit_header() {
    local header_src="$AUR_DIR/PKGBUILD.HEADER" file
    rm -f "$PKGBUILD0" || exit 1
    # --- Write PKGBUILD.0 ---
    # Use PKGBUILD.HEADER if it exists and is readable. If it exists but cannot be read (e.g., permission denied), warn and continue with empty header. If it does not exist, try to generate it from project metadata.
    if [[ ! -f "$header_src" && "$template_dir" != "$AUR_DIR" && -f "$template_dir/PKGBUILD.HEADER" ]]; then
        header_src="$template_dir/PKGBUILD.HEADER"
    fi
    if [[ -f "$header_src" ]]; then
        if [[ ! -r "$header_src" ]]; then
            warn "[gen-pkgbuild0] Warning: $header_src exists but cannot be read (permission denied or unreadable). Continuing with empty header."
            : > "$PKGBUILD0" || { echo -e "${YELLOW:-}[gen-pkgbuild0] Error: Failed to write empty header to $PKGBUILD0 (write error).${RESET:-}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        else
            cat "$header_src" > "$PKGBUILD0" || { echo -e "${YELLOW:-}[gen-pkgbuild0] Error: Failed to write header to $PKGBUILD0 (write error).${RESET:-}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        fi
    else
        # Try to generate PKGBUILD.HEADER from project metadata
        GH_USER_EMAIL=$(git -C "$PROJECT_ROOT" config user.email || echo "nobody@example.com")
        USER_NAME=$(git -C "$PROJECT_ROOT" config user.name || echo "Unknown User")
        gen_pkgbuild_header "$USER_NAME" "$GH_USER_EMAIL" "$PKGNAME" "$LICENSE" "$template_dir/PKGBUILD.HEADER"
        if [[ -f "$template_dir/PKGBUILD.HEADER" && -r "$template_dir/PKGBUILD.HEADER" ]]; then
            cat "$template_dir/PKGBUILD.HEADER" > "$PKGBUILD0" || { echo -e "${YELLOW:-}[gen-pkgbuild0] Error: Failed to write generated header to $PKGBUILD0 (write error).${RESET:-}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        else
            echo "# Maintainer: $USER_NAME <$GH_USER_EMAIL>" > "$PKGBUILD0" || { echo -e "${YELLOW:-}[gen-pkgbuild0] Error: Failed to write default header to $PKGBUILD0 (write error).${RESET:-}" >&2; exit 1; }
            echo >> "$PKGBUILD0"
        fi
    fi

    # --- Collect source files using git ls-files, with exclusions ---
    # SOURCE_FILES stays populated for callers. Release source= is one tarball name.
    SOURCE_FILES=()
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Use filter_pkgbuild_sources to ensure only allowed files are included
        while IFS= read -r file; do
            SOURCE_FILES+=("$file")
        done < <(aurgen_ls_files "$PROJECT_ROOT" | filter_pkgbuild_sources)
        if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
            echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: git ls-files returned no files after exclusions.${RESET:-}" >&2
        fi
    else
        echo -e "${YELLOW:-}[gen-pkgbuild0] Warning: Not a git repository.${RESET:-}" >&2
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
    local pkg_url="${PKG_URL:-$gh_repo_url}"
    {
        printf 'pkgname=%s\n' "$PKGNAME"
        printf 'pkgver=%s\n' "$PKGVER"
        printf 'pkgrel=%s\n' "$PKGREL"
        if [[ -n "${PKG_EPOCH:-}" ]]; then
            printf 'epoch=%s\n' "$PKG_EPOCH"
        fi
        printf 'pkgdesc=%s\n' "$(pkgbuild_squote "$DESC")"
        printf '%s\n' "$arch_field"
        # Callers that only set PKGNAME (tests, older entry points) still name the remote.
        printf 'url=%s\n' "$(pkgbuild_squote "$pkg_url")"
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
}

# Deduplicate dependency arrays and write depends/makedepends/metadata arrays, install=, source=, and b2sums=.
_pkgbuild0_emit_depends_and_sources() {
    # install= is a filename, not a path the PKGBUILD looks up later.
    local install_file="${PKG_INSTALL:-}"
    if [[ -n "$install_file" && ( "$install_file" == */* || "$install_file" == .* ) ]]; then
        err "[gen-pkgbuild0] install must name a file in $AUR_DIR: ${PKG_INSTALL:-}"
        rm -f "$PKGBUILD0"
        return 1
    fi
    if [[ -z "$install_file" || ! -f "$AUR_DIR/$install_file" ]]; then
        if (( ${#scan_lines[@]} > 1 || ${PKG_INSTALL_MESSAGES:-0} )); then
            install_file="$PKGNAME.install"
            # Generated next to PKGBUILD.0 and cached with it; a dry run keeps it in aur/dry-run/.
            generate_install_scriptlet "$template_dir/$install_file" "$PKGNAME" "${scan_lines[@]:1}" || return 1
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
    # A !name in package.makedepends drops that detected build dependency.
    local -A md_dropped=()
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
            if is_base_devel_package "$dep"; then
                continue
            fi
            [[ -n "${optional_bases[$(pkg_dep_base "$dep")]:-}" ]] && continue
            md_items+=("$dep")
        done
    fi
    for dep in "${PKG_MAKEDEPENDS[@]}"; do
        [[ "$dep" == \!* ]] && md_dropped["$(pkg_dep_base "${dep#!}")"]=1
    done
    for dep in "${md_items[@]}" "${PKG_MAKEDEPENDS[@]}"; do
        [[ -z "$dep" || "$dep" == \!* ]] && continue
        base="$(pkg_dep_base "$dep")"
        [[ -n "${md_dropped[$base]:-}" ]] && continue
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
        pkgbuild_write_array groups "${PKG_GROUPS[@]}"
        pkgbuild_write_array depends "${dep_items[@]}"
        pkgbuild_write_array makedepends "${md_items[@]}"
        pkgbuild_write_array checkdepends "${PKG_CHECKDEPENDS[@]}"
        pkgbuild_write_array optdepends "${PKG_OPTDEPENDS[@]}"
        pkgbuild_write_array conflicts "${PKG_CONFLICTS[@]}"
        pkgbuild_write_array provides "${PKG_PROVIDES[@]}"
        pkgbuild_write_array replaces "${PKG_REPLACES[@]}"
        pkgbuild_write_array options "${PKG_OPTIONS[@]}"
        pkgbuild_write_array backup "${PKG_BACKUP[@]}"
        if [[ -n "$install_file" ]]; then
            printf 'install=%s\n' "$(pkgbuild_squote "$install_file")"
        fi
    } >> "$PKGBUILD0"

    # shellcheck disable=SC2016 # $url and source lines hold makepkg variables when PKG_URL is unset
    local source_repo_url='$url'
    if [[ -n "${PKG_URL:-}" ]]; then
        source_repo_url="$gh_repo_url"
    fi
    # shellcheck disable=SC2016 # the source lines hold makepkg variables
    if [[ "$source_kind" == "archive" ]]; then
        printf 'source=("$pkgname-$pkgver.tar.gz::%s/archive/refs/tags/%s.tar.gz")\n' "$source_repo_url" "$source_tag" >> "$PKGBUILD0"
    elif [[ "$source_kind" == "signed-tag" ]]; then
        printf 'source=("$pkgname::git+%s.git#tag=%s?signed")\n' "$source_repo_url" "$source_tag" >> "$PKGBUILD0"
    else
        # One tarball name. local and aur replace this line; git writes its own.
        printf 'source=("$pkgname-$pkgver.tar.gz")\n' >> "$PKGBUILD0"
    fi
    cat >> "$PKGBUILD0" <<'EOF'
b2sums=('SKIP')

EOF
}

# Emit build() and check() sections into PKGBUILD.0.
_pkgbuild0_emit_build_and_check() {
    # package.prepare: patches and source fixes run once, in the source tree, before build().
    if (( ${#PKG_PREPARE[@]} )); then
        local prepare_line
        {
            printf 'prepare() {\n'
            write_source_cd "$source_kind" "$archive_repo"
            for prepare_line in "${PKG_PREPARE[@]}"; do
                printf '    %s\n' "$prepare_line"
            done
            printf '}\n\n'
        } >> "$PKGBUILD0"
    fi
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
                local cmake_configure='cmake -B build -S .'
                local cmake_arg cmake_has_type=0 cmake_has_prefix=0
                for cmake_arg in "${PKG_CMAKE_ARGS[@]}"; do
                    [[ "$cmake_arg" == -DCMAKE_BUILD_TYPE[:=]* ]] && cmake_has_type=1
                    [[ "$cmake_arg" == -DCMAKE_INSTALL_PREFIX[:=]* ]] && cmake_has_prefix=1
                done
                # Arch's CMake package guidelines: install under /usr (CMake's default is
                # /usr/local) and let makepkg's flags choose optimisation (build type None).
                (( cmake_has_type )) || cmake_configure+=' -DCMAKE_BUILD_TYPE=None'
                (( cmake_has_prefix )) || cmake_configure+=' -DCMAKE_INSTALL_PREFIX=/usr'
                for cmake_arg in "${PKG_CMAKE_ARGS[@]}"; do
                    if [[ ! "$cmake_arg" =~ ^-D[A-Za-z0-9_]+(:[A-Z]+)?=[A-Za-z0-9_./+=,-]*$ ]]; then
                        err "[gen-pkgbuild0] Unsafe cmake argument in package.cmake_args: '$cmake_arg'"
                        rm -f "$PKGBUILD0"
                        return 1
                    fi
                    cmake_configure+=" $(pkgbuild_squote "$cmake_arg")"
                done
                printf '    %s\n    cmake --build build\n' "$cmake_configure" >> "$PKGBUILD0"
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
            python-pep517)
                cat >> "$PKGBUILD0" <<'EOB'
    python -m build --wheel --no-isolation
EOB
                ;;
            python)
                cat >> "$PKGBUILD0" <<'EOB'
    python setup.py build
EOB
                ;;
            node)
                if [[ -f "$PROJECT_ROOT/package-lock.json" || -f "$PROJECT_ROOT/npm-shrinkwrap.json" ]]; then
                    cat >> "$PKGBUILD0" <<'EOB'
    npm ci
    npm run build --if-present
EOB
                else
                    cat >> "$PKGBUILD0" <<'EOB'
    npm install
    npm run build --if-present
EOB
                fi
                ;;
            rust)
                if [[ -f "$PROJECT_ROOT/Cargo.lock" ]]; then
                    cat >> "$PKGBUILD0" <<'EOB'
    cargo build --release --locked
EOB
                else
                    cat >> "$PKGBUILD0" <<'EOB'
    cargo build --release
EOB
                fi
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
}

# Emit optional copy_tree() helper and package() function into PKGBUILD.0.
_pkgbuild0_emit_package() {
    # A Makefile install target owns the layout; copy rules would install the same files twice.
    local use_make_install=0
    if [[ "$BUILDSYS" == make && -f "$PROJECT_ROOT/Makefile" ]] && grep -E -q '^install:' "$PROJECT_ROOT/Makefile"; then
        use_make_install=1
    fi

    # Load configuration and generate copy commands.
    # Destinations stay double-quoted so $pkgname still expands at package time.
    local dir_rule="" src_dir="" dest_dir="" permissions="" excludes="" pattern=""
    local copy_rules_output=""
    local -a exclude_array=() copy_rules=()
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
    # The loop installs the first existing name. When the license id came from a
    # later file (an earlier one is a pointer or another license), try that file first.
    # When no standard name exists, install every tracked LICENSE-*/COPYING-*/LICENCE-* file.
    local -a license_names=("${LICENSE_FILE_NAMES[@]}") pattern_licenses=()
    local license_name first_license=""
    for license_name in "${LICENSE_FILE_NAMES[@]}"; do
        if [[ -f "$PROJECT_ROOT/$license_name" ]]; then
            first_license="$license_name"
            break
        fi
    done
    if [[ -z "$first_license" ]]; then
        mapfile -t pattern_licenses < <(_project_pattern_license_files "$PROJECT_ROOT")
    fi
    if (( ${#pattern_licenses[@]} )); then
        local -a quoted_licenses=()
        for license_name in "${pattern_licenses[@]}"; do
            if [[ "$license_name" =~ ^[A-Za-z0-9._+-]+$ ]]; then
                quoted_licenses+=("$license_name")
            else
                quoted_licenses+=("$(pkgbuild_squote "$license_name")")
            fi
        done
        # shellcheck disable=SC2016 # $name, $pkgdir and $pkgname are for makepkg
        printf '    # Install license file\n    for name in %s; do\n        [[ -f "$name" ]] && install -Dm644 "$name" "$pkgdir/usr/share/licenses/$pkgname/$name"\n    done\n' \
            "${quoted_licenses[*]}" >> "$PKGBUILD0"
    else
        if [[ -n "${LICENSE_FILE_DETECTED:-}" && "$LICENSE_FILE_DETECTED" != "$first_license" ]]; then
            license_names=("$LICENSE_FILE_DETECTED")
            for license_name in "${LICENSE_FILE_NAMES[@]}"; do
                [[ "$license_name" == "$LICENSE_FILE_DETECTED" ]] || license_names+=("$license_name")
            done
        fi
        # shellcheck disable=SC2016,SC2154 # $name and $pkgdir are for makepkg; LICENSE_FILE_NAMES from project-metadata.sh
        printf '    # Install license file\n    for name in %s; do\n        [[ -f "$name" ]] && install -Dm644 "$name" "$pkgdir/usr/share/licenses/$pkgname/LICENSE" && break\n    done\n' \
            "${license_names[*]}" >> "$PKGBUILD0"
    fi
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
        python-pep517)
            cat >> "$PKGBUILD0" <<'EOB'
    # Install Python PEP 517 package
    python -m installer --destdir="$pkgdir" dist/*.whl
EOB
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
}

gen_pkgbuild0() {
    local -x LC_ALL=C
    if (( ${dry_run:-0} == 0 )); then
        generate_gitattributes_from_filter
    fi

    local template_dir="$AUR_DIR"
    if (( ${dry_run:-0} == 1 )) && [[ -n "${OUT_DIR:-}" && "$OUT_DIR" != "$AUR_DIR" ]]; then
        template_dir="$OUT_DIR"
    fi
    mkdir -p "$template_dir"

    # Generate default configuration file if it doesn't exist
    if [[ -z "${AURGEN_CONFIG_FILE:-}" && ! -f "$AUR_DIR/aurgen.install.yaml" && ! -f "$template_dir/aurgen.install.yaml" ]]; then
        generate_default_config "$template_dir/aurgen.install.yaml" || return 1
    fi

    # Generate example configuration file if it doesn't exist
    if [[ ! -f "$AUR_DIR/aurgen.install.yaml.example" && ! -f "$template_dir/aurgen.install.yaml.example" ]]; then
        generate_example_config "$template_dir/aurgen.install.yaml.example" || return 1
    fi

    local PKGBUILD0 GH_USER GH_REPO PKGVER PKGREL DESC LICENSE LICENSE_FILE_DETECTED BUILDSYS
    local MAKEDEPENDS RUNTIME_DEPENDS USER_NAME GH_USER_EMAIL
    local source_kind archive_repo source_tag="v\$pkgver"
    local -a scan_lines=() SOURCE_FILES=()

    if [[ "$template_dir" != "$AUR_DIR" ]]; then
        PKGBUILD0="$template_dir/PKGBUILD.0"
    else
        PKGBUILD0="${PKGBUILD0:-$AUR_DIR/PKGBUILD.0}"
    fi

    # Warn and remove existing PKGBUILD.0 if present
    if [[ -f "$PKGBUILD0" ]]; then
        echo -e "${YELLOW:-}[gen-pkgbuild0] Existing $PKGBUILD0 found. Deleting before regeneration.${RESET:-}" >&2
        rm -f "$PKGBUILD0"
    fi

    _pkgbuild0_resolve_metadata || return 1
    local gh_repo_url="https://github.com/${GH_USER:-}/${REPO_NAME:-$PKGNAME}"

    _pkgbuild0_emit_header || return 1
    _pkgbuild0_emit_depends_and_sources || return 1
    _pkgbuild0_emit_build_and_check || return 1
    _pkgbuild0_emit_package || return 1

    if [[ "$BUILDSYS" == "none" ]]; then
        log "${GREEN:-}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME (no-build project)${RESET:-}"
    else
        log "${GREEN:-}[gen-pkgbuild0] Generated $PKGBUILD0 for $PKGNAME ($BUILDSYS)${RESET:-}"
    fi
    pkgbuild0_input_stamp >| "$template_dir/.PKGBUILD.0.stamp"
}
