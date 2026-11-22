#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
# Scratch-repo commits must never sign with the user's key (commit.gpgsign in ~/.gitconfig).
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_JSON AURGEN_STATUS_DIFF \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH nocheck build_only \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" GNUPGHOME="$tmp/gnupg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
mkdir -m 700 "$GNUPGHOME"

fail() {
    echo "$1"
    exit 1
}

pkgrel_of() {
    awk -F= '/^[[:space:]]*pkgrel[[:space:]]*=/ {print $2; exit}' "$1" | tr -d "\"'[:space:]"
}

stub="$tmp/bin"
mkdir -p "$stub"
for tool in gh curl gpg updpkgsums; do
    printf '#!/bin/bash\nexit 1\n' > "$stub/$tool"
    chmod +x "$stub/$tool"
done
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/makepkg"

repo="$tmp/repo"
mkdir -p "$repo/aur"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'x\n' > "$repo/payload.txt"
git -C "$repo" add payload.txt
git -C "$repo" commit -q -m init

write_pkgbuild() {
    local dest="$1"
    local ver="$2"
    local rel="$3"
    cat >| "$dest" <<EOF
pkgname=demo
pkgver=${ver}
pkgrel=${rel}
pkgdesc='demo'
arch=('x86_64')
url='https://example.com'
license=('GPL-3.0-or-later')
source=("https://example.com/demo-${ver}.tar.gz")
b2sums=('SKIP')
EOF
}

write_pkgbuild "$repo/aur/PKGBUILD.0" 1.0.0 1
write_pkgbuild "$repo/aur/PKGBUILD" 1.0.0 4

export PATH="$stub:$PATH"
export PROJECT_ROOT="$repo"
export AUR_DIR="$repo/aur"
export PKGBUILD0="$repo/aur/PKGBUILD.0"
export PKGBUILD="$repo/aur/PKGBUILD"
export SRCINFO="$repo/aur/.SRCINFO"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/out.log"
export color_enabled=0
export dry_run=1
export no_wait=1
export PKGNAME=demo
export GH_USER=example
export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
export LIB_INSTALL_DIR="$tmp/nolib"
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"
mkdir -p "$LIB_INSTALL_DIR"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur.sh
source "$ROOT/lib/modes/aur.sh"
filter_pkgbuild_sources() { cat; }

got=$(aur_next_pkgrel 1.0.0 4 1.0.0)
if [[ "$got" != 5 ]]; then
    fail "same pkgver should bump pkgrel 4 to 5, got ${got}"
fi
got=$(aur_next_pkgrel 1.0.0 4 2.0.0)
if [[ "$got" != 1 ]]; then
    fail "new pkgver should reset pkgrel to 1, got ${got}"
fi
got=$(aur_next_pkgrel 1.0.0 1.1 1.0.0)
if [[ "$got" != 2 ]]; then
    fail "minor pkgrel 1.1 should bump to 2, got ${got}"
fi
got=$(aur_next_pkgrel 1.0.0 'a[$(touch "$tmp/evaluated")]' 1.0.0)
if [[ "$got" != 1 || -e "$tmp/evaluated" ]]; then
    fail "non-numeric pkgrel should fall back to 1 without being evaluated, got ${got}"
fi
got=$(aur_next_pkgrel "" "" 1.0.0)
if [[ "$got" != 1 ]]; then
    fail "missing published pkgrel should start at 1, got ${got}"
fi

printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=2' 'pkgdesc=demo' >| "$tmp/unchanged-candidate"
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=1' 'pkgdesc=demo' >| "$tmp/unchanged-published"
if ! aur_pkgbuild_unchanged "$tmp/unchanged-candidate" "$tmp/unchanged-published" 1; then
    fail "identical except pkgrel should return 0"
fi
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=1' 'pkgdesc=other' >| "$tmp/changed-published"
if aur_pkgbuild_unchanged "$tmp/unchanged-candidate" "$tmp/changed-published" 1; then
    fail "another line differs should return 1"
fi
if aur_pkgbuild_unchanged "$tmp/unchanged-candidate" "$tmp/missing-published" 1; then
    fail "missing published file should return 1"
fi
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=5' 'pkgdesc=demo' >| "$tmp/rel5-candidate"
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=4' 'pkgdesc=demo' >| "$tmp/rel4-published"
if ! aur_pkgbuild_unchanged "$tmp/rel5-candidate" "$tmp/rel4-published" 4; then
    fail "old_pkgrel 4 with candidate pkgrel=5 should return 0"
fi
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=5' "b2sums=('SKIP' 'SKIP')" "validpgpkeys=('TEST_KEY_FOR_DRY_RUN')" 'pkgdesc=demo' >| "$tmp/dry-candidate"
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=4' "b2sums=('deadbeef' 'c0ffee')" "validpgpkeys=('0123456789ABCDEF0123456789ABCDEF01234567')" 'pkgdesc=demo' >| "$tmp/dry-published"
if ! dry_run=1 aur_pkgbuild_unchanged "$tmp/dry-candidate" "$tmp/dry-published" 4; then
    fail "dry_run=1 ignoring placeholder checksums and validpgpkeys should return 0"
