#!/bin/bash
# AUR Integration system for AURGen
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# AUR Integration functionality for AURGen

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# AUR Integration configuration variables
AUR_REPO_DIR=""
AUR_AUTO_PUSH=""
AUR_COMMIT_MESSAGE=""
AUR_GIT_USER_NAME=""
AUR_GIT_USER_EMAIL=""
AUR_SSH_KEY=""
AUR_VALIDATE_BEFORE_PUSH=""
# True only after push_to_aur succeeds; aur-deploy must not claim a push otherwise.
AUR_PUSH_SUCCEEDED="false"
# Verdict of the last aur_probe_ssh call: ok, denied, hostkey, or unreachable.
AUR_SSH_PROBE=""

# Load AUR integration configuration from aurgen.install.yaml
# Usage: load_aur_integration_config
# Only ~ and ~/ expand; ~user would become "$HOME"user, so refuse it.
# Usage: _aur_check_tilde <key> <value>
_aur_check_tilde() {
    # shellcheck disable=SC2088 # literal tilde comparison
    if [[ "$2" == '~'* && "$2" != '~' && "$2" != '~/'* ]]; then
        err "[aur-integration] Invalid configuration value for $1: $2 (use an absolute path, ~ or ~/...)"
        return 1
    fi
}

load_aur_integration_config() {
    local aur_config_file
    if declare -F aurgen_config_file >/dev/null 2>&1; then
        aur_config_file="$(aurgen_config_file)"
    elif [[ -n "${AURGEN_CONFIG_FILE:-}" ]]; then
        aur_config_file="$AURGEN_CONFIG_FILE"
    else
        aur_config_file="$AUR_DIR/aurgen.install.yaml"
    fi
    
    # Initialize with defaults
    # XDG data, not cache: the clones hold commits waiting to be pushed, and every user can write it.
    AUR_REPO_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/aurgen/aur"
    AUR_AUTO_PUSH="true"
    AUR_COMMIT_MESSAGE="Update to version {version}"
    AUR_GIT_USER_NAME=""
    AUR_GIT_USER_EMAIL=""
    AUR_SSH_KEY=""
    AUR_VALIDATE_BEFORE_PUSH="true"
    
    # Try to load from aur directory
    if [[ -f "$aur_config_file" ]]; then
        if [[ ! -r "$aur_config_file" ]]; then
            err "[aur-integration] AUR configuration file is not readable: $aur_config_file"
            return 1
        fi
        debug "[aur-integration] Loading AUR configuration from $aur_config_file"
        parse_aur_integration_config "$aur_config_file" || return 1
    else
        warn "[aur-integration] AUR configuration file not found, using defaults"
    fi
}

