#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
for tool in gh curl gpg updpkgsums; do
    printf '#!/bin/bash\nexit 1\n' > "$stub/$tool"
    chmod +x "$stub/$tool"
done
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/makepkg"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"

# Source rewrite lists the tarball and its signature.
pkg="$tmp/rewrite/PKGBUILD"
mkdir -p "$tmp/rewrite"
cat > "$pkg" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=("https://example.com/old.tar.gz")
b2sums=('deadbeef')
EOF
if ! update_source_array_in_pkgbuild "$pkg" "https://example.com/demo-1.0.0.tar.gz" "https://example.com/demo-1.0.0.tar.gz.sig"; then
    fail "update_source_array_in_pkgbuild failed for .sig" "$pkg"
fi
if ! grep -qx 'source=("https://example.com/demo-1.0.0.tar.gz" "https://example.com/demo-1.0.0.tar.gz.sig")' "$pkg"; then
    fail "source= should list the tarball and its .sig" "$pkg"
fi

cat > "$pkg" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=("https://example.com/old.tar.gz")
b2sums=('deadbeef')
EOF
if ! update_source_array_in_pkgbuild "$pkg" "https://example.com/demo-1.0.0.tar.gz" "https://example.com/demo-1.0.0.tar.gz.asc"; then
    fail "update_source_array_in_pkgbuild failed for .asc" "$pkg"
fi
if ! grep -qx 'source=("https://example.com/demo-1.0.0.tar.gz" "https://example.com/demo-1.0.0.tar.gz.asc")' "$pkg"; then
    fail "source= should list the tarball and its .asc" "$pkg"
fi

# No signature argument leaves a single source (local mode).
cat > "$pkg" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=("https://example.com/old.tar.gz")
b2sums=('deadbeef')
EOF
if ! update_source_array_in_pkgbuild "$pkg" "demo-1.0.0.tar.gz"; then
    fail "update_source_array_in_pkgbuild failed without a signature" "$pkg"
fi
if ! grep -qx 'source=("demo-1.0.0.tar.gz")' "$pkg"; then
    fail "source= without a signature should stay a single tarball" "$pkg"
fi
if ! grep -qx "b2sums=('deadbeef')" "$pkg"; then
    fail "b2sums without a signature should be unchanged" "$pkg"
fi

# Fingerprint comes from the fpr record after sec, not field 5 and not the subkey.
cat > "$stub/gpg" <<'EOF'
#!/bin/bash
if [[ "$1" == "--list-secret-keys" && "${2:-}" == "--with-colons" ]]; then
    printf '%s\n' \
        'sec:u:255:22:ABCD1234ABCD1234:1700000000::::::scESC::::::' \
        'fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:' \
        'uid:u::::1700000000::0123456789ABCDEF0123456789ABCDEF01234567::Test User <t@example.com>::::::::::0:' \
        'ssb:u:255:22:FFFF0000FFFF0000:1700000000::::::e::::::' \
        'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:'
    exit 0
fi
if [[ "$1" == "--list-secret-keys" ]]; then
    printf '%s\n' 'uid           [ ultimate ] Test User <t@example.com>'
    exit 0
fi
exit 1
EOF
chmod +x "$stub/gpg"
(
    set +u
    unset GPG_KEY_ID
    export PATH="$stub:$PATH"
    export dry_run=0
    export color_enabled=0
    export AURGEN_ERROR_LOG="$tmp/err.log"
    select_gpg_key
    printf '%s\n' "$GPG_KEY_ID" > "$tmp/keyid"
)
status=$?
if (( status != 0 )); then
    fail "select_gpg_key should accept the primary fingerprint, got $status"
fi
keyid=$(cat "$tmp/keyid")
if [[ "$keyid" != "0123456789ABCDEF0123456789ABCDEF01234567" ]]; then
    fail "GPG_KEY_ID should be the 40-hex fpr after sec, got $keyid"
fi

keys="$tmp/keys/PKGBUILD"
mkdir -p "$tmp/keys"
cat > "$keys" <<'EOF'
pkgname=demo
validpgpkeys=('ABCD1234ABCD1234')
validpgpkeys=('FFFFFFFFFFFFFFFF')
EOF
if ! write_validpgpkeys "$keys" "$keyid"; then
    fail "write_validpgpkeys failed" "$keys"
fi
count=$(grep -c '^validpgpkeys=' "$keys" || true)
if [[ "$count" != 1 ]]; then
    fail "validpgpkeys should appear once, got $count" "$keys"
fi
if ! grep -qx "validpgpkeys=('0123456789ABCDEF0123456789ABCDEF01234567')" "$keys"; then
    fail "validpgpkeys should be the 40-hex fingerprint" "$keys"
fi

# Dry-run keeps the placeholder and does not ask gpg.
cat > "$stub/gpg" <<'EOF'
#!/bin/bash
echo called >> "$AURGEN_LOG"
exit 1
EOF
chmod +x "$stub/gpg"
: > "$tmp/out.log"
(
    set +u
    unset GPG_KEY_ID
    export PATH="$stub:$PATH"
    export dry_run=1
    export color_enabled=0
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_LOG="$tmp/out.log"
    select_gpg_key
    printf '%s\n' "$GPG_KEY_ID" > "$tmp/drykey"
)
status=$?
if (( status != 0 )); then
    fail "dry-run select_gpg_key should succeed, got $status"