fi
if dry_run=0 aur_pkgbuild_unchanged "$tmp/dry-candidate" "$tmp/dry-published" 4; then
    fail "dry_run=0 comparing full file with different checksums should return 1"
fi
printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=4' "b2sums=('deadbeef' 'c0ffee')" "validpgpkeys=('0123456789ABCDEF0123456789ABCDEF01234567')" 'pkgdesc=other' >| "$tmp/dry-published-diff"
if dry_run=1 aur_pkgbuild_unchanged "$tmp/dry-candidate" "$tmp/dry-published-diff" 4; then
    fail "dry_run=1 with differing field should return 1"
fi

run_aur() {
    local errfile="$1"
    (
        set +u
        mode_aur
    ) >|"$tmp/aur.out" 2>|"$errfile"
}

if ! run_aur "$tmp/aur.err"; then
    echo "first aur run failed"
    cat "$tmp/aur.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 5 ]]; then
    fail "republish of 1.0.0 should keep published pkgrel 4 and bump to 5, got ${got}"
fi

if ! run_aur "$tmp/aur.err"; then
    echo "second aur run failed"
    cat "$tmp/aur.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 6 ]]; then
    fail "second republish of 1.0.0 should bump pkgrel to 6, got ${got}"
fi

write_pkgbuild "$PKGBUILD0" 2.0.0 1
if ! run_aur "$tmp/aur.err"; then
    echo "version-change aur run failed"
    cat "$tmp/aur.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 1 ]]; then
    fail "new pkgver 2.0.0 should set pkgrel to 1, got ${got}"
fi

before=$(cat "$PKGBUILD")
exec 9>"$AUR_DIR/.aurgen.lock"
flock -n 9 || fail "test could not take the PKGBUILD lock"
if run_aur "$tmp/lock.err"; then
    flock -u 9
    echo "concurrent aur run should abort"
    cat "$tmp/lock.err"
    exit 1
fi
flock -u 9
if ! grep -F -q "Another process is already updating PKGBUILD" "$tmp/lock.err"; then
    echo "concurrent aur run did not report the lock"
    cat "$tmp/lock.err"
    exit 1
fi
after=$(cat "$PKGBUILD")
if [[ "$before" != "$after" ]]; then
    fail "concurrent aur run rewrote PKGBUILD"
fi

write_pkgbuild "$PKGBUILD0" 1.0.0 1
write_pkgbuild "$PKGBUILD" 1.0.0 4
export TEST_DIR="$tmp/test"
mkdir -p "$TEST_DIR"
printf 'held\n' > "$AUR_DIR/.aurgen.lock"
lock_inode=$(stat -c %i "$AUR_DIR/.aurgen.lock")

# shellcheck source=../lib/modes/clean.sh
source "$ROOT/lib/modes/clean.sh"
cleanup

if [[ ! -e "$AUR_DIR/.aurgen.lock" ]]; then
    fail "cleanup removed .aurgen.lock"
fi
got=$(stat -c %i "$AUR_DIR/.aurgen.lock")
if [[ "$got" != "$lock_inode" ]]; then
    fail "cleanup replaced .aurgen.lock"
fi
if ! run_aur "$tmp/cleanup.err"; then
    echo "aur run after cleanup failed"
    cat "$tmp/cleanup.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 5 ]]; then
    fail "same-version aur run after cleanup should bump published pkgrel 4 to 5, got ${got}"
fi

export GOLDEN_DIR="$tmp/golden"
export GREEN=""
export RESET=""
mkdir -p "$GOLDEN_DIR"
# A held lock means an aur run is updating PKGBUILD: clean must refuse and keep it.
exec 9>"$AUR_DIR/.aurgen.lock"
flock -n 9 || fail "test could not take the lock for mode_clean"
if (mode_clean) >"$tmp/clean-held.out" 2>"$tmp/clean-held.err"; then
    flock -u 9
    fail "mode_clean ran while the lock was held"
fi
flock -u 9
exec 9>&-
grep -F -q "An aur run holds $AUR_DIR/.aurgen.lock" "$tmp/clean-held.err" || fail "mode_clean did not name the held lock" "$tmp/clean-held.err"
[[ -e "$AUR_DIR/.aurgen.lock" ]] || fail "mode_clean removed a held .aurgen.lock"
# While clean runs it holds the lock, so an aur run started meanwhile aborts.
# find runs after the other deletions; the lock file must still be there.
(
    cleanup() { echo "cleanup ran"; flock -n "$AUR_DIR/.aurgen.lock" true && echo "lock free during clean"; :; }
    find() { echo "find ran"; [[ -e "$AUR_DIR/.aurgen.lock" ]] || echo "lock removed before the last deletion"; command find "$@"; }
    mode_clean
) >"$tmp/clean-during.out" 2>&1
# The probes print only on a violation, so first prove both wrappers ran.
grep -F -q "cleanup ran" "$tmp/clean-during.out" || fail "mode_clean never called cleanup" "$tmp/clean-during.out"
grep -F -q "find ran" "$tmp/clean-during.out" || fail "mode_clean never called find" "$tmp/clean-during.out"
if grep -F -q "lock free during clean" "$tmp/clean-during.out"; then
    fail "mode_clean released the lock before it finished" "$tmp/clean-during.out"
