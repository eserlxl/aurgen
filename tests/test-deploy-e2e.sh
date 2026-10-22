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
    if [[ -f "$tmp/dry.err" ]]; then
        echo "--- dry-run stderr ---"
        cat "$tmp/dry.err"
    fi
    if [[ -f "$tmp/dry.out" ]]; then
        echo "--- dry-run stdout ---"
        cat "$tmp/dry.out"
    fi
    if [[ -f "$tmp/deploygit.err" ]]; then
        echo "--- deploy-git stderr ---"
        cat "$tmp/deploygit.err"
    fi
    if [[ -f "$tmp/deploygit.out" ]]; then
        echo "--- deploy-git stdout ---"
        cat "$tmp/deploygit.out"
    fi
    if [[ -f "$tmp/local.err" ]]; then
        echo "--- deploy local stderr ---"
        cat "$tmp/local.err"
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
    # A dry run writes aur/dry-run/; deploy needs the real aur/ output.
    "$ROOT/bin/aurgen" -n git
) >"$tmp/git.out" 2>"$tmp/git.err"; then
    fail "aurgen git failed"
fi

if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n --dry-run --deploy git
) >"$tmp/deploygit.out" 2>"$tmp/deploygit.err"; then
    fail "aurgen --dry-run --deploy git failed"
fi
if ! grep -F -q "Dry run: nothing was copied" "$tmp/deploygit.out"; then
    fail "deploy dry-run output has no dry-run notice"
fi
if git -C "$git_pkg" rev-parse --verify HEAD >"$tmp/deploygit.head" 2>"$tmp/deploygit.head.err"; then
    fail "--deploy dry-run created a commit"
fi
if (
    # In the scratch repo: a regressed mode check must not act on the caller's checkout.
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n --deploy local
) >"$tmp/local.out" 2>"$tmp/local.err"; then
    fail "--deploy local succeeded"
fi
grep -F -q -- "--deploy is only valid with aur or git" "$tmp/local.err" || fail "--deploy local was not refused by the mode check"

srcinfo="$repo/aur/.SRCINFO"
[[ -f "$srcinfo" ]] || fail "git mode did not write .SRCINFO"
pkgver=$(awk -F ' = ' '/^[[:space:]]*pkgver[[:space:]]*=/ { print $2; exit }' "$srcinfo") || exit 1
pkgrel=$(awk -F ' = ' '/^[[:space:]]*pkgrel[[:space:]]*=/ { print $2; exit }' "$srcinfo") || exit 1
[[ -n "$pkgver" ]] || fail "git mode .SRCINFO has no pkgver"
[[ -n "$pkgrel" ]] || fail "git mode .SRCINFO has no pkgrel"

if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n --dry-run aur-deploy
) >"$tmp/dry.out" 2>"$tmp/dry.err"; then
    fail "aurgen aur-deploy --dry-run failed"
fi
if ! grep -E -q '^(---|\+\+\+) .*PKGBUILD' "$tmp/dry.out"; then
    fail "dry-run output has no PKGBUILD diff header"
fi
if ! grep -F -q "Update to version ${pkgver}-${pkgrel}" "$tmp/dry.out"; then
    fail "dry-run did not print the commit message"
fi
if grep -F -q "Successfully deployed" "$tmp/dry.out"; then
    fail "dry-run reported a successful deploy"
fi
if grep -F -q "has been committed" "$tmp/dry.out"; then
    fail "dry-run reported a commit"
fi
if ! grep -F -q "Dry run" "$tmp/dry.out"; then
    fail "dry-run output has no dry-run notice"
fi
if git -C "$git_pkg" rev-parse --verify HEAD >"$tmp/dry.head" 2>"$tmp/dry.head.err"; then
    fail "dry-run created a commit"
fi
if [[ -n "$(git -C "$git_pkg" status --porcelain --untracked-files=all)" ]]; then
    fail "dry-run changed files in the AUR clone"
fi

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
cp "$srcinfo" "$tmp/srcinfo.good" || exit 1
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
cp "$tmp/srcinfo.good" "$srcinfo" || exit 1

# A co-maintainer pushes to the AUR from a second clone; ours is now behind.
upstream="$tmp/upstream.git"
other="$tmp/other"
{
    git init -q --bare -b master "$upstream" &&
    git -C "$git_pkg" remote add origin "$upstream" &&
    git -C "$git_pkg" push -q -u origin master &&
    git clone -q "$upstream" "$other" &&
    git -C "$other" config user.email "co@example.com" &&
    git -C "$other" config user.name "Co Maintainer" &&
    git -C "$other" config commit.gpgsign false &&
    printf 'co-maintainer note\n' > "$other/NOTES" &&
    git -C "$other" add NOTES &&
    git -C "$other" commit -q -m "Co-maintainer update" &&
    git -C "$other" push -q origin master
} 2>"$tmp/upstream.err" || { cat "$tmp/upstream.err"; fail "upstream setup failed"; }
# A changed PKGBUILD: a deploy that copied it would dirty the clone.
printf '# local change\n' >> "$repo/aur/PKGBUILD"
before=$(git -C "$git_pkg" rev-parse HEAD) || exit 1
if (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n aur-deploy
) >"$tmp/behind.out" 2>"$tmp/behind.err"; then
    fail "deploy from a clone behind origin succeeded"
fi
grep -F -q "AUR clone $git_pkg is behind origin; run git -C $git_pkg pull --ff-only, then re-run aurgen aur" "$tmp/behind.err" \
    || { cat "$tmp/behind.err"; fail "behind clone was not refused with the pull hint"; }
after=$(git -C "$git_pkg" rev-parse HEAD) || exit 1
[[ "$before" == "$after" ]] || fail "behind clone still committed"
[[ -z "$(git -C "$git_pkg" status --porcelain --untracked-files=all)" ]] || fail "behind clone worktree was changed"

# Once pulled, the clone deploys on top of origin.
git -C "$git_pkg" pull -q --ff-only 2>"$tmp/pull.err" || { cat "$tmp/pull.err"; fail "pull --ff-only failed"; }
if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n aur-deploy
) >"$tmp/uptodate.out" 2>"$tmp/uptodate.err"; then
    cat "$tmp/uptodate.err"
    fail "deploy from an up-to-date clone failed"
fi
git -C "$git_pkg" merge-base --is-ancestor origin/master HEAD || fail "up-to-date deploy did not build on origin"
git -C "$git_pkg" show HEAD:PKGBUILD | grep -qx '# local change' || fail "up-to-date deploy did not commit the PKGBUILD"
if grep -F -q "Cannot fetch origin" "$tmp/uptodate.out"; then
    fail "up-to-date deploy warned about fetch"
fi

# Offline: the fetch fails, a warning is printed, and the deploy goes on.
git -C "$git_pkg" remote set-url origin "$tmp/missing.git" || exit 1
printf '# offline change\n' >> "$repo/aur/PKGBUILD"
if ! (
    cd "$repo" || exit 1
    "$ROOT/bin/aurgen" -n aur-deploy
) >"$tmp/offline.out" 2>"$tmp/offline.err"; then
    cat "$tmp/offline.err"
    fail "deploy with a failing fetch was refused"
fi
grep -F -q "Cannot fetch origin in $git_pkg" "$tmp/offline.out" || { cat "$tmp/offline.out"; fail "failing fetch did not warn"; }
git -C "$git_pkg" show HEAD:PKGBUILD | grep -qx '# offline change' || fail "offline deploy did not commit the PKGBUILD"
