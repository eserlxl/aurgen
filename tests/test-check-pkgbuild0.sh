#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-check-pkgbuild0.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

export LIB_INSTALL_DIR="$ROOT/lib"
export AUR_DIR="$tmp/aur"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/aurgen.log"
export color_enabled=0
mkdir -p "$AUR_DIR"
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

# Direct execution of lib/check-pkgbuild0.sh must be rejected.
if bash "$ROOT/lib/check-pkgbuild0.sh" >"$tmp/direct.out" 2>"$tmp/direct.err"; then
    fail "direct execution of lib/check-pkgbuild0.sh succeeded"
fi
grep -Fq 'must be sourced' "$tmp/direct.err" || fail "direct execution did not explain sourcing requirement" "$tmp/direct.err"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/check-pkgbuild0.sh
source "$ROOT/lib/check-pkgbuild0.sh"

write_valid_pkgbuild0() {
    cat >| "$AUR_DIR/PKGBUILD.0" <<'EOF'
pkgname=demo
pkgver=1.2.3
pkgrel=1
pkgdesc='Demo package description'
url='https://github.com/example/demo'
license=('GPL-3.0-or-later')
source=('https://github.com/example/demo/archive/v1.2.3.tar.gz')
EOF
}

# 1. Missing and empty file checks.
rm -f "$AUR_DIR/PKGBUILD.0"
if check_pkgbuild0 2>"$tmp/missing.err"; then
    fail "missing PKGBUILD.0 passed check_pkgbuild0"
fi
grep -Fq 'does not exist' "$tmp/missing.err" || fail "missing file warning absent" "$tmp/missing.err"

: >| "$AUR_DIR/PKGBUILD.0"
if check_pkgbuild0 2>"$tmp/empty.err"; then
    fail "empty PKGBUILD.0 passed check_pkgbuild0"
fi
grep -Fq 'is empty' "$tmp/empty.err" || fail "empty file warning absent" "$tmp/empty.err"

# 2. Caller shell options ($-), caller variables (field, value), and ERR trap must remain untouched.
write_valid_pkgbuild0
set +e
field="caller-field"
value="caller-value"
trap_fired=0
set -E
opts_before="$-"
trap 'trap_fired=1' ERR
check_pkgbuild0 2>"$tmp/valid.err" || fail "valid PKGBUILD.0 failed check_pkgbuild0" "$tmp/valid.err"
[[ "$-" == "$opts_before" ]] || fail "check_pkgbuild0 mutated caller shell options: before=$opts_before after=$-"
[[ "$field" == "caller-field" && "$value" == "caller-value" ]] || fail "check_pkgbuild0 clobbered caller field/value: field=$field value=$value"
(( trap_fired == 0 )) || fail "check_pkgbuild0 triggered ERR trap on valid PKGBUILD.0"
trap - ERR
set +E

# Missing url field must return 1 cleanly without firing ERR trap inside check-pkgbuild0.sh or mutating $-.
grep -v '^url=' "$AUR_DIR/PKGBUILD.0" >| "$tmp/no-url"
mv -f "$tmp/no-url" "$AUR_DIR/PKGBUILD.0"
bash -c '
    set -uo pipefail
    set -E
    trap '\''printf "ERR_AT:%s:%s\n" "${BASH_SOURCE[0]}" "$LINENO" >&2'\'' ERR
    source "$1/lib/helpers.sh"
    source "$1/lib/check-pkgbuild0.sh"
    opts_before="$-"
    rc=0
    check_pkgbuild0 || rc=$?
    [[ "$-" == "$opts_before" ]] || { echo "MUTATED_OPTS:$-" >&2; exit 99; }
    exit "$rc"
' _ "$ROOT" >"$tmp/no-url.out" 2>"$tmp/no-url.err"
rc=$?
(( rc == 1 )) || fail "missing url field returned $rc instead of 1" "$tmp/no-url.err"
! grep -Fq 'ERR_AT:' "$tmp/no-url.err" || fail "check_pkgbuild0 triggered ERR trap on missing url field" "$tmp/no-url.err"
grep -Fq 'missing or invalid url field' "$tmp/no-url.err" || fail "missing url field warning absent" "$tmp/no-url.err"
! grep -Fq 'url field is empty' "$tmp/no-url.err" || fail "missing url field emitted duplicate empty-field warning" "$tmp/no-url.err"