# Parse AUR integration configuration from YAML
# Usage: parse_aur_integration_config <config_file>
parse_aur_integration_config() {
    local config_file="$1"
    local in_aur_section=0
    local key=""
    local value=""
    local LC_ALL=C
    local known_keys="aur_repo_dir, auto_push, commit_message, git_user_name, git_user_email, ssh_key, validate_before_push"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        line="$(_yaml_strip_comment "$line")"
        [[ -z "${line// }" ]] && continue
        
        # Check for aur_integration section
        if [[ "$line" =~ ^aur_integration:[[:space:]]*$ ]]; then
            in_aur_section=1
            continue
        fi
        
        # Exit aur_integration section when we hit another top-level line
        if (( in_aur_section )) && [[ "$line" != [[:space:]]* ]]; then
            in_aur_section=0
            continue
        fi
        
        # Parse aur_integration settings
        if (( in_aur_section )); then
            if [[ ! "$line" =~ ^[[:space:]]+([^:]+):[[:space:]]*(.*)$ ]]; then
                err "[aur-integration] Invalid aur_integration entry: $(_yaml_trim "$line")"
                return 1
            fi
            key="$(_yaml_trim "${BASH_REMATCH[1]}")"
            value="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "${BASH_REMATCH[2]}")")")"
            case "$key" in
                aur_repo_dir|auto_push|commit_message|git_user_name|git_user_email|ssh_key|validate_before_push|backup_existing) ;;
                *)
                    err "[aur-integration] Unknown aur_integration key '$key'; known keys: $known_keys"
                    return 1
                    ;;
            esac
            # An empty value keeps the default: an empty aur_repo_dir would put clones under /.
            [[ -n "$value" ]] || continue
            case "$key" in
                auto_push|validate_before_push)
                    value="${value,,}"
                    case "$value" in
                        true|false) ;;
                        *) err "[aur-integration] Invalid configuration value for $key: expected true or false"; return 1 ;;
                    esac
                    ;;
            esac
            case "$key" in
                # update_checksums and generate_srcinfo cd into aur/, so a relative
                # clone dir would be reread there. ~ is expanded first; an absolute
                # path (including one that ~ produced) is kept as written.
                aur_repo_dir)
                    _aur_check_tilde aur_repo_dir "$value" || return 1
                    AUR_REPO_DIR="${value/#\~/$HOME}"
                    if [[ "$AUR_REPO_DIR" != /* ]]; then
                        AUR_REPO_DIR="$(realpath -m -- "${PROJECT_ROOT:-$PWD}/${AUR_REPO_DIR}")"
                    fi
                    ;;
                auto_push) AUR_AUTO_PUSH="$value" ;;
                commit_message) AUR_COMMIT_MESSAGE="$value" ;;
                git_user_name) AUR_GIT_USER_NAME="$value" ;;
                git_user_email) AUR_GIT_USER_EMAIL="$value" ;;
                ssh_key)
                    _aur_check_tilde ssh_key "$value" || return 1
                    AUR_SSH_KEY="$value"
                    ;;
                validate_before_push) AUR_VALIDATE_BEFORE_PUSH="$value" ;;
                backup_existing) ;;
            esac
        fi
    done < "$config_file"
    
    debug "[aur-integration] Loaded configuration:"
    debug "[aur-integration]   AUR_REPO_DIR: $AUR_REPO_DIR"
    debug "[aur-integration]   AUR_AUTO_PUSH: $AUR_AUTO_PUSH"
    debug "[aur-integration]   AUR_COMMIT_MESSAGE: $AUR_COMMIT_MESSAGE"
}

# Check if AUR repository exists for the package
# Usage: check_aur_repo_exists <pkgname>
# Returns: 0 if exists, 1 if not
check_aur_repo_exists() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    if [[ -d "$aur_repo_path" && -d "$aur_repo_path/.git" ]]; then
        debug "[aur-integration] AUR repository exists: $aur_repo_path"
        return 0
    else
        debug "[aur-integration] AUR repository does not exist: $aur_repo_path"
        return 1
    fi
}

# Same key file git uses. Empty means ssh's own configuration.
# A value that is not a path is still one argument: evaluating it would run
# whatever the config file contained.
# Usage: aur_resolve_ssh_key <var-name>
aur_resolve_ssh_key() {
    local -n _resolved="$1"
    _resolved=""
    [[ -n "$AUR_SSH_KEY" ]] || return 0
    local expanded="${AUR_SSH_KEY/#\~/$HOME}"
    if [[ -f "$expanded" ]]; then
        _resolved="$expanded"
        return 0
    fi
    warn "[aur-integration] ssh_key ${AUR_SSH_KEY} does not exist; using the ssh configuration"
}

# Append core.sshCommand only when the configured key is a real file.
# Usage: aur_apply_ssh_key <array-name>
aur_apply_ssh_key() {
    local -n _git_cmd="$1"
    local key=""
    aur_resolve_ssh_key key
    [[ -n "$key" ]] || return 0
    _git_cmd+=(-c "core.sshCommand=ssh -o IdentitiesOnly=yes -i $(printf %q "$key")")
    debug "[aur-integration] Using SSH key: $AUR_SSH_KEY"
}

# Non-interactive check of the AUR account. Returns 0 either way: a failed
# check must not abort aur-init. An unknown host key is reported, not accepted.
# Also sets AUR_SSH_PROBE to ok, denied, hostkey, or unreachable.
# Usage: aur_probe_ssh
aur_probe_ssh() {
    AUR_SSH_PROBE=""
    local key=""
    aur_resolve_ssh_key key
    # StrictHostKeyChecking=yes: an ssh_config accept-new must not record the key here.
    local -a ssh_cmd=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes)
    if [[ -n "$key" ]]; then
        ssh_cmd+=(-i "$key")
    fi
    ssh_cmd+=(aur@aur.archlinux.org help)

    local output=""
    local status=0
    output=$("${ssh_cmd[@]}" 2>&1) || status=$?
    if (( status == 0 )); then
        AUR_SSH_PROBE="ok"
        log "AUR SSH: ok"
        return 0
    fi
    if [[ "$output" == *"Permission denied"* ]]; then
        AUR_SSH_PROBE="denied"
        warn "AUR SSH: permission denied: add your public key at https://aur.archlinux.org/account, or load the key into ssh-agent (ssh-add)"
    elif [[ "$output" == *"Host key verification failed"* ]]; then
        AUR_SSH_PROBE="hostkey"
        warn "AUR SSH: host key verification failed: connect once with ssh aur@aur.archlinux.org to verify the key"
    else
        # shellcheck disable=SC2034 # read by doctor.sh and callers of aur_probe_ssh
        AUR_SSH_PROBE="unreachable"
        local first="${output%%$'\n'*}"
        warn "AUR SSH: unreachable: ${first}"
    fi
    return 0
}

# Initialize new AUR repository
# Usage: init_aur_repo <pkgname>
init_aur_repo() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    log "[aur-integration] Initializing AUR repository: $aur_repo_path"

    if [[ -e "$aur_repo_path" || -L "$aur_repo_path" ]]; then
        err "[aur-integration] Destination already exists at $aur_repo_path; move/remove it or run 'aurgen aur-init' to reinitialize"
        return 1
    fi
    
    # Create AUR directory if it doesn't exist
    if ! mkdir -p "$AUR_REPO_DIR" 2>>"${AURGEN_ERROR_LOG:-/dev/null}"; then
        err "[aur-integration] Cannot create $AUR_REPO_DIR. Set aur_integration.aur_repo_dir in aurgen.install.yaml to a writable directory."
        return 1
    fi
    
    # Anonymous https clone; only the push needs the ssh key. The push URL is
    # set by the clone itself, so no clone is left without it.
    if ! git clone -c "remote.origin.pushurl=ssh://aur@aur.archlinux.org/$pkgname.git" \
        "https://aur.archlinux.org/$pkgname.git" "$aur_repo_path" 2>>"${AURGEN_ERROR_LOG:-/dev/null}"; then
        rm -rf "$aur_repo_path" 2>/dev/null || true
        err "[aur-integration] Failed to clone AUR repository for $pkgname"
        return 1
    fi
    
    log "[aur-integration] Successfully initialized AUR repository: $aur_repo_path"
    return 0
}

# First "key = value" in a makepkg .SRCINFO. Leading tabs are normal.
# Usage: aur_srcinfo_field <key> <file>
aur_srcinfo_field() {
    local key="$1"
    local file="$2"
    local line value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        value="${BASH_REMATCH[1]}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ -n "$value" ]]; then
            printf '%s\n' "$value"
            return 0
        fi
    done < "$file"
    return 1
}

# AUR clone name. pkgbase wins (git mode stores the -git name there); else pkgname.
# No .SRCINFO file means PKGNAME. Returns 1 when the file has neither field.
# Usage: aur_package_name
aur_package_name() {
    local name=""
    if [[ -f "${SRCINFO:-}" ]]; then
        name=$(aur_srcinfo_field pkgbase "$SRCINFO") || name=""
        if [[ -z "$name" ]]; then
            name=$(aur_srcinfo_field pkgname "$SRCINFO") || name=""
        fi
        if [[ -z "$name" ]]; then
            return 1
        fi
        printf '%s\n' "$name"
        return 0
    fi
    # shellcheck disable=SC2153 # PKGNAME is set by init.sh
    printf '%s\n' "$PKGNAME"
}

# Deploy PKGBUILD and .SRCINFO to AUR repository
# Usage: deploy_to_aur <pkgname>
# A downloaded file must be pinned before it reaches the AUR: SKIP is only valid for a
# VCS source (git+...), a local file, or a signature file. Reads .SRCINFO, where sources and each
# checksum array are listed in the same order.
aur_srcinfo_checksums_pinned() {
    local LC_ALL=C
    local srcinfo="$1" line key value i src fname arch_suffix
    local -A sources_by_arch=()
    local -A sums=()
    local -a arch_sources=()
    [[ -f "$srcinfo" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]=[[:space:]](.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
            pkgname) break ;;
            source)
                sources_by_arch["_"]+="$value"$'\n' ;;
            source_*)
                sources_by_arch["${key#source}"]+="$value"$'\n' ;;
            md5sums|sha1sums|sha224sums|sha256sums|sha384sums|sha512sums|b2sums|cksums|\
            md5sums_*|sha1sums_*|sha224sums_*|sha256sums_*|sha384sums_*|sha512sums_*|b2sums_*|cksums_*)
                sums["$key"]+="$value"$'\n' ;;
        esac
    done < "$srcinfo"
    for key in "${!sums[@]}"; do
        if [[ "$key" == *_* ]]; then
            arch_suffix="_${key#*_}"
        else
            arch_suffix="_"
        fi
        arch_sources=()
        if [[ -n "${sources_by_arch[$arch_suffix]:-}" ]]; then
            mapfile -t arch_sources <<< "${sources_by_arch[$arch_suffix]%$'\n'}"
        fi
        i=0
        while IFS= read -r value; do
            # makepkg itself writes SKIP for signature files (*.sig, *.sign, *.asc), judged by
            # the name before "::"; gpg verifies those, so they are not unpinned downloads.
            src="${arch_sources[i]:-}"
            fname="${src%%::*}"
            if [[ "$value" == SKIP && "$src" =~ ^([^:/]+::)?(https?|ftp):// \
                  && "$fname" != *.sig && "$fname" != *.sign && "$fname" != *.asc ]]; then
                err "[aur-integration] $key is SKIP for downloaded source $src; run aurgen aur so the checksum is pinned before deploying"
                return 1
            fi
            i=$((i + 1))
        done <<< "${sums[$key]%$'\n'}"
    done
    return 0
}

# Tracked *.install names at the clone root, except the current install= file.
# git ls-files '*.install' also lists nested paths; those stay.
# Usage: aur_stale_install_files <repo> <keep>
aur_stale_install_files() {
    local aur_repo_path="$1"
    local keep="$2"
    local tracked="" name=""
    if [[ ! -d "$aur_repo_path/.git" ]]; then
        return 0
    fi
    if ! tracked=$(git -C "$aur_repo_path" -c core.quotePath=off ls-files -- '*.install'); then
        err "[aur-integration] Failed to list install files in $aur_repo_path"
        return 1
    fi
    while IFS= read -r name || [[ -n "$name" ]]; do
        [[ -n "$name" ]] || continue
        [[ "$name" == */* ]] && continue
        if [[ -n "$keep" && "$name" == "$keep" ]]; then
            continue
        fi
        printf '%s\n' "$name"
    done <<< "$tracked"
}

# Usage: _aur_rev_range_count <repo> <ahead|behind>
_aur_rev_range_count() {
    local repo="$1" direction="$2" upstream range
    upstream=$(git -C "$repo" rev-parse --symbolic-full-name '@{u}' 2>/dev/null) || upstream=""
    upstream="${upstream:-origin/master}"
    if [[ "$direction" == behind ]]; then
        range="HEAD..${upstream}"
    else
        range="${upstream}..HEAD"
    fi
    git -C "$repo" rev-list --count "$range" 2>/dev/null
}

# Usage: aur_ahead_count <repo>
aur_ahead_count() {
    _aur_rev_range_count "$1" ahead
}

# Usage: aur_behind_count <repo>
aur_behind_count() {
    _aur_rev_range_count "$1" behind
}