fi
if grep -F -q "lock removed before the last deletion" "$tmp/clean-during.out"; then
    fail "mode_clean removed the lock file before its other deletions" "$tmp/clean-during.out"
fi
mode_clean >/dev/null
if [[ -e "$AUR_DIR/.aurgen.lock" ]]; then
    fail "mode_clean left .aurgen.lock in place"
fi

write_pkgbuild "$PKGBUILD0" 1.0.0 1
write_pkgbuild "$PKGBUILD" 1.0.0 "3 # rebuild"
if ! run_aur "$tmp/comment.err"; then
    echo "aur run over a commented pkgrel failed"
    cat "$tmp/comment.err"
    exit 1
fi
got=$(pkgrel_of "$PKGBUILD")
if [[ "$got" != 4 ]]; then
    fail "published pkgrel=3 # rebuild should bump to 4, got ${got}"
fi

# A child run inside aurgen test (AURGEN_KEEP_PREV=1) writes into a test log; its
# cleanup must not delete that log. A plain cleanup still removes old logs.
mkdir -p "$TEST_DIR"
printf 'child output\n' >| "$TEST_DIR/test-aur-1.log"
AURGEN_KEEP_PREV=1 cleanup
[[ -f "$TEST_DIR/test-aur-1.log" ]] || fail "cleanup inside aurgen test deleted the running test log"
cleanup
[[ ! -e "$TEST_DIR/test-aur-1.log" ]] || fail "plain cleanup kept an old test log"

# Exercise published-version lookup without uploading assets or building packages.
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
export LIB_INSTALL_DIR="$ROOT/lib"
export PKG_SOURCE=archive
export dry_run=0
export SILVER=""
aur_require_remote_tag() { :; }
orig_update_checksums="$(declare -f update_checksums)"
update_checksums() {
    if (( ${dry_run:-0} )); then
        eval "$orig_update_checksums"
        update_checksums
    fi
}
generate_srcinfo() { :; }
install_pkg() { :; }
set -o noclobber

clone_root="$tmp/clones"
mkdir -p "$clone_root/release-demo"
printf 'aur_integration:\n    aur_repo_dir: %s\n' "$clone_root" >| "$AUR_DIR/aurgen.install.yaml"
printf 'pkgbase = release-demo\n' >| "$SRCINFO"
printf 'pkgbase = release-demo\n\tpkgver = 1.0.0\n\tpkgrel = 4\n' >| "$clone_root/release-demo/.SRCINFO"
write_pkgbuild "$PKGBUILD0" 1.0.0 1

check_published_pkgrel() {
    local expected="$1" source="$2"
    write_pkgbuild "$AUR_DIR/PKGBUILD.prev" 1.0.0 9 || exit 1
    rm -f "$PKGBUILD" || exit 1
    run_aur "$tmp/published.err" || { cat "$tmp/published.err"; fail "aur run using $source failed"; }
    got=$(pkgrel_of "$PKGBUILD") || exit 1
    [[ "$got" == "$expected" ]] || fail "$source should give pkgrel $expected, got $got"
    grep -F -q "pkgrel source: $source" "$tmp/aur.out" || fail "missing pkgrel source log: $source"
}

check_published_pkgrel 5 "AUR clone $clone_root/release-demo/.SRCINFO"
# The clone already holds this PKGBUILD at pkgrel 4: a re-run keeps 4 instead of a no-op bump.
sed 's/^pkgrel=.*/pkgrel=4/' "$PKGBUILD" >| "$clone_root/release-demo/PKGBUILD"
check_published_pkgrel 4 "AUR clone $clone_root/release-demo/.SRCINFO"
grep -F -q "PKGBUILD unchanged since the published release, keeping pkgrel=4" "$tmp/aur.out" ||
    fail "unchanged PKGBUILD was not logged"
# A clone PKGBUILD equal to a fresh generation except real checksums and key
# gives the published pkgrel under --dry-run.
rm -f "$clone_root/release-demo/PKGBUILD"
dry_run=1 PKG_SOURCE=release check_published_pkgrel 5 "AUR clone $clone_root/release-demo/.SRCINFO"
sed -e 's/^pkgrel=.*/pkgrel=4/' \
    -e "s/^b2sums=.*/b2sums=('1111222233334444555566667777888811112222333344445555666677778888' 'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111')/" \
    -e "s/^validpgpkeys=.*/validpgpkeys=('0123456789ABCDEF0123456789ABCDEF01234567')/" \
    "$PKGBUILD" >| "$clone_root/release-demo/PKGBUILD"
