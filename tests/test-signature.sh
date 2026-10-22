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
# The key tests start a gpg-agent for $tmp/gnupg; stop it on every exit, failures included.
trap 'gpgconf --homedir "$tmp/gnupg" --kill gpg-agent >/dev/null 2>&1; rm -rf "$tmp"' EXIT

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
# The top-level rewrite checks validate with makepkg; stub only makepkg here,
# the key tests below need the real gpg.
mkdir -p "$tmp/mkbin"
ln -s "$stub/makepkg" "$tmp/mkbin/makepkg"
PATH="$tmp/mkbin:$PATH"

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
    select_gpg_key || exit 1
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

# package.gpg_key picks one of two secret keys without a prompt; GPG_KEY_ID wins.
first=0123456789ABCDEF0123456789ABCDEF01234567
second=89ABCDEF0123456789ABCDEF0123456789ABCDEF
cat >| "$stub/gpg" <<EOF
#!/bin/bash
if [[ "\$1" == "--list-secret-keys" && "\${2:-}" == "--with-colons" ]]; then
    printf '%s\n' \\
        'sec:u:255:22:0123456789ABCDEF:1700000000::::::scESC::::::' \\
        'fpr:::::::::$first:' \\
        'uid:u::::1700000000::$first::First <first@example.com>::::::::::0:' \\
        'sec:u:255:22:89ABCDEF01234567:1700000000::::::scESC::::::' \\
        'fpr:::::::::$second:' \\
        'uid:u::::1700000000::$second::Second <second@example.com>::::::::::0:'
    exit 0
fi
if [[ "\$1" == "--list-secret-keys" ]]; then
    printf '%s\n' 'uid           [ ultimate ] Test User <t@example.com>'
    exit 0
fi
exit 1
EOF
chmod +x "$stub/gpg"
mkdir -p "$tmp/home" "$tmp/gnupg-stub"
# select_with_config GPG_KEY [PRESET_GPG_KEY_ID]: stdin is never a terminal.
select_with_config() {
    (
        set +u
        unset GPG_KEY_ID
        if [[ -n "${2:-}" ]]; then
            export GPG_KEY_ID="$2"
        fi
        export HOME="$tmp/home"
        export GNUPGHOME="$tmp/gnupg-stub"
        export PATH="$stub:$PATH"
        export dry_run=0
        export color_enabled=0
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export PKG_GPG_KEY="$1"
        select_gpg_key || exit 1
        printf '%s\n' "$GPG_KEY_ID" >| "$tmp/selkey"
    ) </dev/null 2>"$tmp/select.err"
}
rm -f "$tmp/selkey"
select_with_config "$second" || fail "gpg_key with the second fingerprint should select it" "$tmp/select.err"
if [[ "$(cat "$tmp/selkey")" != "$second" ]]; then
    fail "gpg_key should select the second key, got $(cat "$tmp/selkey")"
fi
rm -f "$tmp/selkey"
select_with_config "0123456789abcdef" || fail "a 16-hex gpg_key suffix should select its key" "$tmp/select.err"
if [[ "$(cat "$tmp/selkey")" != "$second" ]]; then
    fail "a 16-hex gpg_key suffix should give the full second fingerprint, got $(cat "$tmp/selkey")"
fi
rm -f "$tmp/selkey"
select_with_config "$second" "$first" || fail "GPG_KEY_ID with gpg_key set should succeed" "$tmp/select.err"
if [[ "$(cat "$tmp/selkey")" != "$first" ]]; then
    fail "GPG_KEY_ID should win over gpg_key, got $(cat "$tmp/selkey")"
fi
if select_with_config "DEADBEEFDEADBEEF"; then
    fail "a gpg_key matching no secret key should fail"
fi
if ! grep -q 'package.gpg_key' "$tmp/select.err"; then
    fail "a gpg_key matching no secret key should name gpg_key" "$tmp/select.err"
fi

