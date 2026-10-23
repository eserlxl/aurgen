#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Local generation must succeed when gh and gpg are not on PATH.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-optional-tools.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$stub" "$repo/aur"

# PATH is only this directory. Copy every other tool, and leave gh and gpg out.
IFS=: read -r -a path_dirs <<< "${PATH}"
for dir in "${path_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for bin in "$dir"/*; do
        [[ -x "$bin" ]] || continue
        name="${bin##*/}"
        [[ "$name" == "gh" || "$name" == "gpg" ]] && continue
        [[ -e "$stub/$name" ]] && continue
        ln -s "$bin" "$stub/$name"
    done
done

if PATH="$stub" command -v gh >/dev/null 2>&1; then
    fail "gh is still on PATH"
fi
if PATH="$stub" command -v gpg >/dev/null 2>&1; then
    fail "gpg is still on PATH"
fi

printf 'Local package without optional tools.\n' > "$repo/README.md"
printf '1.2.3\n' > "$repo/VERSION"
git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
git -C "$repo" remote add origin "https://example.com/testuser/optpkg.git"
git -C "$repo" add README.md VERSION
git -C "$repo" commit -q -m init

if ! (
    export PATH="$stub"
    unset GPG_KEY_ID
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=optpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=local
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/local.out" 2>"$tmp/local.err"; then
    fail "local generation failed without gh or gpg" "$tmp/local.err"
fi

pkgbuild="$repo/aur/PKGBUILD.0"
if [[ ! -f "$pkgbuild" ]]; then
    fail "PKGBUILD.0 was not written"
fi
if ! grep -F -x -q -- "pkgdesc='Local package without optional tools.'" "$pkgbuild"; then
    fail "pkgdesc should fall back to the README line" "$pkgbuild"
fi
if grep -q '^validpgpkeys=' "$pkgbuild"; then
    fail "local mode should omit validpgpkeys" "$pkgbuild"
fi

# aur mode still requires a key (gpg is absent, so selection fails before gh).
if (
    export PATH="$stub"
    unset GPG_KEY_ID
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=optpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=aur
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/aur.out" 2>"$tmp/aur.err"; then
    fail "aur generation should abort without a GPG key" "$tmp/aur.out"
fi
# gh is missing too, so only this message shows the key check is what stopped it.
grep -F -q 'No GPG key found and not in test mode' "$tmp/aur.err" || fail "aur generation did not stop on the missing GPG key" "$tmp/aur.err"

# One signing-capable secret key, still no gh: aur release generation must succeed.
git -C "$repo" tag v1.2.3
cat >| "$stub/gpg" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--list-secret-keys" ]]; then
    printf '%s\n' 'sec:u:4096:1:ABC:1::::::scSC:'
    printf '%s\n' 'fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:'
    exit 0
fi
printf '%s\n' 'uid                            Test <t@example.com>'
exit 0
EOF
chmod +x "$stub/gpg"
if ! (
    export PATH="$stub"
    unset GPG_KEY_ID
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=optpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=aur
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >|"$tmp/aur-gh.out" 2>|"$tmp/aur-gh.err"; then
    fail "aur generation failed without gh" "$tmp/aur-gh.err"
fi
if [[ ! -f "$pkgbuild" ]]; then
    fail "aur release generation did not write PKGBUILD.0"
fi
if ! grep -F -x -q -- "pkgver=1.2.3" "$pkgbuild"; then
    fail "aur release generation should preserve the tagged version" "$pkgbuild"
fi
if ! grep -F -q -- "0123456789ABCDEF0123456789ABCDEF01234567" "$pkgbuild"; then
    fail "aur release generation should include the signing key" "$pkgbuild"
fi