# 3. Reject empty license arrays, empty/whitespace scalars, array-valued scalars, and non-GitHub URLs.
for bad_case in \
    "pkgname=()|missing or invalid pkgname" \
    "pkgname=\"   \"|missing or invalid pkgname" \
    "pkgver=()|missing or invalid pkgver" \
    "pkgrel=()|missing or invalid pkgrel" \
    "pkgdesc='   '|pkgdesc field is empty" \
    "pkgdesc=\"   \"|missing or invalid pkgdesc" \
    "url='https://githubXcom/example/demo'|missing or invalid url" \
    "license=()|license field is empty" \
    "license=('')|license field is empty" \
    "license=(\"   \")|license field is empty" \
    "source=|source field is empty" \
    "source=''|source field is empty" \
    "source=\"   \"|source field is empty"; do
    bad_override="${bad_case%%|*}"
    expect_msg="${bad_case#*|}"
    key="${bad_override%%=*}"
    write_valid_pkgbuild0
    grep -v "^${key}=" "$AUR_DIR/PKGBUILD.0" >| "$tmp/mod"
    printf '%s\n' "$bad_override" >> "$tmp/mod"
    mv -f "$tmp/mod" "$AUR_DIR/PKGBUILD.0"
    if check_pkgbuild0 2>"$tmp/bad.err"; then
        fail "check_pkgbuild0 accepted invalid $bad_override" "$AUR_DIR/PKGBUILD.0"
    fi
    grep -Fq "$expect_msg" "$tmp/bad.err" || fail "expected '$expect_msg' for $bad_override" "$tmp/bad.err"
done

# 4. Reject multi-line empty license arrays, while accepting valid multi-line arrays and empty source=() templates.
write_valid_pkgbuild0
grep -v '^license=' "$AUR_DIR/PKGBUILD.0" >| "$tmp/ml-empty"
cat >> "$tmp/ml-empty" <<'EOF'
license=(
    # only a comment
    ''
)
EOF
mv -f "$tmp/ml-empty" "$AUR_DIR/PKGBUILD.0"
if check_pkgbuild0 2>"$tmp/ml-empty.err"; then
    fail "check_pkgbuild0 accepted multi-line empty license array"
fi
grep -Fq 'license field is empty' "$tmp/ml-empty.err" || fail "multi-line empty license warning absent" "$tmp/ml-empty.err"

write_valid_pkgbuild0
grep -Ev '^(license|source)=' "$AUR_DIR/PKGBUILD.0" >| "$tmp/ml-valid"
cat >> "$tmp/ml-valid" <<'EOF'
license=(
    'GPL-3.0-or-later'
    'MIT'
)
source=(
)
EOF
mv -f "$tmp/ml-valid" "$AUR_DIR/PKGBUILD.0"
check_pkgbuild0 2>"$tmp/ml-valid.err" || fail "check_pkgbuild0 rejected multi-line license array or empty source=() template" "$tmp/ml-valid.err"

# 5. Non-GitHub url= fails when PKG_URL is unset, and succeeds only with a valid scheme URL when PKG_URL is set.
write_valid_pkgbuild0
grep -v '^url=' "$AUR_DIR/PKGBUILD.0" >| "$tmp/custom-url"
cat >> "$tmp/custom-url" <<'EOF'
epoch=2
url='https://example.org/demo'
replaces=('old-demo')
options=('!lto')
EOF
mv -f "$tmp/custom-url" "$AUR_DIR/PKGBUILD.0"
if PKG_URL="" check_pkgbuild0 2>"$tmp/custom-unset.err"; then
    fail "check_pkgbuild0 accepted non-GitHub url when PKG_URL is unset"
fi
grep -Fq 'missing or invalid url field' "$tmp/custom-unset.err" || fail "expected url error when PKG_URL is unset" "$tmp/custom-unset.err"

PKG_URL="https://example.org/demo" check_pkgbuild0 2>"$tmp/custom-set.err" || fail "check_pkgbuild0 rejected custom url when PKG_URL is set" "$tmp/custom-set.err"

grep -v '^url=' "$AUR_DIR/PKGBUILD.0" >| "$tmp/bad-scheme"
printf "url='example.org/demo'\n" >> "$tmp/bad-scheme"
mv -f "$tmp/bad-scheme" "$AUR_DIR/PKGBUILD.0"
if PKG_URL="https://example.org/demo" check_pkgbuild0 2>"$tmp/bad-scheme.err"; then
    fail "check_pkgbuild0 accepted schemeless url even with PKG_URL set"
fi
grep -Fq 'missing or invalid url field' "$tmp/bad-scheme.err" || fail "expected url error for schemeless url" "$tmp/bad-scheme.err"
