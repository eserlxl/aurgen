#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# A leftover .git/index.lock in the AUR clone stops aur-deploy and --rollback with one clear message.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    [[ -n "${2:-}" && -f "$2" ]] && cat "$2"
    exit 1
}

export color_enabled=0 AURGEN_ERROR_LOG="$tmp/err.log" AURGEN_LOG="$tmp/out.log"
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null dry_run=0
export SILVER="" RESET="" YELLOW="" GREEN="" RED="" CYAN=""
mkdir -p "$HOME" "$tmp/proj"
export PKGBUILD="$tmp/proj/PKGBUILD" SRCINFO="$tmp/proj/.SRCINFO" AUR_DIR="$tmp/proj"
printf 'pkgname=demo\npkgver=1.0.0\npkgrel=1\n' > "$PKGBUILD"
printf 'pkgbase = demo\n\tpkgver = 1.0.0\n\tpkgrel = 1\npkgname = demo\n' > "$SRCINFO"
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"
export AUR_REPO_DIR="$tmp/aur" AUR_AUTO_PUSH=false AUR_VALIDATE_BEFORE_PUSH=false

upstream="$tmp/upstream.git"
clone="$AUR_REPO_DIR/demo"
git init -q --bare -b master "$upstream"
git clone -q "$upstream" "$clone" 2>/dev/null
printf 'pkgname=demo\n' > "$clone/PKGBUILD"
git -C "$clone" add PKGBUILD
git -C "$clone" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m init
git -C "$clone" push -q -u origin master
before="$(git -C "$clone" rev-parse HEAD)"

: > "$clone/.git/index.lock"
if ( rollback_aur_repo demo ) >"$tmp/rb.out" 2>"$tmp/rb.err"; then
    fail "rollback ran with a leftover index.lock"
fi
grep -Fq "leftover $clone/.git/index.lock" "$tmp/rb.err" || fail "rollback did not name the leftover index.lock" "$tmp/rb.err"
if ( deploy_to_aur demo ) >"$tmp/dep.out" 2>"$tmp/dep.err"; then
    fail "deploy ran with a leftover index.lock"
fi
grep -Fq "leftover $clone/.git/index.lock" "$tmp/dep.err" || fail "deploy did not name the leftover index.lock" "$tmp/dep.err"
[[ "$(git -C "$clone" rev-parse HEAD)" == "$before" ]] || fail "a locked clone was changed"
[[ "$(cat "$clone/PKGBUILD")" == "pkgname=demo" ]] || fail "a locked clone's PKGBUILD was overwritten"

# Without the lock the same rollback runs (nothing to roll back).
rm -f "$clone/.git/index.lock"
( rollback_aur_repo demo ) >"$tmp/rb2.out" 2>"$tmp/rb2.err" || fail "rollback failed on an unlocked clone" "$tmp/rb2.err"

echo "PASS test-aur-index-lock.sh"