fi
if [[ "$(cat "$tmp/drykey")" != "TEST_KEY_FOR_DRY_RUN" ]]; then
    fail "dry-run should keep TEST_KEY_FOR_DRY_RUN, got $(cat "$tmp/drykey")"
fi
if [[ -s "$tmp/out.log" ]]; then
    fail "dry-run should not call gpg"
fi

# Release PKGBUILD: signature in source=, placeholder key exactly once.
repo="$tmp/aur"
mkdir -p "$repo/aur"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
printf 'x\n' > "$repo/payload.txt"
git -C "$repo" add payload.txt
git -C "$repo" commit -q -m init
cat > "$repo/aur/PKGBUILD.0" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
pkgdesc='demo'
arch=('x86_64')
url='https://example.com'
license=('GPL-3.0-or-later')
validpgpkeys=('ABCD1234ABCD1234')
validpgpkeys=('FFFFFFFFFFFFFFFF')
source=("https://example.com/demo-1.0.0.tar.gz")
b2sums=('SKIP')
EOF
cp "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD"
(
    set +u
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
    export ascii_armor=0
    export PKGNAME=demo
    export GH_USER=example
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export LIB_INSTALL_DIR="$tmp/nolib"
    mkdir -p "$LIB_INSTALL_DIR"
    : > "$AURGEN_ERROR_LOG"
    : > "$AURGEN_LOG"
    # shellcheck source=../lib/modes/aur.sh
    source "$ROOT/lib/modes/aur.sh"
    filter_pkgbuild_sources() { cat; }
    mode_aur
) >"$tmp/aur.out" 2>"$tmp/aur.err"
status=$?
if (( status != 0 )); then
    echo "mode_aur failed"
    cat "$tmp/aur.err"
    fail "mode_aur dry-run should succeed, got $status" "$repo/aur/PKGBUILD"
fi
if ! grep -q 'demo-1.0.0.tar.gz"' "$repo/aur/PKGBUILD"; then
    fail "release source= should list the tarball" "$repo/aur/PKGBUILD"
fi
if ! grep -q 'demo-1.0.0.tar.gz.sig"' "$repo/aur/PKGBUILD"; then
    fail "release source= should list the .sig" "$repo/aur/PKGBUILD"
fi
count=$(grep -c '^validpgpkeys=' "$repo/aur/PKGBUILD" || true)
if [[ "$count" != 1 ]]; then
    fail "release PKGBUILD should have one validpgpkeys line, got $count" "$repo/aur/PKGBUILD"
fi
if ! grep -qx "validpgpkeys=('TEST_KEY_FOR_DRY_RUN')" "$repo/aur/PKGBUILD"; then
    fail "dry-run release PKGBUILD should keep the test key" "$repo/aur/PKGBUILD"
fi
if ! grep -qx 'b2sums=("SKIP" "SKIP")' "$repo/aur/PKGBUILD"; then
    fail "dry-run signature package should SKIP both sums" "$repo/aur/PKGBUILD"
fi

# VCS output has no validpgpkeys, even when the template and GPG_KEY_ID supply one.
grepo="$tmp/git"
mkdir -p "$grepo/aur"
git -C "$grepo" init -q -b devel
git -C "$grepo" config user.email "t@example.com"
git -C "$grepo" config user.name "t"
git -C "$grepo" config commit.gpgsign false
printf 'x\n' > "$grepo/README"
git -C "$grepo" add README
git -C "$grepo" commit -q -m init
cat > "$grepo/aur/PKGBUILD.0" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
pkgdesc='demo'
arch=('x86_64')
url='https://example.com'
license=('GPL-3.0-or-later')
depends=()
makedepends=('cmake')
validpgpkeys=('ABCD1234ABCD1234')
validpgpkeys=(
  'FFFFFFFFFFFFFFFF'
)
source=("https://example.com/demo-1.0.0.tar.gz")
b2sums=('SKIP')
EOF
(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$grepo"
    export AUR_DIR="$grepo/aur"
    export PKGBUILD0="$grepo/aur/PKGBUILD.0"
    export PKGBUILD="$grepo/aur/PKGBUILD"
    export SRCINFO="$grepo/aur/.SRCINFO"
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
    # shellcheck source=../lib/modes/git.sh
    source "$ROOT/lib/modes/git.sh"
    mode_git
) >"$tmp/git.out" 2>"$tmp/git.err"
status=$?
if (( status != 0 )); then
    echo "mode_git failed"
    cat "$tmp/git.err"
    fail "mode_git should succeed, got $status" "$grepo/aur/PKGBUILD"
fi
if grep -q '^validpgpkeys=' "$grepo/aur/PKGBUILD"; then
    fail "VCS package without a signature should not emit validpgpkeys" "$grepo/aur/PKGBUILD"
fi
if grep -q 'FFFFFFFFFFFFFFFF' "$grepo/aur/PKGBUILD"; then
    fail "VCS package should drop a multi-line validpgpkeys array" "$grepo/aur/PKGBUILD"
fi
