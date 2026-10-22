#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-aur-status.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export color_enabled=0
export DEBUG_LEVEL=0

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

log() { :; }

# get_aur_status ends in aur_web_version, which curls the AUR RPC; never reach it.
stub="$tmp/bin"
mkdir -p "$stub"
PATH="$stub:$PATH"

install_curl_stub() {
    printf '%s\n' '#!/bin/bash' "$1" >| "$stub/curl"
    chmod +x "$stub/curl"
}
install_curl_stub 'exit 1'

export AUR_REPO_DIR="$tmp/aur"
repo="$AUR_REPO_DIR/demopkg"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'hello\n' > "$repo/PKGBUILD"
git -C "$repo" add PKGBUILD
git -C "$repo" commit -q -m init
printf 'changed\n' > "$repo/PKGBUILD"

if ! get_aur_status demopkg >|"$tmp/status.out"; then
    echo "modified repository status returned non-zero"
    exit 1
fi
if ! grep -q '^  .*PKGBUILD' "$tmp/status.out"; then
    echo "modified file line is not indented by two spaces"
    cat "$tmp/status.out"
    exit 1
fi

if get_aur_status missingpkg >|"$tmp/missing.out"; then
    echo "missing repository returned 0"
    exit 1
fi
if ! grep -F -q 'Status: Repository does not exist' "$tmp/missing.out"; then
    echo "missing repository status text changed"
    cat "$tmp/missing.out"
    exit 1
fi
if grep -q '^Version:' "$tmp/status.out"; then
    echo "version line printed without .SRCINFO"
    cat "$tmp/status.out"
    exit 1
fi

write_srcinfo() {
    local path="$1"
    local pkgver="$2"
    local pkgrel="$3"
    printf 'pkgbase = demopkg\n\tpkgver = %s\n\tpkgrel = %s\n' "$pkgver" "$pkgrel" >|"$path"
}

export SRCINFO="$tmp/generated.SRCINFO"
write_srcinfo "$SRCINFO" "1.2.3" "1"
write_srcinfo "$repo/.SRCINFO" "1.2.3" "1"

if ! get_aur_status demopkg >|"$tmp/same.out"; then
    echo "matching versions returned non-zero"
    exit 1
fi
if ! grep -F -q 'Version: AUR 1.2.3-1, generated 1.2.3-1 (up to date)' "$tmp/same.out"; then
    echo "matching versions did not report up to date"
    cat "$tmp/same.out"
    exit 1
fi

write_srcinfo "$SRCINFO" "1.2.4" "1"
if ! get_aur_status demopkg >|"$tmp/diff.out"; then
    echo "differing versions returned non-zero"
    exit 1
fi
if ! grep -F -q 'Version: AUR 1.2.3-1, generated 1.2.4-1 (deploy pending)' "$tmp/diff.out"; then
    echo "differing versions did not report deploy pending"
    cat "$tmp/diff.out"
    exit 1
fi


assert_web_line() {
    local name="$1"
    local line="$2"
    if ! get_aur_status demopkg >|"$tmp/$name.out"; then
        echo "$name returned non-zero"
        exit 1
    fi
    if ! grep -F -q "$line" "$tmp/$name.out"; then
        echo "$name did not print: $line"
        cat "$tmp/$name.out"
        exit 1
    fi
}

install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\"}]}'"
assert_web_line web-version 'AUR web: 1.2.3-1'

if get_aur_status missingpkg >|"$tmp/missing-web.out"; then
    echo "missing repository with web version returned 0"
    exit 1
fi
if ! grep -F -q 'AUR web: 1.2.3-1' "$tmp/missing-web.out"; then
    echo "missing repository did not print AUR web version"
    cat "$tmp/missing-web.out"
    exit 1
fi

install_curl_stub "printf '%s\n' '{\"resultcount\":0,\"results\":[]}'"
assert_web_line web-empty 'AUR web: not published'

install_curl_stub 'exit 1'
assert_web_line web-fail 'AUR web: unavailable'
