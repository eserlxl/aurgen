#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-source-kind.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
# aur mode reads pkgrel from the AUR clone dir; never the user's real one.
export XDG_DATA_HOME="$tmp/data"
export XDG_STATE_HOME="$tmp/state"

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
# curl -f exits 22 on a 404; any other failure means GitHub was not reached.
printf '#!/bin/bash\nexit 22\n' > "$stub/curl"
chmod +x "$stub/makepkg" "$stub/curl"

cat > "$stub/gh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
    "release upload"|"release create") exit 0 ;;
    "release view") exit 1 ;;
esac
exit 0
EOF

cat > "$stub/gpg" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GPG_LOG"
# git ignores GOODSIG unless a status line precedes it. The last VALIDSIG field is the signer.
if [[ "$*" == *--verify* ]]; then
    fpr="$TAG_SIGNER"
    printf '%s\n' \
        '[GNUPG:] NEWSIG' \
        "[GNUPG:] GOODSIG ${fpr:24} Test <t@example.com>" \
        "[GNUPG:] VALIDSIG ${fpr} 1700000000 1700000000 0 4 0 22 10 00 ${fpr}" \
        '[GNUPG:] TRUST_ULTIMATE 0 pgp'
    exit 0
fi
args=("$@")
i=0
while (( i < ${#args[@]} )); do
    if [[ "${args[$i]}" == "--output" ]]; then
        printf 'sig\n' > "${args[$((i + 1))]}"
    fi
    i=$((i + 1))
done
exit 0
EOF

cat > "$stub/updpkgsums" << 'EOF'
#!/bin/bash
printf 'called\n' >> "$UPD_LOG"
[[ -f PKGBUILD ]] || exit 1
sed -i "s/^b2sums=.*/b2sums=('deadbeef')/" PKGBUILD
exit 0
EOF
chmod +x "$stub/gh" "$stub/gpg" "$stub/updpkgsums"

export GH_LOG="$tmp/gh.log"
export GPG_LOG="$tmp/gpg.log"
export UPD_LOG="$tmp/upd.log"
: > "$GH_LOG"
: > "$GPG_LOG"
: > "$UPD_LOG"
: > "$tmp/err.log"
: > "$tmp/out.log"

KEY='0123456789ABCDEF0123456789ABCDEF01234567'
export TAG_SIGNER='89ABCDEF0123456789ABCDEF0123456789ABCDEF'

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    if [[ -f "$tmp/run.err" ]]; then
        echo "--- run.err ---"
        cat "$tmp/run.err"
    fi
    exit 1
}

func_body() {
    local file="$1"
    local name="$2"
    awk -v fn="$name" '
        $0 ~ "^" fn "\\(\\) \\{" { capture = 1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$file"
}

new_repo() {
    local name="$1"
    local repo="$tmp/$name"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" config commit.gpgsign false
    git -C "$repo" config tag.gpgsign false
    git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
    printf 'all:\n\t@true\ncheck:\n\t@true\n' > "$repo/Makefile"
    printf 'demo package\n' > "$repo/README.md"
    git -C "$repo" add Makefile README.md
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

# kind is release, archive, signed-tag, or empty (omit package.source).
write_config() {
    local repo="$1"
    local kind="$2"
    if [[ -n "$kind" ]]; then
        printf 'package:\n  source: %s\n' "$kind" > "$repo/aur/aurgen.install.yaml"
    else
        printf 'package:\n  name: testpkg\n' > "$repo/aur/aurgen.install.yaml"
    fi
}

light_tag() {
    local repo="$1"
    git -C "$repo" tag -a v1.0.0 -m 'unsigned'
}

signed_tag() {
    local repo="$1"
    local tag="${2:-v1.0.0}"
    local commit tagfile tagsha
    commit="$(git -C "$repo" rev-parse HEAD)"
    tagfile="$tmp/tagobj"
    cat > "$tagfile" << EOF
object ${commit}
type commit
tag ${tag}
tagger Test <t@example.com> 1700000000 +0000

${tag}

-----BEGIN PGP SIGNATURE-----

ZmFrZQ==
-----END PGP SIGNATURE-----
EOF
    tagsha="$(git -C "$repo" hash-object -t tag -w "$tagfile")"
    git -C "$repo" update-ref "refs/tags/${tag}" "$tagsha"
}

run_aur() {
    local repo="$1"
    : > "$GH_LOG"
    : > "$GPG_LOG"
    : > "$UPD_LOG"
    (
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$repo/aur/PKGBUILD"
        export SRCINFO="$repo/aur/.SRCINFO"
        export PKGNAME=testpkg
        cd "$repo" || exit 1
        export REPO_NAME=testpkg
        export GH_USER=testuser
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export AURGEN_MODE=aur
        export GPG_KEY_ID="$KEY"
        export color_enabled=0
        export dry_run=0
        export no_wait=1
        export ascii_armor=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config
        gen_pkgbuild0
        # shellcheck source=../lib/modes/aur.sh
        source "$ROOT/lib/modes/aur.sh"
        # origin is https://example.com; the remote-tag check is covered by test-remote-tag.sh.
        aur_require_remote_tag() { :; }
        mode_aur
    ) >"$tmp/run.out" 2>"$tmp/run.err"
}

# Unknown package.source is rejected before a PKGBUILD is written.
(
    export AUR_DIR="$tmp/bad"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    mkdir -p "$AUR_DIR"
    printf 'package:\n  source: tarball\n' > "$AUR_DIR/aurgen.install.yaml"
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    load_aurgen_config
) >"$tmp/bad.out" 2>"$tmp/bad.err"
status=$?
if (( status == 0 )); then
    fail "package.source tarball should be rejected" "$tmp/bad.err"
fi
if ! grep -q "package.source must be release, archive, or signed-tag" "$tmp/bad.err"; then
    fail "unknown package.source should name the allowed values" "$tmp/bad.err"
fi

# Default (no package.source) is the release asset, including its upload.
repo="$(new_repo default)"
write_config "$repo" ""
light_tag "$repo"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "default source should behave as release, got $status" "$repo/aur/PKGBUILD"
fi
pkg="$repo/aur/PKGBUILD"
if ! grep -F -x -q 'source=("https://github.com/testuser/testpkg/releases/download/v1.0.0/testpkg-1.0.0.tar.gz" "https://github.com/testuser/testpkg/releases/download/v1.0.0/testpkg-1.0.0.tar.gz.sig")' "$pkg"; then
    fail "default source should be the release asset and its signature" "$pkg"
fi
if ! grep -F -x -q "b2sums=('deadbeef')" "$pkg"; then
    fail "default source should take the updpkgsums checksum" "$pkg"
fi
if ! grep -F -x -q "validpgpkeys=('$KEY')" "$pkg"; then
    fail "default source should keep the signing fingerprint" "$pkg"
fi
body="$(func_body "$pkg" package)"
if grep -q 'cd "' <<<"$body"; then
    fail "release package() should not cd into a subdirectory" "$pkg"
fi
if ! grep -q 'release create' "$GH_LOG"; then
    fail "default source should upload the release asset" "$GH_LOG"
fi
if ! grep -q called "$UPD_LOG"; then
    fail "default source should run updpkgsums" "$UPD_LOG"
fi
if [[ ! -f "$repo/aur/testpkg-1.0.0.tar.gz" ]]; then
    fail "default source should build the release tarball"
fi

# Explicit release is the same path.
repo="$(new_repo release)"
write_config "$repo" release
light_tag "$repo"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "source: release failed, got $status" "$repo/aur/PKGBUILD"
fi
pkg="$repo/aur/PKGBUILD"
if ! grep -F -x -q 'source=("https://github.com/testuser/testpkg/releases/download/v1.0.0/testpkg-1.0.0.tar.gz" "https://github.com/testuser/testpkg/releases/download/v1.0.0/testpkg-1.0.0.tar.gz.sig")' "$pkg"; then
    fail "source: release should be the release asset and its signature" "$pkg"
fi
if ! grep -F -x -q "validpgpkeys=('$KEY')" "$pkg"; then
    fail "source: release should keep the signing fingerprint" "$pkg"
fi
if ! grep -F -x -q "b2sums=('deadbeef')" "$pkg"; then
    fail "source: release should take the updpkgsums checksum" "$pkg"
fi
# The annotated tag's commit time, not text parsed from the tag header.
want_mtime="$(git -C "$repo" show -s --format=%ct 'v1.0.0^{commit}')"
got_mtime="$(python3 -I -c 'import sys, tarfile; print(int(tarfile.open(sys.argv[1]).getmembers()[0].mtime))' "$repo/aur/testpkg-1.0.0.tar.gz")"
if [[ "$got_mtime" != "$want_mtime" ]]; then
    fail "release tarball mtime should be the tag commit time: got $got_mtime, want $want_mtime"
fi

# Archive: tag tarball, real checksum, cd into <repo>-<pkgver>, no asset upload.
repo="$(new_repo archive)"
write_config "$repo" archive
light_tag "$repo"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "source: archive failed, got $status" "$repo/aur/PKGBUILD"
fi
pkg="$repo/aur/PKGBUILD"
if ! grep -F -x -q 'source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")' "$pkg"; then
    fail "archive source line mismatch" "$pkg"
fi
if ! grep -F -x -q "b2sums=('deadbeef')" "$pkg"; then
    fail "archive should take the updpkgsums checksum" "$pkg"
fi
if grep -q '^validpgpkeys=' "$pkg"; then
    fail "archive has no signature, so validpgpkeys should be absent" "$pkg"
fi
if ! grep -q called "$UPD_LOG"; then
    fail "archive should run updpkgsums" "$UPD_LOG"
fi
if grep -q 'release upload\|release create' "$GH_LOG"; then
    fail "archive should not upload a release asset" "$GH_LOG"
fi
if [[ -e "$repo/aur/testpkg-1.0.0.tar.gz" ]]; then
    fail "archive should not build a release tarball"
fi
if [[ -s "$GPG_LOG" ]]; then
    fail "archive should not call gpg" "$GPG_LOG"
fi
for fn in build check package; do
    body="$(func_body "$pkg" "$fn")"
    if ! grep -F -q 'cd "$srcdir/testpkg-$pkgver"' <<<"$body"; then
        fail "archive ${fn}() should cd into the tag archive directory" "$pkg"
    fi
done
if ! bash -n "$pkg"; then
    fail "archive PKGBUILD failed bash -n" "$pkg"
fi
cp "$repo/aur/PKGBUILD.0" "$tmp/archive-prefixed"
git -C "$repo" tag 1.0.0
run_aur "$repo" || fail "archive with both tags failed"
cmp -s "$tmp/archive-prefixed" "$repo/aur/PKGBUILD.0" || fail "bare tag changed v-prefixed archive template"

# Signed tag: named git source, SKIP sums, fingerprint, cd into $pkgname.
repo="$(new_repo signed)"
write_config "$repo" signed-tag
signed_tag "$repo"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "source: signed-tag failed, got $status" "$repo/aur/PKGBUILD"
fi
pkg="$repo/aur/PKGBUILD"
if ! grep -F -x -q 'source=("$pkgname::git+$url.git#tag=v$pkgver?signed")' "$pkg"; then
    fail "signed-tag source line mismatch" "$pkg"
fi
if ! grep -F -x -q "b2sums=('SKIP')" "$pkg"; then
    fail "signed-tag should keep b2sums SKIP" "$pkg"
fi
if ! grep -F -x -q "validpgpkeys=('$TAG_SIGNER')" "$pkg"; then
    fail "signed-tag validpgpkeys should be the verified signer fingerprint" "$pkg"
fi
if ! grep -F -x -q "makedepends=('git')" "$pkg"; then
    fail "signed-tag should makedepend on git" "$pkg"
fi
if [[ -s "$UPD_LOG" ]]; then
    fail "signed-tag should not run updpkgsums" "$UPD_LOG"
fi
if grep -q 'release upload\|release create' "$GH_LOG"; then
    fail "signed-tag should not upload a release asset" "$GH_LOG"
fi
if [[ -e "$repo/aur/testpkg-1.0.0.tar.gz" ]]; then
    fail "signed-tag should not build a release tarball"
fi
if grep -q -- '--detach-sign' "$GPG_LOG"; then
    fail "signed-tag should not detach-sign a tarball" "$GPG_LOG"
fi
for fn in build check package; do
    body="$(func_body "$pkg" "$fn")"
    if ! grep -F -q 'cd "$srcdir/$pkgname"' <<<"$body"; then
        fail "signed-tag ${fn}() should cd into \$srcdir/\$pkgname" "$pkg"
    fi
done
if ! bash -n "$pkg"; then
    fail "signed-tag PKGBUILD failed bash -n" "$pkg"
fi
cp "$repo/aur/PKGBUILD.0" "$tmp/signed-prefixed"
git -C "$repo" tag 1.0.0
run_aur "$repo" || fail "signed-tag with both tags failed"
cmp -s "$tmp/signed-prefixed" "$repo/aur/PKGBUILD.0" || fail "bare tag changed v-prefixed signed-tag template"

# Bare tags keep makepkg variables and use the same tag for signature verification.
for kind in archive signed-tag; do
    repo="$(new_repo "$kind-bare")"
    write_config "$repo" "$kind"
    if [[ "$kind" == archive ]]; then
        git -C "$repo" tag -a 1.2.3 -m unsigned
        # shellcheck disable=SC2016 # makepkg variables must remain literal
        expected='source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/$pkgver.tar.gz")'
    else
        signed_tag "$repo" 1.2.3
        # shellcheck disable=SC2016 # makepkg variables must remain literal
        expected='source=("$pkgname::git+$url.git#tag=$pkgver?signed")'
    fi
    run_aur "$repo" || fail "$kind with bare tag failed"
    pkg="$repo/aur/PKGBUILD"
    grep -F -x -q "$expected" "$pkg" || fail "$kind bare source line mismatch" "$pkg"
    if [[ "$(grep -F -c 'Using bare version tag 1.2.3' "$tmp/run.out")" != 1 ]]; then
        fail "$kind should print one bare-tag notice" "$tmp/run.out"
    fi
    if [[ "$kind" == signed-tag ]]; then
        grep -F -x -q "validpgpkeys=('$TAG_SIGNER')" "$pkg" || fail "bare signed-tag signer mismatch" "$pkg"
    fi
done

# An unsigned annotated tag is not a signed tag.
repo="$(new_repo unsigned)"
write_config "$repo" signed-tag
light_tag "$repo"
run_aur "$repo"
status=$?
if (( status == 0 )); then
    fail "unsigned tag should fail signed-tag" "$repo/aur/PKGBUILD"
fi
if ! grep -q 'not a signed tag' "$tmp/run.err"; then
    fail "unsigned tag should report that the tag is not signed" "$tmp/run.err"
fi
if [[ -e "$repo/aur/testpkg-1.0.0.tar.gz" ]]; then
    fail "unsigned tag should not build a release tarball"
fi
if grep -q 'release upload\|release create' "$GH_LOG"; then
    fail "unsigned tag should not upload a release asset" "$GH_LOG"
fi

# A missing vX.Y.Z tag fails before any upload.
repo="$(new_repo missing)"
write_config "$repo" signed-tag
run_aur "$repo"
status=$?
if (( status == 0 )); then
    fail "missing tag should fail signed-tag" "$repo/aur/PKGBUILD"
fi
if ! grep -q 'requires local tag v1.0.0' "$tmp/run.err"; then
    fail "missing tag should name v1.0.0" "$tmp/run.err"
fi
