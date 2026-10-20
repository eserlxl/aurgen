#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-deploy-e2e.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -f "$tmp/git.err" ]]; then
        echo "--- git stderr ---"
        cat "$tmp/git.err"
    fi
    if [[ -f "$tmp/deploy.err" ]]; then
        echo "--- deploy stderr ---"
        cat "$tmp/deploy.err"
    fi
    if [[ -f "$tmp/bad.err" ]]; then
        echo "--- bad deploy stderr ---"
        cat "$tmp/bad.err"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
printf '#!/bin/bash\nexit 1\n' > "$stub/gpg"
chmod +x "$stub/gh" "$stub/gpg"

repo="$tmp/src"
mkdir -p "$repo"
cp -a "$ROOT/tests/fixtures/tmpcleaner/." "$repo/"
cat >> "$repo/aur/aurgen.install.yaml" << EOF

aur_integration:
  aur_repo_dir: $tmp/aur
  auto_push: false
  commit_message: Update to version {version}
  git_user_name: AURGen Test
  git_user_email: test@example.com
  backup_existing: false
  validate_before_push: false
EOF

git -C "$repo" init -q -b master
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config tag.gpgsign false
git -C "$repo" add -A
git -C "$repo" commit -q -m init
git -C "$repo" tag v9.8.7
git -C "$repo" remote add origin "https://github.com/eserlxl/tmpCleaner.git"

aur_root="$tmp/aur"
git_pkg="$aur_root/linux-tmpcleaner-git"
release_pkg="$aur_root/linux-tmpcleaner"
for dest in "$git_pkg" "$release_pkg"; do
    git init -q -b master "$dest"
    git -C "$dest" config user.email "test@example.com"
    git -C "$dest" config user.name "AURGen Test"
    git -C "$dest" config commit.gpgsign false
done

export PATH="$stub:$PATH"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_STATE_HOME"
unset PKGVER
unset PKGREL

if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n --dry-run git
) >"$tmp/git.out" 2>"$tmp/git.err"; then
    fail "aurgen git failed"
fi

srcinfo="$repo/aur/.SRCINFO"
[[ -f "$srcinfo" ]] || fail "git mode did not write .SRCINFO"
pkgver=$(awk -F ' = ' '/^[[:space:]]*pkgver[[:space:]]*=/ { print $2; exit }' "$srcinfo") || exit 1
pkgrel=$(awk -F ' = ' '/^[[:space:]]*pkgrel[[:space:]]*=/ { print $2; exit }' "$srcinfo") || exit 1
[[ -n "$pkgver" ]] || fail "git mode .SRCINFO has no pkgver"
[[ -n "$pkgrel" ]] || fail "git mode .SRCINFO has no pkgrel"

if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n aur-deploy
) >"$tmp/deploy.out" 2>"$tmp/deploy.err"; then
    fail "aurgen aur-deploy failed"
fi

msg=$(git -C "$git_pkg" log -1 --format=%s) || fail "no commit in linux-tmpcleaner-git"
# Tag v9.8.7 above; the message must carry that version, not one read from .SRCINFO.
[[ "$msg" == *'9.8.7-1'* ]] || fail "commit message [$msg] does not contain 9.8.7-1"
git -C "$git_pkg" show HEAD:PKGBUILD | grep -qx 'pkgname=linux-tmpcleaner-git' || fail "committed PKGBUILD is not the -git package"

if git -C "$release_pkg" rev-parse --verify HEAD >"$tmp/release.head" 2>"$tmp/release.err"; then
    fail "linux-tmpcleaner received a commit"
fi

before=$(git -C "$git_pkg" rev-parse HEAD) || exit 1
grep -E -v '^[[:space:]]*pkgver[[:space:]]*=' "$srcinfo" > "$tmp/srcinfo.nopkgver" || exit 1
cp "$tmp/srcinfo.nopkgver" "$srcinfo" || exit 1
if (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n aur-deploy
) >"$tmp/bad.out" 2>"$tmp/bad.err"; then
    fail "deploy without pkgver succeeded"
fi
if ! grep -F -q ".SRCINFO has no pkgver" "$tmp/bad.err"; then
    fail "missing pkgver did not report an error"
fi
after=$(git -C "$git_pkg" rev-parse HEAD) || exit 1
[[ "$before" == "$after" ]] || fail "failed deploy still committed"
