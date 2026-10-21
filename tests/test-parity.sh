#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# The three maintained packages regenerate from package: keys plus detection.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-parity.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"
# A decoy description proves package.description replaces what gh returns.
cat > "$stub/gh" <<'EOF'
#!/bin/bash
if [[ "${1:-} ${2:-}" == "repo view" ]]; then
    printf '%s\n' "decoy description from gh"
fi
exit 0
EOF
printf '#!/bin/bash\nexit 1\n' > "$stub/gpg"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/gh" "$stub/gpg" "$stub/makepkg"

fail() {
    echo "$1"
    exit 1
}

new_repo() {
    local name="$1"
    local origin="$2"
    local repo="$tmp/${3:-$name}"
    mkdir -p "$repo"
    cp -a "$ROOT/tests/fixtures/$name/." "$repo/"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" config commit.gpgsign false
    git -C "$repo" remote add origin "$origin"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

generate() {
    local repo="$1"
    local name="$2"
    if ! (
        cd "$repo" || exit 1
        unset GPG_KEY_ID
        origin="$(git config --get remote.origin.url)" || exit 1
        # shellcheck disable=SC2034 # gen_pkgbuild0 reads REPO_NAME for url=
        REPO_NAME="$(basename "${origin%.git}")"
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config || exit 1
        # shellcheck disable=SC2153 # PKG_NAME comes from load_aurgen_config
        [[ "$PKG_NAME" == "$name" ]] || exit 1
        # shellcheck disable=SC2034 # gen_pkgbuild0 reads PKGNAME
        PKGNAME="$PKG_NAME"
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
        echo "gen_pkgbuild0 failed for $name"
        cat "$tmp/gen.err"
        exit 1
    fi
}

# errexit does not apply inside an if condition, so every check exits explicitly.
# shellcheck disable=SC1090,SC2154
source_pkg() {
    local pkg="$1"
    bash -n "$pkg" || { echo "bash -n failed: $pkg"; exit 1; }
    # shellcheck disable=SC1090
    source "$pkg" || exit 1
    # makepkg assumes base-devel; none of the real packages lists make.
    local dep
    for dep in "${makedepends[@]}"; do
        [[ "$dep" == make ]] && { echo "makedepends lists base-devel make: $pkg"; exit 1; }
    done
    return 0
}

# The generated scriptlet must print exactly what the project's hand-written one printed.
# A hook the hand file lacks (pre_remove for tmpcleaner) may be added by aurgen.
check_install_parity() {
    local generated="$1" hand="$2" hook want got
    bash -n "$generated" || fail "invalid scriptlet: $generated"
    for hook in post_install post_upgrade pre_remove; do
        want="$(bash -c 'source "$1"; declare -F "$2" >/dev/null || exit 0; "$2"' _ "$hand" "$hook")"
        [[ -n "$want" ]] || continue
        got="$(bash -c 'source "$1"; declare -F "$2" >/dev/null || exit 0; "$2"' _ "$generated" "$hook")"
        [[ "$got" == "$want" ]] || fail "$hook output differs from $hand:
--- want
$want
--- got
$got"
    done
}

# mode_git rewrites PKGBUILD.0 into the -git package. Release checks above never see it.
# $5... are configured conflicts entries (none of these fixtures configure provides).
check_git_pkg() {
    local repo="$1" name="$2" gh_repo="$3" with_check="$4"
    shift 4
    local -a conflicts_extra=("$@")
    local branch pkg
    if branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
        branch="${branch#refs/remotes/origin/}"
    else
        branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD) || fail "no branch for $name"
    fi
    pkg="$repo/aur/PKGBUILD"
    if ! (
        export PATH="$stub:$PATH"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$pkg"
        export SRCINFO="$repo/aur/.SRCINFO"
        # shellcheck disable=SC2034 # mode_git reads these
        export PKGNAME="$name"
        # shellcheck disable=SC2034 # mode_git reads these
        export REPO_NAME="$gh_repo"
        # shellcheck disable=SC2034 # mode_git reads these
        export GH_USER=eserlxl
        export dry_run=1
        export color_enabled=0
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/modes/git.sh
        source "$ROOT/lib/modes/git.sh"
        mode_git
    ) >"$tmp/git.out" 2>"$tmp/git.err"; then
        echo "mode_git failed for $name"
        cat "$tmp/git.err"
        exit 1
    fi
    # shellcheck disable=SC2154 # fields come from the sourced PKGBUILD
    if ! (
        local body extra item
        source_pkg "$pkg"
        [[ "$pkgname" == "$name-git" ]] || { echo "$name git pkgname=[$pkgname]"; exit 1; }
        [[ -v conflicts ]] || { echo "$name git conflicts unset"; exit 1; }
        [[ -v provides ]] || { echo "$name git provides unset"; exit 1; }
        contains() {
            local needle="$1"
            shift
            local item
            for item in "$@"; do
                [[ "$item" == "$needle" ]] && return 0
            done
            return 1
        }
        contains "$name" "${conflicts[@]}" || { echo "$name git conflicts missing $name: ${conflicts[*]}"; exit 1; }
        contains "$name" "${provides[@]}" || { echo "$name git provides missing $name: ${provides[*]}"; exit 1; }
        for extra in "${conflicts_extra[@]}"; do
            contains "$extra" "${conflicts[@]}" || { echo "$name git conflicts missing $extra: ${conflicts[*]}"; exit 1; }
        done
        [[ "${source[0]}" == "git+https://github.com/eserlxl/${gh_repo}.git#branch=${branch}" ]] || { echo "$name git source=[${source[0]}]"; exit 1; }
        for item in build package; do
            body="$(declare -f "$item")" || { echo "$name git ${item}() missing"; exit 1; }
            [[ "$body" == *'cd "$srcdir/'"$gh_repo"'"'* ]] || { echo "$name git ${item} cd missing"; exit 1; }
        done
        if [[ "$with_check" == 1 ]]; then
            body="$(declare -f check)" || { echo "$name git check() missing"; exit 1; }
            [[ "$body" == *'cd "$srcdir/'"$gh_repo"'"'* ]] || { echo "$name git check cd missing"; exit 1; }
        fi
    ); then
        echo "$name git parity failed"
        cat "$pkg"
        exit 1
    fi
}

repo="$(new_repo tmpcleaner "https://github.com/eserlxl/tmpCleaner.git")"
generate "$repo" linux-tmpcleaner
pkg="$repo/aur/PKGBUILD.0"
[[ -f "$pkg" ]] || fail "tmpcleaner PKGBUILD.0 was not written"
# shellcheck disable=SC2154 # fields come from the sourced PKGBUILD
if ! (
    source_pkg "$pkg"
    [[ "$pkgname" == "linux-tmpcleaner" ]] || { echo "tmpcleaner pkgname=[$pkgname]"; exit 1; }
    [[ "$pkgdesc" == "Systemd timer that deletes old /tmp entries while protecting files in use" ]] || { echo "tmpcleaner pkgdesc=[$pkgdesc]"; exit 1; }
    [[ "$url" == "https://github.com/eserlxl/tmpCleaner" ]] || { echo "tmpcleaner url=[$url]"; exit 1; }
    [[ "${arch[*]}" == "any" ]] || { echo "tmpcleaner arch=[${arch[*]}]"; exit 1; }
    [[ "${license[*]}" == "GPL-3.0-or-later" ]] || { echo "tmpcleaner license=[${license[*]}]"; exit 1; }
    got="$(printf '%s\n' "${depends[@]}" | sort)" || exit 1
    want="$(printf '%s\n' bash coreutils findutils gawk grep sed 'systemd>=249' | sort)" || exit 1
    [[ "$got" == "$want" ]] || { echo "tmpcleaner depends got=[$got] want=[$want]"; exit 1; }
    [[ -v optdepends ]] && { echo "tmpcleaner unexpected optdepends"; exit 1; }
    [[ "${conflicts[*]}" == "tmpcleaner" ]] || { echo "tmpcleaner conflicts=[${conflicts[*]}]"; exit 1; }
    [[ "${backup[*]}" == "etc/tmpcleaner/tmpcleaner.conf" ]] || { echo "tmpcleaner backup=[${backup[*]}]"; exit 1; }
    [[ "$install" == "linux-tmpcleaner.install" ]] || { echo "tmpcleaner install=[$install]"; exit 1; }
    [[ "${source[0]}" == "$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz" ]] || { echo "tmpcleaner source=[${source[0]}]"; exit 1; }
    body="$(declare -f check)" || { echo "tmpcleaner check() missing"; exit 1; }
    [[ "$body" == *'cd "$srcdir/tmpCleaner-$pkgver"'* ]] || { echo "tmpcleaner check cd missing"; exit 1; }
    [[ "$body" == *'make check'* ]] || { echo "tmpcleaner check command missing"; exit 1; }
    body="$(declare -f package)" || exit 1
    [[ "$body" == *'cd "$srcdir/tmpCleaner-$pkgver"'* ]] || { echo "tmpcleaner package cd missing"; exit 1; }
    [[ "$body" == *'make install DESTDIR="$pkgdir" PREFIX=/usr UNITDIR=/usr/lib/systemd/system'* ]] || { echo "tmpcleaner install line missing"; exit 1; }
    [[ "$body" != *compileall* ]] || { echo "tmpcleaner unexpected post_package"; exit 1; }
    body="$(declare -f build)" || { echo "tmpcleaner build() missing"; exit 1; }
    [[ "$body" != *$'\n    make'* ]] || { echo "tmpcleaner build() runs make"; exit 1; }
); then
    echo "tmpcleaner parity failed"
    cat "$pkg"
    exit 1
fi
check_install_parity "$repo/aur/linux-tmpcleaner.install" "$ROOT/tests/fixtures/tmpcleaner/hand/tmpcleaner.install"
check_git_pkg "$repo" linux-tmpcleaner tmpCleaner 1 tmpcleaner

repo="$(new_repo cleaner "https://github.com/eserlxl/cleaner.git")"
generate "$repo" linux-cleaner
pkg="$repo/aur/PKGBUILD.0"
[[ -f "$pkg" ]] || fail "cleaner PKGBUILD.0 was not written"
# shellcheck disable=SC2154 # fields come from the sourced PKGBUILD
if ! (
    source_pkg "$pkg"
    [[ "$pkgname" == "linux-cleaner" ]] || { echo "cleaner pkgname=[$pkgname]"; exit 1; }
    [[ "$pkgdesc" == "Safe, configuration-driven cleaner for caches and temporary files" ]] || { echo "cleaner pkgdesc=[$pkgdesc]"; exit 1; }
    [[ "$url" == "https://github.com/eserlxl/cleaner" ]] || { echo "cleaner url=[$url]"; exit 1; }
    [[ "${arch[*]}" == "any" ]] || { echo "cleaner arch=[${arch[*]}]"; exit 1; }
    [[ "${license[*]}" == "GPL-3.0-or-later" ]] || { echo "cleaner license=[${license[*]}]"; exit 1; }
    got="$(printf '%s\n' "${depends[@]}" | sort)" || exit 1
    want="$(printf '%s\n' 'bash>=4.4' coreutils findutils | sort)" || exit 1
    [[ "$got" == "$want" ]] || { echo "cleaner depends got=[$got] want=[$want]"; exit 1; }
    [[ "${optdepends[0]}" == "pacman-contrib: paccache-based package-cache actions" ]] || { echo "cleaner optdepends0"; exit 1; }
    [[ "${optdepends[1]}" == "libnotify: desktop notifications for --notify" ]] || { echo "cleaner optdepends1"; exit 1; }
    [[ "${optdepends[2]}" == "git: skip cleanup targets that hold git-tracked files" ]] || { echo "cleaner optdepends2"; exit 1; }
    [[ ${#optdepends[@]} -eq 3 ]] || { echo "cleaner optdepends count"; exit 1; }
    [[ -v conflicts ]] && { echo "cleaner unexpected conflicts"; exit 1; }
    [[ "${backup[*]}" == "etc/linux-cleaner/cleaner.conf" ]] || { echo "cleaner backup=[${backup[*]}]"; exit 1; }
    [[ "$install" == "linux-cleaner.install" ]] || { echo "cleaner install=[$install]"; exit 1; }
    [[ "${source[0]}" == "$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz" ]] || { echo "cleaner source=[${source[0]}]"; exit 1; }
    declare -F check >/dev/null && { echo "cleaner unexpected check()"; exit 1; }
    body="$(declare -f package)" || exit 1
    [[ "$body" == *'cd "$srcdir/cleaner-$pkgver"'* ]] || { echo "cleaner package cd missing"; exit 1; }
    [[ "$body" == *'make install DESTDIR="$pkgdir" PREFIX=/usr'* ]] || { echo "cleaner install line missing"; exit 1; }
    [[ "$body" != *UNITDIR* ]] || { echo "cleaner unexpected install var"; exit 1; }
    [[ "$body" != *compileall* ]] || { echo "cleaner unexpected post_package"; exit 1; }
    body="$(declare -f build)" || { echo "cleaner build() missing"; exit 1; }
    [[ "$body" != *$'\n    make'* ]] || { echo "cleaner build() runs make"; exit 1; }
); then
    echo "cleaner parity failed"
    cat "$pkg"
    exit 1
fi
check_install_parity "$repo/aur/linux-cleaner.install" "$ROOT/tests/fixtures/cleaner/hand/linux-cleaner.install"
check_git_pkg "$repo" linux-cleaner cleaner 0

repo="$(new_repo ramcleaner "https://github.com/eserlxl/ramCleaner.git")"
generate "$repo" ramcleaner
pkg="$repo/aur/PKGBUILD.0"
[[ -f "$pkg" ]] || fail "ramcleaner PKGBUILD.0 was not written"
# shellcheck disable=SC2154 # fields come from the sourced PKGBUILD
if ! (
    source_pkg "$pkg"
    [[ "$pkgname" == "ramcleaner" ]] || { echo "ramcleaner pkgname=[$pkgname]"; exit 1; }
    [[ "$pkgdesc" == "Find processes holding unused memory, attribute them to their owner, and stop them only after approval" ]] || { echo "ramcleaner pkgdesc=[$pkgdesc]"; exit 1; }
    [[ "$url" == "https://github.com/eserlxl/ramCleaner" ]] || { echo "ramcleaner url=[$url]"; exit 1; }
    [[ "${arch[*]}" == "any" ]] || { echo "ramcleaner arch=[${arch[*]}]"; exit 1; }
    [[ "${license[*]}" == "GPL-3.0-or-later" ]] || { echo "ramcleaner license=[${license[*]}]"; exit 1; }
    got="$(printf '%s\n' "${depends[@]}" | sort)" || exit 1
    want="$(printf '%s\n' 'python>=3.11' | sort)" || exit 1
    [[ "$got" == "$want" ]] || { echo "ramcleaner depends got=[$got] want=[$want]"; exit 1; }
    [[ "${optdepends[0]}" == "libnotify: Stop/Later/Hide desktop notifications for ramcleaner watch" ]] || { echo "ramcleaner optdepends0"; exit 1; }
    [[ "${optdepends[1]}" == "zenity: Hide duration menu for ramcleaner watch" ]] || { echo "ramcleaner optdepends1"; exit 1; }
    [[ ${#optdepends[@]} -eq 2 ]] || { echo "ramcleaner optdepends count"; exit 1; }
    [[ -v conflicts ]] && { echo "ramcleaner unexpected conflicts"; exit 1; }
    [[ -v backup ]] && { echo "ramcleaner unexpected backup"; exit 1; }
    [[ "$install" == "ramcleaner.install" ]] || { echo "ramcleaner install=[$install]"; exit 1; }
    [[ "${source[0]}" == "$pkgname::git+$url.git#tag=v$pkgver?signed" ]] || { echo "ramcleaner source=[${source[0]}]"; exit 1; }
    body="$(declare -f check)" || { echo "ramcleaner check() missing"; exit 1; }
    [[ "$body" == *'cd "$srcdir/$pkgname"'* ]] || { echo "ramcleaner check cd missing"; exit 1; }
    [[ "$body" == *'make check'* ]] || { echo "ramcleaner check command missing"; exit 1; }
    body="$(declare -f package)" || exit 1
    [[ "$body" == *'cd "$srcdir/$pkgname"'* ]] || { echo "ramcleaner package cd missing"; exit 1; }
    [[ "$body" == *'make install DESTDIR="$pkgdir" PREFIX=/usr'* ]] || { echo "ramcleaner install line missing"; exit 1; }
    [[ "$body" == *'python -m compileall -q -o 0 -o 1 -d /usr/lib/ramcleaner "$pkgdir/usr/lib/ramcleaner"'* ]] || { echo "ramcleaner post_package missing"; exit 1; }
    body="$(declare -f build)" || { echo "ramcleaner build() missing"; exit 1; }
    [[ "$body" != *$'\n    make'* ]] || { echo "ramcleaner build() runs make"; exit 1; }
); then
    echo "ramcleaner parity failed"
    cat "$pkg"
    exit 1
fi
check_install_parity "$repo/aur/ramcleaner.install" "$ROOT/tests/fixtures/ramcleaner/hand/ramcleaner.install"
check_git_pkg "$repo" ramcleaner ramCleaner 1

# A Makefile whose first target builds (all:) still runs make in build().
repo="$(new_repo tmpcleaner "https://github.com/eserlxl/tmpCleaner.git" make-all)"
cat > "$repo/Makefile" <<'EOF'
all:
	@true
EOF
generate "$repo" linux-tmpcleaner
pkg="$repo/aur/PKGBUILD.0"
[[ -f "$pkg" ]] || fail "make-all PKGBUILD.0 was not written"
# shellcheck disable=SC2154 # fields come from the sourced PKGBUILD
if ! (
    source_pkg "$pkg"
    body="$(declare -f build)" || { echo "make-all build() missing"; exit 1; }
    [[ "$body" == *$'\n    make'* ]] || { echo "make-all build() missing make"; exit 1; }
    [[ "$body" != *'No build steps required'* ]] || { echo "make-all build() is a no-op"; exit 1; }
); then
    echo "make-all parity failed"
    cat "$pkg"
    exit 1
fi
