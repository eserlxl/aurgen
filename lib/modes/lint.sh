#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen lint mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

# Ensure script is run with Bash
if [ -z "$BASH_VERSION" ]; then
  echo "[FATAL] This script must be run with bash." >&2
  exit 99
fi

_lint_print_json() {
    local ok_bool="$1" sc_avail_bool="$2" maxdepth_val="$3" report_dir_json="$4"
    local total_count="$5" passed_count="$6" failed_count="$7"
    shift 7
    local -a file_entries=("$@")
    local i
    printf '{"ok":%s,"shellcheck_available":%s,"maxdepth":%s,"report_dir":%s,"summary":{"total":%s,"passed":%s,"failed":%s},"files":[' \
        "$ok_bool" "$sc_avail_bool" "$maxdepth_val" "$report_dir_json" \
        "$total_count" "$passed_count" "$failed_count"
    for (( i = 0; i < ${#file_entries[@]}; i++ )); do
        if (( i > 0 )); then
            printf ','
        fi
        printf '%s' "${file_entries[$i]}"
    done
    printf ']}\n'
}

mode_lint() {
    # This file is sourced before --maxdepth is parsed and exported.
    LINT_DEPTH="${MAXDEPTH:-5}"
    log "${SILVER}[lint] Searching for bash files in $PROJECT_ROOT (${CYAN}depth $LINT_DEPTH${SILVER})...${RESET}"
    # Include new scripts but skip ignored files in Git work trees.
    mapfile -d '' -t bash_files < <(
        if [[ "$(git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]]; then
            git -C "$PROJECT_ROOT" ls-files -z --cached --others --exclude-standard |
            while IFS= read -r -d '' path; do
                case "/$path" in
                    */aur/*|*/Backups/*) continue ;;
                esac
                # A root file has find depth 1, one more than its slash count.
                slashes="${path//[^\/]/}"
                (( ${#slashes} < LINT_DEPTH )) || continue
                printf '%s\0' "$PROJECT_ROOT/$path"
            done
        else
            find "$PROJECT_ROOT" -maxdepth "$LINT_DEPTH" \
                \( -type d \( -name .git -o -name aur -o -name Backups \) -prune \) -o \
                -type f -print0
        fi |
        while IFS= read -r -d '' file; do
            [[ -f "$file" ]] || continue
            if [[ "$file" == *.sh ]]; then
                printf '%s\0' "$file"
                continue
            fi
            IFS= read -r shebang < "$file" || continue
            if [[ "$shebang" =~ ^#!.*[[:space:]/]bash([[:space:]]|$) ]]; then
                printf '%s\0' "$file"
            fi
        done
    )
    # The install scriptlet runs as root during pacman transactions, so lint it too even
    # though aur/ is skipped above: the one the PKGBUILD.0 names, from aur/ or aur/dry-run/.
    local lint_aur_dir="${AUR_DIR:-$PROJECT_ROOT/aur}" scriptlet="" scriptlet_path=""
    if declare -F pkgbuild_install_file >/dev/null 2>&1; then
        scriptlet="$(pkgbuild_install_file "${PKGBUILD0:-$lint_aur_dir/PKGBUILD.0}" 2>/dev/null || true)"
    fi
    if [[ -n "$scriptlet" && "$scriptlet" != */* && "$scriptlet" != .* ]]; then
        for scriptlet_path in "$lint_aur_dir/$scriptlet" "$lint_aur_dir/dry-run/$scriptlet"; do
            if [[ -f "$scriptlet_path" ]]; then
                bash_files+=("$scriptlet_path")
                break
            fi
        done
    fi
    if [[ ${#bash_files[@]} -eq 0 ]]; then
        warn "[lint] No bash files found to lint."
        if (( ${AURGEN_JSON:-0} )); then
            local empty_sc_avail="false"
            if command -v shellcheck > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
                empty_sc_avail="true"
            fi
            _lint_print_json "true" "$empty_sc_avail" "$LINT_DEPTH" "null" 0 0 0
        fi
        exit 0
    fi

    # Check for shellcheck availability and warn if missing
    if ! command -v shellcheck > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        warn "[lint] shellcheck not found - only bash syntax checking will be performed."
        warn "[lint] Install shellcheck for enhanced linting: sudo pacman -S shellcheck"
        SHELLCHECK_AVAILABLE=0
    else
        SHELLCHECK_AVAILABLE=1
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
    local -a LINT_JSON_FILES=()
    for file in "${bash_files[@]}"; do
        rel_path="${file#"$PROJECT_ROOT"/}"
        rel_path="${rel_path#./}"
        local rel_dir
        rel_dir="$(dirname "$rel_path")"
        if [[ "$rel_dir" == "." ]]; then
            out_dir="$LINT_DIR"
        else
            out_dir="$LINT_DIR/$rel_dir"
        fi
        mkdir -p "$out_dir"
        warn "[lint] Checking $file"
        FILE_OK=1
        local file_bashn_ok="true"
        local file_sc_ok="null"
        local file_sc_report=""
        local file_bashn_report=""
        shellcheck_out="$out_dir/$(basename "$file").shellcheck.txt"
        bashn_out="$out_dir/$(basename "$file").bashn.txt"
        if [[ "$SHELLCHECK_AVAILABLE" -eq 1 ]]; then
            file_sc_ok="true"
            shellcheck_status=0
            # -x with SCRIPTDIR follows a sibling helper a script sources; a .shellcheckrc still applies.
            local -a sc_args=(-x --source-path=SCRIPTDIR)
            # A scriptlet has no shebang; pacman runs it with bash.
            [[ "$file" == *.install ]] && sc_args+=(--shell=bash)
            shellcheck_output=$(shellcheck "${sc_args[@]}" -- "$file" 2>&1) || shellcheck_status=$?
            if (( shellcheck_status != 0 )) || [[ -n "$shellcheck_output" ]]; then
                printf '%s\n' "$shellcheck_output" >| "$shellcheck_out"
                log "[lint] shellcheck output: $shellcheck_out"
                SHELLCHECK_OK=0; FILE_OK=0; file_sc_ok="false"
                file_sc_report="${shellcheck_out#"$PROJECT_ROOT"/}"
            fi
        fi
        bashn_status=0
        bashn_output=$(bash -n -- "$file" 2>&1) || bashn_status=$?
        if (( bashn_status != 0 )) || [[ -n "$bashn_output" ]]; then
            printf '%s\n' "$bashn_output" >| "$bashn_out"
            log "[lint] bash -n output: $bashn_out"
            BASHN_OK=0; FILE_OK=0; file_bashn_ok="false"
            file_bashn_report="${bashn_out#"$PROJECT_ROOT"/}"
        fi
        local file_passed="false"
        if [ "$FILE_OK" -eq 1 ]; then
            PASSED_COUNT=$((PASSED_COUNT+1))
            file_passed="true"
        else
            FAILED_COUNT=$((FAILED_COUNT+1))
            FAILED_FILES+=("$file")
        fi
        LINT_JSON_FILES+=("{\"path\":\"$(_aurgen_json_escape "$rel_path")\",\"passed\":$file_passed,\"bashn_ok\":$file_bashn_ok,\"shellcheck_ok\":$file_sc_ok,\"bashn_report\":$(_aurgen_json_nullable_string "$file_bashn_report"),\"shellcheck_report\":$(_aurgen_json_nullable_string "$file_sc_report")}")
    done
    log "[lint] ${SILVER}Lint summary: ${GREEN}$PASSED_COUNT passed${RESET}, ${RED}$FAILED_COUNT failed${RESET}."
    if (( ${AURGEN_JSON:-0} )); then
        local lint_ok_json="false" sc_avail_json="false"
        (( SHELLCHECK_OK && BASHN_OK )) && lint_ok_json="true"
        (( SHELLCHECK_AVAILABLE )) && sc_avail_json="true"
        local report_dir_rel="${LINT_DIR#"$PROJECT_ROOT"/}"
        _lint_print_json "$lint_ok_json" "$sc_avail_json" "$LINT_DEPTH" "\"$(_aurgen_json_escape "$report_dir_rel")\"" \
            "$((PASSED_COUNT + FAILED_COUNT))" "$PASSED_COUNT" "$FAILED_COUNT" "${LINT_JSON_FILES[@]}"
    fi
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