# Only usable signing keys are candidates, including for package.gpg_key.
cat >| "$stub/gpg" <<EOF
#!/bin/bash
if [[ "\$1" == "--list-secret-keys" && "\${2:-}" == "--with-colons" ]]; then
    printf '%s\n' \\
        'sec:e:255:22:0123456789ABCDEF:1700000000::::::scESC::::::' \\
        'fpr:::::::::$first:' \\
        'sec:r:255:22:1111111111111111:1700000000::::::scESC::::::' \\
        'fpr:::::::::1111111111111111111111111111111111111111:' \\
        'sec:d:255:22:2222222222222222:1700000000::::::scESC::::::' \\
        'fpr:::::::::2222222222222222222222222222222222222222:' \\
        'sec:i:255:22:3333333333333333:1700000000::::::scESC::::::' \\
        'fpr:::::::::3333333333333333333333333333333333333333:' \\
        'sec:u:255:22:4444444444444444:1700000000::::::cC::::::' \\
        'fpr:::::::::4444444444444444444444444444444444444444:'
    if [[ "\${NO_USABLE_GPG_KEYS:-0}" != 1 ]]; then
        printf '%s\n' \\
            'sec:u:255:22:89ABCDEF01234567:1700000000::::::scESC::::::' \\
            'fpr:::::::::$second:'
    fi
    exit 0
fi
if [[ "\$1" == "--list-secret-keys" ]]; then
    printf '%s\n' 'uid           [ ultimate ] Test User <t@example.com>'
    exit 0
fi
exit 1
EOF
select_with_config "" || fail "the only usable signing key should be auto-selected" "$tmp/select.err"
if [[ "$(cat "$tmp/selkey")" != "$second" ]]; then
    fail "auto-selection should skip unusable keys, got $(cat "$tmp/selkey")"
fi
select_with_config "$second" || fail "gpg_key should accept a usable signing key" "$tmp/select.err"
for unusable_key in "$first" \
    1111111111111111111111111111111111111111 \
    2222222222222222222222222222222222222222 \
    3333333333333333333333333333333333333333 \
    4444444444444444444444444444444444444444; do
    if select_with_config "$unusable_key"; then
        fail "gpg_key should reject unusable key $unusable_key"
    fi
done
select_with_config "" "$first" || fail "a preset GPG_KEY_ID should still bypass filtering" "$tmp/select.err"
if [[ "$(cat "$tmp/selkey")" != "$first" ]]; then
    fail "a preset GPG_KEY_ID should be preserved"
fi
if NO_USABLE_GPG_KEYS=1 select_with_config ""; then
    fail "selection should fail when no usable signing keys remain"
fi
if ! grep -Fq 'No usable GPG signing key found (expired, revoked or certify-only keys are skipped). Create one with: gpg --full-generate-key' "$tmp/select.err"; then
    fail "no usable signing keys should explain how to create one" "$tmp/select.err"
fi

# A typed "08" picks key 8: a leading zero must not be read as octal.
stub9="$tmp/stub9"
mkdir -p "$stub9"
cat > "$stub9/gpg" <<'EOF'
#!/bin/bash
if [[ "$1" == "--list-secret-keys" && "${2:-}" == "--with-colons" ]]; then
    for i in 1 2 3 4 5 6 7 8 9; do
        printf 'sec:u:255:22:%016d:1700000000::::::scESC::::::\n' "$i"
        printf 'fpr:::::::::%040d:\n' "$i"
    done
    exit 0
fi
if [[ "$1" == "--list-secret-keys" ]]; then
    printf '%s\n' 'uid           [ ultimate ] Test User <t@example.com>'
    exit 0
