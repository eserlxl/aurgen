#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# Bump VERSION and print the release commands without running them.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
version_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

usage() {
    printf 'Usage: scripts/bump-version.sh <major|minor|patch|X.Y.Z> [--dry-run]\n'
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Numeric compare: "1.10.0" is greater than "1.9.0".
version_gt() {
    local left_major left_minor left_patch right_major right_minor right_patch
    IFS=. read -r left_major left_minor left_patch <<< "$1"
    IFS=. read -r right_major right_minor right_patch <<< "$2"
    if (( left_major != right_major )); then
        (( left_major > right_major ))
        return
    fi
    if (( left_minor != right_minor )); then
        (( left_minor > right_minor ))
        return
    fi
    (( left_patch > right_patch ))
}

dry=0
case $# in
    1)
        if [[ "$1" == "-h" || "$1" == "--help" ]]; then
            usage
            exit 0
        fi
        spec="$1"
        ;;
    2)
        if [[ "$2" != "--dry-run" ]]; then
            usage >&2
            exit 1
        fi
        dry=1
        spec="$1"
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac

if [[ ! -f "$ROOT/VERSION" ]]; then
    die "VERSION not found in ${ROOT}"
fi

current="$(<"$ROOT/VERSION")"
if [[ ! "$current" =~ $version_re ]]; then
    die "invalid current version: ${current}"
fi

IFS=. read -r major minor patch <<< "$current"
case "$spec" in
    major)
        target="$((major + 1)).0.0"
        ;;
    minor)
        target="${major}.$((minor + 1)).0"
        ;;
    patch)
        target="${major}.${minor}.$((patch + 1))"
        ;;
    *)
        if [[ ! "$spec" =~ $version_re ]]; then
            die "invalid version: ${spec}"
        fi
        target="$spec"
        ;;
esac

if ! version_gt "$target" "$current"; then
    die "target ${target} is not greater than current ${current}"
fi

# A directory that is not a git work tree has no dirty state or tags to refuse.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "${ALLOW_DIRTY:-}" != "1" ]]; then
        porcelain="$(git -C "$ROOT" status --porcelain)"
        if [[ -n "$porcelain" ]]; then
            die "git tree is dirty (set ALLOW_DIRTY=1 to override)"
        fi
    fi
    if git -C "$ROOT" rev-parse --verify --quiet "refs/tags/v${target}" >/dev/null 2>&1; then
        die "tag v${target} already exists"
    fi
fi

if [[ "$dry" -eq 0 ]]; then
    printf '%s\n' "$target" > "$ROOT/VERSION"
fi

printf '%s -> %s\n' "$current" "$target"
if [[ "$dry" -eq 0 ]]; then
    branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch=main
    if [[ "$branch" == HEAD ]]; then
        branch=main
    fi
    printf 'git commit -m "chore: release v%s" -- VERSION\n' "$target"
    printf 'git tag -a v%s -m "v%s"\n' "$target" "$target"
    printf 'git push origin %s v%s\n' "$branch" "$target"
fi
