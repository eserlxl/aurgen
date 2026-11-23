#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aur-push refuses a clone that has diverged from origin, and still pushes one that is only ahead.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    [[ -n "${2:-}" && -f "$2" ]] && cat "$2"
    exit 1
}

export color_enabled=0 AURGEN_ERROR_LOG="$tmp/err.log" AURGEN_LOG="$tmp/out.log" LIB_INSTALL_DIR="$ROOT/lib"
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null dry_run=0
export SILVER="" RESET="" YELLOW="" GREEN="" RED="" CYAN=""
mkdir -p "$HOME" "$tmp/proj/aur"
export AUR_DIR="$tmp/proj/aur" SRCINFO="$tmp/proj/aur/.SRCINFO"
printf 'pkgbase = demo\n\tpkgver = 1.0.0\n\tpkgrel = 1\npkgname = demo\n' > "$SRCINFO"
printf 'aur_integration:\n  aur_repo_dir: %s\n  validate_before_push: false\n' "$tmp/aur" > "$AUR_DIR/aurgen.install.yaml"
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/modes/aur-deploy.sh
source "$ROOT/lib/modes/aur-deploy.sh"

commit_in() {
    git -C "$1" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m "$2"
}

upstream="$tmp/upstream.git"
clone="$tmp/aur/demo"
other="$tmp/other"
git init -q --bare -b master "$upstream"
git clone -q "$upstream" "$clone" 2>/dev/null
printf 'pkgname=demo\n' > "$clone/PKGBUILD"
git -C "$clone" add PKGBUILD && commit_in "$clone" init
git -C "$clone" push -q -u origin master

# Only ahead: the push goes through.
printf '# local 1\n' >> "$clone/PKGBUILD"
git -C "$clone" add PKGBUILD && commit_in "$clone" "local 1"
( mode_aur_push ) >"$tmp/ahead.out" 2>"$tmp/ahead.err" || fail "aur-push refused a clone that is only ahead" "$tmp/ahead.err"
[[ "$(git -C "$upstream" rev-parse master)" == "$(git -C "$clone" rev-parse HEAD)" ]] || fail "the ahead clone was not pushed"

# A co-maintainer pushes; the clone then gets its own commit: diverged.
git clone -q "$upstream" "$other" 2>/dev/null
printf 'note\n' > "$other/NOTES"
git -C "$other" add NOTES && commit_in "$other" "co-maintainer"
git -C "$other" push -q origin master
printf '# local 2\n' >> "$clone/PKGBUILD"
git -C "$clone" add PKGBUILD && commit_in "$clone" "local 2"
before="$(git -C "$clone" rev-parse HEAD)"
upstream_before="$(git -C "$upstream" rev-parse master)"
if ( mode_aur_push ) >"$tmp/div.out" 2>"$tmp/div.err"; then
    fail "aur-push pushed from a diverged clone"
fi
grep -Fq "has diverged from origin" "$tmp/div.err" || fail "a diverged clone was not reported" "$tmp/div.err"
grep -Fq "aurgen aur-deploy --rollback" "$tmp/div.err" || fail "the diverged clone hint does not name the rollback" "$tmp/div.err"
[[ "$(git -C "$clone" rev-parse HEAD)" == "$before" ]] || fail "the diverged clone's HEAD changed"
[[ "$(git -C "$upstream" rev-parse master)" == "$upstream_before" ]] || fail "the diverged push reached origin"

# deploy_to_aur names the rollback for the same diverged clone, not a pull that would abort.
export PKGBUILD="$tmp/proj/aur/PKGBUILD"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"
load_aur_integration_config >/dev/null 2>&1 || fail "load_aur_integration_config failed"
printf 'pkgname=demo\npkgver=1.0.0\npkgrel=1\n' > "$PKGBUILD"
if ( deploy_to_aur demo ) >"$tmp/dep-div.out" 2>"$tmp/dep-div.err"; then
    fail "deploy_to_aur ran on a diverged clone"
fi
grep -Fq "has diverged from origin" "$tmp/dep-div.err" || fail "deploy_to_aur did not report the diverged clone" "$tmp/dep-div.err"
grep -Fq "aurgen aur-deploy --rollback" "$tmp/dep-div.err" || fail "deploy_to_aur did not name the rollback" "$tmp/dep-div.err"

echo "PASS test-aur-push-diverged.sh"
