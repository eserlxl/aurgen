#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen aur-deploy mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_aur_deploy() {
    log "${SILVER}[aur-deploy] Deploy package to AUR repository.${RESET}"
    
    # Source AUR integration library
    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/aur-integration.sh"
    
    # Load AUR integration configuration
    load_aur_integration_config
    
    # Ensure PKGBUILD and .SRCINFO exist
    if [[ ! -f "$PKGBUILD" ]]; then
        err "[aur-deploy] PKGBUILD not found. Run 'aurgen aur' first to generate it."
        return 1
    fi
    
    if [[ ! -f "$SRCINFO" ]]; then
        err "[aur-deploy] .SRCINFO not found. Run 'aurgen aur' first to generate it."
        return 1
    fi
    
    log "[aur-deploy] Deploying package $PKGNAME to AUR"
    
    # Deploy to AUR
    if deploy_to_aur "$PKGNAME"; then
        log "[aur-deploy] Successfully deployed $PKGNAME to AUR"
        if [[ "$AUR_AUTO_PUSH" == "true" ]]; then
            log "[aur-deploy] Package has been pushed to AUR and should be available shortly"
        else
            log "[aur-deploy] Package has been committed to local AUR repository"
            log "[aur-deploy] Run 'git -C $AUR_REPO_DIR/$PKGNAME push' to push to AUR"
        fi
    else
        err "[aur-deploy] Failed to deploy $PKGNAME to AUR"
        return 1
    fi
} 