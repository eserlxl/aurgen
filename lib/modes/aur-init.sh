#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen aur-init mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_aur_init() {
    log "${SILVER}[aur-init] Initialize AUR repository for package deployment.${RESET}"
    
    # Source AUR integration library
    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/aur-integration.sh"
    
    # Load AUR integration configuration
    load_aur_integration_config || return 1

    local aur_name
    aur_name=$(aur_package_name) || aur_name="$PKGNAME"

    # Joined onto AUR_REPO_DIR and passed to rm -rf. Only a single path segment.
    if [[ -z "$aur_name" || "$aur_name" == */* || "$aur_name" == .* ]]; then
        err "[aur-init] Invalid AUR package name: $aur_name"
        return 1
    fi

    log "[aur-init] Initializing AUR repository for package: $aur_name"

    # shellcheck disable=SC2154 # dry_run is set by the caller; default to 0 if unset
    : "${dry_run:=0}"
    local aur_repo_path="$AUR_REPO_DIR/$aur_name"
    local backup_parent="" backup_path=""
    local has_existing=0 existing_kind=""

    # Check if AUR repository or a colliding non-git path already exists
    if check_aur_repo_exists "$aur_name"; then
        has_existing=1
        existing_kind="repo"
        warn "[aur-init] AUR repository already exists for $aur_name"
    elif [[ -e "$aur_repo_path" || -L "$aur_repo_path" ]]; then
        has_existing=1
        existing_kind="collision"
        warn "[aur-init] Existing non-git path collides with AUR repository location: $aur_repo_path"
    fi

    if (( has_existing )); then
        local reinit_choice prompt_msg skip_msg
        if [[ "$existing_kind" == "repo" ]]; then
            prompt_msg="Do you want to reinitialize it? This will replace the existing repository. [y/N] "
            skip_msg="repository already exists"
        else
            prompt_msg="Do you want to replace it? This will remove the existing path. [y/N] "
            skip_msg="colliding path already exists"
        fi
        prompt "$prompt_msg" reinit_choice n
        if [[ "$reinit_choice" =~ ^[Yy]$ ]]; then
            if (( dry_run )); then
                log "[aur-init] Dry run: would remove $aur_repo_path"
            else
                if ! mkdir -p "$AUR_REPO_DIR" 2>>"${AURGEN_ERROR_LOG:-/dev/null}"; then
                    err "[aur-init] Cannot create $AUR_REPO_DIR. Set aur_integration.aur_repo_dir in aurgen.install.yaml to a writable directory."
                    return 1
                fi
                if ! backup_parent="$(mktemp -d "$AUR_REPO_DIR/.aur-init-backup.XXXXXX" 2>>"${AURGEN_ERROR_LOG:-/dev/null}")"; then
                    err "[aur-init] Failed to create backup staging directory in $AUR_REPO_DIR"
                    return 1
                fi
                backup_path="$backup_parent/$aur_name"
                log "[aur-init] Backing up existing path before reinitialization: $aur_repo_path"
                if ! mv -- "$aur_repo_path" "$backup_path" 2>>"${AURGEN_ERROR_LOG:-/dev/null}"; then
                    rmdir "$backup_parent" 2>/dev/null || true
                    err "[aur-init] Failed to back up existing path: $aur_repo_path"
                    return 1
                fi
            fi
        elif [[ "$existing_kind" == collision ]]; then
            # Nothing usable is left at the clone path, so aur-deploy would fail there.
            err "[aur-init] Not initialized: $aur_repo_path is not an AUR git repository; move it away or rerun and replace it"
            return 1
        else
            log "[aur-init] Skipping initialization - $skip_msg"
            return 0
        fi
    fi

    if (( dry_run )); then
        log "[aur-init] Dry run: would clone https://aur.archlinux.org/${aur_name}.git into $aur_repo_path and set the push URL to ssh://aur@aur.archlinux.org/${aur_name}.git"
        return 0
    fi

    # Initialize AUR repository
    if init_aur_repo "$aur_name"; then
        if [[ -n "$backup_parent" ]]; then
            rm -rf "$backup_parent"
        fi
        log "[aur-init] Successfully initialized AUR repository for $aur_name"
        log "[aur-init] Repository location: $AUR_REPO_DIR/$aur_name"
        log "[aur-init] You can now use 'aurgen aur-deploy' to deploy your package"
        aur_probe_ssh
    else
        if [[ -n "$backup_parent" && -n "$backup_path" ]] && [[ -e "$backup_path" || -L "$backup_path" ]]; then
            rm -rf "$aur_repo_path" 2>/dev/null || true
            if mv -- "$backup_path" "$aur_repo_path" 2>>"${AURGEN_ERROR_LOG:-/dev/null}"; then
                rmdir "$backup_parent" 2>/dev/null || rm -rf "$backup_parent" 2>/dev/null || true
                warn "[aur-init] Restored previous path after clone failure: $aur_repo_path"
            else
                err "[aur-init] Failed to restore backup from $backup_path"
            fi
        fi
        err "[aur-init] Failed to initialize AUR repository for $aur_name"
        return 1
    fi
} 