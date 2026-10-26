#!/bin/bash
# AURGen config mode
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Configuration management mode for AURGen

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# shellcheck source=lib/config.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/config.sh"
# shellcheck source=lib/config-import.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/config-import.sh"

# One parsed scalar. Empty means the key was absent, so generation will not use it.
_config_print_scalar() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
        printf '%s: %s\n' "$key" "$value"
    fi
}

# One parsed list, in the order the YAML reader stored it.
_config_print_list() {
    local key="$1"
    shift
    local item
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    printf '%s:\n' "$key"
    for item in "$@"; do
        printf '  - %s\n' "$item"
    done
}

# Package fields as parse_yaml_config stored them, then copy rules as generation emits them.
# shellcheck disable=SC2154 # PKG_* are set by parse_yaml_config
_config_show_effective() {
    local -a copy_rules=()
    local copy_rules_output
    load_aurgen_config || return 1
    copy_rules_output=$(get_copy_directories) || return 1
    if [[ -n "$copy_rules_output" ]]; then
        mapfile -t copy_rules <<< "$copy_rules_output"
    fi
    _config_print_scalar name "$PKG_NAME"
    _config_print_scalar description "$PKG_DESCRIPTION"
    _config_print_scalar install "$PKG_INSTALL"
    _config_print_scalar check "$PKG_CHECK"
    _config_print_scalar source "$PKG_SOURCE"
    _config_print_scalar gpg_key "$PKG_GPG_KEY"
    _config_print_list arch "${PKG_ARCH[@]}"
    _config_print_list depends "${PKG_DEPENDS[@]}"
    _config_print_list optdepends "${PKG_OPTDEPENDS[@]}"
    _config_print_list makedepends "${PKG_MAKEDEPENDS[@]}"
    _config_print_list checkdepends "${PKG_CHECKDEPENDS[@]}"
    _config_print_list conflicts "${PKG_CONFLICTS[@]}"
    _config_print_list provides "${PKG_PROVIDES[@]}"
    _config_print_list backup "${PKG_BACKUP[@]}"
    _config_print_list install_vars "${PKG_INSTALL_VARS[@]}"
    _config_print_list keep "${PKG_KEEP[@]}"
    _config_print_list license "${PKG_LICENSE[@]}"
    _config_print_list post_package "${PKG_POST_PACKAGE[@]}"
    if (( ${#PKG_POST_INSTALL[@]} + ${#PKG_POST_UPGRADE[@]} + ${#PKG_PRE_REMOVE[@]} )); then
        printf 'install_messages:\n'
        _config_print_list post_install "${PKG_POST_INSTALL[@]}" | sed 's/^/  /'
        _config_print_list post_upgrade "${PKG_POST_UPGRADE[@]}" | sed 's/^/  /'
        _config_print_list pre_remove "${PKG_PRE_REMOVE[@]}" | sed 's/^/  /'
    fi
    _config_print_list copy "${copy_rules[@]}"
    # Where aur-init clones and whether aur-deploy pushes, after defaults.
    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/aur-integration.sh"
    load_aur_integration_config
    printf 'aur_integration:\n'
    {
        _config_print_scalar aur_repo_dir "$AUR_REPO_DIR"
        _config_print_scalar auto_push "$AUR_AUTO_PUSH"
        _config_print_scalar validate_before_push "$AUR_VALIDATE_BEFORE_PUSH"
        _config_print_scalar commit_message "$AUR_COMMIT_MESSAGE"
        _config_print_scalar ssh_key "$AUR_SSH_KEY"
        _config_print_scalar git_user_name "$AUR_GIT_USER_NAME"
        _config_print_scalar git_user_email "$AUR_GIT_USER_EMAIL"
    } | sed 's/^/  /'
}

# Config mode implementation
mode_config() {
    local action="${1:-}"
    local config_file="$AUR_DIR/aurgen.install.yaml"
    # Drop the action word so it is not treated as the output path.
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$action" in
        generate|gen|g)
            if generate_default_config "$config_file"; then
                echo -e "${GREEN}[config] Configuration file generated successfully.${RESET}" >&2
            else
                return 1
            fi
            ;;
        edit|e)
            if [[ -f "$config_file" ]]; then
                echo -e "${CYAN}[config] Opening configuration file: $config_file${RESET}" >&2
                if [[ -n "${EDITOR:-}" ]] && command -v "$EDITOR" >/dev/null 2>&1; then
                    "$EDITOR" "$config_file"
                elif command -v nano >/dev/null 2>&1; then
                    nano "$config_file"
                elif command -v vim >/dev/null 2>&1; then
                    vim "$config_file"
                elif command -v vi >/dev/null 2>&1; then
                    vi "$config_file"
                else
                    echo -e "${RED}[config] Error: No suitable editor found. Please set EDITOR environment variable or install nano/vim.${RESET}" >&2
                    return 1
                fi
            else
                echo -e "${YELLOW}[config] No configuration file found. Generating default configuration...${RESET}" >&2
                if generate_default_config "$config_file"; then
                    echo -e "${CYAN}[config] Opening newly generated configuration file...${RESET}" >&2
                    if [[ -n "${EDITOR:-}" ]] && command -v "$EDITOR" >/dev/null 2>&1; then
                        "$EDITOR" "$config_file"
                    elif command -v nano >/dev/null 2>&1; then
                        nano "$config_file"
                    elif command -v vim >/dev/null 2>&1; then
                        vim "$config_file"
                    elif command -v vi >/dev/null 2>&1; then
                        vi "$config_file"
                    else
                        echo -e "${RED}[config] Error: No suitable editor found. Please set EDITOR environment variable or install nano/vim.${RESET}" >&2
                        return 1
                    fi
                else
                    return 1
                fi
            fi
            ;;
        show|s|list|l)
            if [[ "${1:-}" == "effective" ]]; then
                _config_show_effective
            elif [[ -f "$config_file" ]]; then
                echo -e "${CYAN}[config] Configuration file: $config_file${RESET}" >&2
                echo "---"
                cat "$config_file"
            else
                echo -e "${YELLOW}[config] No configuration file found. Using default configuration:${RESET}" >&2
                echo "---"
                echo "bin: usr/bin (executable)"
                echo "lib: usr/lib/\$pkgname (read-only)"
                echo "etc: etc/\$pkgname (read-only)"
                echo "share: usr/share/\$pkgname (read-only)"
                echo "include: usr/include/\$pkgname (read-only)"
                echo "local: usr/local/\$pkgname (read-only)"
                echo "var: var/\$pkgname (read-only)"
                echo "opt: opt/\$pkgname (read-only)"
            fi
            ;;
        validate|v)
            # Load and validate configuration
            local copy_rules_output source_dir dest_dir permissions
            if load_aurgen_config && copy_rules_output=$(get_copy_directories); then
                echo -e "${GREEN}[config] Configuration is valid.${RESET}" >&2
                echo -e "${CYAN}[config] Active copy rules:${RESET}" >&2
                while IFS=':' read -r source_dir dest_dir permissions _; do
                    [[ -n "$source_dir" ]] || continue
                    printf '  %s: %s (%s)\n' "$source_dir" "$dest_dir" "$permissions"
                done <<< "$copy_rules_output"
            else
                echo -e "${RED}[config] Configuration validation failed.${RESET}" >&2
                return 1
            fi
            ;;
        reset|r)
            if [[ -f "$config_file" ]]; then
                local config_status
                if ! config_status=$(git -C "$PROJECT_ROOT" status --porcelain -- "$config_file" 2>/dev/null) ||
                    [[ -n "$config_status" ]] ||
                    ! git -C "$PROJECT_ROOT" ls-files --error-unmatch -- "$config_file" >/dev/null 2>&1; then
                    echo -e "${RED}[config] Error: Cannot reset $config_file unless it is tracked and clean in a git work tree. Commit the file or delete it by hand.${RESET}" >&2
                    return 1
                fi
                rm -f "$config_file" || return 1
                generate_default_config "$config_file" || return 1
                echo -e "${GREEN}[config] Configuration file reset to defaults.${RESET}" >&2
                printf '%b[config] Restore the previous version with: git checkout -- %q%b\n' "$CYAN" "$config_file" "$RESET" >&2
            else
                echo -e "${YELLOW}[config] No configuration file found. Generating default configuration...${RESET}" >&2
                generate_default_config "$config_file" || return 1
                echo -e "${GREEN}[config] Configuration file generated.${RESET}" >&2
            fi
            ;;
        import|i)
            if ! config_import "${1:-$AUR_DIR/PKGBUILD}" "$config_file"; then
                return 1
            fi
            ;;
        help|h|--help|-h)
            echo -e "${CYAN}AURGen Install Configuration Management${RESET}" >&2
            echo "" >&2
            echo "Usage: aurgen config <action>" >&2
            echo "" >&2
            echo "Actions:" >&2
            echo "  generate, gen, g    Generate default configuration file" >&2
            echo "  edit, e             Edit configuration file with default editor" >&2
            echo "  show, s, list, l    Show current configuration" >&2
            echo "  show effective      Print parsed package metadata and copy rules" >&2
            echo "  validate, v         Validate configuration syntax" >&2
            echo "  reset, r            Reset configuration to defaults (requires a clean tracked file)" >&2
            echo "  import, i [path]    Import package metadata from a PKGBUILD (default: aur/PKGBUILD)" >&2
            echo "  help, h             Show this help message" >&2
            echo "" >&2
            echo "Configuration file format (YAML):" >&2
            echo "  section_name:" >&2
            echo "    source: source_directory" >&2
            echo "    destination: destination_path" >&2
            echo "    permissions: executable|read-only" >&2
            echo "    exclude: [item1, item2]" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  executables:" >&2
            echo "    source: bin" >&2
            echo "    destination: usr/bin" >&2
            echo "    permissions: executable" >&2
            echo "    exclude: []" >&2
            echo "" >&2
            echo "  # headers:  # Commented out - won't copy include/" >&2
            echo "  #   source: include" >&2
            echo "  #   destination: usr/include/\$pkgname" >&2
            echo "  #   permissions: read-only" >&2
            echo "" >&2
            echo "Configuration file locations:" >&2
            echo "  $config_file" >&2
            echo "  ${config_file}.example" >&2
            echo "" >&2
            echo "Note: Configuration files are project-specific and located in the aur/ directory." >&2
            echo "      They are automatically generated when PKGBUILD.0 is created for the first time." >&2
            echo "" >&2
            ;;
        "")
            echo -e "${YELLOW}[config] No action specified. Use 'aurgen config help' for usage information.${RESET}" >&2
            return 1
            ;;
        *)
            echo -e "${RED}[config] Unknown action: $action${RESET}" >&2
            echo -e "${YELLOW}[config] Use 'aurgen config help' for usage information.${RESET}" >&2
            return 1
            ;;
    esac
}
