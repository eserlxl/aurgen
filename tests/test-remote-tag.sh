#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-remote-tag.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
# Scratch-repo commits and tags must never sign with the user's key.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
unset AURGEN_PUSH_TAG

bare="$tmp/origin.git"
repo="$tmp/repo"
git init -q --bare "$bare"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'x\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
git -C "$repo" remote add origin "$bare"
git -C "$repo" tag v1.0.0

export PROJECT_ROOT="$repo"
export PKGVER=1.0.0
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
: >| "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"

if ( aur_require_remote_tag ) >"$tmp/before.out" 2>"$tmp/before.err"; then
    echo "expected failure before the tag is pushed"
    exit 1
fi
grep -F -q "[aur] Tag v1.0.0 is not on origin; push it first: git push origin v1.0.0" "$tmp/before.err" || exit 1

if ! git -C "$repo" push origin v1.0.0 >"$tmp/push.out" 2>"$tmp/push.err"; then
    echo "git push origin v1.0.0 failed"
    cat "$tmp/push.err"
    exit 1
fi

if ! ( aur_require_remote_tag ) >"$tmp/after.out" 2>"$tmp/after.err"; then
    echo "expected success after the tag is on origin"
    cat "$tmp/after.err"
    exit 1
fi

# AURGEN_PUSH_TAG=1 pushes the local tag and continues.
git -C "$repo" -c tag.gpgsign=false tag v1.1.0
PKGVER=1.1.0
export AURGEN_PUSH_TAG=1
if ! ( aur_require_remote_tag ) >"$tmp/flag.out" 2>"$tmp/flag.err"; then
    echo "AURGEN_PUSH_TAG=1 should push the local tag and continue"
    cat "$tmp/flag.err"
    exit 1
fi
grep -F -q "[aur] AURGEN_PUSH_TAG=1: pushing tag v1.1.0 to origin" "$tmp/flag.out" || exit 1
if ! git -C "$bare" rev-parse -q --verify refs/tags/v1.1.0 >/dev/null; then
    echo "AURGEN_PUSH_TAG=1 did not push v1.1.0"
    exit 1
fi

# Unset keeps the hint and does not push.
unset AURGEN_PUSH_TAG
git -C "$repo" -c tag.gpgsign=false tag v1.2.0
PKGVER=1.2.0
if ( aur_require_remote_tag ) >"$tmp/unset.out" 2>"$tmp/unset.err"; then
    echo "expected failure when AURGEN_PUSH_TAG is unset"
    exit 1
fi
grep -F -q "[aur] Tag v1.2.0 is not on origin; push it first: git push origin v1.2.0" "$tmp/unset.err" || exit 1
if git -C "$bare" rev-parse -q --verify refs/tags/v1.2.0 >/dev/null; then
    echo "unset AURGEN_PUSH_TAG pushed v1.2.0"
    exit 1
fi

# A value other than 1 keeps the hint.
export AURGEN_PUSH_TAG=yes
git -C "$repo" -c tag.gpgsign=false tag v1.2.1
PKGVER=1.2.1
if ( aur_require_remote_tag ) >"$tmp/other.out" 2>"$tmp/other.err"; then
    echo "expected failure when AURGEN_PUSH_TAG is not 1"
    exit 1
fi
grep -F -q "[aur] Tag v1.2.1 is not on origin; push it first: git push origin v1.2.1" "$tmp/other.err" || exit 1

# Flag set, but no local tag: same hint, no push.
export AURGEN_PUSH_TAG=1
PKGVER=9.9.9
if ( aur_require_remote_tag ) >"$tmp/missing.out" 2>"$tmp/missing.err"; then
    echo "expected failure when the local tag is missing"
    exit 1
fi
grep -F -q "[aur] Tag v9.9.9 is not on origin; push it first: git push origin v9.9.9" "$tmp/missing.err" || exit 1
if git -C "$bare" rev-parse -q --verify refs/tags/v9.9.9 >/dev/null; then
    echo "missing local tag was pushed"
    exit 1
fi

# A pre-receive hook that exits 1 rejects the push and stops the run.
git -C "$repo" -c tag.gpgsign=false tag v1.3.0
PKGVER=1.3.0
export AURGEN_PUSH_TAG=1
git -C "$bare" config core.hooksPath "$bare/hooks"
printf '%s\n' '#!/bin/sh' 'exit 1' >| "$bare/hooks/pre-receive"
chmod +x "$bare/hooks/pre-receive"
if ( aur_require_remote_tag ) >"$tmp/reject.out" 2>"$tmp/reject.err"; then
    echo "expected failure when origin rejects the tag push"
    exit 1
fi
grep -F -q "[aur] Failed to push tag v1.3.0 to origin" "$tmp/reject.err" || exit 1
if git -C "$bare" rev-parse -q --verify refs/tags/v1.3.0 >/dev/null; then
    echo "rejected push left v1.3.0 on origin"
    exit 1
fi
