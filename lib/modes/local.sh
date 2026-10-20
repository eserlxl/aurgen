#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen local mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_local() {
    log "${SILVER}[local] Build and install from local tarball.${RESET}"
    
    # Extract version and package name for local mode
    extract_pkgbuild_data || exit 1
    
    declare -r TARBALL="${PKGNAME}-${PKGVER}.tar.gz"
    
    # Create tarball for local mode (similar to aur mode but without GPG signing)
    cd "$PROJECT_ROOT" || exit 1
    
    # Use current HEAD for local mode
    GIT_REF="HEAD"
    log "[local] Using HEAD for local tarball creation"
    
    # Set mtime for reproducible builds
    if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
        ARCHIVE_MTIME="--mtime=@$SOURCE_DATE_EPOCH"
        log "[local] Using SOURCE_DATE_EPOCH=\"$SOURCE_DATE_EPOCH\" for tarball mtime."
    else
        COMMIT_EPOCH=$(git show -s --format=%ct "$GIT_REF")
        ARCHIVE_MTIME="--mtime=@$COMMIT_EPOCH"
        log "[local] Using commit date (epoch \"$COMMIT_EPOCH\") of \"$GIT_REF\" for tarball mtime."
    fi
    
    # Archive and signed-tag build() cd into $srcdir/<dir>. A flat tarball leaves that directory missing.
    local source_dir=""
    local cd_line=""
    local -a prefix_args=()
    # shellcheck disable=SC2016 # $srcdir is the makepkg variable written by write_source_cd
    if cd_line=$(grep -m1 -E '^[[:space:]]*cd[[:space:]]+"\$srcdir/[^"]+"' "$PKGBUILD0"); then
        source_dir=${cd_line#*\"\$srcdir/}
        source_dir=${source_dir%%\"*}
        source_dir=${source_dir//\$pkgver/$PKGVER}
        source_dir=${source_dir//\$pkgname/$PKGNAME}
        # S applies the rewrite to member names only, so symlink targets stay relative.
        prefix_args=(--transform "s,^,$source_dir/,S")
    fi

    # Create tarball using filtered file list (same as aur mode).
    # A process substitution hides git's status, so collect the list first.
    local git_files=""
    local list_file=""
    local tar_status=0
    local -a files=()
    # Default core.quotePath C-quotes non-ASCII names, so tar would miss the path.
    git_files=$(git -c core.quotePath=false -C "$PROJECT_ROOT" ls-files) || {
        err "[local] Failed to list project files"
        exit 1
    }
    if [[ -n "$git_files" ]]; then
        mapfile -t files < <(printf '%s\n' "$git_files" | filter_pkgbuild_sources)
    fi
    list_file=$(mktemp)
    if ((${#files[@]} > 0)); then
        printf '%s\n' "${files[@]}" >| "$list_file"
    fi
    local out="${OUT_DIR:-$AUR_DIR}"
    (
        set -euo pipefail
        unset CI
        trap '' ERR
        tar czf "$out/$TARBALL" "$ARCHIVE_MTIME" "${prefix_args[@]}" -C "$PROJECT_ROOT" -T "$list_file"
    ) || tar_status=$?
    rm -f -- "$list_file"
    if ((tar_status != 0)); then
        exit "$tar_status"
    fi
    log "Created $out/$TARBALL using filtered file list and reproducible mtime."
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Copy PKGBUILD.0 to PKGBUILD and update it for local mode
    cp -f "$PKGBUILD0" "$PKGBUILD"
    
    # Update PKGBUILD to use the local tarball
    update_source_array_in_pkgbuild "$PKGBUILD" "$TARBALL"
    log "[local] Updated PKGBUILD to use local tarball: $TARBALL"
    
    # A local tarball is not a VCS source, so SKIP is not a finished checksum.
    update_checksums || exit 1

    generate_srcinfo || exit 1
    install_pkg "local"
}