# Return 1, naming the file, when an interrupted git command left index.lock in the clone.
# Usage: aur_clone_unlocked <aur_repo_path>
aur_clone_unlocked() {
    local aur_repo_path="$1" lock=""
    lock="$(git -C "$aur_repo_path" rev-parse --git-path index.lock 2>/dev/null)" || return 0
    [[ -n "$lock" ]] || return 0
    [[ "$lock" == /* ]] || lock="$aur_repo_path/$lock"
    if [[ -f "$lock" ]]; then
        err "[aur-integration] AUR clone $aur_repo_path has a leftover $lock from an interrupted git command; if no git process is running there, remove it and retry"
        return 1
    fi
}

# Fetch origin and return 1 when it has commits HEAD lacks (behind or diverged).
# Offline, the last fetched state is checked. A missing ref or unborn HEAD is not behind.
# Usage: aur_upstream_contained <aur_repo_path>
aur_upstream_contained() {
    local aur_repo_path="$1"
    local -a fetch_cmd=(git -C "$aur_repo_path")
    aur_apply_ssh_key fetch_cmd
    fetch_cmd+=(fetch -q origin)
    if ! "${fetch_cmd[@]}" 2>>"${AURGEN_ERROR_LOG:-/dev/null}"; then
        warn "[aur-integration] Cannot fetch origin in $aur_repo_path; checking against the last fetched state"
    fi
    local upstream='@{u}'
    if ! git -C "$aur_repo_path" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
        upstream=origin/master
    fi
    local ancestor_status=0
    git -C "$aur_repo_path" merge-base --is-ancestor "$upstream" HEAD 2>/dev/null || ancestor_status=$?
    (( ancestor_status != 1 ))
}

# Roll back copied or staged files after the initial PKGBUILD copy succeeds.
# Usage: _aur_rollback_clone_staging <repo> <stage_count> <stage_file>... <new_file>...
_aur_rollback_clone_staging() {
    local aur_repo_path="$1"
    local stage_count="$2"
    shift 2
    local -a staged_targets=("${@:1:stage_count}")
    shift "$stage_count"
    local -a newly_created=("$@")
    local f="" head_entry=""

    if git -C "$aur_repo_path" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        git -C "$aur_repo_path" reset -q --hard HEAD >/dev/null 2>&1 || true
        for f in "${newly_created[@]}"; do
            [[ -n "$f" && -e "$aur_repo_path/$f" ]] || continue
            if head_entry=$(git -C "$aur_repo_path" ls-tree --name-only HEAD -- "$f" 2>/dev/null) \
                && [[ -z "$head_entry" ]]; then
                rm -f -- "$aur_repo_path/$f"
            fi
        done
    else
        if (( ${#staged_targets[@]} > 0 )); then
            git -C "$aur_repo_path" rm -r -q --cached --ignore-unmatch -- "${staged_targets[@]}" >/dev/null 2>&1 || true
        fi
        for f in "${newly_created[@]}"; do
            [[ -n "$f" ]] && rm -f -- "$aur_repo_path/$f"
        done
    fi
}

deploy_to_aur() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    # shellcheck disable=SC2034 # read by aur-deploy.sh
    AUR_PUSH_SUCCEEDED="false"
    
    log "[aur-integration] Deploying to AUR repository: $aur_repo_path"

    : "${dry_run:=0}"
    if (( ! dry_run )) && ! aur_srcinfo_checksums_pinned "$SRCINFO"; then
        return 1
    fi

    # Generated scriptlets live beside PKGBUILD; hand-written ones stay in AUR_DIR.
    local install_file="" install_src=""
    install_file=$(pkgbuild_install_file "$PKGBUILD")
    if [[ -n "$install_file" ]]; then
        if [[ "$install_file" == */* || "$install_file" == .* ]]; then
            err "[aur-integration] install must name a file in $AUR_DIR: $install_file"
            return 1
        fi
        install_src="$(dirname "$PKGBUILD")/$install_file"
        if [[ ! -f "$install_src" ]]; then
            install_src="$AUR_DIR/$install_file"
        fi
        if [[ ! -f "$install_src" ]]; then
            err "[aur-integration] install file not found: $install_src"
            return 1
        fi
    fi

    # aur-deploy does not set PKGVER; the commit message version is
    # pkgver-pkgrel from .SRCINFO. A caller that already exported PKGVER (the
    # commit unit test) keeps that string when .SRCINFO has no pkgver line.
    # A dry-run aur-deploy previews the .SRCINFO a real run would regenerate; SRCINFO
    # itself is readonly, so mode_aur_deploy passes that file as AUR_PREVIEW_SRCINFO.
    local srcinfo_src="$SRCINFO"
    if (( ${dry_run:-0} )) && [[ -n "${AUR_PREVIEW_SRCINFO:-}" ]]; then
        srcinfo_src="$AUR_PREVIEW_SRCINFO"
    fi
    local src_epoch src_pkgver src_pkgrel version
    src_epoch=$(aur_srcinfo_field epoch "$srcinfo_src") || src_epoch=""
    src_pkgver=$(aur_srcinfo_field pkgver "$srcinfo_src") || src_pkgver=""
    src_pkgrel=$(aur_srcinfo_field pkgrel "$srcinfo_src") || src_pkgrel=""
    if [[ -z "$src_pkgver" ]]; then
        if [[ -n "${PKGVER:-}" ]]; then
            version="$PKGVER"
        else
            err "[aur-integration] .SRCINFO has no pkgver"
            return 1
        fi
    elif [[ -z "$src_pkgrel" ]]; then
        err "[aur-integration] .SRCINFO has no pkgrel"
        return 1
    else
        version="${src_epoch:+${src_epoch}:}${src_pkgver}-${src_pkgrel}"
    fi
    local commit_msg="${AUR_COMMIT_MESSAGE//\{version\}/$version}"
    # Quoted replacements: bash 5.2 patsub_replacement would expand a bare &.
    commit_msg="${commit_msg//\{pkgname\}/"$pkgname"}"
    commit_msg="${commit_msg//\{pkgver\}/"${src_pkgver:-$version}"}"
    commit_msg="${commit_msg//\{pkgrel\}/"$src_pkgrel"}"
    commit_msg="${commit_msg//\{epoch\}/"$src_epoch"}"

    # Preview only. The copy, commit, and push below must not run.
    : "${dry_run:=0}"
    if (( dry_run )); then
        local -a preview_names=(PKGBUILD .SRCINFO)
        if [[ -n "$install_file" ]]; then
            preview_names+=("$install_file")
        fi
        local preview_name preview_src preview_dest preview_status
        for preview_name in "${preview_names[@]}"; do
            case "$preview_name" in
                PKGBUILD) preview_src="$PKGBUILD" ;;
                .SRCINFO) preview_src="$srcinfo_src" ;;
                *) preview_src="$install_src" ;;
            esac
            preview_dest="$aur_repo_path/$preview_name"
            if [[ ! -f "$preview_dest" ]]; then
                printf 'new file: %s\n' "$preview_name"
                preview_dest=/dev/null
            fi
            preview_status=0
            diff -u --label "a/$preview_name" --label "b/$preview_name" -- "$preview_dest" "$preview_src" || preview_status=$?
            if (( preview_status > 1 )); then
                err "[aur-integration] diff failed for $preview_name"
                return 1
            fi
        done
        local stale_list="" stale=""
        if ! stale_list=$(aur_stale_install_files "$aur_repo_path" "$install_file"); then
            return 1
        fi
        while IFS= read -r stale || [[ -n "$stale" ]]; do
            [[ -n "$stale" ]] || continue
            printf 'deleted file: %s\n' "$stale"
        done <<< "$stale_list"
        printf '%s\n' "$commit_msg"
        return 0
    fi
    
    # Check if AUR repository exists
    if ! check_aur_repo_exists "$pkgname"; then
        warn "[aur-integration] AUR repository does not exist for $pkgname"
        if ! init_aur_repo "$pkgname"; then
            err "[aur-integration] Failed to initialize AUR repository"
            return 1
        fi
    else
        # A clone behind origin would commit on a stale base and the push would be
        # refused as non-fast-forward.
        if ! aur_upstream_contained "$aur_repo_path"; then
            # Rerun the generating mode, not aur-deploy alone: pkgrel is read from the updated clone.
            local rerun_mode=aur
            [[ "$pkgname" == *-git ]] && rerun_mode=git
            # With commits of its own the clone has diverged: a pull --ff-only would abort.
            local own_commits=0
            own_commits="$(aur_ahead_count "$aur_repo_path" 2>/dev/null)" || own_commits=0
            if [[ "$own_commits" =~ ^[1-9][0-9]*$ ]]; then
                err "[aur-integration] AUR clone $aur_repo_path has diverged from origin (it has unpushed commits and origin has commits it lacks); run aurgen aur-deploy --rollback, then git -C $(printf '%q' "$aur_repo_path") pull --ff-only and re-run aurgen $rerun_mode --deploy"
            else
                err "[aur-integration] AUR clone $aur_repo_path is behind origin; run git -C $(printf '%q' "$aur_repo_path") pull --ff-only, then re-run aurgen $rerun_mode --deploy"
            fi
            return 1
        fi
    fi

    aur_clone_unlocked "$aur_repo_path" || return 1

    local repo_status
    if ! repo_status=$(git -C "$aur_repo_path" status --porcelain --untracked-files=no) || [[ -n "$repo_status" ]]; then
        err "[aur-integration] AUR clone $aur_repo_path has uncommitted changes, or git status failed there; commit or discard the changes there before deploying"
        return 1
    fi

    # A commit with no identity fails after the copy and git add. Refuse first.
    # The override, when set, is the identity; otherwise the clone's config
    # (local, then global) supplies it. The write of the override stays below.
    local git_name git_email
    git_name="$AUR_GIT_USER_NAME"
    git_email="$AUR_GIT_USER_EMAIL"
    if [[ -z "$git_name" ]]; then
        git_name=$(git -C "$aur_repo_path" config user.name 2>/dev/null || true)
    fi
    if [[ -z "$git_email" ]]; then
        git_email=$(git -C "$aur_repo_path" config user.email 2>/dev/null || true)
    fi
    # git also takes the identity from its environment.
    git_name="${git_name:-${GIT_AUTHOR_NAME:-${GIT_COMMITTER_NAME:-}}}"
    git_email="${git_email:-${GIT_AUTHOR_EMAIL:-${GIT_COMMITTER_EMAIL:-${EMAIL:-}}}}"
    if [[ -z "$git_name" || -z "$git_email" ]]; then
        err "[aur-integration] No git identity for the AUR clone; set aur_integration.git_user_name/git_user_email or run: git -C $aur_repo_path config user.name ... && git -C $aur_repo_path config user.email ..."
        return 1
    fi

    local had_pre_pkgbuild=0 had_pre_srcinfo=0 had_pre_install=0
    [[ -e "$aur_repo_path/PKGBUILD" ]] && had_pre_pkgbuild=1
    [[ -e "$aur_repo_path/.SRCINFO" ]] && had_pre_srcinfo=1
    [[ -n "$install_file" && -e "$aur_repo_path/$install_file" ]] && had_pre_install=1
    local -a newly_created=()

    # Copy PKGBUILD and .SRCINFO. errexit is off: mode_aur_deploy calls this
    # function inside if, so a failed cp must be checked here.
    if ! cp "$PKGBUILD" "$aur_repo_path/"; then
        err "[aur-integration] Failed to copy PKGBUILD to $aur_repo_path"
        return 1
    fi
    (( ! had_pre_pkgbuild )) && newly_created+=(PKGBUILD)
    if ! cp "$SRCINFO" "$aur_repo_path/"; then
        _aur_rollback_clone_staging "$aur_repo_path" 0 "${newly_created[@]}"
        err "[aur-integration] Failed to copy .SRCINFO to $aur_repo_path"
        return 1
    fi
    (( ! had_pre_srcinfo )) && newly_created+=(.SRCINFO)
    if [[ -n "$install_file" ]]; then
        if ! cp "$install_src" "$aur_repo_path/"; then
            _aur_rollback_clone_staging "$aur_repo_path" 0 "${newly_created[@]}"
            err "[aur-integration] Failed to copy $install_file to $aur_repo_path"
            return 1
        fi
        (( ! had_pre_install )) && newly_created+=("$install_file")
    fi
    
    if [[ -n "$install_file" ]]; then
        log "[aur-integration] Copied PKGBUILD, .SRCINFO and ${install_file} to AUR repository"
    else
        log "[aur-integration] Copied PKGBUILD and .SRCINFO to AUR repository"
    fi

    # A renamed or dropped install= file stays in the clone until it is removed.
    local stale_list="" stale=""
    if ! stale_list=$(aur_stale_install_files "$aur_repo_path" "$install_file"); then
        _aur_rollback_clone_staging "$aur_repo_path" 0 "${newly_created[@]}"
        return 1
    fi
    while IFS= read -r stale || [[ -n "$stale" ]]; do
        [[ -n "$stale" ]] || continue
        if ! git -C "$aur_repo_path" rm -q -- "$stale"; then
            _aur_rollback_clone_staging "$aur_repo_path" 0 "${newly_created[@]}"
            err "[aur-integration] Failed to remove $stale from $aur_repo_path"
            return 1
        fi
    done <<< "$stale_list"
    
    # Configure git user if specified
    if [[ -n "$AUR_GIT_USER_NAME" ]]; then
        git -C "$aur_repo_path" config user.name "$AUR_GIT_USER_NAME"
    fi
    if [[ -n "$AUR_GIT_USER_EMAIL" ]]; then
        git -C "$aur_repo_path" config user.email "$AUR_GIT_USER_EMAIL"
    fi
    
    local -a stage_files=(PKGBUILD .SRCINFO)
    if [[ -n "$install_file" ]]; then
        stage_files+=("$install_file")
    fi
    if ! git -C "$aur_repo_path" add -- "${stage_files[@]}"; then
        _aur_rollback_clone_staging "$aur_repo_path" "${#stage_files[@]}" "${stage_files[@]}" "${newly_created[@]}"
        err "[aur-integration] Failed to stage files for commit"
        return 1
    fi
    
    if ! git -C "$aur_repo_path" commit -m "$commit_msg"; then
        # Exit 0 means the index is empty. Any other status is a real commit failure.
        if git -C "$aur_repo_path" diff --cached --quiet; then
            warn "[aur-integration] No changes to commit (files may be identical)"
            # A previous deploy may have committed and then failed to push.
            if [[ "$AUR_AUTO_PUSH" == "true" ]]; then
                local ahead="0"
                if ! ahead=$(aur_ahead_count "$aur_repo_path"); then
                    ahead=0
                    if git -C "$aur_repo_path" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
                        ahead=1
                    fi
                fi
                if [[ "$ahead" =~ ^[1-9][0-9]*$ ]]; then
                    log "[aur-integration] Pushing a previous unpushed commit"
                    if ! push_to_aur "$pkgname"; then
                        err "[aur-integration] Failed to push to AUR"
                        return 1
                    fi
                    # shellcheck disable=SC2034 # read by aur-deploy.sh
                    AUR_PUSH_SUCCEEDED="true"
                fi
            fi
            return 0
        fi
        _aur_rollback_clone_staging "$aur_repo_path" "${#stage_files[@]}" "${stage_files[@]}" "${newly_created[@]}"
        err "[aur-integration] Failed to commit changes"
        return 1
    fi
    
    log "[aur-integration] Committed changes to AUR repository"
    
    # Push to AUR if auto-push is enabled
    if [[ "$AUR_AUTO_PUSH" == "true" ]]; then
        if ! push_to_aur "$pkgname"; then
            err "[aur-integration] Failed to push to AUR"
            return 1
        fi
        # shellcheck disable=SC2034 # read by aur-deploy.sh
        AUR_PUSH_SUCCEEDED="true"
    else
        log "[aur-integration] Auto-push disabled. Run 'aurgen aur-push' to push changes"
    fi
    
    return 0
}