dry_run=1 PKG_SOURCE=release check_published_pkgrel 4 "AUR clone $clone_root/release-demo/.SRCINFO"
grep -F -q "PKGBUILD unchanged since the published release, keeping pkgrel=4" "$tmp/aur.out" ||
    fail "unchanged PKGBUILD was not logged under dry-run"
# Multi-line validpgpkeys and b2sums with parenthesized comments in the published clone must still skip cleanly under dry-run.
awk '
    /^pkgrel=/ { print "pkgrel=4"; next }
    /^b2sums=/ {
        print "b2sums=( # pinned hashes (release)"
        print "  \x271111222233334444555566667777888811112222333344445555666677778888\x27 # tarball (1)"
        print "  \x27aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111\x27 # signature (2)"
        print ")"
        next
    }
    /^validpgpkeys=/ {
        print "validpgpkeys=( # maintainers (active)"
        print "  \x270123456789ABCDEF0123456789ABCDEF01234567\x27 # primary (ed25519)"
        print "  \x2789ABCDEF0123456789ABCDEF0123456789ABCDEF\x27 # backup (rsa)"
        print ")"
        next
    }
    { print }
' "$PKGBUILD" >| "$clone_root/release-demo/PKGBUILD"
dry_run=1 PKG_SOURCE=release check_published_pkgrel 4 "AUR clone $clone_root/release-demo/.SRCINFO"
# A real run still compares the full file, so differing checksums/key bump pkgrel.
check_published_pkgrel 5 "AUR clone $clone_root/release-demo/.SRCINFO"
# Restore clean clone PKGBUILD for remaining cases.
sed 's/^pkgrel=.*/pkgrel=4/' "$PKGBUILD" >| "$clone_root/release-demo/PKGBUILD"
check_published_pkgrel 4 "AUR clone $clone_root/release-demo/.SRCINFO"
# AURGEN_BUMP_PKGREL=1 forces the bump for a dependency rebuild.
AURGEN_BUMP_PKGREL=1 check_published_pkgrel 5 "AUR clone $clone_root/release-demo/.SRCINFO"
# Any other difference still bumps.
printf '# local edit\n' >> "$clone_root/release-demo/PKGBUILD"
check_published_pkgrel 5 "AUR clone $clone_root/release-demo/.SRCINFO"
# install= is deployed beside PKGBUILD. The same scriptlet keeps pkgrel; an edit bumps it.
printf "install='demo.install'\n" >> "$PKGBUILD0"
printf 'post_install() { :; }\n' >| "$AUR_DIR/demo.install"
printf 'post_install() { :; }\n' >| "$clone_root/release-demo/demo.install"
sed 's/^pkgrel=.*/pkgrel=4/' "$PKGBUILD0" >| "$clone_root/release-demo/PKGBUILD"
check_published_pkgrel 4 "AUR clone $clone_root/release-demo/.SRCINFO"
printf 'post_upgrade() { :; }\n' >> "$AUR_DIR/demo.install"
check_published_pkgrel 5 "AUR clone $clone_root/release-demo/.SRCINFO"
rm -f "$clone_root/release-demo/PKGBUILD" "$clone_root/release-demo/demo.install" "$AUR_DIR/demo.install"
write_pkgbuild "$PKGBUILD0" 2.0.0 1
check_published_pkgrel 1 "AUR clone $clone_root/release-demo/.SRCINFO"
write_pkgbuild "$PKGBUILD0" 1.0.0 1
rm -f "$clone_root/release-demo/.SRCINFO"
check_published_pkgrel 1 "AUR clone $clone_root/release-demo (unpublished)"
rmdir "$clone_root/release-demo"

export AUR_RPC_RESPONSE="$tmp/rpc.json"
export AUR_RPC_CALLS="$tmp/rpc.calls"
cat >| "$stub/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$AUR_RPC_CALLS"
cat "$AUR_RPC_RESPONSE"
EOF
chmod +x "$stub/curl"
printf '{"resultcount":0,"results":[]}\n' >| "$AUR_RPC_RESPONSE"
check_published_pkgrel 1 "AUR RPC (release-demo, unpublished)"
grep -F -q 'https://aur.archlinux.org/rpc/v5/info/release-demo' "$AUR_RPC_CALLS" || fail "RPC used the wrong package name"

