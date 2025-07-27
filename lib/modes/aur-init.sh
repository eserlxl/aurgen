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
    # shellcheck source=../lib/aur-integration.sh
    . "$LIB_INSTALL_DIR/aur-integration.sh"
    
    # Load AUR integration configuration
    load_aur_integration_config
    
    log "[aur-init] Initializing AUR repository for package: $PKGNAME"
    
    # Check if AUR repository already exists
    if check_aur_repo_exists "$PKGNAME"; then
        warn "[aur-init] AUR repository already exists for $PKGNAME"
        prompt "Do you want to reinitialize it? This will delete the existing repository. [y/N] " reinit_choice n
        if [[ "$reinit_choice" =~ ^[Yy]$ ]]; then
            local aur_repo_path="$AUR_REPO_DIR/$PKGNAME"
            log "[aur-init] Removing existing AUR repository: $aur_repo_path"
            rm -rf "$aur_repo_path"
        else
            log "[aur-init] Skipping initialization - repository already exists"
            return 0
        fi
    fi
    
    # Initialize AUR repository
    if init_aur_repo "$PKGNAME"; then
        log "[aur-init] Successfully initialized AUR repository for $PKGNAME"
        log "[aur-init] Repository location: $AUR_REPO_DIR/$PKGNAME"
        log "[aur-init] You can now use 'aurgen aur-deploy' to deploy your package"
    else
        err "[aur-init] Failed to initialize AUR repository for $PKGNAME"
        return 1
    fi
} 