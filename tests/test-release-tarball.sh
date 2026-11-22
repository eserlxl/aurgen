#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-release-tarball.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config tag.gpgsign false
printf 'tagged\n' > "$repo/src.txt"
printf 'readme\n' > "$repo/README.md"
printf 'cafe\n' > "$repo/café.txt"
git -C "$repo" add src.txt README.md café.txt
git -C "$repo" commit -q -m init
git -C "$repo" tag v1.0.0
printf 'later\n' > "$repo/src.txt"
printf 'extra\n' > "$repo/extra.txt"
git -C "$repo" add src.txt extra.txt
git -C "$repo" commit -q -m later
printf 'dirty\n' > "$repo/src.txt"

export PROJECT_ROOT="$repo"
export LIB_INSTALL_DIR="$ROOT/lib"
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
: > "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/gen-pkgbuild0.sh
source "$ROOT/lib/gen-pkgbuild0.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"
# gen-pkgbuild0.sh enables set -e; this file reports failures itself.
set +e

epoch=$(git -C "$repo" show -s --format=%ct v1.0.0)
export ARCHIVE_MTIME="--mtime=@${epoch}"

out1="$tmp/a.tar.gz"
out2="$tmp/b.tar.gz"
if ! aur_create_tarball v1.0.0 "$out1"; then
    fail "first archive failed" "$AURGEN_ERROR_LOG"
fi
if ! aur_create_tarball v1.0.0 "$out2"; then
    fail "second archive failed" "$AURGEN_ERROR_LOG"
fi
if ! cmp -s "$out1" "$out2"; then
    fail "two runs of the same ref differ"
fi