# Push changes to AUR
# Usage: push_to_aur <pkgname>
# Read-only checks a push must pass; aur-push --dry-run runs them too.
# Usage: aur_push_preconditions <pkgname>
aur_push_preconditions() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"

    local repo_status
    if ! repo_status=$(git -C "$aur_repo_path" status --porcelain --untracked-files=no) || [[ -n "$repo_status" ]]; then
        err "[aur-integration] AUR clone $aur_repo_path has uncommitted changes, or git status failed there; commit or discard the changes in $aur_repo_path, then re-run aurgen aur-push"
        return 1
    fi
    
    # The anonymous https URL clones but cannot push; the AUR takes pushes over SSH only.
    local push_url=""
    push_url="$(git -C "$aur_repo_path" remote get-url --push origin 2>/dev/null || true)"
    if [[ "$push_url" =~ ^https?://aur\.archlinux\.org/ ]]; then
        err "[aur-integration] AUR clone $aur_repo_path pushes to $push_url, which the AUR does not accept; run: git -C $aur_repo_path remote set-url --push origin ssh://aur@aur.archlinux.org/${pkgname}.git"
        return 1
    fi
}

push_to_aur() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"

    aur_push_preconditions "$pkgname" || return 1

    log "[aur-integration] Pushing to AUR: $pkgname"
    
    # Validate before push if configured
    if [[ "$AUR_VALIDATE_BEFORE_PUSH" == "true" ]]; then
        if ! validate_aur_repo "$pkgname"; then
            err "[aur-integration] AUR repository validation failed"
            return 1
        fi
    fi
    
    local -a git_cmd=(git -C "$aur_repo_path")
    aur_apply_ssh_key git_cmd
    # A fresh clone of an empty AUR repo is on init.defaultBranch; the AUR only takes master.
    git_cmd+=(push origin HEAD:master)

    # Push to AUR
    if ! "${git_cmd[@]}"; then
        err "[aur-integration] Failed to push to AUR"
        return 1
    fi
    
    log "[aur-integration] Successfully pushed to AUR: $pkgname"
    return 0
}

