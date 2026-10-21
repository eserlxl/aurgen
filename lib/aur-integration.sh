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
AUR_BACKUP_EXISTING=""
AUR_VALIDATE_BEFORE_PUSH=""
# True only after push_to_aur succeeds; aur-deploy must not claim a push otherwise.
AUR_PUSH_SUCCEEDED="false"

# Load AUR integration configuration from aurgen.install.yaml
# Usage: load_aur_integration_config
load_aur_integration_config() {
    local aur_config_file="$AUR_DIR/aurgen.install.yaml"
    
    # Initialize with defaults
    # XDG data, not cache: the clones hold commits waiting to be pushed, and every user can write it.
    AUR_REPO_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/aurgen/aur"
    AUR_AUTO_PUSH="true"
    AUR_COMMIT_MESSAGE="Update to version {version}"
    AUR_GIT_USER_NAME=""
    AUR_GIT_USER_EMAIL=""
    AUR_SSH_KEY=""
    AUR_BACKUP_EXISTING="true"
    AUR_VALIDATE_BEFORE_PUSH="true"
    
    # Try to load from aur directory
    if [[ -f "$aur_config_file" && -r "$aur_config_file" ]]; then
        debug "[aur-integration] Loading AUR configuration from $aur_config_file"
        parse_aur_integration_config "$aur_config_file"
    else
        warn "[aur-integration] AUR configuration file not found, using defaults"
    fi
}

# Parse AUR integration configuration from YAML
# Usage: parse_aur_integration_config <config_file>
parse_aur_integration_config() {
    local config_file="$1"
    local in_aur_section=0
    local value=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check for aur_integration section
        if [[ "$line" =~ ^[[:space:]]*aur_integration:[[:space:]]*$ ]]; then
            in_aur_section=1
            continue
        fi
        
        # Exit aur_integration section when we hit another top-level section
        if (( in_aur_section )) && [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$ ]]; then
            in_aur_section=0
            continue
        fi
        
        # Parse aur_integration settings
        if (( in_aur_section )) && [[ "$line" =~ ^[[:space:]]*([a-z_]+):[[:space:]]*(.+)$ ]]; then
            value="$(_yaml_trim "$(_yaml_unquote "$(_yaml_trim "${BASH_REMATCH[2]}")")")"
            case "${BASH_REMATCH[1]}" in
                aur_repo_dir) AUR_REPO_DIR="${value/#\~/$HOME}" ;;
                auto_push) AUR_AUTO_PUSH="$value" ;;
                commit_message) AUR_COMMIT_MESSAGE="$value" ;;
                git_user_name) AUR_GIT_USER_NAME="$value" ;;
                git_user_email) AUR_GIT_USER_EMAIL="$value" ;;
                ssh_key) AUR_SSH_KEY="$value" ;;
                backup_existing) AUR_BACKUP_EXISTING="$value" ;;
                validate_before_push) AUR_VALIDATE_BEFORE_PUSH="$value" ;;
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

# Append core.sshCommand only when the configured key is a real file.
# A value that is not a path is still one quoted argument: evaluating it
# would run whatever the config file contained.
# Usage: aur_apply_ssh_key <array-name>
aur_apply_ssh_key() {
    local -n _git_cmd="$1"
    [[ -n "$AUR_SSH_KEY" ]] || return 0
    local key="${AUR_SSH_KEY/#\~/$HOME}"
    if [[ -f "$key" || "$key" == *[^A-Za-z0-9._~/-]* ]]; then
        _git_cmd+=(-c "core.sshCommand=ssh -i $(printf %q "$key")")
        debug "[aur-integration] Using SSH key: $AUR_SSH_KEY"
        return 0
    fi
    warn "[aur-integration] ssh_key ${AUR_SSH_KEY} does not exist; using the ssh configuration"
}

