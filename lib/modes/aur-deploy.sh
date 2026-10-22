#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen aur-deploy and aur-push mode-specific logic

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

    # generate_srcinfo cds into the PKGBUILD directory; the subshell keeps that local.
    # A second run after aur or git rewrites the same bytes when the PKGBUILD is unchanged.
    # shellcheck disable=SC2154 # dry_run is set by the caller; default to 0 if unset
    : "${dry_run:=0}"
    local srcinfo_preview=""
    if (( ! dry_run )); then
        local srcinfo_prev cmp_status
        srcinfo_prev=$(mktemp "${TMPDIR:-/tmp}/aurgen-srcinfo.XXXXXX") || return 1
        if ! cp -f "$SRCINFO" "$srcinfo_prev"; then
            rm -f "$srcinfo_prev"
            return 1
        fi
        ( generate_srcinfo ) || {
            # generate_srcinfo removes .SRCINFO when makepkg fails; put the old one back.
            err "[aur-deploy] Could not regenerate .SRCINFO from $PKGBUILD"
            if cp -f "$srcinfo_prev" "$SRCINFO"; then
                rm -f "$srcinfo_prev"
            else
                err "[aur-deploy] Could not restore .SRCINFO; the previous file is at $srcinfo_prev"
            fi
            return 1
        }
        cmp_status=0
        cmp -s "$srcinfo_prev" "$SRCINFO" || cmp_status=$?
        rm -f "$srcinfo_prev"
        if (( cmp_status == 1 )); then
            log "[aur-deploy] Regenerated .SRCINFO from $PKGBUILD"
        elif (( cmp_status != 0 )); then
            err "[aur-deploy] Could not compare regenerated .SRCINFO from $PKGBUILD"
            return 1
        fi
    else
        # Preview what a real run would publish without touching aur/. deploy_to_aur
        # reads AUR_PREVIEW_SRCINFO for its diff and commit version (SRCINFO is readonly).
        srcinfo_preview=$(mktemp "${TMPDIR:-/tmp}/aurgen-srcinfo.XXXXXX") || return 1
        if (cd "$(dirname "$PKGBUILD")" && makepkg --printsrcinfo) >| "$srcinfo_preview" 2>>"$AURGEN_ERROR_LOG"; then
            if ! cmp -s "$srcinfo_preview" "$SRCINFO"; then
                log "[aur-deploy] (dry run) .SRCINFO would be regenerated from $PKGBUILD"
                # shellcheck disable=SC2034 # read by deploy_to_aur through dynamic scope
                local AUR_PREVIEW_SRCINFO="$srcinfo_preview"
            fi
        else
            warn "[aur-deploy] (dry run) Could not regenerate .SRCINFO from $PKGBUILD; previewing the current file"
        fi
    fi
    
    local deploy_name deploy_status=0
    deploy_name=$(aur_package_name) || deploy_name=""
    if [[ -z "$deploy_name" ]]; then
        err "[aur-deploy] .SRCINFO has no pkgbase or pkgname"
        [[ -z "$srcinfo_preview" ]] || rm -f "$srcinfo_preview"
        return 1
    fi

    log "[aur-deploy] Deploying package $deploy_name to AUR"
    
    # Deploy to AUR. The dry-run preview file is no longer needed afterwards.
    deploy_to_aur "$deploy_name" || deploy_status=$?
    [[ -z "$srcinfo_preview" ]] || rm -f "$srcinfo_preview"
    if (( deploy_status == 0 )); then
        : "${dry_run:=0}"
        if (( dry_run )); then
            log "[aur-deploy] Dry run: nothing was copied, committed or pushed"
            return 0
        fi
        if [[ "$AUR_AUTO_PUSH" == "true" ]]; then
            if [[ "$AUR_PUSH_SUCCEEDED" == "true" ]]; then
                log "[aur-deploy] Successfully deployed $deploy_name to AUR"
                log "[aur-deploy] Package has been pushed to AUR and should be available shortly"
                aur_web_version "$deploy_name" just-pushed
            fi
        else
            log "[aur-deploy] Successfully deployed $deploy_name to AUR"
            log "[aur-deploy] Package has been committed to local AUR repository"
            log "[aur-deploy] Run 'aurgen aur-push' to push to AUR"
        fi
    else
        err "[aur-deploy] Failed to deploy $deploy_name to AUR"
        return 1
    fi
}

mode_aur_push() {
    log "${SILVER}[aur-push] Push the deployed AUR clone.${RESET}"

    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/aur-integration.sh"

    load_aur_integration_config

    local push_name
    push_name=$(aur_package_name) || push_name=""
    if [[ -z "$push_name" ]]; then
        err "[aur-push] .SRCINFO has no pkgbase or pkgname"
        return 1
    fi

    local aur_repo_path="$AUR_REPO_DIR/$push_name"
    if ! check_aur_repo_exists "$push_name"; then
        err "[aur-push] AUR clone does not exist: $aur_repo_path"
        return 1
    fi

    # @{u} when the clone tracks a branch; origin/master when it does not.
    local upstream='@{u}'
    if ! git -C "$aur_repo_path" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
        upstream=origin/master
    fi
    local ahead=0
    if ! ahead=$(git -C "$aur_repo_path" rev-list --count "${upstream}..HEAD" 2>/dev/null); then
        # A fresh clone has no origin/master. A local HEAD still needs HEAD:master.
        ahead=0
        if git -C "$aur_repo_path" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
            ahead=1
        fi
    fi
    if [[ ! "$ahead" =~ ^[1-9][0-9]*$ ]]; then
        log "[aur-push] Nothing to push"
        return 0
    fi

    : "${dry_run:=0}"
    if (( dry_run )); then
        log "[aur-push] (dry run) Would push $ahead commit(s) from $aur_repo_path to AUR"
        return 0
    fi

    local rc=0
    push_to_aur "$push_name" || rc=$?
    return "$rc"
} 