printf '{"resultcount":1,"results":[{"Version":"1.0.0-4"}]}\n' >| "$AUR_RPC_RESPONSE"
check_published_pkgrel 5 "AUR RPC (release-demo)"
printf '{"resultcount":1,"results":[{"Version":"1:1.0.0-4"}]}\n' >| "$AUR_RPC_RESPONSE"
check_published_pkgrel 5 "AUR RPC (release-demo)"
printf '{"resultcount":1,"results":[{"Version":"1.0.0-4.1"}]}\n' >| "$AUR_RPC_RESPONSE"
check_published_pkgrel 5 "AUR RPC (release-demo)"
write_pkgbuild "$PKGBUILD0" 2.0.0 1
check_published_pkgrel 1 "AUR RPC (release-demo)"
write_pkgbuild "$PKGBUILD0" 1.0.0 1

for response in '{"error":"unavailable"}' 'invalid JSON' '{"resultcount":1,"results":[]}'; do
    printf '%s\n' "$response" >| "$AUR_RPC_RESPONSE"
    check_published_pkgrel 10 "local fallback $AUR_DIR/PKGBUILD.prev"
done
printf '#!/bin/bash\nexit 1\n' >| "$stub/curl"
check_published_pkgrel 10 "local fallback $AUR_DIR/PKGBUILD.prev"

printf '#!/bin/bash\nprintf called >> "$AUR_RPC_CALLS"\nexit 1\n' >| "$stub/curl"
rm -f "$AUR_RPC_CALLS"
dry_run=1 check_published_pkgrel 10 "local fallback $AUR_DIR/PKGBUILD.prev"
[[ ! -e "$AUR_RPC_CALLS" ]] || fail "dry run queried the AUR RPC"

no_curl="$tmp/no-curl"
mkdir -p "$no_curl"
for tool in awk tr cp flock mv cmp rm cat jq grep; do
    ln -s "$(command -v "$tool")" "$no_curl/$tool"
done
PATH="$no_curl" check_published_pkgrel 10 "local fallback $AUR_DIR/PKGBUILD.prev"

