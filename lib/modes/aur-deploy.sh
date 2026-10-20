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
    
    # The AUR clone is named by pkgbase (pkgname= on a -git PKGBUILD), not PKGNAME.
    local deploy_name
    deploy_name=$(aur_srcinfo_field pkgbase "$SRCINFO") || deploy_name=""
    if [[ -z "$deploy_name" ]]; then
        deploy_name=$(aur_srcinfo_field pkgname "$SRCINFO") || deploy_name=""
    fi
    if [[ -z "$deploy_name" ]]; then
        err "[aur-deploy] .SRCINFO has no pkgbase or pkgname"
        return 1
    fi

    log "[aur-deploy] Deploying package $deploy_name to AUR"
    
    # Deploy to AUR
    if deploy_to_aur "$deploy_name"; then
        : "${dry_run:=0}"
        if (( dry_run )); then
            log "[aur-deploy] Dry run: nothing was copied, committed or pushed"
            return 0
        fi
        if [[ "$AUR_AUTO_PUSH" == "true" ]]; then
            if [[ "$AUR_PUSH_SUCCEEDED" == "true" ]]; then
                log "[aur-deploy] Successfully deployed $deploy_name to AUR"
                log "[aur-deploy] Package has been pushed to AUR and should be available shortly"
                aur_web_version "$deploy_name"
            fi
        else
            log "[aur-deploy] Successfully deployed $deploy_name to AUR"
            log "[aur-deploy] Package has been committed to local AUR repository"
            log "[aur-deploy] Run 'git -C $AUR_REPO_DIR/$deploy_name push' to push to AUR"
        fi
    else
        err "[aur-deploy] Failed to deploy $deploy_name to AUR"
        return 1
    fi
} 