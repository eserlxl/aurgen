#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen aur-status mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_aur_status() {
    log "${SILVER}[aur-status] Check AUR repository status.${RESET}"
    
    # Source AUR integration library
    # shellcheck source=../lib/aur-integration.sh
    . "$LIB_INSTALL_DIR/aur-integration.sh"
    
    # Load AUR integration configuration
    load_aur_integration_config
    
    log "[aur-status] Checking AUR repository status for package: $PKGNAME"
    
    # Get AUR repository status
    if ! get_aur_status "$PKGNAME"; then
        # Repository doesn't exist, which is not an error for status check
        echo ""
    fi
    
    # Show configuration
    echo ""
    echo "=== AUR Integration Configuration ==="
    echo "AUR Repository Directory: $AUR_REPO_DIR"
    echo "Auto Push: $AUR_AUTO_PUSH"
    echo "Backup Existing: $AUR_BACKUP_EXISTING"
    echo "Validate Before Push: $AUR_VALIDATE_BEFORE_PUSH"
    
    if [[ -n "$AUR_GIT_USER_NAME" ]]; then
        echo "Git User Name: $AUR_GIT_USER_NAME"
    fi
    
    if [[ -n "$AUR_GIT_USER_EMAIL" ]]; then
        echo "Git User Email: $AUR_GIT_USER_EMAIL"
    fi
    
    if [[ -n "$AUR_SSH_KEY" ]]; then
        echo "SSH Key: $AUR_SSH_KEY"
    fi
} 