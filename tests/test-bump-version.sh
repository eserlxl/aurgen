#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-bump.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
unset GIT_DIR GIT_WORK_TREE

fail() {
    printf '%s\n' "$1"
    exit 1
}

repo="$tmp/repo with spaces and 'quote"
script="$repo/scripts/bump-version.sh"
out="$tmp/out"
err="$tmp/err"
mkdir -p "$repo/scripts"
cp "$ROOT/scripts/bump-version.sh" "$script"
chmod +x "$script"
printf '1.2.3\n' > "$repo/VERSION"

git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config tag.gpgsign false
git -C "$repo" add scripts/bump-version.sh VERSION
git -C "$repo" commit -q -m init

run() {
    : >| "$out"
    : >| "$err"
    bash "$script" "$@" >|"$out" 2>|"$err"
    status=$?
}

expect_status() {
    local label="$1"
    local want="$2"
    if [[ "$status" -ne "$want" ]]; then
        fail "${label}: exit ${status}, want ${want} ($(cat "$err"))"
    fi
}

expect_file() {
    local label="$1"
    local path="$2"
    local text="$3"
    printf '%s\n' "$text" >| "$tmp/expect"
    if ! cmp -s "$tmp/expect" "$path"; then
        fail "${label}: file mismatch ($(cat "$path"))"
    fi
}

expect_stdout() {
    local label="$1"
    local text="$2"
    printf '%s\n' "$text" >| "$tmp/expect"
    if ! cmp -s "$tmp/expect" "$out"; then
        fail "${label}: stdout [$(cat "$out")]"
    fi
}

expect_stderr_has() {
    local label="$1"
    local needle="$2"
    if [[ "$(cat "$err")" != *"$needle"* ]]; then
        fail "${label}: stderr [$(cat "$err")]"
    fi
}

set_version() {
    local v="$1"
    git -C "$repo" reset -q --hard HEAD
    git -C "$repo" clean -q -fd
    printf '%s\n' "$v" >| "$repo/VERSION"
    git -C "$repo" add -- VERSION
    if [[ -n "$(git -C "$repo" status --porcelain -- VERSION)" ]]; then
        git -C "$repo" commit -q -m "version ${v}"
    fi
}

release_text() {
    local from="$1"
    local to="$2"
    local branch="${3:-main}"
    printf '%s -> %s\ngit -C %q commit -m "chore: release v%s" -- VERSION\ngit tag -a v%s -m "v%s"\ngit push origin %s v%s' \
        "$from" "$to" "${script%/scripts/bump-version.sh}" "$to" "$to" "$to" "$branch" "$to"
}

check_bump() {
    local label="$1"
    local from="$2"
    local arg="$3"
    local to="$4"
    local head
    set_version "$from"
    head="$(git -C "$repo" rev-parse HEAD)"
    run "$arg"
    expect_status "$label" 0
    if [[ -n "$(cat "$err")" ]]; then
        fail "${label}: unexpected stderr ($(cat "$err"))"
    fi
    expect_stdout "$label" "$(release_text "$from" "$to" "${5:-main}")"
    expect_file "$label" "$repo/VERSION" "$to"
    if [[ "$(git -C "$repo" rev-parse HEAD)" != "$head" ]]; then
        fail "${label}: created a commit"
    fi
    if [[ -n "$(git -C "$repo" tag --list)" ]]; then
        fail "${label}: created a tag"
    fi
}

check_bump patch 1.2.3 patch 1.2.4
(
    cd "$repo/scripts" || exit 1
    check_bump "from scripts directory" 1.2.3 patch 1.2.4
    hint="$(sed -n '2p' "$out")"
    bash -c "${hint/ commit / commit --dry-run }" >| "$out" 2>| "$err" || exit 1
) || fail "from scripts directory: commit hint failed"
check_bump "patch rollover" 1.2.9 patch 1.2.10
check_bump minor 1.2.3 minor 1.3.0
check_bump "minor rollover" 1.9.0 minor 1.10.0
check_bump major 1.2.3 major 2.0.0
check_bump explicit 1.9.0 1.10.0 1.10.0

git -C "$repo" checkout -q -b feature
check_bump "feature branch" 1.2.3 patch 1.2.4 feature
git -C "$repo" checkout -q -b 'rel;x'
check_bump "shell metacharacter branch" 1.2.3 patch 1.2.4 'rel\;x'
git -C "$repo" checkout -q --detach
check_bump "detached HEAD" 1.2.3 patch 1.2.4
set_version 1.2.3
git -C "$repo" checkout -q main

set_version 1.2.3
run patch --dry-run
expect_status dry-run 0
expect_stdout dry-run "1.2.3 -> 1.2.4"
expect_file dry-run "$repo/VERSION" "1.2.3"
if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    fail "dry-run: wrote the work tree"
fi

set_version 1.2.3
printf 'noise\n' > "$repo/noise.txt"
run patch
expect_status dirty 1
expect_stderr_has dirty "dirty"
expect_file dirty "$repo/VERSION" "1.2.3"

ALLOW_DIRTY=1 run patch
expect_status ALLOW_DIRTY 0
expect_stdout ALLOW_DIRTY "$(release_text 1.2.3 1.2.4)"
expect_file ALLOW_DIRTY "$repo/VERSION" "1.2.4"

set_version 1.2.3
for bad in 01.2.3 1.02.3 1.2.03 1.2 v1.2.3 1.2.3.4; do
    set_version "$bad"
    run patch
    expect_status "invalid current ${bad}" 1
    expect_stderr_has "invalid current ${bad}" "invalid current version"
    expect_file "invalid current ${bad}" "$repo/VERSION" "$bad"
done

set_version 1.2.3
for bad in 01.2.4 1.2.03 foo 1.2 1.2.3.4; do
    run "$bad"
    expect_status "invalid explicit ${bad}" 1
    expect_stderr_has "invalid explicit ${bad}" "invalid version"
    expect_file "invalid explicit ${bad}" "$repo/VERSION" "1.2.3"
done

run 1.2.3
expect_status "non-increasing equal" 1
expect_stderr_has "non-increasing equal" "not greater"
expect_file "non-increasing equal" "$repo/VERSION" "1.2.3"

run 1.2.2
expect_status "non-increasing lower" 1
expect_stderr_has "non-increasing lower" "not greater"

set_version 1.10.0
run 1.9.0
expect_status "non-increasing numeric" 1
expect_stderr_has "non-increasing numeric" "not greater"
expect_file "non-increasing numeric" "$repo/VERSION" "1.10.0"

set_version 1.2.3
git -C "$repo" tag v1.2.4
run patch
expect_status "existing tag" 1
expect_stderr_has "existing tag" "tag v1.2.4 already exists"
expect_file "existing tag" "$repo/VERSION" "1.2.3"

plain="$tmp/plain"
mkdir -p "$plain/scripts"
cp "$script" "$plain/scripts/bump-version.sh"
printf '1.2.3\n' > "$plain/VERSION"
script="$plain/scripts/bump-version.sh"
run patch
expect_status "not a work tree" 0
expect_stdout "not a work tree" "$(release_text 1.2.3 1.2.4)"
expect_file "not a work tree" "$plain/VERSION" "1.2.4"

script="$repo/scripts/bump-version.sh"
run -h
expect_status help 0
if [[ "$(cat "$out")" != Usage:* ]]; then
    fail "help: stdout [$(cat "$out")]"
fi
run --help
expect_status "help long" 0
run
expect_status "bad args none" 1
run patch extra
expect_status "bad args extra" 1
run --dry-run patch
expect_status "bad args order" 1