# Lock lifetime and contention checks across aur, local, and git modes
(
    set -euo pipefail

    assert_lock_held() {
        local lockfile="$1" stage="$2"
        if ( exec {probe_fd}>>"$lockfile"; flock -n "$probe_fd" ); then
            fail "$stage should hold $lockfile"
        fi
    }

    assert_lock_free() {
        local lockfile="$1" stage="$2"
        if ! ( exec {probe_fd}>>"$lockfile"; flock -n "$probe_fd" ); then
            fail "$stage should release $lockfile before running"
        fi
    }

    make_lock_repo() {
        local dir="$1"
        mkdir -p "$dir/aur"
        git -C "$dir" init -q -b main
        git -C "$dir" config user.name test
        git -C "$dir" config user.email test@example.com
        printf 'payload\n' >| "$dir/f"
        git -C "$dir" add f
        git -C "$dir" commit -q -m init
        git -C "$dir" tag v1.0.0
        git -C "$dir" remote add origin https://github.com/example/demo.git
        git -C "$dir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
        write_pkgbuild "$dir/aur/PKGBUILD.0" 1.0.0 1
    }

    # 1. mode_aur holds .aurgen.lock through update_checksums and generate_srcinfo,
    # releases before install_pkg, releases on early return, and handles repeated calls.
    aur_repo="$tmp/lock-aur"
    make_lock_repo "$aur_repo"
    (
        export PROJECT_ROOT="$aur_repo" AUR_DIR="$aur_repo/aur" OUT_DIR="$aur_repo/aur"
        export PKGBUILD0="$aur_repo/aur/PKGBUILD.0" PKGBUILD="$aur_repo/aur/PKGBUILD" SRCINFO="$aur_repo/aur/.SRCINFO"
        export LIB_INSTALL_DIR="$ROOT/lib" PKG_SOURCE=release PKGNAME=demo REPO_NAME=demo GH_USER=example GH_REPO=demo
        export dry_run=1 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN

        seen_checksums=0
        seen_srcinfo=0
        seen_install=0
        update_checksums() {
            assert_lock_held "$OUT_DIR/.aurgen.lock" "mode_aur update_checksums"
            seen_checksums=$((seen_checksums + 1))
        }
        generate_srcinfo() {
            assert_lock_held "$OUT_DIR/.aurgen.lock" "mode_aur generate_srcinfo"
            seen_srcinfo=$((seen_srcinfo + 1))
            printf 'pkgbase = demo\n' >| "$SRCINFO"
        }
        install_pkg() {
            assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_aur install_pkg"
            seen_install=$((seen_install + 1))
        }

        # Early return from load_aur_integration_config must still release .aurgen.lock.
        mkdir -p "$tmp/lock-lib-fail"
        printf 'load_aur_integration_config() { return 1; }\n' >| "$tmp/lock-lib-fail/aur-integration.sh"
        LIB_INSTALL_DIR="$tmp/lock-lib-fail"
        if mode_aur 2>"$tmp/lock-aur-early.err"; then
            fail "mode_aur should return non-zero when load_aur_integration_config fails"
        fi
        assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_aur early return"

        # Two consecutive in-process calls prove fd release and no fd leak.
        export LIB_INSTALL_DIR="$tmp/nolib"
        mode_aur >"$tmp/lock-aur-1.out" 2>"$tmp/lock-aur-1.err" || { cat "$tmp/lock-aur-1.err"; fail "first mode_aur failed"; }
        mode_aur >"$tmp/lock-aur-2.out" 2>"$tmp/lock-aur-2.err" || { cat "$tmp/lock-aur-2.err"; fail "second mode_aur failed"; }
        assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_aur post-exit"
        [[ "$seen_checksums" -ge 2 && "$seen_srcinfo" -eq 2 && "$seen_install" -eq 2 ]] || fail "mode_aur stages did not all run"
    ) || exit 1

    # 2. mode_local holds .aurgen.lock through update_checksums and generate_srcinfo,
    # rejects concurrent runs without modifying PKGBUILD, and releases before install_pkg.
    local_repo="$tmp/lock-local"
    make_lock_repo "$local_repo"
    (
        source "$ROOT/lib/modes/local.sh"
        export PROJECT_ROOT="$local_repo" AUR_DIR="$local_repo/aur" OUT_DIR="$local_repo/aur"
        export PKGBUILD0="$local_repo/aur/PKGBUILD.0" PKGBUILD="$local_repo/aur/PKGBUILD" SRCINFO="$local_repo/aur/.SRCINFO"
        export PKG_SOURCE=archive PKGNAME=demo REPO_NAME=demo EXCLUDE_DIRS_STR="" EXCLUDE_FILES_STR=""
        export dry_run=0

        seen_checksums=0
        seen_srcinfo=0
        seen_install=0
        update_checksums() {
            assert_lock_held "$OUT_DIR/.aurgen.lock" "mode_local update_checksums"
            seen_checksums=$((seen_checksums + 1))
        }
        generate_srcinfo() {
            assert_lock_held "$OUT_DIR/.aurgen.lock" "mode_local generate_srcinfo"
            seen_srcinfo=$((seen_srcinfo + 1))
            printf 'pkgbase = demo\n' >| "$SRCINFO"
        }
        install_pkg() {
            assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_local install_pkg"
            seen_install=$((seen_install + 1))
        }

        printf 'sentinel\n' >| "$PKGBUILD"
        (
            exec 201>>"$OUT_DIR/.aurgen.lock"
            flock -n 201 || fail "test failed to lock local .aurgen.lock"
            if ( mode_local >"$tmp/lock-local-contend.out" 2>"$tmp/lock-local-contend.err" ); then
                fail "concurrent mode_local succeeded while .aurgen.lock was held"
            fi
            grep -q "Another process is already updating PKGBUILD" "$tmp/lock-local-contend.err" || fail "concurrent mode_local missing lock message"
        ) || exit 1
        [[ "$(cat "$PKGBUILD")" == "sentinel" ]] || fail "contended mode_local modified PKGBUILD"

        mode_local >"$tmp/lock-local-1.out" 2>"$tmp/lock-local-1.err" || { cat "$tmp/lock-local-1.err"; fail "first mode_local failed"; }
        mode_local >"$tmp/lock-local-2.out" 2>"$tmp/lock-local-2.err" || { cat "$tmp/lock-local-2.err"; fail "second mode_local failed"; }
        assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_local post-exit"
        [[ "$seen_checksums" -eq 2 && "$seen_srcinfo" -eq 2 && "$seen_install" -eq 2 ]] || fail "mode_local stages did not all run"
    ) || exit 1

    # 3. mode_git holds .aurgen.lock through PKGBUILD.git and .SRCINFO generation,
    # rejects concurrent runs without modifying PKGBUILD, and releases before install_pkg.
    git_repo="$tmp/lock-git"
    make_lock_repo "$git_repo"
    (
        source "$ROOT/lib/modes/git.sh"
        export PROJECT_ROOT="$git_repo" AUR_DIR="$git_repo/aur" OUT_DIR="$git_repo/aur"
        export PKGBUILD0="$git_repo/aur/PKGBUILD.0" PKGBUILD="$git_repo/aur/PKGBUILD" SRCINFO="$git_repo/aur/.SRCINFO"
        export PKGNAME=demo REPO_NAME=demo GH_USER=example GH_REPO=demo
        export dry_run=0

        seen_srcinfo=0
        seen_install=0
        generate_srcinfo() {
            assert_lock_held "$OUT_DIR/.aurgen.lock" "mode_git generate_srcinfo"
            seen_srcinfo=$((seen_srcinfo + 1))
            printf 'pkgbase = demo-git\n' >| "$SRCINFO"
        }
        install_pkg() {
            assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_git install_pkg"
            seen_install=$((seen_install + 1))
        }

        printf 'sentinel\n' >| "$PKGBUILD"
        (
            exec 201>>"$OUT_DIR/.aurgen.lock"
            flock -n 201 || fail "test failed to lock git .aurgen.lock"
            if ( mode_git >"$tmp/lock-git-contend.out" 2>"$tmp/lock-git-contend.err" ); then
                fail "concurrent mode_git succeeded while .aurgen.lock was held"
            fi
            grep -q "Another process is already updating PKGBUILD" "$tmp/lock-git-contend.err" || fail "concurrent mode_git missing lock message"
        ) || exit 1
        [[ "$(cat "$PKGBUILD")" == "sentinel" ]] || fail "contended mode_git modified PKGBUILD"

        mode_git >"$tmp/lock-git-1.out" 2>"$tmp/lock-git-1.err" || { cat "$tmp/lock-git-1.err"; fail "first mode_git failed"; }
        mode_git >"$tmp/lock-git-2.out" 2>"$tmp/lock-git-2.err" || { cat "$tmp/lock-git-2.err"; fail "second mode_git failed"; }
        assert_lock_free "$OUT_DIR/.aurgen.lock" "mode_git post-exit"
        [[ "$seen_srcinfo" -eq 2 && "$seen_install" -eq 2 ]] || fail "mode_git stages did not all run"
    ) || exit 1
) || exit 1

