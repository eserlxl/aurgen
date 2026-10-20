#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# --dry-run must not rewrite lib/tool-mapping.sh.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-update-mapping.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$repo" "$stub"
cp -a "$ROOT/scripts" "$repo/scripts"
cp -a "$ROOT/lib" "$repo/lib"

# A real expand queries packages. Stubs keep that off the host if dry-run regresses.
cat > "$stub/pacman" << 'EOF'
#!/bin/bash
printf '/usr/bin/%s is owned by core/dryrun-pkg 1.0-1\n' "${2##*/}"
EOF
cat > "$stub/expac" << 'EOF'
#!/bin/bash
printf 'dryrun-pkg\n'
EOF
chmod +x "$stub/pacman" "$stub/expac"

mapping="$repo/lib/tool-mapping.sh"
before="$tmp/before"
cp "$mapping" "$before"

shared="/tmp/aurgen-mapping"
shared_before=0
if [[ -e "$shared" ]]; then
    shared_before=1
fi
export TMPDIR="$tmp"

run_dry() {
    local command="$1"
    if ! (
        export PATH="$stub:$PATH"
        "$repo/scripts/update-mapping" --dry-run "$command"
    ) >"$tmp/out" 2>"$tmp/err"; then
        fail "dry-run $command failed" "$tmp/err"
    fi
    if ! grep -q 'DRY RUN' "$tmp/out"; then
        fail "dry-run $command did not say what it would run" "$tmp/out"
    fi
    if ! cmp -s "$before" "$mapping"; then
        fail "dry-run $command modified lib/tool-mapping.sh"
    fi
}

run_dry expand
run_dry clean
run_dry workflow

if ! "$repo/scripts/update-mapping" --help >"$tmp/help" 2>"$tmp/err"; then
    fail "help failed" "$tmp/err"
fi
if grep -q -- '--force' "$tmp/help"; then
    fail "usage still documents --force"
fi

shared_after=0
if [[ -e "$shared" ]]; then
    shared_after=1
fi
if [[ "$shared_before" -ne "$shared_after" ]]; then
    fail "test changed /tmp/aurgen-mapping"
fi
if [[ ! -d "$tmp/aurgen-mapping" ]]; then
    fail "mapping scratch is missing from the test temp dir"
fi
scratch="$(realpath "$tmp/aurgen-mapping")"
root_tmp="$(realpath "$tmp")"
case "$scratch" in
    "$root_tmp"/*) ;;
    *) fail "mapping scratch is outside the trapped dir" ;;
esac
