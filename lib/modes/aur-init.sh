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
    load_aur_integration_config

    local aur_name
    aur_name=$(aur_package_name) || aur_name="$PKGNAME"

    log "[aur-init] Initializing AUR repository for package: $aur_name"
    
    # Check if AUR repository already exists
    if check_aur_repo_exists "$aur_name"; then
        warn "[aur-init] AUR repository already exists for $aur_name"
        local reinit_choice
        prompt "Do you want to reinitialize it? This will delete the existing repository. [y/N] " reinit_choice n
        if [[ "$reinit_choice" =~ ^[Yy]$ ]]; then
            local aur_repo_path="$AUR_REPO_DIR/$aur_name"
            log "[aur-init] Removing existing AUR repository: $aur_repo_path"
            rm -rf "$aur_repo_path"
        else
            log "[aur-init] Skipping initialization - repository already exists"
            return 0
        fi
    fi
    
    # Initialize AUR repository
    if init_aur_repo "$aur_name"; then
        log "[aur-init] Successfully initialized AUR repository for $aur_name"
        log "[aur-init] Repository location: $AUR_REPO_DIR/$aur_name"
        log "[aur-init] You can now use 'aurgen aur-deploy' to deploy your package"
    else
        err "[aur-init] Failed to initialize AUR repository for $aur_name"
        return 1
    fi
} 