# Inline # comments on published OLD_PKGVER and OLD_PKGREL must be stripped before version comparison.
write_pkgbuild "$PKGBUILD0" 1.0.0 1
sed -i 's/^pkgver=.*/pkgver=1.0.0 # (rc)/' "$PKGBUILD0"
write_pkgbuild "$AUR_DIR/PKGBUILD.prev" 1.0.0 4
sed -i -e "s/^pkgver=.*/pkgver='1.0.0' # (rc)/" -e "s/^pkgrel=.*/pkgrel='4' # (rebuild)/" "$AUR_DIR/PKGBUILD.prev"
rm -f "$PKGBUILD"
dry_run=1 run_aur "$tmp/comment-fallback.err" || { cat "$tmp/comment-fallback.err"; fail "aur run with commented PKGBUILD.prev failed"; }
got=$(pkgrel_of "$PKGBUILD") || exit 1
[[ "$got" == "5" ]] || fail "commented PKGBUILD.prev should give pkgrel 5, got $got"

# A run that dies after the release archive, before .SRCINFO is committed, must
# drop the tarball and signature it created. A later successful run keeps them.
# A file this run did not create is left in place.
art_repo="$tmp/artifact-repo"
art_stub="$tmp/artifact-bin"
art_tarball="$art_repo/aur/artifactkeep-1.0.0.tar.gz"
art_sig="$art_repo/aur/artifactkeep-1.0.0.tar.gz.sig"
art_kept="$art_repo/aur/kept-not-ours.tar.gz"
art_kept_sig="$art_repo/aur/kept-not-ours.tar.gz.sig"
mkdir -p "$art_repo/aur" "$art_stub"
git -C "$art_repo" init -q -b main
git -C "$art_repo" config user.email "t@example.com"
git -C "$art_repo" config user.name "t"
git -C "$art_repo" config commit.gpgsign false
git -C "$art_repo" remote add origin "https://github.com/example/artifactkeep.git"
printf 'payload\n' >| "$art_repo/payload.txt"
printf '1.0.0\n' >| "$art_repo/VERSION"
git -C "$art_repo" add payload.txt VERSION
git -C "$art_repo" commit -q -m init
printf 'package:\n  name: artifactkeep\n  description: artifact cleanup test\n  check: false\n' >| "$art_repo/aur/aurgen.install.yaml"
printf 'previous pkgbuild\n' >| "$art_repo/aur/PKGBUILD"
printf 'previous srcinfo\n' >| "$art_repo/aur/.SRCINFO"
printf 'keep\n' >| "$art_kept"
printf 'keep-sig\n' >| "$art_kept_sig"
printf '#!/bin/bash\nexit 0\n' >| "$art_stub/updpkgsums"
printf '#!/bin/bash\nexit 22\n' >| "$art_stub/curl"
cat >| "$art_stub/gh" <<'EOF'
#!/bin/bash
case "${1:-} ${2:-}" in
    "auth status"|"release create"|"release upload") exit 0 ;;
esac
exit 1
EOF
cat >| "$art_stub/makepkg" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--printsrcinfo"* ]]; then
    exit "${STUB_PRINTSRCINFO_RC:-0}"
fi
exit 0
EOF
chmod +x "$art_stub/updpkgsums" "$art_stub/curl" "$art_stub/gh" "$art_stub/makepkg"