# Initialize new AUR repository
# Usage: init_aur_repo <pkgname>
init_aur_repo() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    log "[aur-integration] Initializing AUR repository: $aur_repo_path"
    
    # Create AUR directory if it doesn't exist
    if ! mkdir -p "$AUR_REPO_DIR" 2>>"$AURGEN_ERROR_LOG"; then
        err "[aur-integration] Cannot create $AUR_REPO_DIR. Set aur_integration.aur_repo_dir in aurgen.install.yaml to a writable directory."
        return 1
    fi
    
    local -a git_cmd=(git)
    aur_apply_ssh_key git_cmd
    git_cmd+=(clone "ssh://aur@aur.archlinux.org/$pkgname.git" "$aur_repo_path")

    # Clone AUR repository
    if ! "${git_cmd[@]}" 2>>"$AURGEN_ERROR_LOG"; then
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
    local srcinfo="$1" line key value i src fname
    local -a sources=()
    local -A sums=()
    [[ -f "$srcinfo" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*([a-z0-9]+)[[:space:]]=[[:space:]](.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
            pkgname) break ;;
            source) sources+=("$value") ;;
            md5sums|sha1sums|sha224sums|sha256sums|sha384sums|sha512sums|b2sums|cksums)
                sums["$key"]+="$value"$'\n' ;;
        esac
    done < "$srcinfo"
    for key in "${!sums[@]}"; do
        i=0
        while IFS= read -r value; do
            # makepkg itself writes SKIP for signature files (*.sig, *.sign, *.asc), judged by
            # the name before "::"; gpg verifies those, so they are not unpinned downloads.
            src="${sources[i]:-}"
            fname="${src%%::*}"
            if [[ "$value" == SKIP && "$src" =~ ^([^:/]+::)?(https?|ftp):// \
                  && "$fname" != *.sig && "$fname" != *.sign && "$fname" != *.asc ]]; then
                err "[aur-integration] $key is SKIP for downloaded source ${sources[i]}; run aurgen aur so the checksum is pinned before deploying"
                return 1
            fi
            i=$((i + 1))
        done <<< "${sums[$key]%$'\n'}"
    done
    return 0
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
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*install=(.*)$ ]] || continue
        install_file="${BASH_REMATCH[1]}"
        install_file="${install_file#"${install_file%%[![:space:]]*}"}"
        install_file="${install_file%"${install_file##*[![:space:]]}"}"
        if [[ ${#install_file} -ge 2 ]]; then
            case "$install_file" in
                \'*\') install_file="${install_file:1:${#install_file}-2}" ;;
                \"*\") install_file="${install_file:1:${#install_file}-2}" ;;
            esac
        fi
        break
    done < "$PKGBUILD"
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
    local src_pkgver src_pkgrel version
    src_pkgver=$(aur_srcinfo_field pkgver "$SRCINFO") || src_pkgver=""
    src_pkgrel=$(aur_srcinfo_field pkgrel "$SRCINFO") || src_pkgrel=""
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
        version="${src_pkgver}-${src_pkgrel}"
    fi
    local commit_msg="${AUR_COMMIT_MESSAGE//\{version\}/$version}"

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
                .SRCINFO) preview_src="$SRCINFO" ;;
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
    fi
    
    # Backup existing files if configured
    if [[ "$AUR_BACKUP_EXISTING" == "true" ]]; then
        local backup_dir
        backup_dir="$aur_repo_path/backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        if [[ -f "$aur_repo_path/PKGBUILD" ]]; then
            cp "$aur_repo_path/PKGBUILD" "$backup_dir/"
        fi
        if [[ -f "$aur_repo_path/.SRCINFO" ]]; then
            cp "$aur_repo_path/.SRCINFO" "$backup_dir/"
        fi
        if [[ -n "$install_file" && -f "$aur_repo_path/$install_file" ]]; then
            cp "$aur_repo_path/$install_file" "$backup_dir/"
        fi
        debug "[aur-integration] Created backup in: $backup_dir"
    fi
    
    # Copy PKGBUILD and .SRCINFO. errexit is off: mode_aur_deploy calls this
    # function inside if, so a failed cp must be checked here.
    if ! cp "$PKGBUILD" "$aur_repo_path/"; then
        err "[aur-integration] Failed to copy PKGBUILD to $aur_repo_path"
        return 1
    fi
    if ! cp "$SRCINFO" "$aur_repo_path/"; then
        err "[aur-integration] Failed to copy .SRCINFO to $aur_repo_path"
        return 1
    fi
    if [[ -n "$install_file" ]]; then
        if ! cp "$install_src" "$aur_repo_path/"; then
            err "[aur-integration] Failed to copy $install_file to $aur_repo_path"
            return 1
        fi
    fi
    
    if [[ -n "$install_file" ]]; then
        log "[aur-integration] Copied PKGBUILD, .SRCINFO and ${install_file} to AUR repository"
    else
        log "[aur-integration] Copied PKGBUILD and .SRCINFO to AUR repository"
    fi
    
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
    if ! git -C "$aur_repo_path" add "${stage_files[@]}"; then
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
                if ! ahead=$(git -C "$aur_repo_path" rev-list --count origin/master..HEAD 2>/dev/null); then
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
        log "[aur-integration] Auto-push disabled. Run 'git -C $aur_repo_path push' to push changes"
    fi
    
    return 0
}

# Push changes to AUR
# Usage: push_to_aur <pkgname>
push_to_aur() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
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
        err "[aur-integration] .SRCINFO is out of date; run makepkg --printsrcinfo > .SRCINFO"
        return 1
    fi
    rm -f "$printed"
    
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
# Usage: aur_web_version <pkgname> [just-pushed]
aur_web_version() {
    local pkgname="$1"
    local just_pushed="${2:-}"
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 0
    fi
    local web_body web_count web_ver
    web_body=$(mktemp)
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
                echo "AUR web: ${web_ver}"
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

# Get AUR repository status
# Usage: get_aur_status <pkgname>
get_aur_status() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    echo "=== AUR Repository Status: $pkgname ==="
    
    if ! check_aur_repo_exists "$pkgname"; then
        echo "Status: Repository does not exist"
        echo "Path: $aur_repo_path"
        aur_web_version "$pkgname"
        return 1
    fi
    
    echo "Status: Repository exists"
    echo "Path: $aur_repo_path"
    
    # Check git status
    local git_status
    git_status=$(git -C "$aur_repo_path" status --porcelain 2>/dev/null || echo "error")
    
    if [[ "$git_status" == "error" ]]; then
        echo "Git Status: Error accessing repository"
    elif [[ -z "$git_status" ]]; then
        echo "Git Status: Clean working directory"
    else
        echo "Git Status: Modified files:"
        printf '%s\n' "$git_status" | sed 's/^/  /'
    fi
    
    # Check remote status
    local remote_status
    remote_status=$(git -C "$aur_repo_path" status --porcelain --branch 2>/dev/null | grep '^##' || echo "error")
    
    if [[ "$remote_status" != "error" ]]; then
        echo "Remote Status: $remote_status"
    fi

    # Published checkout vs the .SRCINFO aurgen just wrote. Either file
    # missing means there is nothing to compare.
    if [[ -n "${SRCINFO:-}" && -f "$SRCINFO" && -f "$aur_repo_path/.SRCINFO" ]]; then
        local gen_pkgver gen_pkgrel aur_pkgver aur_pkgrel gen_ver aur_ver verdict
        gen_pkgver=$(aur_srcinfo_field pkgver "$SRCINFO") || gen_pkgver=""
        gen_pkgrel=$(aur_srcinfo_field pkgrel "$SRCINFO") || gen_pkgrel=""
        aur_pkgver=$(aur_srcinfo_field pkgver "$aur_repo_path/.SRCINFO") || aur_pkgver=""
        aur_pkgrel=$(aur_srcinfo_field pkgrel "$aur_repo_path/.SRCINFO") || aur_pkgrel=""
        if [[ -n "$gen_pkgver" && -n "$gen_pkgrel" && -n "$aur_pkgver" && -n "$aur_pkgrel" ]]; then
            gen_ver="${gen_pkgver}-${gen_pkgrel}"
            aur_ver="${aur_pkgver}-${aur_pkgrel}"
            if [[ "$aur_ver" == "$gen_ver" ]]; then
                verdict="up to date"
            else
                verdict="deploy pending"
            fi
            echo "Version: AUR ${aur_ver}, generated ${gen_ver} (${verdict})"
        fi
    fi

    # The clone can lag the website after a push from another machine.
    aur_web_version "$pkgname"

    return 0
}
