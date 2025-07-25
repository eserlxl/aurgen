#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen test mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_test() {
    log "${SILVER}[test] Running all modes in dry-run mode to check for errors.${RESET}"
    mkdir -p "$TEST_DIR"
    debug "[test] Cleaning up old test logs..."
    rm -f "$TEST_DIR"/*.log
    debug "[test] Old test logs removed."
    TEST_ERRORS=0
    for test_mode in local aur aur-git; do
        log "${SILVER}--- Testing \"$test_mode\" mode ---${RESET}"
        debug "[test] Running clean before \"$test_mode\" test..."
        if ! aurgen clean 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"; then
            warn "[test] Warning: Clean failed for \"$test_mode\" test, but continuing..."
        fi
        TEST_LOG_FILE="$TEST_DIR/test-$test_mode-$(date +%s).log"
        _old_ci=${CI:-}
        export CI=1
        # GPG_KEY_ID will be automatically set to TEST_KEY_FOR_DRY_RUN for dry-run mode
        # No need to set it explicitly here
        if aurgen --dry-run "$test_mode" >| "$TEST_LOG_FILE" 2>&1; then
            log "${GREEN}[test] ✓ $test_mode mode passed${RESET}"
            # --- Begin golden PKGBUILD diff ---
            GOLDEN_FILE="$GOLDEN_DIR/PKGBUILD.$test_mode.golden"
            GENERATED_PKG="$PKGBUILD"
            if [[ -f "$GOLDEN_FILE" ]]; then
                if ! diff -u <(tail -n +2 "$GOLDEN_FILE") "$GENERATED_PKG" > "$TEST_DIR/diff-$test_mode.log"; then
                    err "[test] ✗ $test_mode PKGBUILD does not match golden file! See \"$TEST_DIR/diff-$test_mode.log\""
                    cat "$TEST_DIR/diff-$test_mode.log" >&2
                    TEST_ERRORS=$((TEST_ERRORS + 1))
                else
                    log "${GREEN}[test] ✓ $test_mode PKGBUILD matches golden file.${RESET}"
                fi
            else
                warn "[test] Golden file \"$GOLDEN_FILE\" not found. Skipping PKGBUILD diff for \"$test_mode\"."
            fi
            # --- End golden PKGBUILD diff ---
        else
            err "[test] ✗ $test_mode mode failed"
            TEST_ERRORS=$((TEST_ERRORS + 1))
            warn "Error output for $test_mode is in: \"$TEST_LOG_FILE\""
            cat "$TEST_LOG_FILE" >&2
        fi
        if [[ -n $_old_ci ]]; then
            export CI="$_old_ci"
        else
            unset CI
        fi
        debug "[test] Log for $test_mode: $TEST_LOG_FILE"
    done
    # Additional: Test invalid/nonsense command-line arguments
    log "${SILVER}[test] Running invalid argument tests...${RESET}"
    INVALID_ARGS_LIST=(
        "-0"
        "-1"
        "--usagex"
        "-X"
        "-0 local"
        "-1 aur"
        "--usagex aur-git"
        "-X lint"
        "-n -0 local"
        "-a --usagex aur"
        "-d -X test"
        "-n -a -1"
        "--no-color --usagex"
        "-n -a -X lint"
        "-d --usagex test"
    )
    for invalid_args_str in "${INVALID_ARGS_LIST[@]}"; do
        read -r -a invalid_args <<< "$invalid_args_str"
        TEST_LOG_FILE="$TEST_DIR/test-invalid-$(echo "$invalid_args_str" | tr ' /' '__').log"
        debug "[test] Testing invalid args: $invalid_args_str"
        if aurgen "${invalid_args[@]}" >"$TEST_LOG_FILE" 2>&1; then
            err "[test] ✗ Invalid args '$invalid_args_str' did NOT fail as expected!"
            TEST_ERRORS=$((TEST_ERRORS + 1))
            cat "$TEST_LOG_FILE" >&2
        else
            log "${GREEN}[test] ✓ Invalid args '$invalid_args_str' failed as expected.${RESET}"
        fi
        debug "[test] Log for invalid args '$invalid_args_str': $TEST_LOG_FILE"
    done
    if [[ $TEST_ERRORS -eq 0 ]]; then
        log "${GREEN}[test] ✓ All test modes passed successfully!${RESET}"
    else
        err "[test] ✗ $TEST_ERRORS test mode(s) failed"
        exit 1
    fi
    exit 0
} 