listing=$(tar -tzf "$out1")
if [[ "$listing" != "café.txt
src.txt" ]]; then
    fail "tarball should be the flat filtered tag, got: ${listing}"
fi

extract="$tmp/extract"
mkdir -p "$extract"
tar -xzf "$out1" -C "$extract"
if [[ "$(cat "$extract/src.txt")" != "tagged" ]]; then
    fail "extracted file is not the tagged content" "$extract/src.txt"
fi
if [[ "$(cat "$extract/café.txt")" != "cafe" ]]; then
    fail "extracted non-ASCII path is not the tagged content" "$extract/café.txt"
fi

filter_pkgbuild_sources() { cat >/dev/null; }
empty="$tmp/empty.tar.gz"
if ! aur_create_tarball v1.0.0 "$empty"; then
    fail "empty filtered archive failed" "$AURGEN_ERROR_LOG"
fi
empty_listing=$(tar -tzf "$empty") || fail "empty filtered archive is not a readable tarball"
if [[ -n "$empty_listing" ]]; then
    fail "filtered-out tree should not be archived, got: ${empty_listing}"
fi

# A failed listing must not become an empty archive that aur signs and uploads.
missing="$tmp/missing.tar.gz"
if aur_create_tarball no-such-ref "$missing" 2>/dev/null; then
    fail "a missing ref should fail the archive"
fi
[[ ! -e "$missing" ]] || fail "a missing ref left an archive behind"
filter_pkgbuild_sources() { cat >/dev/null; return 1; }
failed="$tmp/failed-filter.tar.gz"
if aur_create_tarball v1.0.0 "$failed"; then
    fail "a failing source filter should fail the archive"
fi
[[ ! -e "$failed" ]] || fail "a failing source filter left an archive behind"

# Tracked names are passed to git archive as paths, not pathspecs: a leading ":" is not
# magic, and "*" does not pull in a sibling the filter dropped.
printf 'c\n' > "$repo/:colon.txt"
printf 's\n' > "$repo/star*.txt"
printf 'x\n' > "$repo/starX.txt"
git -C "$repo" add -- ':(literal):colon.txt' ':(literal)star*.txt' starX.txt
git -C "$repo" commit -q -m names
git -C "$repo" tag v2.0.0
filter_pkgbuild_sources() { grep -v -x -e 'starX.txt' -e 'src.txt' -e 'extra.txt' -e 'README.md' -e 'café.txt'; }
names="$tmp/names.tar.gz"
if ! aur_create_tarball v2.0.0 "$names"; then
    fail "archive with literal names failed" "$AURGEN_ERROR_LOG"
fi
names_listing=$(tar -tzf "$names" | LC_ALL=C sort)
[[ "$names_listing" == $':colon.txt\nstar*.txt' ]] || fail "literal names were not archived exactly, got: ${names_listing}"

# mode_aur resolves release refs strictly under refs/tags/ even when branches or worktree paths collide.
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/state" "$tmp/data"
for cmd in makepkg gh gpg updpkgsums; do
    printf '#!/bin/bash\nexit 0\n' > "$stub/$cmd"
    chmod +x "$stub/$cmd"
done
printf '#!/bin/bash\nexit 1\n' > "$stub/curl"
chmod +x "$stub/curl"

run_mode_aur_repo() {
    local target_repo="$1"
    local out_file="$2"
    local err_file="$3"
    (
        unset SOURCE_DATE_EPOCH ARCHIVE_MTIME
        export PATH="$stub:$PATH"
        export XDG_STATE_HOME="$tmp/state"
        export XDG_DATA_HOME="$tmp/data"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$target_repo"
        export AUR_DIR="$target_repo/aur"
        export PKGBUILD0="$target_repo/aur/PKGBUILD.0"
        export PKGBUILD="$target_repo/aur/PKGBUILD"
        export SRCINFO="$target_repo/aur/.SRCINFO"
        export PKGNAME=demo
        export REPO_NAME=demo
        export GH_USER=testuser
        export AURGEN_ERROR_LOG="$tmp/mode-aur.err.log"
        export AURGEN_LOG="$tmp/mode-aur.out.log"
        export AURGEN_MODE=aur
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        export dry_run=1
        export no_wait=1
        export ascii_armor=0
        : >| "$AURGEN_ERROR_LOG"
        : >| "$AURGEN_LOG"
        cd "$target_repo" || exit 1
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config || exit 1
        gen_pkgbuild0 || exit 1
        # shellcheck source=../lib/modes/aur.sh
        source "$ROOT/lib/modes/aur.sh"
        mode_aur
    ) >"$out_file" 2>"$err_file"
}

tag_vs_branch="$tmp/tag-vs-branch"
mkdir -p "$tag_vs_branch/aur"
git -C "$tag_vs_branch" init -q
git -C "$tag_vs_branch" config user.email "t@example.com"
git -C "$tag_vs_branch" config user.name "t"
git -C "$tag_vs_branch" config commit.gpgsign false
git -C "$tag_vs_branch" config tag.gpgsign false
git -C "$tag_vs_branch" remote add origin "https://example.com/testuser/demo.git"
printf 'package:\n  name: demo\n  check: false\n' > "$tag_vs_branch/aur/aurgen.install.yaml"
printf 'demo\n' > "$tag_vs_branch/README.md"
printf 'from-tag\n' > "$tag_vs_branch/src.txt"
git -C "$tag_vs_branch" add README.md src.txt
GIT_AUTHOR_DATE="@1700000100" GIT_COMMITTER_DATE="@1700000100" \
    git -C "$tag_vs_branch" commit -q -m "tag-commit"
git -C "$tag_vs_branch" tag v1.0.0
printf 'from-branch\n' > "$tag_vs_branch/src.txt"
git -C "$tag_vs_branch" add src.txt
GIT_AUTHOR_DATE="@1700000900" GIT_COMMITTER_DATE="@1700000900" \
    git -C "$tag_vs_branch" commit -q -m "branch-commit"
git -C "$tag_vs_branch" branch v1.0.0

if ! run_mode_aur_repo "$tag_vs_branch" "$tmp/tvb.out" "$tmp/tvb.err"; then
    fail "mode_aur failed when refs/tags/v1.0.0 collided with refs/heads/v1.0.0" "$tmp/tvb.err"
fi
if ! grep -Fq "[aur] Using tag v1.0.0 for archiving" "$tmp/tvb.out"; then
    fail "mode_aur did not log short tag v1.0.0 for archiving" "$tmp/tvb.out"
fi
if ! grep -Fq '[aur] Using commit date (epoch "1700000100") of "v1.0.0" for tarball mtime.' "$tmp/tvb.out"; then
    fail "mode_aur did not use refs/tags/v1.0.0 commit epoch with short label" "$tmp/tvb.out"
fi
mkdir -p "$tmp/tvb-extract"
tar -xzf "$tag_vs_branch/aur/demo-1.0.0.tar.gz" -C "$tmp/tvb-extract"
[[ "$(cat "$tmp/tvb-extract/src.txt")" == "from-tag" ]] || fail "mode_aur archived branch v1.0.0 instead of tag v1.0.0" "$tmp/tvb-extract/src.txt"
[[ "$(stat -c %Y "$tmp/tvb-extract/src.txt")" == "1700000100" ]] || fail "tarball mtime did not match tag commit epoch"

untagged_collision="$tmp/untagged-collision"
mkdir -p "$untagged_collision/aur" "$untagged_collision/1.0.0"
git -C "$untagged_collision" init -q
git -C "$untagged_collision" config user.email "t@example.com"
git -C "$untagged_collision" config user.name "t"
git -C "$untagged_collision" config commit.gpgsign false
git -C "$untagged_collision" config tag.gpgsign false
git -C "$untagged_collision" remote add origin "https://example.com/testuser/demo.git"
printf 'package:\n  name: demo\n  check: false\n' > "$untagged_collision/aur/aurgen.install.yaml"
printf '1.0.0\n' > "$untagged_collision/VERSION"
printf 'demo\n' > "$untagged_collision/README.md"
printf 'dir-file\n' > "$untagged_collision/1.0.0/file.txt"
printf 'from-branch\n' > "$untagged_collision/src.txt"
git -C "$untagged_collision" add VERSION README.md 1.0.0/file.txt src.txt
GIT_AUTHOR_DATE="@1700000200" GIT_COMMITTER_DATE="@1700000200" \
    git -C "$untagged_collision" commit -q -m "branch-base"
git -C "$untagged_collision" branch v1.0.0
printf 'from-head\n' > "$untagged_collision/src.txt"
git -C "$untagged_collision" add src.txt
GIT_AUTHOR_DATE="@1700000800" GIT_COMMITTER_DATE="@1700000800" \
    git -C "$untagged_collision" commit -q -m "head-commit"

if ! run_mode_aur_repo "$untagged_collision" "$tmp/uc.out" "$tmp/uc.err"; then
    fail "mode_aur failed on untagged repo with 1.0.0/ directory and v1.0.0 branch" "$tmp/uc.err"
fi
if ! grep -Fq "[aur] Warning: No tag found for version 1.0.0, using HEAD" "$tmp/uc.out"; then
    fail "mode_aur did not warn about falling back to HEAD on untagged repo" "$tmp/uc.out"
fi
mkdir -p "$tmp/uc-extract"
tar -xzf "$untagged_collision/aur/demo-1.0.0.tar.gz" -C "$tmp/uc-extract"
[[ "$(cat "$tmp/uc-extract/src.txt")" == "from-head" ]] || fail "mode_aur did not archive HEAD on untagged repo" "$tmp/uc-extract/src.txt"
[[ "$(stat -c %Y "$tmp/uc-extract/src.txt")" == "1700000800" ]] || fail "untagged fallback mtime did not match HEAD commit epoch"
