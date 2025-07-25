#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen lint mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    err "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

# Ensure script is run with Bash
if [ -z "$BASH_VERSION" ]; then
  echo "[FATAL] This script must be run with bash." >&2
  exit 99
fi

# Use external MAXDEPTH if provided, otherwise default to 5
LINT_DEPTH="${MAXDEPTH:-5}"  # Max search depth for linting

mode_lint() {
    log "${SILVER}[lint] Searching for bash files in $PROJECT_ROOT (${CYAN}depth $LINT_DEPTH${SILVER})...${RESET}"
    mapfile -t bash_files < <(find "$PROJECT_ROOT" -maxdepth "$LINT_DEPTH" -type d -name aur -prune -o -type f -name '*.sh' -print)
    if [[ ${#bash_files[@]} -eq 0 ]]; then
        warn "[lint] No bash files found to lint."
        exit 0
    fi

    # Prepare fresh lint output directory
    LINT_DIR="$PROJECT_ROOT/aur/lint"
    rm -rf "$LINT_DIR"
    mkdir -p "$LINT_DIR"

    SHELLCHECK_OK=1
    BASHN_OK=1
    PASSED_COUNT=0
    FAILED_COUNT=0
    FAILED_FILES=()
    for file in "${bash_files[@]}"; do
        rel_path="${file#"$PROJECT_ROOT"/}"
        out_dir="$LINT_DIR/$(dirname "$rel_path")"
        mkdir -p "$out_dir"
        warn "[lint] Checking $file"
        FILE_OK=1
        shellcheck_out="$out_dir/$(basename "$file").shellcheck.txt"
        bashn_out="$out_dir/$(basename "$file").bashn.txt"
        if command -v shellcheck > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
            shellcheck_output=$(shellcheck "$file" 2>&1 || true)
            if [ -n "$shellcheck_output" ]; then
                echo "$shellcheck_output" >| "$shellcheck_out"
                log "[lint] shellcheck output: $shellcheck_out"
                SHELLCHECK_OK=0; FILE_OK=0;
            fi
        else
            warn "[lint] shellcheck not found; skipping shellcheck for $file."
            log "${RED}[lint] shellcheck not found${RESET}"
        fi
        bashn_output=$(bash -n "$file" 2>&1 || true)
        if [ -n "$bashn_output" ]; then
            echo "$bashn_output" >| "$bashn_out"
            log "[lint] bash -n output: $bashn_out"
            BASHN_OK=0; FILE_OK=0;
        fi
        if [ "$FILE_OK" -eq 1 ]; then
            PASSED_COUNT=$((PASSED_COUNT+1))
        else
            FAILED_COUNT=$((FAILED_COUNT+1))
            FAILED_FILES+=("$file")
        fi
    done
    log "[lint] ${SILVER}Lint summary: ${GREEN}$PASSED_COUNT passed${RESET}, ${RED}$FAILED_COUNT failed${RESET}."
    if (( SHELLCHECK_OK && BASHN_OK )); then
        log "${GREEN}[lint] ✓ All lint checks passed.${RESET}"
        exit 0
    else
        if (( FAILED_COUNT > 0 )); then
            log "${RED}[lint] Failed files:"
            for f in "${FAILED_FILES[@]}"; do
                log "  $f"
            done
            log "${RED}[lint] ✗ Lint checks failed.${RESET}"
        fi
        exit 1
    fi
} 