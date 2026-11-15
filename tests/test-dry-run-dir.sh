#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# A dry run writes under aur/dry-run/ and leaves published files byte-identical.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-dry-run.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" GNUPGHOME="$tmp/gnupg"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
mkdir -m 700 "$GNUPGHOME"
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nif [[ "${1:-}" == --printsrcinfo ]]; then\n    printf "pkgbase = tmpcleaner\\n"\nfi\nexit 0\n' > "$stub/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 0\n' > "$stub/curl"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/makepkg" "$stub/updpkgsums" "$stub/curl" "$stub/gh"

repo="$tmp/repo"
mkdir -p "$repo"
cp -a "$ROOT/tests/fixtures/tmpcleaner/." "$repo/"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
printf '*.txt text\n' > "$repo/.gitattributes"
cp "$repo/.gitattributes" "$tmp/gitattributes.orig"
git -C "$repo" add -A
git -C "$repo" commit -q -m init
git -C "$repo" remote add origin "https://github.com/eserlxl/tmpCleaner.git"

printf 'published pkgbuild\n' > "$repo/aur/PKGBUILD"
printf 'published srcinfo\n' > "$repo/aur/.SRCINFO"
cp "$repo/aur/PKGBUILD" "$tmp/PKGBUILD.orig"
cp "$repo/aur/.SRCINFO" "$tmp/SRCINFO.orig"

export PATH="$stub:$PATH"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_STATE_HOME"

run_dry() {
    local name="$1"
    shift
    if ! (cd "$repo" && "$ROOT/bin/aurgen" -n "$@") >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail "dry-run $name failed" "$tmp/$name.err"
    fi
}

assert_no_aur_templates() {
    cmp -s "$tmp/gitattributes.orig" "$repo/.gitattributes" || fail ".gitattributes changed during dry-run/test initialization" "$repo/.gitattributes"
    local f
    for f in PKGBUILD.0 PKGBUILD.0.bak .PKGBUILD.0.stamp PKGBUILD.HEADER aurgen.install.yaml.example linux-tmpcleaner.install; do
        [[ ! -e "$repo/aur/$f" ]] || fail "initialization created aur/$f" "$repo/aur/$f"
    done
}

assert_published() {
    cmp -s "$tmp/PKGBUILD.orig" "$repo/aur/PKGBUILD" || fail "published PKGBUILD changed" "$repo/aur/PKGBUILD"
    cmp -s "$tmp/SRCINFO.orig" "$repo/aur/.SRCINFO" || fail "published .SRCINFO changed" "$repo/aur/.SRCINFO"
    assert_no_aur_templates
    [[ -f "$repo/aur/dry-run/PKGBUILD" ]] || fail "aur/dry-run/PKGBUILD was not written"
    [[ -f "$repo/aur/dry-run/PKGBUILD.0" ]] || fail "aur/dry-run/PKGBUILD.0 was not written"
    [[ -f "$repo/aur/dry-run/.PKGBUILD.0.stamp" ]] || fail "aur/dry-run/.PKGBUILD.0.stamp was not written"
    [[ -s "$repo/aur/dry-run/.SRCINFO" ]] || fail "aur/dry-run/.SRCINFO was not written or is empty"
    grep -qF 'pkgbase = ' "$repo/aur/dry-run/.SRCINFO" || fail "aur/dry-run/.SRCINFO is missing pkgbase"
    local stray
    stray=$(find "$repo" -path "$repo/aur/dry-run" -prune -o -type f \( -name '*.tar.gz' -o -name '*.tar.gz.sig' -o -name '*.tar.gz.asc' -o -name '*.pkg.tar.*' \) -print)
    [[ -z "$stray" ]] || fail "generated archive outside aur/dry-run/: $stray"
}

run_dry local --dry-run local
assert_published
run_dry git --dry-run git
assert_published

# Test mode initialization must not create or mutate templates or .gitattributes.
if ! (
    cd "$repo" || exit 1
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AURGEN_ERROR_LOG="$tmp/test-init.errlog"
    export AURGEN_LOG="$tmp/test-init.log"
    export AURGEN_MODE=test
    export dry_run=0
    source "$ROOT/lib/init.sh"
    aurgen_init
) >"$tmp/test-init.out" 2>"$tmp/test-init.err"; then
    fail "AURGEN_MODE=test aurgen_init failed" "$tmp/test-init.err"
fi
assert_no_aur_templates

# Stale aur/PKGBUILD.0 + stamp must be read-only under dry-run: no PKGBUILD.0.bak or overwrite in aur/.
cat > "$repo/aur/PKGBUILD.0" <<'EOF'
pkgname=linux-tmpcleaner
pkgver=1.0.0
pkgrel=1
pkgdesc='stale template'
arch=('any')
url='https://github.com/eserlxl/tmpCleaner'
license=('MIT')
source=('tmpcleaner')
EOF
printf 'stale-stamp\n' > "$repo/aur/.PKGBUILD.0.stamp"
cp "$repo/aur/PKGBUILD.0" "$tmp/PKGBUILD0.stale"
rm -rf "$repo/aur/dry-run"

run_dry stale --dry-run local
cmp -s "$tmp/PKGBUILD0.stale" "$repo/aur/PKGBUILD.0" || fail "dry-run modified stale aur/PKGBUILD.0"
[[ ! -e "$repo/aur/PKGBUILD.0.bak" ]] || fail "dry-run wrote aur/PKGBUILD.0.bak"
[[ "$(<"$repo/aur/.PKGBUILD.0.stamp")" == "stale-stamp" ]] || fail "dry-run overwrote aur/.PKGBUILD.0.stamp"
[[ ! -e "$repo/aur/linux-tmpcleaner.install" ]] || fail "stale dry-run wrote aur/linux-tmpcleaner.install"
cmp -s "$tmp/gitattributes.orig" "$repo/.gitattributes" || fail "stale dry-run modified .gitattributes"
[[ -f "$repo/aur/dry-run/PKGBUILD.0" ]] || fail "stale dry-run did not write preview PKGBUILD.0"
grep -qF 'pkgname=linux-tmpcleaner' "$repo/aur/dry-run/PKGBUILD.0" || fail "stale dry-run preview PKGBUILD.0 missing pkgname" "$repo/aur/dry-run/PKGBUILD.0"
! grep -qF "pkgdesc='stale template'" "$repo/aur/dry-run/PKGBUILD.0" || fail "stale dry-run reused stale pkgdesc" "$repo/aur/dry-run/PKGBUILD.0"
