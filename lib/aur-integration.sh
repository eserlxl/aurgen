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

# Load AUR integration configuration from aurgen.install.yaml
# Usage: load_aur_integration_config
load_aur_integration_config() {
    local aur_config_file="$AUR_DIR/aurgen.install.yaml"
    
    # Initialize with defaults
    AUR_REPO_DIR="/opt/AUR"
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
    
    while IFS= read -r line; do
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
        if (( in_aur_section )); then
            if [[ "$line" =~ ^[[:space:]]*aur_repo_dir:[[:space:]]*(.+)$ ]]; then
                AUR_REPO_DIR="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*auto_push:[[:space:]]*(.+)$ ]]; then
                AUR_AUTO_PUSH="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*commit_message:[[:space:]]*(.+)$ ]]; then
                AUR_COMMIT_MESSAGE="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*git_user_name:[[:space:]]*(.+)$ ]]; then
                AUR_GIT_USER_NAME="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*git_user_email:[[:space:]]*([^[:space:]].*)$ ]]; then
                AUR_GIT_USER_EMAIL="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*ssh_key:[[:space:]]*(.+)$ ]]; then
                AUR_SSH_KEY="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*backup_existing:[[:space:]]*(.+)$ ]]; then
                AUR_BACKUP_EXISTING="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*validate_before_push:[[:space:]]*(.+)$ ]]; then
                AUR_VALIDATE_BEFORE_PUSH="${BASH_REMATCH[1]}"
            fi
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

# Initialize new AUR repository
# Usage: init_aur_repo <pkgname>
init_aur_repo() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    log "[aur-integration] Initializing AUR repository: $aur_repo_path"
    
    # Create AUR directory if it doesn't exist
    mkdir -p "$AUR_REPO_DIR"
    
    # Clone AUR repository
    if ! git clone "ssh://aur@aur.archlinux.org/$pkgname.git" "$aur_repo_path" 2>>"$AURGEN_ERROR_LOG"; then
        err "[aur-integration] Failed to clone AUR repository for $pkgname"
        return 1
    fi
    
    log "[aur-integration] Successfully initialized AUR repository: $aur_repo_path"
    return 0
}

# Deploy PKGBUILD and .SRCINFO to AUR repository
# Usage: deploy_to_aur <pkgname>
deploy_to_aur() {
    local pkgname="$1"
    local aur_repo_path="$AUR_REPO_DIR/$pkgname"
    
    log "[aur-integration] Deploying to AUR repository: $aur_repo_path"
    
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
        local backup_dir="$aur_repo_path/backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        if [[ -f "$aur_repo_path/PKGBUILD" ]]; then
            cp "$aur_repo_path/PKGBUILD" "$backup_dir/"
        fi
        if [[ -f "$aur_repo_path/.SRCINFO" ]]; then
            cp "$aur_repo_path/.SRCINFO" "$backup_dir/"
        fi
        debug "[aur-integration] Created backup in: $backup_dir"
    fi
    
    # Copy PKGBUILD and .SRCINFO
    cp "$PKGBUILD" "$aur_repo_path/"
    cp "$SRCINFO" "$aur_repo_path/"
    
    log "[aur-integration] Copied PKGBUILD and .SRCINFO to AUR repository"
    
    # Configure git user if specified
    if [[ -n "$AUR_GIT_USER_NAME" ]]; then
        git -C "$aur_repo_path" config user.name "$AUR_GIT_USER_NAME"
    fi
    if [[ -n "$AUR_GIT_USER_EMAIL" ]]; then
        git -C "$aur_repo_path" config user.email "$AUR_GIT_USER_EMAIL"
    fi
    
    # Commit changes
    local commit_msg="${AUR_COMMIT_MESSAGE//\{version\}/$PKGVER}"
    if ! git -C "$aur_repo_path" add PKGBUILD .SRCINFO; then
        err "[aur-integration] Failed to stage files for commit"
        return 1
    fi
    
    if ! git -C "$aur_repo_path" commit -m "$commit_msg"; then
        warn "[aur-integration] No changes to commit (files may be identical)"
        return 0
    fi
    
    log "[aur-integration] Committed changes to AUR repository"
    
    # Push to AUR if auto-push is enabled
    if [[ "$AUR_AUTO_PUSH" == "true" ]]; then
        if ! push_to_aur "$pkgname"; then
            err "[aur-integration] Failed to push to AUR"
            return 1
        fi
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
    
    # Push to AUR
    if ! git -C "$aur_repo_path" push origin master; then
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
    
    # Validate .SRCINFO syntax
    if ! (cd "$aur_repo_path" && makepkg --printsrcinfo > /dev/null); then
        err "[aur-integration] .SRCINFO validation failed"
        return 1
    fi
    
    log "[aur-integration] AUR repository validation passed"
    return 0
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
        echo "$git_status" | sed 's/^/  /'
    fi
    
    # Check remote status
    local remote_status
    remote_status=$(git -C "$aur_repo_path" status --porcelain --branch 2>/dev/null | grep '^##' || echo "error")
    
    if [[ "$remote_status" != "error" ]]; then
        echo "Remote Status: $remote_status"
    fi
    
    return 0
} 