# Validate AUR repository
# Usage: validate_aur_repo <pkgname>
# Returns: 0 if valid, 1 if invalid
validate_aur_repo() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    log "[aur-integration] Validating AUR repository: $pkgname"
    
    # Check if required files exist
    if [[ ! -f "$aur_repo_path/PKGBUILD" ]]; then
        err "[aur-integration] PKGBUILD not found in AUR repository"
        return 1
    fi
    
    if [[ ! -f "$aur_repo_path/.SRCINFO" ]]; then
        err "[aur-integration] .SRCINFO not found in AUR repository"
        return 1
    fi
    
    # Validate PKGBUILD syntax
    if ! (cd "$aur_repo_path" && bash -n PKGBUILD); then
        err "[aur-integration] PKGBUILD syntax validation failed"
        return 1
    fi
    
    # printsrcinfo reads the PKGBUILD, so a hand-edited .SRCINFO can still parse.
    local printed
    printed=$(mktemp)
    if ! (cd "$aur_repo_path" && makepkg --printsrcinfo >| "$printed"); then
        rm -f "$printed"
        err "[aur-integration] .SRCINFO validation failed"
        return 1
    fi
    if ! cmp -s "$printed" "$aur_repo_path/.SRCINFO"; then
        rm -f "$printed"
        err "[aur-integration] .SRCINFO is out of date; run (cd $(printf '%q' "$aur_repo_path") && makepkg --printsrcinfo >| .SRCINFO)"
        return 1
    fi
    rm -f "$printed"

    local srcinfo_name=""
    srcinfo_name=$(aur_srcinfo_field pkgbase "$aur_repo_path/.SRCINFO" 2>/dev/null || true)
    if [[ -z "$srcinfo_name" ]]; then
        srcinfo_name=$(aur_srcinfo_field pkgname "$aur_repo_path/.SRCINFO" 2>/dev/null || true)
    fi
    if [[ -z "$srcinfo_name" ]]; then
        err "[aur-integration] .SRCINFO is missing pkgbase/pkgname"
        return 1
    fi

    if ! aur_srcinfo_checksums_pinned "$aur_repo_path/.SRCINFO"; then
        return 1
    fi

    local install_file=""
    install_file=$(pkgbuild_install_file "$aur_repo_path/PKGBUILD")
    if [[ -n "$install_file" ]]; then
        if [[ "$install_file" == */* || "$install_file" == .* ]]; then
            err "[aur-integration] Invalid install= path in PKGBUILD: $install_file"
            return 1
        fi
        if [[ ! -f "$aur_repo_path/$install_file" ]]; then
            err "[aur-integration] install= file not found in AUR repository: $install_file"
            return 1
        fi
        if ! (cd "$aur_repo_path" && bash -n -- "$install_file"); then
            err "[aur-integration] install= script syntax validation failed: $install_file"
            return 1
        fi
    fi

    # namcap's errors (W: lines stay warnings) stop the push, as in local and test mode.
    if command -v namcap >/dev/null 2>&1 && ! namcap_report "$aur_repo_path/PKGBUILD"; then
        err "[aur-integration] namcap reported errors in $aur_repo_path/PKGBUILD"
        return 1
    fi

    log "[aur-integration] AUR repository validation passed"
    return 0
}

# Empty output means unpublished; failure means the RPC could not be used.
aur_rpc_version() {
    local pkgname="$1"
    local body count version
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
    body=$(curl -fsS --max-time 10 "https://aur.archlinux.org/rpc/v5/info/${pkgname}" 2>/dev/null) || return 1
    count=$(jq -r '.resultcount' <<< "$body" 2>/dev/null) || return 1
    [[ "$count" =~ ^[0-9]+$ ]] || return 1
    [[ "$count" != 0 ]] || return 0
    version=$(jq -er '.results[0].Version | select(type == "string")' <<< "$body" 2>/dev/null) || return 1
    [[ "$version" =~ ^.+-[0-9]+(\.[0-9]+)?$ ]] || return 1
    printf '%s\n' "$version"
}

# Print the AUR RPC version line. A failed fetch must not fail the caller.
# A numeric OutOfDate and a JSON null Maintainer are noted on that line, and
# set AUR_ST_OUT_OF_DATE (the flag date, else empty) and AUR_ST_ORPHANED
# (yes, no, or empty when unknown) for --json.
# Usage: aur_web_version <pkgname> [just-pushed]
aur_web_version() {
    local pkgname="$1"
    local just_pushed="${2:-}"
    AUR_ST_OUT_OF_DATE=""
    AUR_ST_ORPHANED=""
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 0
    fi
    local web_body web_count web_ver web_note out_of_date flagged_on orphaned
    web_body=$(mktemp) || { echo "AUR web: unavailable"; return 0; }
    if curl -fsS --max-time 10 "https://aur.archlinux.org/rpc/v5/info/${pkgname}" >| "$web_body" 2>/dev/null; then
        web_count=$(jq -r '.resultcount' "$web_body" 2>/dev/null) || web_count=""
        if [[ "$web_count" == "0" ]]; then
            if [[ "$just_pushed" == "just-pushed" ]]; then
                echo "AUR web: not listed yet (the AUR index can lag a few minutes)"
            else
                echo "AUR web: not published"
            fi
        elif [[ "$web_count" =~ ^[0-9]+$ ]]; then
            web_ver=$(jq -r '.results[0].Version' "$web_body" 2>/dev/null) || web_ver=""
            if [[ -n "$web_ver" && "$web_ver" != "null" ]]; then
                web_note=""
                # || true: errtrace would otherwise turn a bad jq or date into a fatal exit.
                out_of_date=$(jq -r '.results[0].OutOfDate | select(type == "number")' "$web_body" 2>/dev/null || true)
                if [[ "$out_of_date" =~ ^[0-9]+$ ]]; then
                    # LC_ALL=C: a Turkish locale must not change the calendar date.
                    flagged_on=$(LC_ALL=C date -u -d "@$out_of_date" +%F 2>/dev/null || true)
                    if [[ -n "$flagged_on" ]]; then
                        web_note+=" (flagged out of date since ${flagged_on})"
                        AUR_ST_OUT_OF_DATE="$flagged_on"
                    fi
                fi
                # has(): a missing Maintainer is not an orphan; only JSON null is.
                orphaned=$(jq -r '.results[0] | if has("Maintainer") and (.Maintainer == null) then "yes" else "no" end' "$web_body" 2>/dev/null || true)
                if [[ "$orphaned" == "yes" ]]; then
                    web_note+=" (orphaned)"
                fi
                [[ "$orphaned" == yes || "$orphaned" == no ]] && AUR_ST_ORPHANED="$orphaned"
                echo "AUR web: ${web_ver}${web_note}"
            else
                echo "AUR web: unavailable"
            fi
        else
            echo "AUR web: unavailable"
        fi
    else
        echo "AUR web: unavailable"
    fi
    rm -f "$web_body"
}

# Fill AUR_ST_AUR_WEB in this shell: a $(...) capture would drop the
# AUR_ST_OUT_OF_DATE and AUR_ST_ORPHANED that aur_web_version sets.
_aur_st_fetch_web() {
    local web_out
    AUR_ST_AUR_WEB=""
    web_out=$(mktemp) || return 0
    aur_web_version "$1" >| "$web_out"
    AUR_ST_AUR_WEB="$(sed 's/^AUR web: //' "$web_out")"
    rm -f "$web_out"
}

# Probe GitHub release tarball and detached signature (.sig/.asc) via asset_exists.
# Never fails aur-status or alters exit codes: offline or failing probes yield "unknown".
_aur_st_fetch_github() {
    local pkgname="$1"
    AUR_ST_GH_RELEASE=""
    AUR_ST_GH_TAG=""
    AUR_ST_GH_TARBALL=""
    AUR_ST_GH_SIGNATURE=""

    local source_kind="${PKG_SOURCE:-release}"
    : "${source_kind:=release}"
    [[ "$source_kind" == "release" ]] || return 0

    [[ -n "${SRCINFO:-}" && -f "$SRCINFO" ]] || return 0
    # A -git package builds from the repository; it never has release assets.
    local pkgbase=""
    pkgbase=$(aur_srcinfo_field pkgbase "$SRCINFO" 2>/dev/null) || pkgbase=""
    if [[ "$pkgbase" == *-git ]] || grep -Eq '^[[:space:]]*source(_[A-Za-z0-9_]+)?[[:space:]]*=.*git\+' "$SRCINFO" 2>/dev/null; then
        return 0
    fi
    local pkgver=""
    pkgver=$(aur_srcinfo_field pkgver "$SRCINFO" 2>/dev/null) || pkgver=""
    [[ -n "$pkgver" ]] || return 0

    local proj_root="${PROJECT_ROOT:-}"
    if [[ -z "$proj_root" && -n "${SRCINFO:-}" ]]; then
        proj_root=$(git -C "$(dirname "$SRCINFO")" rev-parse --show-toplevel 2>/dev/null || true)
    fi
    if [[ -z "$proj_root" ]]; then
        proj_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    fi
    [[ -n "$proj_root" ]] || return 0

    local origin_url="" gh_owner="" gh_repo=""
    origin_url=$(git -C "$proj_root" config --get remote.origin.url 2>/dev/null || true)
    origin_url="${origin_url%/}"
    if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        gh_owner="${GH_USER:-${BASH_REMATCH[1]}}"
        gh_repo="${BASH_REMATCH[2]%.git}"
    fi
    [[ -n "$gh_owner" && -n "$gh_repo" ]] || return 0

    # aur mode writes the release tag into the source URL; probe that one.
    local tag="" src_tag=""
    src_tag=$(sed -n 's|.*/releases/download/\([^/]*\)/.*|\1|p' "$SRCINFO" 2>/dev/null | head -n 1)
    if [[ -n "$src_tag" ]]; then
        tag="$src_tag"
    elif git -C "$proj_root" show-ref --verify --quiet "refs/tags/${pkgver}" 2>/dev/null && \
        ! git -C "$proj_root" show-ref --verify --quiet "refs/tags/v${pkgver}" 2>/dev/null; then
        tag="${pkgver}"
    else
        tag="v${pkgver}"
    fi

    set_signature_ext
    local sig_ext="${SIGNATURE_EXT:-.sig}"
    if (( ${ascii_armor:-0} == 0 )); then
        if grep -Eq '^[[:space:]]*source(_[a-zA-Z0-9_]+)?[[:space:]]*=.*\.asc$' "$SRCINFO" 2>/dev/null; then
            sig_ext=".asc"
        elif grep -Eq '^[[:space:]]*source(_[a-zA-Z0-9_]+)?[[:space:]]*=.*\.sig$' "$SRCINFO" 2>/dev/null; then
            sig_ext=".sig"
        fi
    fi

    local tarball="${pkgname}-${pkgver}.tar.gz"
    local tarball_url="https://github.com/${gh_owner}/${gh_repo}/releases/download/${tag}/${tarball}"
    local sig_name="${tarball}${sig_ext}"
    local sig_url="${tarball_url}${sig_ext}"

    local AURGEN_LOG="${AURGEN_LOG:-/dev/null}"
    local AURGEN_ERROR_LOG="${AURGEN_ERROR_LOG:-/dev/null}"
    local tarball_rc=0 sig_rc=0
    asset_exists "$tarball_url" "$tag" "$tarball" || tarball_rc=$?
    case "$tarball_rc" in
        0) AUR_ST_GH_TARBALL="present" ;;
        1) AUR_ST_GH_TARBALL="missing" ;;
        *) AUR_ST_GH_TARBALL="unknown" ;;
    esac
    asset_exists "$sig_url" "$tag" "$sig_name" || sig_rc=$?
    case "$sig_rc" in
        0) AUR_ST_GH_SIGNATURE="present" ;;
        1) AUR_ST_GH_SIGNATURE="missing" ;;
        *) AUR_ST_GH_SIGNATURE="unknown" ;;
    esac

    AUR_ST_GH_TAG="$tag"
    AUR_ST_GH_RELEASE="${tag} (tarball: ${AUR_ST_GH_TARBALL}, signature: ${AUR_ST_GH_SIGNATURE})"
}

