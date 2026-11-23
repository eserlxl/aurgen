#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# push_to_aur refuses a clone whose push URL is the anonymous https AUR URL.

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
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

export AUR_REPO_DIR="$tmp/aur"
export AUR_VALIDATE_BEFORE_PUSH=false
clone="$AUR_REPO_DIR/demo"
mkdir -p "$clone"
git -C "$clone" init -q -b master
printf 'pkgname=demo\n' > "$clone/PKGBUILD"
git -C "$clone" add PKGBUILD
git -C "$clone" -c user.email=t@example.com -c user.name=t commit -q -m init

# An https origin with no pushurl: refused before any push, with the set-url fix.
git -C "$clone" remote add origin "https://aur.archlinux.org/demo.git"
if push_to_aur demo >"$tmp/https.out" 2>"$tmp/https.err"; then
    fail "push_to_aur accepted the anonymous https push URL"
fi
grep -Fq "remote set-url --push origin ssh://aur@aur.archlinux.org/demo.git" "$tmp/https.err" || \
    fail "push_to_aur did not name the set-url fix" "$tmp/https.err"

# A push URL that is not the https AUR URL is used (a local bare repo stands in for the AUR).
upstream="$tmp/upstream.git"
git init -q --bare -b master "$upstream"
git -C "$clone" remote set-url --push origin "$upstream"
push_to_aur demo >"$tmp/ok.out" 2>"$tmp/ok.err" || fail "push_to_aur refused a non-https push URL" "$tmp/ok.err"
[[ "$(git -C "$upstream" rev-parse master)" == "$(git -C "$clone" rev-parse HEAD)" ]] || fail "the push did not reach the push URL"

echo "PASS test-aur-push-url.sh"
