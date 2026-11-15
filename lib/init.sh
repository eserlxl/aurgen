#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen initialization: color setup, env vars, traps, and early checks

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

# Source helpers for logging and info output
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/helpers.sh"
# Source color setup
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/colors.sh"

# Call color initialization
init_colors

# Tool-to-package mapping for Arch Linux hints (declared on source so pre-init require() hints work)
if ! declare -p PKG_HINT >/dev/null 2>&1; then
    # shellcheck disable=SC2034 # Used externally by sourced scripts
    declare -gAr PKG_HINT=(
        [updpkgsums]=pacman-contrib
        [makepkg]=base-devel
        [curl]=curl
        [gpg]=gnupg
        [gh]=github-cli
        [flock]=util-linux
        [awk]=gawk
        [git]=git
        [jq]=jq
        [shellcheck]=shellcheck
        [namcap]=namcap
    )
fi

# shellcheck disable=SC1091
# --- Directory Setup ---
# Always require git repo for project root

aurgen_init() {
    # Pin C locale so [a-z]/[A-Za-z] validation and child AWK/grep helpers keep ASCII semantics.
    local -x LC_ALL=C
    # Namerefs (4.3) and mapfile -d (4.4) appear below, starting with the PKGBUILD import.
    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
        err "Bash ≥ 4.4 required" >&2
        exit 1
    fi
    if git_root=$(git rev-parse --show-toplevel 2>>"$AURGEN_ERROR_LOG"); then
        PROJECT_ROOT="$git_root"
    else
        echo "[aurgen] ERROR: This script must be run inside a git repository (no .git found)." >&2
        exit 1
    fi
    declare -gr PROJECT_ROOT
    declare -gr AUR_DIR="$PROJECT_ROOT/aur"
    GOLDEN_DIR="$PROJECT_ROOT/aur/golden"
    TEST_DIR="$PROJECT_ROOT/aur/test"
    if [[ -n "${AURGEN_CONFIG_FILE:-}" ]]; then
        if [[ -d "$AURGEN_CONFIG_FILE" ]]; then
            err "[aurgen] Configuration path is a directory: $AURGEN_CONFIG_FILE"
            exit 1
        fi
        local allow_missing_cfg=0
        if [[ "${AURGEN_MODE:-}" == "config" ]]; then
            case "${AURGEN_CONFIG_ACTION:-}" in
                generate|gen|g|edit|e|reset|r|import|i|help|h|--help|-h|"")
                    allow_missing_cfg=1
                    ;;
            esac
        fi
        if (( ! allow_missing_cfg )) && [[ ! -f "$AURGEN_CONFIG_FILE" ]]; then
            err "[aurgen] Configuration file not found: $AURGEN_CONFIG_FILE"
            exit 1
        fi
    fi
    mkdir -p "$AUR_DIR"
    # Everything in aur/ is generated except the package config: ignore all of it
    # and re-include only aurgen.install.yaml. A file aurgen wrote with the older
    # rules (which also kept PKGBUILD, .SRCINFO and *.install) is upgraded; any
    # other existing file is the project's own rules.
    local old_ignore=$'*\n!.gitignore\n!PKGBUILD\n!.SRCINFO\n!*.install\n!aurgen.install.yaml'
    if [[ ! -e "$AUR_DIR/.gitignore" || "$(<"$AUR_DIR/.gitignore")" == "$old_ignore" ]]; then
        printf '%s\n' '*' '!.gitignore' '!aurgen.install.yaml' >| "$AUR_DIR/.gitignore"
    fi

    # --- Environment and Trap Setup ---
    # Dry runs write generated files under aur/dry-run/. Published files stay in aur/.
    local out_dir="$AUR_DIR" dry_isolated=0
    if (( ${dry_run:-0} == 1 )); then
        case "${AURGEN_MODE:-}" in
            local|aur|git)
                out_dir="$AUR_DIR/dry-run"
                dry_isolated=1
                mkdir -p "$out_dir"
                ;;
        esac
    fi
    declare -g PKGBUILD0="$AUR_DIR/PKGBUILD.0"
    declare -gr OUT_DIR="$out_dir"
    declare -gr PKGBUILD="$OUT_DIR/PKGBUILD"
    declare -gr SRCINFO="$OUT_DIR/.SRCINFO"
    declare -gr GOLDEN_DIR
    export PKGBUILD0 PKGBUILD SRCINFO GOLDEN_DIR TEST_DIR AUR_DIR OUT_DIR

    set -E
    set -o errtrace
    trap 'err "[FATAL] ${BASH_SOURCE[0]}:$LINENO: $BASH_COMMAND"' ERR

    # --- Constants ---
    # REPO_NAME keeps the remote's spelling for GitHub URLs. pkgname is
    # package.name when that is set, otherwise the lowercased repo name.
    if git_root=$(git rev-parse --show-toplevel 2>>"$AURGEN_ERROR_LOG"); then
        repo_url=$(git config --get remote.origin.url || true)
        if [[ -n "$repo_url" ]]; then
            REPO_NAME=$(basename "${repo_url%.git}")
        else
            REPO_NAME=$(basename "$git_root")
        fi
    else
        echo "[aurgen] ERROR: This script must be run inside a git repository (no .git found)." >&2
        exit 1
    fi
    declare -grx REPO_NAME

    # shellcheck source=../lib/config.sh
    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/config.sh"
    # Import before load_aurgen_config fixes PKGNAME. After that the name is
    # readonly, so a hand-written pkgname would be replaced by the repo name.
    # config mode skips it: its generate and import actions decide what is written.
    local config_file
    config_file="$(aurgen_config_file)"
    if [[ -z "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" && -f "$AUR_DIR/PKGBUILD" && "${AURGEN_MODE:-}" != "lint" && "${AURGEN_MODE:-}" != "clean" && "${AURGEN_MODE:-}" != "config" && "${AURGEN_MODE:-}" != "test" ]]; then
        if (( dry_isolated )); then
            config_file="$out_dir/aurgen.install.yaml"
            if [[ ! -f "$config_file" ]]; then
                # shellcheck source=../lib/config-import.sh
                # shellcheck disable=SC1091
                . "$LIB_INSTALL_DIR/config-import.sh"
                if config_import "$AUR_DIR/PKGBUILD" "$config_file"; then
                    log "[aurgen] Imported $AUR_DIR/PKGBUILD into $config_file"
                else
                    err "[aurgen] Could not import $AUR_DIR/PKGBUILD; fix the PKGBUILD, or write aur/aurgen.install.yaml with 'aurgen config generate'."
                    exit 1
                fi
            fi
        elif (( ${dry_run:-0} == 0 )); then
            # shellcheck source=../lib/config-import.sh
            # shellcheck disable=SC1091
            . "$LIB_INSTALL_DIR/config-import.sh"
            if config_import "$AUR_DIR/PKGBUILD" "$config_file"; then
                log "[aurgen] Imported $AUR_DIR/PKGBUILD into aurgen.install.yaml"
            else
                err "[aurgen] Could not import $AUR_DIR/PKGBUILD; fix the PKGBUILD, or write aur/aurgen.install.yaml with 'aurgen config generate'."
                exit 1
            fi
        fi
    fi
    if (( dry_isolated )) && [[ -z "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" && -f "$out_dir/aurgen.install.yaml" ]]; then
        config_file="$out_dir/aurgen.install.yaml"
    fi
    # config edit/reset/validate are how an invalid file gets repaired, so that
    # mode must not die on the load that every other mode still requires.
    local config_loaded=0
    if load_aurgen_config "$config_file"; then
        config_loaded=1
    elif [[ "${AURGEN_MODE:-}" == "config" ]]; then
        warn "[aurgen] $(basename "$config_file") is invalid; config mode continues so you can fix it"
    else
        exit 1
    fi
    # Checked before PKGBUILD.0 generation asks for a signing key: a release
    # source uploads its tarball and signature before any build could run.
    if [[ "${build_only:-0}" == 1 && "${AURGEN_MODE:-}" == "aur" && "${PKG_SOURCE:-release}" == "release" ]]; then
        err "[aur] --build-only is not supported with package.source=release: release assets are uploaded before building. Use archive or signed-tag."
        exit 1
    fi
    if [[ -n "${PKG_NAME:-}" ]]; then
        PKGNAME="$PKG_NAME"
    else
        # ${REPO_NAME,,} follows LC_CTYPE; a Turkish locale folds I to a dotless i.
        PKGNAME="$(printf '%s' "$REPO_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    fi
    # Both names end up in file paths (tarballs, the AUR clone dir) and URLs; package.name
    # comes from YAML, so refuse anything but makepkg's charset and a leading dot or hyphen.
    if [[ ! "$PKGNAME" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
        if [[ "${AURGEN_MODE:-}" == "config" ]]; then
            warn "[aurgen] Invalid package name '$PKGNAME'; config mode continues so you can fix it"
        else
            echo "[aurgen] ERROR: Invalid package name '$PKGNAME' (lowercase letters, digits and @._+- only; no leading dot or hyphen)." >&2
            exit 1
        fi
    fi
    if [[ ! "$REPO_NAME" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
        echo "[aurgen] ERROR: Invalid repository name '$REPO_NAME'." >&2
        exit 1
    fi
    # shellcheck disable=SC2034 # Read by the mode scripts sourced after init
    declare -gr PKGNAME

    # Skip PKGBUILD.0 and GH_USER logic for lint, clean, config and test modes
    # (and for non-isolated dry runs whose mode reads aur/ directly).
    if [[ "$config_loaded" -eq 1 && "${AURGEN_MODE:-}" != "lint" && "${AURGEN_MODE:-}" != "clean" && "${AURGEN_MODE:-}" != "config" && "${AURGEN_MODE:-}" != "test" ]] && (( dry_isolated || ${dry_run:-0} == 0 )); then
        # Source PKGBUILD.0 checker
        # shellcheck source=../lib/check-pkgbuild0.sh
        . "$LIB_INSTALL_DIR/check-pkgbuild0.sh"
        # shellcheck source=../lib/gen-pkgbuild0.sh
        . "$LIB_INSTALL_DIR/gen-pkgbuild0.sh"

        local use_aur_pkgbuild0=0
        local target_dir="$AUR_DIR"
        local stamp_header="$AUR_DIR/PKGBUILD.HEADER"
        if (( dry_isolated )); then
            if [[ -f "$AUR_DIR/PKGBUILD.0" ]] && check_pkgbuild0 "$AUR_DIR/PKGBUILD.0"; then
                if [[ -f "$AUR_DIR/.PKGBUILD.0.stamp" ]]; then
                    local stamp_now stamp_saved
                    stamp_now=$(pkgbuild0_input_stamp "$config_file" "$AUR_DIR/PKGBUILD.HEADER")
                    stamp_saved=$(<"$AUR_DIR/.PKGBUILD.0.stamp")
                    [[ "$stamp_now" == "$stamp_saved" ]] && use_aur_pkgbuild0=1
                else
                    # A valid hand-written PKGBUILD.0 with no stamp; read it in place.
                    use_aur_pkgbuild0=1
                fi
            fi
            if (( ! use_aur_pkgbuild0 )); then
                target_dir="$out_dir"
                PKGBUILD0="$out_dir/PKGBUILD.0"
                [[ -f "$stamp_header" ]] || stamp_header="$out_dir/PKGBUILD.HEADER"
            fi
        fi

        # Ensure PKGBUILD.0 exists and is valid before GH_USER detection
        if (( ! use_aur_pkgbuild0 )); then
            local bak_label="PKGBUILD.0.bak"
            [[ "$target_dir" != "$AUR_DIR" ]] && bak_label="$target_dir/PKGBUILD.0.bak"
            if ! check_pkgbuild0 "$PKGBUILD0"; then
                if [[ -f "$PKGBUILD0" ]]; then
                    cp -f "$PKGBUILD0" "$target_dir/PKGBUILD.0.bak"
                    warn "[aurgen] PKGBUILD.0 is invalid and will be regenerated. The previous file has been backed up as ${bak_label}."
                fi
                gen_pkgbuild0
                if ! check_pkgbuild0 "$PKGBUILD0"; then
                    err "[aurgen] ERROR: Failed to generate a valid PKGBUILD.0.\n" >&2
                    exit 1
                else
                    log "[aurgen] Created new PKGBUILD.0 in $PKGBUILD0"
                fi
            elif [[ -f "$target_dir/.PKGBUILD.0.stamp" ]]; then
                # A valid PKGBUILD.0 with no stamp was written by hand; leave it alone.
                local stamp_now stamp_saved
                stamp_now=$(pkgbuild0_input_stamp "$config_file" "$stamp_header")
                stamp_saved=$(<"$target_dir/.PKGBUILD.0.stamp")
                if [[ "$stamp_now" != "$stamp_saved" ]]; then
                    cp -f "$PKGBUILD0" "$target_dir/PKGBUILD.0.bak"
                    warn "[aurgen] aurgen.install.yaml, PKGBUILD.HEADER, VERSION, Makefile, scanned source files, the latest tag or the aurgen version changed since PKGBUILD.0 was generated. The previous file has been backed up as ${bak_label}."
                    gen_pkgbuild0
                    if ! check_pkgbuild0 "$PKGBUILD0"; then
                        err "[aurgen] ERROR: Failed to generate a valid PKGBUILD.0.\n" >&2
                        exit 1
                    fi
                fi
            fi
        fi

        # --- GH_USER detection and validation ---
        if [[ -z "${GH_USER:-}" ]]; then
            # The generator writes url= single-quoted; older PKGBUILD.0 files use double quotes.
            PKGBUILD0_URL=$(awk -F/ '/^url=["\047]https:\/\/github\.com\// {print $4}' "$PKGBUILD0")
            if [[ -n "$PKGBUILD0_URL" ]]; then
                GH_USER="${PKGBUILD0_URL%[\"\']}"
            else
                printf "[aurgen] ERROR: Could not parse GitHub user/org from PKGBUILD.0 url field.\n" >&2
                printf "[aurgen] Please set the url field in PKGBUILD.0 to your real GitHub repo, e.g.:\n" >&2
                printf '[aurgen]     url="https://github.com/<yourusername>/%s"\n' "$REPO_NAME" >&2
                exit 1
            fi
        fi
        # Repositories such as tmux/tmux are valid. Reject the match only when
        # origin's owner disagrees with the owner in the PKGBUILD.0 url.
        if [[ "$GH_USER" == "$REPO_NAME" ]]; then
            local remote_url remote_owner=""
            remote_url=$(git config --get remote.origin.url || true)
            if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
                remote_owner="${BASH_REMATCH[1]}"
            fi
            if [[ "$remote_owner" != "$GH_USER" ]]; then
                echo "[aurgen] ERROR: Detected GH_USER='$GH_USER' (same as the repository name). This usually means the url field in PKGBUILD.0 is wrong." >&2
                echo "[aurgen] Please set the url field in PKGBUILD.0 to your real GitHub repo, e.g.:" >&2
                echo "[aurgen]     url=\"https://github.com/<yourusername>/$REPO_NAME\"" >&2
                echo "[aurgen] Detected url line:" >&2
                grep '^url=' "$PKGBUILD0" >&2
                err "[aurgen] Aborting due to invalid GH_USER configuration."
                exit 1
            fi
        fi
        declare -gr GH_USER
    fi

    # Enable debug tracing if DEBUG_LEVEL is set to a value greater than 1
    if (( ${DEBUG_LEVEL:-0} > 1 )); then
        set -x
    fi

    if GPG_TTY=$(tty 2>/dev/null); then
        export GPG_TTY
    fi

    set -euo pipefail
    set -o noclobber
}