fi
exit 1
EOF
chmod +x "$stub9/gpg"
if ! (
    set +u
    unset GPG_KEY_ID PKG_GPG_KEY
    export HOME="$tmp/home" GNUPGHOME="$tmp/gnupg-stub" PATH="$stub9:$PATH"
    export dry_run=0 color_enabled=0 AURGEN_ERROR_LOG="$tmp/err.log"
    have_tty() { return 0; }
    select_gpg_key || exit 1
    printf '%s\n' "$GPG_KEY_ID" >| "$tmp/selkey"
) <<<"08" 2>"$tmp/select.err"; then
    fail "choosing 08 should select key 8" "$tmp/select.err"
fi
[[ "$(cat "$tmp/selkey")" == "$(printf '%040d' 8)" ]] || fail "choosing 08 should give the eighth key, got $(cat "$tmp/selkey")"

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
    select_gpg_key || exit 1
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

# A dry run with a real preset GPG_KEY_ID writes an empty signature and never runs gpg.
gpglog="$tmp/gpg.argv"
: > "$gpglog"
recstub="$tmp/recbin"
mkdir -p "$recstub"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\nexit 0\n' "$gpglog" > "$recstub/gpg"
chmod +x "$recstub/gpg"
cp "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD"
rm -f "$repo/aur/demo-1.0.0.tar.gz.sig"
(
    set +u
    export PATH="$recstub:$stub:$PATH"
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
    export GPG_KEY_ID=ABCDEF0123456789
    export LIB_INSTALL_DIR="$tmp/nolib"
    # shellcheck source=../lib/modes/aur.sh
    source "$ROOT/lib/modes/aur.sh"
    filter_pkgbuild_sources() { cat; }
    mode_aur
) >"$tmp/aur-key.out" 2>"$tmp/aur-key.err"
status=$?
if (( status != 0 )); then
    fail "dry run with a preset GPG_KEY_ID should succeed, got $status" "$tmp/aur-key.err"
fi
if grep -q -- '--detach-sign' "$gpglog"; then
    fail "dry run with a preset GPG_KEY_ID ran gpg --detach-sign" "$gpglog"
fi
if [[ ! -f "$repo/aur/demo-1.0.0.tar.gz.sig" || -s "$repo/aur/demo-1.0.0.tar.gz.sig" ]]; then
    fail "dry run should leave an empty signature file" "$tmp/aur-key.err"
fi
if ! grep -qx "validpgpkeys=('ABCDEF0123456789')" "$repo/aur/PKGBUILD"; then
    fail "dry run should keep the preset key in validpgpkeys" "$repo/aur/PKGBUILD"
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

# validpgpkeys follows the key that signed v$pkgver, not another local secret key.
mkdir -p "$tmp/makepkg-bin" "$tmp/gnupg"
chmod 700 "$tmp/gnupg"
printf '#!/bin/bash\nexit 0\n' > "$tmp/makepkg-bin/makepkg"
chmod +x "$tmp/makepkg-bin/makepkg"
export GNUPGHOME="$tmp/gnupg"
if ! gpg --batch --passphrase '' --quick-gen-key 'Signer <signer@example.com>' >"$tmp/gpg-signer.out" 2>&1; then
    fail "could not create the signing key" "$tmp/gpg-signer.out"
fi
if ! gpg --batch --passphrase '' --quick-gen-key 'Other <other@example.com>' >"$tmp/gpg-other.out" 2>&1; then
    fail "could not create the second secret key" "$tmp/gpg-other.out"
fi
signer="$(gpg --batch --with-colons --list-secret-keys 'signer@example.com' 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
other="$(gpg --batch --with-colons --list-secret-keys 'other@example.com' 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
if [[ -z "$signer" || -z "$other" || "$signer" == "$other" ]]; then
    fail "expected two distinct fingerprints, signer=$signer other=$other"
fi

init_sig_repo() {
    local repo="$1"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" config commit.gpgsign false
    git -C "$repo" config tag.gpgsign false
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
source=("https://example.com/demo-1.0.0.tar.gz")
b2sums=('SKIP')
EOF
    cp "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD"
}