run_artifact_aur() {
    local name="$1"
    shift
    (
        cd "$art_repo" || exit 1
        env -u PKG_SOURCE -u AURGEN_KEEP_PREV -u AUR_DIR -u OUT_DIR -u PROJECT_ROOT \
            -u PKGBUILD -u PKGBUILD0 -u SRCINFO -u LIB_INSTALL_DIR -u PKGNAME -u GH_USER \
            -u REPO_NAME -u DRY_RUN \
            PATH="$art_stub:$PATH" \
            DRY_RUN=0 \
            GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN \
            AURGEN_LOG="$tmp/$name.log" \
            AURGEN_ERROR_LOG="$tmp/$name.errlog" \
            "$@" \
            "$ROOT/bin/aurgen" -n --no-wait aur
    ) >|"$tmp/$name.out" 2>|"$tmp/$name.err"
}

if run_artifact_aur artifact-fail STUB_PRINTSRCINFO_RC=1; then
    cat "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"
    fail "aur run should fail when .SRCINFO generation fails after the archive"
fi
if ! grep -F -q "Created $art_tarball" "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"; then
    cat "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"
    fail "failed aur run did not reach the archive step"
fi
if ! grep -F -q "Created dummy signature file: $art_sig" "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"; then
    cat "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"
    fail "failed aur run did not create a signature"
fi
if ! grep -F -q "restored previous PKGBUILD/.SRCINFO state" "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"; then
    cat "$tmp/artifact-fail.out" "$tmp/artifact-fail.err"
    fail "failed aur run did not restore packaging files"
fi
if [[ -e "$art_tarball" || -e "$art_sig" ]]; then
    fail "failed aur run left the tarball or signature it created"
fi
cmp -s "$art_repo/aur/PKGBUILD" <(printf 'previous pkgbuild\n') || fail "failed aur run did not restore PKGBUILD"
cmp -s "$art_repo/aur/.SRCINFO" <(printf 'previous srcinfo\n') || fail "failed aur run did not restore .SRCINFO"
cmp -s "$art_kept" <(printf 'keep\n') || fail "failed aur run removed a tarball it did not create"
cmp -s "$art_kept_sig" <(printf 'keep-sig\n') || fail "failed aur run removed a signature it did not create"

if ! run_artifact_aur artifact-ok STUB_PRINTSRCINFO_RC=0; then
    cat "$tmp/artifact-ok.out" "$tmp/artifact-ok.err"
    fail "successful aur run failed"
fi
if [[ ! -s "$art_tarball" || ! -e "$art_sig" ]]; then
    fail "successful aur run did not keep the tarball and signature"
fi
cmp -s "$art_kept" <(printf 'keep\n') || fail "successful aur run removed a tarball it did not create"
cmp -s "$art_kept_sig" <(printf 'keep-sig\n') || fail "successful aur run removed a signature it did not create"
if grep -F -q "restored previous PKGBUILD/.SRCINFO state" "$tmp/artifact-ok.out" "$tmp/artifact-ok.err"; then
    cat "$tmp/artifact-ok.out" "$tmp/artifact-ok.err"
    fail "successful aur run restored packaging files"
fi

# In-process mode_aur (bypassing startup cleanup) with $out/$TARBALL and its .sig
# already present and a later step failing must keep both files and leave
# _AURGEN_RUN_ARTIFACTS empty.
(
    export PROJECT_ROOT="$art_repo" AUR_DIR="$art_repo/aur" OUT_DIR="$art_repo/aur"
    export PKGBUILD0="$art_repo/aur/PKGBUILD.0" PKGBUILD="$art_repo/aur/PKGBUILD" SRCINFO="$art_repo/aur/.SRCINFO"
    export LIB_INSTALL_DIR="$tmp/nolib" PKG_SOURCE=release PKGNAME=artifactkeep REPO_NAME=artifactkeep GH_USER=example GH_REPO=artifactkeep
    export dry_run=1 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    write_pkgbuild "$PKGBUILD0" 1.0.0 1
    printf 'pre-existing-tarball\n' >| "$art_tarball"
    printf 'pre-existing-sig\n' >| "$art_sig"
    _AURGEN_RUN_ARTIFACTS=()
    # shellcheck disable=SC2154 # lock_fd is mode_aur's local, reached through dynamic scope
    _aur_resolve_published_version() { exec {lock_fd}>&-; return 1; }
    if mode_aur >|"$tmp/inproc-exist.out" 2>|"$tmp/inproc-exist.err"; then
        fail "in-process mode_aur should fail when _aur_resolve_published_version fails"
    fi
    for _artifact in ${_AURGEN_RUN_ARTIFACTS[@]+"${_AURGEN_RUN_ARTIFACTS[@]}"}; do
        rm -f -- "$_artifact"
    done
    (( ${#_AURGEN_RUN_ARTIFACTS[@]} == 0 )) || fail "pre-existing tarball/sig should keep _AURGEN_RUN_ARTIFACTS empty, got (${_AURGEN_RUN_ARTIFACTS[*]})"
    [[ -f "$art_tarball" && -f "$art_sig" ]] || fail "pre-existing tarball or signature did not survive failed in-process mode_aur"
) || exit 1
