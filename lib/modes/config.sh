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

# Config mode implementation
mode_config() {
    local action="${1:-}"
    local config_file="$AUR_DIR/aurgen.install.conf"
    

    
    case "$action" in
        generate|gen|g)
            generate_default_config
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}[config] Configuration file generated successfully.${RESET}" >&2
            fi
            ;;
        edit|e)
            if [[ -f "$config_file" ]]; then
                echo -e "${CYAN}[config] Opening configuration file: $config_file${RESET}" >&2
                if command -v "$EDITOR" >/dev/null 2>&1; then
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
                generate_default_config
                if [[ $? -eq 0 ]]; then
                    echo -e "${CYAN}[config] Opening newly generated configuration file...${RESET}" >&2
                    if command -v "$EDITOR" >/dev/null 2>&1; then
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
                fi
            fi
            ;;
        show|s|list|l)
            if [[ -f "$config_file" ]]; then
                echo -e "${CYAN}[config] Configuration file: $config_file${RESET}" >&2
                echo "---"
                cat "$config_file"
            else
                echo -e "${YELLOW}[config] No configuration file found. Using default configuration:${RESET}" >&2
                echo "---"
                for dir_rule in "${DEFAULT_COPY_DIRS[@]}"; do
                    echo "$dir_rule"
                done
            fi
            ;;
        validate|v)
            # Load and validate configuration
            load_aurgen_config
            if validate_config; then
                echo -e "${GREEN}[config] Configuration is valid.${RESET}" >&2
                echo -e "${CYAN}[config] Active copy rules:${RESET}" >&2
                for dir_rule in "${COPY_DIRS[@]}"; do
                    echo "  $dir_rule"
                done
            else
                echo -e "${RED}[config] Configuration validation failed.${RESET}" >&2
                return 1
            fi
            ;;
        reset|r)
            if [[ -f "$config_file" ]]; then
                echo -e "${YELLOW}[config] Backing up existing configuration to $config_file.bak${RESET}" >&2
                cp "$config_file" "$config_file.bak"
                rm -f "$config_file"
                generate_default_config
                echo -e "${GREEN}[config] Configuration file reset to defaults.${RESET}" >&2
            else
                echo -e "${YELLOW}[config] No configuration file found. Generating default configuration...${RESET}" >&2
                generate_default_config
                echo -e "${GREEN}[config] Configuration file generated.${RESET}" >&2
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
            echo "  validate, v         Validate configuration syntax" >&2
            echo "  reset, r            Reset configuration to defaults (with backup)" >&2
            echo "  help, h             Show this help message" >&2
            echo "" >&2
            echo "Configuration file format:" >&2
            echo "  source_dir:dest_dir:permissions" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  bin:usr/bin:755          # Copy bin/ to usr/bin/ with executable permissions" >&2
            echo "  lib:usr/lib/\$pkgname:644 # Copy lib/ to usr/lib/\$pkgname/ with read permissions" >&2
            echo "  # include:usr/include/\$pkgname:644  # Commented out - won't copy include/" >&2
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