_aur_print_file_diff() {
    local label="$1" left="$2" right="$3"
    if [[ ! -f "$left" && ! -f "$right" ]]; then
        return 0
    elif [[ ! -f "$left" ]]; then
        echo "Diff ($label): missing in AUR clone ($left)"
        return 0
    elif [[ ! -f "$right" ]]; then
        echo "Diff ($label): missing generated artifact ($right)"
        return 0
    elif cmp -s "$left" "$right"; then
        echo "Diff ($label): identical"
        return 0
    fi
    diff -u "$left" "$right" || true
}

_aur_inspect_status() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    AUR_ST_REPO_EXISTS=0
    AUR_ST_REPO_PATH="$aur_repo_path"
    AUR_ST_GIT_STATUS=""
    AUR_ST_REMOTE_STATUS=""
    AUR_ST_AHEAD_COUNT=""
    AUR_ST_BEHIND_COUNT=""
    AUR_ST_AUR_VER=""
    AUR_ST_GEN_VER=""
    AUR_ST_VERDICT=""
    AUR_ST_RELEASE_PENDING=""
    AUR_ST_INSTALL_FILE=""
    AUR_ST_INSTALL_SRC=""
    AUR_ST_AUR_WEB=""
    AUR_ST_OUT_OF_DATE=""
    AUR_ST_ORPHANED=""
    AUR_ST_GH_RELEASE=""
    AUR_ST_GH_TAG=""
    AUR_ST_GH_TARBALL=""
    AUR_ST_GH_SIGNATURE=""
    AUR_ST_RC=0

    if ! check_aur_repo_exists "$pkgname"; then
        AUR_ST_RC=1
        _aur_st_fetch_web "$pkgname"
        _aur_st_fetch_github "$pkgname"
        return 1
    fi

    AUR_ST_REPO_EXISTS=1
    AUR_ST_GIT_STATUS=$(git -C "$aur_repo_path" status --porcelain 2>/dev/null || echo "error")
    AUR_ST_REMOTE_STATUS=$(git -C "$aur_repo_path" status --porcelain --branch 2>/dev/null | grep '^##' || echo "error")

    if [[ -n "${SRCINFO:-}" && -f "$SRCINFO" && -f "$aur_repo_path/.SRCINFO" ]]; then
        local gen_epoch gen_pkgver gen_pkgrel aur_epoch aur_pkgver aur_pkgrel gen_ver aur_ver verdict
        gen_epoch=$(aur_srcinfo_field epoch "$SRCINFO") || gen_epoch=""
        gen_pkgver=$(aur_srcinfo_field pkgver "$SRCINFO") || gen_pkgver=""
        gen_pkgrel=$(aur_srcinfo_field pkgrel "$SRCINFO") || gen_pkgrel=""
        aur_epoch=$(aur_srcinfo_field epoch "$aur_repo_path/.SRCINFO") || aur_epoch=""
        aur_pkgver=$(aur_srcinfo_field pkgver "$aur_repo_path/.SRCINFO") || aur_pkgver=""
        aur_pkgrel=$(aur_srcinfo_field pkgrel "$aur_repo_path/.SRCINFO") || aur_pkgrel=""
        if [[ -n "$gen_pkgver" && -n "$gen_pkgrel" && -n "$aur_pkgver" && -n "$aur_pkgrel" ]]; then
            gen_ver="${gen_epoch:+${gen_epoch}:}${gen_pkgver}-${gen_pkgrel}"
            aur_ver="${aur_epoch:+${aur_epoch}:}${aur_pkgver}-${aur_pkgrel}"
            if [[ "$aur_ver" == "$gen_ver" ]]; then
                verdict="up to date"
                if ! cmp -s "$SRCINFO" "$aur_repo_path/.SRCINFO"; then
                    verdict="deploy pending; only metadata differs"
                    AUR_ST_RC=3
                else
                    local install_file="" install_src=""
                    install_file=$(pkgbuild_install_file "${PKGBUILD:-}")
                    if [[ -n "$install_file" ]]; then
                        install_src="$(dirname "$PKGBUILD")/$install_file"
                        if [[ ! -f "$install_src" ]]; then
                            install_src="$AUR_DIR/$install_file"
                        fi
                        AUR_ST_INSTALL_FILE="$install_file"
                        AUR_ST_INSTALL_SRC="$install_src"
                        if ! cmp -s "$install_src" "$aur_repo_path/$install_file"; then
                            verdict="deploy pending; install scriptlet differs or is missing"
                            AUR_ST_RC=3
                        fi
                    fi
                    if [[ "$verdict" == "up to date" ]]; then
                        if [[ -n "${PKGBUILD:-}" && -f "$PKGBUILD" ]]; then
                            if ! cmp -s "$PKGBUILD" "$aur_repo_path/PKGBUILD"; then
                                verdict="deploy pending; PKGBUILD differs"
                                AUR_ST_RC=3
                            fi
                        fi
                    fi
                fi
            else
                verdict="deploy pending"
                AUR_ST_RC=3
            fi
            AUR_ST_AUR_VER="$aur_ver"
            AUR_ST_GEN_VER="$gen_ver"
            AUR_ST_VERDICT="$verdict"
        fi
        if [[ -n "$gen_pkgver" ]]; then
            local pkgbase=""
            pkgbase=$(aur_srcinfo_field pkgbase "$SRCINFO" 2>/dev/null) || pkgbase=""
            # A signed-tag source is git+ too, but it packages a version tag; only -git is skipped.
            if [[ "$pkgbase" != *-git ]]; then
                local proj_root="${PROJECT_ROOT:-}"
                if [[ -z "$proj_root" ]]; then
                    proj_root=$(git -C "$(dirname "$SRCINFO")" rev-parse --show-toplevel 2>/dev/null || true)
                fi
                if [[ -n "$proj_root" ]] && command -v vercmp >/dev/null 2>&1; then
                    if ! declare -F detect_project_version >/dev/null 2>&1; then
                        # shellcheck source=project-metadata.sh
                        # shellcheck disable=SC1091
                        . "$LIB_INSTALL_DIR/project-metadata.sh"
                    fi
                    local ver_src="" tag_ver=""
                    IFS=$'\t' read -r ver_src tag_ver < <(detect_project_version "$proj_root")
                    # A tagless project takes pkgver from VERSION, so a bumped VERSION is unpackaged too.
                    if [[ ( "$ver_src" == "tag" || "$ver_src" == "version-file" ) && -n "$tag_ver" ]] && (( $(vercmp "$tag_ver" "$gen_pkgver") > 0 )); then
                        AUR_ST_RELEASE_PENDING="$tag_ver"
                        AUR_ST_RC=3
                    fi
                fi
            fi
        fi
    fi

    # Commits that are not on the upstream still need a push. Same rule as aur-push:
    # @{u}, else origin/master; a first commit to an empty AUR repo has neither.
    local ahead_count=""
    if ahead_count=$(aur_ahead_count "$aur_repo_path"); then
        AUR_ST_AHEAD_COUNT="$ahead_count"
        if [[ "$ahead_count" =~ ^[0-9]+$ ]] && (( ahead_count > 0 )); then
            AUR_ST_RC=3
        fi
    elif git -C "$aur_repo_path" remote get-url origin >/dev/null 2>&1 \
        && git -C "$aur_repo_path" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        AUR_ST_RC=3
    fi

    local behind_count=""
    if behind_count=$(aur_behind_count "$aur_repo_path"); then
        AUR_ST_BEHIND_COUNT="$behind_count"
    fi

    _aur_st_fetch_web "$pkgname"
    _aur_st_fetch_github "$pkgname"
    return "$AUR_ST_RC"
}