invoke_signed_aur() {
    local repo="$1"
    local key_id="$2"
    (
        set +u
        export PATH="$tmp/makepkg-bin:$PATH"
        export GNUPGHOME="$tmp/gnupg"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$repo/aur/PKGBUILD"
        export SRCINFO="$repo/aur/.SRCINFO"
        export AURGEN_ERROR_LOG="$tmp/signed.aurerr"
        export AURGEN_LOG="$tmp/signed.aurlog"
        export color_enabled=0
        export dry_run=1
        export no_wait=1
        export ascii_armor=0
        export PKGNAME=demo
        export GH_USER=example
        export REPO_NAME=demo
        export GPG_KEY_ID="$key_id"
        export PKG_SOURCE=signed-tag
        export LIB_INSTALL_DIR="$tmp/nolib"
        : > "$AURGEN_ERROR_LOG"
        : > "$AURGEN_LOG"
        # shellcheck source=../lib/modes/aur.sh
        source "$ROOT/lib/modes/aur.sh"
        mode_aur
    )
}

srepo="$tmp/signtag"
init_sig_repo "$srepo"
printf "validpgpkeys=('%s')\n" "$other" >> "$srepo/aur/PKGBUILD.0"
cp "$srepo/aur/PKGBUILD.0" "$srepo/aur/PKGBUILD"
if ! git -C "$srepo" -c user.signingkey="$signer" tag -s v1.0.0 -m 'v1.0.0' >"$tmp/tag.out" 2>&1; then
    fail "could not sign tag v1.0.0" "$tmp/tag.out"
fi
invoke_signed_aur "$srepo" "$other" >"$tmp/sign.out" 2>"$tmp/sign.err"
status=$?
if (( status != 0 )); then
    fail "signed-tag mode_aur should use the tag signer, got $status" "$tmp/sign.err"
fi
if ! grep -qx "validpgpkeys=('$signer')" "$srepo/aur/PKGBUILD"; then
    fail "signed-tag validpgpkeys should be the key that signed v1.0.0" "$srepo/aur/PKGBUILD"
fi
if grep -q "$other" "$srepo/aur/PKGBUILD"; then
    fail "signed-tag validpgpkeys should not be the other secret key" "$srepo/aur/PKGBUILD"
fi

# An armored tag that does not verify stops aur mode.
brepo="$tmp/badsign"
init_sig_repo "$brepo"
bcommit="$(git -C "$brepo" rev-parse HEAD)"
cat > "$tmp/fake-tag" << EOF
object ${bcommit}
type commit
tag v1.0.0
tagger Test <t@example.com> 1700000000 +0000

v1.0.0

-----BEGIN PGP SIGNATURE-----

ZmFrZQ==
-----END PGP SIGNATURE-----
EOF
btag="$(git -C "$brepo" hash-object -t tag -w "$tmp/fake-tag")"
git -C "$brepo" update-ref refs/tags/v1.0.0 "$btag"
invoke_signed_aur "$brepo" "$other" >"$tmp/badsign.out" 2>"$tmp/badsign.err"
status=$?
if (( status == 0 )); then
    fail "unverifiable tag should stop aur mode" "$brepo/aur/PKGBUILD"
fi
if ! grep -q 'signature verification failed' "$tmp/badsign.err"; then
    fail "unverifiable tag should report verification failure" "$tmp/badsign.err"
fi
ascii_armor=1
set_signature_ext
if [[ "$SIGNATURE_EXT" != ".asc" || "$GPG_ARMOR_OPT" != "--armor" ]]; then
    fail "ascii_armor=1 should give .asc and --armor, got '$SIGNATURE_EXT' '$GPG_ARMOR_OPT'"
fi
ascii_armor=0
set_signature_ext
if [[ "$SIGNATURE_EXT" != ".sig" || -n "$GPG_ARMOR_OPT" ]]; then
    fail "ascii_armor=0 should give .sig and no armor option, got '$SIGNATURE_EXT' '$GPG_ARMOR_OPT'"
fi

