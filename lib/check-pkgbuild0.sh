#!/bin/bash
# Check if aur/PKGBUILD.0 is a valid PKGBUILD.0 for aurgen
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

if [[ -z "${_AWK_PKGBUILD_UNQUOTED:-}" ]]; then
    _AWK_PKGBUILD_UNQUOTED=$(
        # shellcheck disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh" && printf '%s\n' "$_AWK_PKGBUILD_UNQUOTED"
    )
fi

# Return 0 if top-level <field>= in <file> has a valid value (allowing an empty array only when
# <allow_empty_array> is 1, as gen_pkgbuild0 writes source=() when all tracked files are excluded),
# 1 if present with an empty/whitespace-only value, or 2 if missing.
_check_pkgbuild0_array_or_scalar() {
    local file="$1"
    local target="$2"
    local allow_empty_array="${3:-0}"
    LC_ALL=C awk -v target="$target" -v allow_empty_arr="$allow_empty_array" -v sq="'" "$_AWK_PKGBUILD_UNQUOTED"'
        function content_chars(s,    i, n, c, out, prev) {
            out = ""; prev = ""; n = length(s)
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (c == sq) {
                    for (i++; i <= n; i++) {
                        c = substr(s, i, 1)
                        if (c == sq) break
                        if (c !~ /[[:space:]]/) out = out c
                    }
                    prev = "_"; continue
                }
                if (c == "\"") {
                    for (i++; i <= n; i++) {
                        c = substr(s, i, 1)
                        if (c == "\\") {
                            i++
                            if (i <= n && substr(s, i, 1) !~ /[[:space:]]/) out = out substr(s, i, 1)
                            continue
                        }
                        if (c == "\"") break
                        if (c !~ /[[:space:]]/) out = out c
                    }
                    prev = "_"; continue
                }
                if (c == "\\") {
                    i++
                    if (i <= n && substr(s, i, 1) == sq) out = out sq
                    else if (i <= n && substr(s, i, 1) !~ /[[:space:]]/) out = out substr(s, i, 1)
                    prev = "_"; continue
                }
                if (c == "#" && (prev == "" || prev ~ /[[:space:]()]/)) break
                if (c !~ /[[:space:]()]/) out = out c
                prev = c
            }
            return out
        }
        /^(build|check|package|prepare|pkgver)\(\)/ { in_fn = 1; next }
        in_fn { if (/^}[[:space:]]*$/) in_fn = 0; next }
        in_arr {
            u = unquoted($0)
            closed = (u ~ /\)[[:space:]]*$/)
            body = body content_chars($0)
            if (closed) in_arr = 0
            next
        }
        $0 ~ ("^" target "=") {
            seen = 1
            rest = substr($0, length(target) + 2)
            u = unquoted(rest)
            if (u ~ /^[[:space:]]*\(/) {
                saw_arr = 1
                closed = (u ~ /\)[[:space:]]*$/)
                body = body content_chars(rest)
                if (!closed) in_arr = 1
            } else {
                body = body content_chars(rest)
            }
            next
        }
        END {
            if (!seen) exit 2
            if (body == "" && !(saw_arr && allow_empty_arr == 1)) exit 1
            exit 0
        }
    ' "$file"
}

# Usage: check_pkgbuild0 [pkgbuild0_file]
check_pkgbuild0() {
    # Check if PKGBUILD.0 is a valid PKGBUILD.0 for aurgen
    # Returns 0 if valid, 1 if not
    local -x LC_ALL=C
    local PKGBUILD0="${1:-${AUR_DIR:-}/PKGBUILD.0}"

    local valid=1
    local field rc scalar_re
    scalar_re='([^[:space:]"'\''()#]+|"[^"]*[^"[:space:]][^"]*"|'\''[^'\'']*[^'\''[:space:]][^'\'']*'\'')([[:space:]]*(#.*)?)?$'

    # Check existence
    if [[ ! -f "$PKGBUILD0" ]]; then
        warn "[check-pkgbuild0] $PKGBUILD0 does not exist." >&2
        return 1
    fi

    # Check for non-empty file
    if [[ ! -s "$PKGBUILD0" ]]; then
        warn "[check-pkgbuild0] $PKGBUILD0 is empty." >&2
        return 1
    fi

    if ! bash -n "$PKGBUILD0"; then
        warn "[check-pkgbuild0] $PKGBUILD0 has a syntax error." >&2
        return 1
    fi

    local -A scalar_fields=(
        [pkgname]="^pkgname=${scalar_re}"
        [pkgver]="^pkgver=${scalar_re}"
        [pkgrel]="^pkgrel=${scalar_re}"
        # pkgbuild_squote writes an embedded quote as '\'', even as the first character.
        [pkgdesc]="^pkgdesc=(\"[^\"]*[^\"[:space:]][^\"]*\"|'([^']|'\\\\'')+')([[:space:]]*(#.*)?)?$"
        [url]="^url=(\"https://github\\.com/[^/\"[:space:]]+/[^/\"[:space:]]+\"|'https://github\\.com/[^/'[:space:]]+/[^/'[:space:]]+')([[:space:]]*(#.*)?)?$"
    )

    for field in pkgname pkgver pkgrel pkgdesc url; do
        if ! grep -Eq "${scalar_fields[$field]}" "$PKGBUILD0"; then
            warn "[check-pkgbuild0] $PKGBUILD0 missing or invalid $field field." >&2
            valid=0
        elif [[ "$field" == "pkgdesc" ]] && grep -Eq "^pkgdesc='[[:space:]]*'([[:space:]]*(#.*)?)?$" "$PKGBUILD0"; then
            warn "[check-pkgbuild0] $PKGBUILD0 pkgdesc field is empty." >&2
            valid=0
        fi
    done

    for field in license source; do
        rc=0
        local allow_empty_arr=0
        [[ "$field" == "source" ]] && allow_empty_arr=1
        _check_pkgbuild0_array_or_scalar "$PKGBUILD0" "$field" "$allow_empty_arr" || rc=$?
        if (( rc == 2 )); then
            warn "[check-pkgbuild0] $PKGBUILD0 missing or invalid $field field." >&2
            valid=0
        elif (( rc != 0 )); then
            warn "[check-pkgbuild0] $PKGBUILD0 $field field is empty." >&2
            valid=0
        fi
    done

    if (( valid == 0 )); then
        return 1
    fi
    return 0
}