_aur_print_status_json() {
    local pkgname="$1"
    local include_config="${2:-0}"
    local pending="false" repo_exists="false" git_clean="null"
    (( AUR_ST_RC == 3 )) && pending="true"
    (( AUR_ST_REPO_EXISTS == 1 )) && repo_exists="true"

    local modified_json="[]"
    if (( AUR_ST_REPO_EXISTS == 1 )); then
        if [[ "$AUR_ST_GIT_STATUS" == "error" ]]; then
            git_clean="null"
        elif [[ -z "$AUR_ST_GIT_STATUS" ]]; then
            git_clean="true"
        else
            git_clean="false"
            local line items=""
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                items+="${items:+, }\"$(_aurgen_json_escape "$line")\""
            done <<< "$AUR_ST_GIT_STATUS"
            modified_json="[$items]"
        fi
    fi

    local remote_json="null" ahead_json="null" behind_json="null" aur_ver_json="null" gen_ver_json="null" verdict_json="null" release_pending_json="null" aur_web_json="null"
    if [[ -n "$AUR_ST_REMOTE_STATUS" && "$AUR_ST_REMOTE_STATUS" != "error" ]]; then
        remote_json="\"$(_aurgen_json_escape "$AUR_ST_REMOTE_STATUS")\""
    fi
    if [[ "$AUR_ST_AHEAD_COUNT" =~ ^[0-9]+$ ]]; then
        ahead_json="$AUR_ST_AHEAD_COUNT"
    fi
    if [[ "$AUR_ST_BEHIND_COUNT" =~ ^[0-9]+$ ]]; then
        behind_json="$AUR_ST_BEHIND_COUNT"
    fi
    [[ -n "$AUR_ST_AUR_VER" ]] && aur_ver_json="\"$(_aurgen_json_escape "$AUR_ST_AUR_VER")\""
    [[ -n "$AUR_ST_GEN_VER" ]] && gen_ver_json="\"$(_aurgen_json_escape "$AUR_ST_GEN_VER")\""
    [[ -n "$AUR_ST_VERDICT" ]] && verdict_json="\"$(_aurgen_json_escape "$AUR_ST_VERDICT")\""
    [[ -n "${AUR_ST_RELEASE_PENDING:-}" ]] && release_pending_json="\"$(_aurgen_json_escape "$AUR_ST_RELEASE_PENDING")\""
    [[ -n "$AUR_ST_AUR_WEB" ]] && aur_web_json="\"$(_aurgen_json_escape "$AUR_ST_AUR_WEB")\""
    local out_of_date_json="null" orphaned_json="null" github_release_json="null"
    [[ "${AUR_ST_OUT_OF_DATE:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && out_of_date_json="\"$AUR_ST_OUT_OF_DATE\""
    [[ "${AUR_ST_ORPHANED:-}" == yes ]] && orphaned_json="true"
    [[ "${AUR_ST_ORPHANED:-}" == no ]] && orphaned_json="false"
    if [[ -n "${AUR_ST_GH_TAG:-}" ]]; then
        github_release_json=$(printf '{"tag": "%s", "tarball": "%s", "signature": "%s"}' \
            "$(_aurgen_json_escape "$AUR_ST_GH_TAG")" \
            "$(_aurgen_json_escape "$AUR_ST_GH_TARBALL")" \
            "$(_aurgen_json_escape "$AUR_ST_GH_SIGNATURE")")
    fi

    printf '{'
    printf '"package": "%s", ' "$(_aurgen_json_escape "$pkgname")"
    printf '"repo_exists": %s, ' "$repo_exists"
    printf '"repo_path": "%s", ' "$(_aurgen_json_escape "$AUR_ST_REPO_PATH")"
    printf '"git_clean": %s, ' "$git_clean"
    printf '"modified_files": %s, ' "$modified_json"
    printf '"remote_status": %s, ' "$remote_json"
    printf '"ahead_count": %s, ' "$ahead_json"
    printf '"behind_count": %s, ' "$behind_json"
    printf '"aur_version": %s, ' "$aur_ver_json"
    printf '"generated_version": %s, ' "$gen_ver_json"
    printf '"verdict": %s, ' "$verdict_json"
    printf '"release_pending": %s, ' "$release_pending_json"
    printf '"pending": %s, ' "$pending"
    printf '"aur_web": %s, ' "$aur_web_json"
    printf '"aur_out_of_date": %s, ' "$out_of_date_json"
    printf '"aur_orphaned": %s, ' "$orphaned_json"
    printf '"github_release": %s' "$github_release_json"
    if (( include_config )); then
        local auto_push="false" validate_push="false"
        [[ "${AUR_AUTO_PUSH:-}" == "true" ]] && auto_push="true"
        [[ "${AUR_VALIDATE_BEFORE_PUSH:-}" == "true" ]] && validate_push="true"
        printf ', "aur_integration": {'
        printf '"aur_repo_dir": "%s", ' "$(_aurgen_json_escape "${AUR_REPO_DIR:-}")"
        printf '"auto_push": %s, ' "$auto_push"
        printf '"validate_before_push": %s, ' "$validate_push"
        printf '"git_user_name": "%s", ' "$(_aurgen_json_escape "${AUR_GIT_USER_NAME:-}")"
        printf '"git_user_email": "%s", ' "$(_aurgen_json_escape "${AUR_GIT_USER_EMAIL:-}")"
        printf '"ssh_key": "%s"' "$(_aurgen_json_escape "${AUR_SSH_KEY:-}")"
        printf '}'
    fi
    printf '}\n'
}

# Get AUR repository status.
# Returns 1 when the clone is missing, 3 when a deploy or push is pending, and 0 otherwise.
# Usage: get_aur_status <pkgname>
get_aur_status() {
    local pkgname="$1"
    local status=0
    _aur_inspect_status "$pkgname" || status=$?

    if (( ${AURGEN_JSON:-0} )); then
        _aur_print_status_json "$pkgname" 0
        return "$status"
    fi

    echo "=== AUR Repository Status: $pkgname ==="
    if (( AUR_ST_REPO_EXISTS == 0 )); then
        echo "Status: Repository does not exist"
        echo "Path: $AUR_ST_REPO_PATH"
        if [[ -n "$AUR_ST_AUR_WEB" ]]; then
            echo "AUR web: $AUR_ST_AUR_WEB"
        fi
        if [[ -n "$AUR_ST_GH_RELEASE" ]]; then
            echo "GitHub release: $AUR_ST_GH_RELEASE"
        fi
        return 1
    fi

    echo "Status: Repository exists"
    echo "Path: $AUR_ST_REPO_PATH"

    if [[ "$AUR_ST_GIT_STATUS" == "error" ]]; then
        echo "Git Status: Error accessing repository"
    elif [[ -z "$AUR_ST_GIT_STATUS" ]]; then
        echo "Git Status: Clean working directory"
    else
        echo "Git Status: Modified files:"
        printf '%s\n' "$AUR_ST_GIT_STATUS" | sed 's/^/  /'
    fi

    if [[ "$AUR_ST_REMOTE_STATUS" != "error" ]]; then
        echo "Remote Status: $AUR_ST_REMOTE_STATUS"
    fi
    if [[ "$AUR_ST_BEHIND_COUNT" =~ ^[0-9]+$ ]] && (( AUR_ST_BEHIND_COUNT > 0 )); then
        if [[ "$AUR_ST_AHEAD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            echo "Behind: ${AUR_ST_BEHIND_COUNT} commit(s) behind upstream and ${AUR_ST_AHEAD_COUNT} unpushed: the clone has diverged; run aurgen aur-deploy --rollback, then git -C $(printf '%q' "$AUR_ST_REPO_PATH") pull --ff-only"
        else
            echo "Behind: ${AUR_ST_BEHIND_COUNT} commit(s) behind upstream; run git -C $(printf '%q' "$AUR_ST_REPO_PATH") pull --ff-only"
        fi
    fi

    if [[ -n "$AUR_ST_AUR_VER" && -n "$AUR_ST_GEN_VER" ]]; then
        echo "Version: AUR ${AUR_ST_AUR_VER}, generated ${AUR_ST_GEN_VER} (${AUR_ST_VERDICT})"
    fi

    if [[ -n "${AUR_ST_RELEASE_PENDING:-}" ]]; then
        echo "Release: ${AUR_ST_RELEASE_PENDING} is not packaged yet; run aurgen aur"
    fi

    if [[ -n "$AUR_ST_AUR_WEB" ]]; then
        echo "AUR web: $AUR_ST_AUR_WEB"
    fi

    if [[ -n "$AUR_ST_GH_RELEASE" ]]; then
        echo "GitHub release: $AUR_ST_GH_RELEASE"
    fi

    if (( ${AURGEN_STATUS_DIFF:-0} )); then
        echo ""
        echo "=== AUR Clone Diff ==="
        if [[ -n "${PKGBUILD:-}" ]]; then
            _aur_print_file_diff "PKGBUILD" "$AUR_ST_REPO_PATH/PKGBUILD" "$PKGBUILD"
        fi
        if [[ -n "${SRCINFO:-}" ]]; then
            _aur_print_file_diff ".SRCINFO" "$AUR_ST_REPO_PATH/.SRCINFO" "$SRCINFO"
        fi
        local diff_install_file="$AUR_ST_INSTALL_FILE" diff_install_src="$AUR_ST_INSTALL_SRC"
        if [[ -z "$diff_install_file" ]]; then
            diff_install_file=$(pkgbuild_install_file "${PKGBUILD:-}")
            [[ -n "$diff_install_file" ]] || diff_install_file=$(pkgbuild_install_file "$AUR_ST_REPO_PATH/PKGBUILD")
            if [[ -n "$diff_install_file" && -n "${PKGBUILD:-}" ]]; then
                diff_install_src="$(dirname "$PKGBUILD")/$diff_install_file"
                [[ -f "$diff_install_src" ]] || diff_install_src="$AUR_DIR/$diff_install_file"
            fi
        fi
        if [[ -n "$diff_install_file" ]]; then
            _aur_print_file_diff "$diff_install_file" "$AUR_ST_REPO_PATH/$diff_install_file" "$diff_install_src"
        fi
        if [[ -n "$AUR_ST_GIT_STATUS" && "$AUR_ST_GIT_STATUS" != "error" ]]; then
            git -C "$AUR_ST_REPO_PATH" diff || true
        fi
    fi

    return "$status"
}

# Safely roll back unpushed local commits and dirty working tree state in the AUR clone.
# Usage: rollback_aur_repo <pkgname>
rollback_aur_repo() {
    local pkgname="$1"
    if [[ -z "$pkgname" || "$pkgname" == */* || "$pkgname" == .* ]]; then
        err "[aur-integration] Invalid AUR package name: '$pkgname'"
        return 1
    fi
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    if [[ ! -d "$aur_repo_path/.git" ]]; then
        err "[aur-integration] AUR repository does not exist: $aur_repo_path"
        return 1
    fi
    aur_clone_unlocked "$aur_repo_path" || return 1

    local upstream="" upstream_short=""
    if ! upstream=$(git -C "$aur_repo_path" rev-parse --symbolic-full-name '@{u}' 2>/dev/null) \
        || [[ -z "$upstream" ]] \
        || ! git -C "$aur_repo_path" rev-parse --verify --quiet "${upstream}^{commit}" >/dev/null 2>&1; then
        err "[aur-integration] No valid upstream tracking branch (@{u}) in $aur_repo_path; refusing history rollback to protect pushed commits"
        return 1
    fi
    upstream_short=$(git -C "$aur_repo_path" rev-parse --abbrev-ref '@{u}' 2>/dev/null) || upstream_short="$upstream"

    local ahead_count="" git_status=""
    if ! ahead_count=$(aur_ahead_count "$aur_repo_path") || [[ ! "$ahead_count" =~ ^[0-9]+$ ]]; then
        err "[aur-integration] Failed to determine unpushed commit count against $upstream_short in $aur_repo_path"
        return 1
    fi
    if ! git_status=$(git -C "$aur_repo_path" status --porcelain 2>/dev/null); then
        err "[aur-integration] Failed to inspect working tree status in $aur_repo_path"
        return 1
    fi

    if (( ahead_count == 0 )) && [[ -z "$git_status" ]]; then
        log "[aur-integration] AUR repository $aur_repo_path is clean and up to date with $upstream_short; nothing to roll back"
        return 0
    fi

    : "${dry_run:=0}"
    if (( dry_run )); then
        if (( ahead_count > 0 )); then
            log "[aur-integration] (dry run) Would reset $ahead_count unpushed commit(s) to $upstream_short in $aur_repo_path"
        fi
        if [[ -n "$git_status" ]]; then
            log "[aur-integration] (dry run) Would discard uncommitted changes and untracked files in $aur_repo_path:"
            printf '%s\n' "$git_status" | sed 's/^/  /'
        fi
        return 0
    fi

    if (( ahead_count > 0 )); then
        log "[aur-integration] Resetting $ahead_count unpushed commit(s) to $upstream_short in $aur_repo_path"
        if ! git -C "$aur_repo_path" reset --hard "$upstream" >>"$AURGEN_ERROR_LOG" 2>&1; then
            err "[aur-integration] Failed to reset $aur_repo_path to $upstream_short"
            return 1
        fi
    elif [[ -n "$git_status" ]]; then
        log "[aur-integration] Discarding uncommitted working tree changes in $aur_repo_path"
        if ! git -C "$aur_repo_path" reset --hard HEAD >>"$AURGEN_ERROR_LOG" 2>&1; then
            err "[aur-integration] Failed to reset working tree in $aur_repo_path"
            return 1
        fi
    fi

    if [[ -n "$git_status" ]]; then
        if ! git -C "$aur_repo_path" clean -fd >>"$AURGEN_ERROR_LOG" 2>&1; then
            err "[aur-integration] Failed to remove untracked files in $aur_repo_path"
            return 1
        fi
    fi

    log "[aur-integration] Rolled back local AUR clone state: $aur_repo_path"
    return 0
}
