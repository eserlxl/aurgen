#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-aur-upload.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export color_enabled=0
export DEBUG_LEVEL=0

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/gh" << 'EOF'
#!/bin/bash
if [[ "$1 $2" == "release create" ]]; then
    printf '%s\n' "$*" >> "$GH_ARGV_LOG"
    exit 0
fi
if [[ "$1 $2" == "release view" ]]; then
    exit "${GH_VIEW_RC:-0}"
fi
if [[ "$1 $2" == "release upload" ]]; then
    printf '%s\n' "$4" >> "${GH_UPLOAD_LOG:-/dev/null}"
    # GH_UPLOAD_FAIL_SIG fails only the signature, so the tarball upload succeeds first.
    if [[ -n "${GH_UPLOAD_FAIL_SIG:-}" ]]; then
        for arg in "$@"; do
            [[ "$arg" == *.sig ]] && exit 1
        done
        exit 0
    fi
    exit "${GH_UPLOAD_RC:-1}"
fi
exit 0
EOF
chmod +x "$stub/gh"

: >| "$tmp/err.log"
: >| "$tmp/out.log"

run_upload() {
    (
        export PATH="$stub:$PATH"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        export DEBUG_LEVEL=0
        export asset_exists=0
        export RELEASE_TAG=1.0.0
        export TARBALL=demo-1.0.0.tar.gz
        export TARBALL_URL="https://example.invalid/demo-1.0.0.tar.gz"
        export AUR_DIR="$tmp"
        export GH_USER=example
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/modes/aur.sh
        source "$ROOT/lib/modes/aur.sh"
        aur_upload_assets demo
    ) >| "$1" 2>| "$2" < /dev/null
}

export GH_ARGV_LOG="$tmp/gh-create.log"
: >| "$GH_ARGV_LOG"
export GH_VIEW_RC=0
export GH_UPLOAD_RC=1
fail_status=0
run_upload "$tmp/fail.out" "$tmp/fail.err" || fail_status=$?
if [[ "$fail_status" -eq 0 ]]; then
    echo "failed release upload returned 0"
    exit 1
fi
if grep -F -q 'Asset(s) uploaded.' "$tmp/fail.out" "$tmp/fail.err"; then
    echo "success line printed after failed upload"
    exit 1
fi

export GH_UPLOAD_RC=0
export GH_UPLOAD_LOG="$tmp/gh-upload.log"
: >| "$GH_UPLOAD_LOG"
ok_status=0
run_upload "$tmp/ok.out" "$tmp/ok.err" || ok_status=$?
if [[ "$ok_status" -ne 0 ]]; then
    echo "successful release upload returned $ok_status"
    cat "$tmp/ok.err"
    exit 1
fi
if ! grep -F -q 'Asset(s) uploaded.' "$tmp/ok.out"; then
    echo "successful release upload omitted the success line"
    cat "$tmp/ok.out"
    exit 1
fi
if ! grep -q '/demo-1\.0\.0\.tar\.gz$' "$GH_UPLOAD_LOG" || ! grep -q '/demo-1\.0\.0\.tar\.gz\.[a-z]*$' "$GH_UPLOAD_LOG"; then
    echo "existing release did not upload both the tarball and its signature"
    cat "$GH_UPLOAD_LOG"
    exit 1
fi
unset GH_UPLOAD_LOG
if [[ -s "$GH_ARGV_LOG" ]]; then
    echo "existing release invoked release create"
    cat "$GH_ARGV_LOG"
    exit 1
fi

export GH_VIEW_RC=1
export GH_UPLOAD_RC=0
: >| "$GH_ARGV_LOG"
create_status=0
run_upload "$tmp/create.out" "$tmp/create.err" || create_status=$?
if [[ "$create_status" -ne 0 ]]; then
    echo "release create returned $create_status"
    cat "$tmp/create.err"
    exit 1
fi
if ! grep -F -q -- '--generate-notes' "$GH_ARGV_LOG"; then
    echo "release create omitted --generate-notes"
    cat "$GH_ARGV_LOG"
    exit 1
fi
if grep -E -q '(^|[[:space:]])--notes([[:space:]]|$)' "$GH_ARGV_LOG"; then
    echo "release create passed --notes"
    cat "$GH_ARGV_LOG"
    exit 1
fi

export GH_UPLOAD_FAIL_SIG=1
for view_rc in 0 1; do
    export GH_VIEW_RC="$view_rc"
    sig_status=0
    run_upload "$tmp/sig.out" "$tmp/sig.err" || sig_status=$?
    if [[ "$sig_status" -eq 0 ]]; then
        echo "failed signature upload returned 0 (release view rc $view_rc)"
        exit 1
    fi
    if grep -F -q 'Asset(s) uploaded.' "$tmp/sig.out" "$tmp/sig.err"; then
        echo "success line printed after failed signature upload (release view rc $view_rc)"
        exit 1
    fi
done
unset GH_UPLOAD_FAIL_SIG

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"

export PKGBUILD="$tmp/PKGBUILD"
printf 'pkgname=demo\ninstall=demo.install\n' >| "$PKGBUILD"
aur_print_copy_steps >| "$tmp/copy.out"
if ! grep -F -q 'PKGBUILD, .SRCINFO, and demo.install' "$tmp/copy.out"; then
    echo "closing text omitted the install file"
    cat "$tmp/copy.out"
    exit 1
fi

printf 'pkgname=demo\n' >| "$PKGBUILD"
aur_print_copy_steps >| "$tmp/copy-plain.out"
if ! grep -F -q 'PKGBUILD and .SRCINFO to your local AUR git repository' "$tmp/copy-plain.out"; then
    echo "closing text without install= changed"
    cat "$tmp/copy-plain.out"
    exit 1
fi
if grep -F -q 'demo.install' "$tmp/copy-plain.out"; then
    echo "closing text named an install file that is not in the PKGBUILD"
    cat "$tmp/copy-plain.out"
    exit 1
fi
