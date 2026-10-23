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

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    require bash
)
status=$?
if (( status != 0 )); then
    echo "require bash should succeed, got $status"
    exit 1
fi

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    require aurgen-missing-tool-xyz
)
status=$?
if (( status == 0 )); then
    echo "require aurgen-missing-tool-xyz should fail"
    exit 1
fi

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/makepkg" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$stub/makepkg"

(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/srcinfo"
    export SRCINFO="$tmp/srcinfo/aur/.SRCINFO"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    mkdir -p "$PROJECT_ROOT/aur"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    generate_srcinfo
)
status=$?
if (( status == 0 )); then
    echo "generate_srcinfo should fail when makepkg --printsrcinfo fails"
    exit 1
fi
if [[ -e "$tmp/srcinfo/aur/.SRCINFO" ]]; then
    echo "generate_srcinfo should remove partial .SRCINFO"
    exit 1
fi

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    export PKGBUILD0="$tmp/dynamic/PKGBUILD.0"
    mkdir -p "$tmp/dynamic"
    printf '%s\n' 'pkgver=$(date)' >| "$PKGBUILD0"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    extract_pkgbuild_data
)
status=$?
if (( status == 0 )); then
    echo "extract_pkgbuild_data should fail on dynamic pkgver"
    exit 1
fi

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    export PKGBUILD0="$tmp/missing-pkgver/PKGBUILD.0"
    mkdir -p "$tmp/missing-pkgver"
    printf '%s\n' 'pkgname=example' >| "$PKGBUILD0"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    extract_pkgbuild_data
)
status=$?
if (( status == 0 )); then
    echo "extract_pkgbuild_data should fail when pkgver is missing"
    exit 1
fi

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    export PKGBUILD0="$tmp/static/PKGBUILD.0"
    mkdir -p "$tmp/static"
    printf '%s\n' 'pkgver=1.2.3' >| "$PKGBUILD0"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    extract_pkgbuild_data || exit 1
    [[ "$PKGVER" == "1.2.3" ]] || exit 1
)
status=$?
if (( status != 0 )); then
    echo "extract_pkgbuild_data should set PKGVER=1.2.3"
    exit 1
fi

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    have_tty() { return 0; }
    answer=
    payload='a"b$(touch '"$tmp"'/pwned)'
    prompt 'msg: ' answer <<< "$payload" || exit 1
    [[ "$answer" == "$payload" ]] || exit 1
    [[ ! -e "$tmp/pwned" ]] || exit 1
    prompt 'msg: ' answer 'fallback' <<< '' || exit 1
    [[ "$answer" == 'fallback' ]] || exit 1
)
status=$?
if (( status != 0 )); then
    echo "prompt should store the answer verbatim and use the default when empty"
    exit 1
fi

okstub="$tmp/bin-ok"
mkdir -p "$okstub"
printf '#!/bin/bash\nexit 0\n' >| "$okstub/makepkg"
chmod +x "$okstub/makepkg"
pkg="$tmp/noclobber/PKGBUILD"
mkdir -p "$tmp/noclobber"
printf '%s\n' 'pkgname=demo' 'source=("https://example.com/old.tar.gz")' >| "$pkg"
printf 'stale\n' >| "$pkg.tmp"

(
    set +u
    set -o noclobber
    export PATH="$okstub:$PATH"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    update_source_array_in_pkgbuild "$pkg" "https://example.com/new.tar.gz" || exit 1
    grep -qx 'source=("https://example.com/new.tar.gz")' "$pkg" || exit 1
)
status=$?
if (( status != 0 )); then
    echo "update_source_array_in_pkgbuild should replace source= when PKGBUILD.tmp already exists"
    exit 1
fi

pkg="$tmp/rollback/PKGBUILD"
mkdir -p "$tmp/rollback/home"
printf '%s\n' 'pkgname=demo' 'source=("https://example.com/old.tar.gz")' >| "$pkg"
cp "$pkg" "$pkg.original"
(
    set +u
    export HOME="$tmp/rollback/home"
    export PATH="$stub:$PATH"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    update_source_array_in_pkgbuild "$pkg" "https://example.com/new.tar.gz"
)
status=$?
if (( status == 0 )); then
    echo "update_source_array_in_pkgbuild should fail when makepkg --printsrcinfo fails"
    exit 1
fi
if ! cmp -s "$pkg.original" "$pkg"; then
    echo "update_source_array_in_pkgbuild should restore the original PKGBUILD when makepkg fails"
    exit 1
fi

# A multi-line source array may close on its last element; the lines after it stay.
pkg="$tmp/lastclose/PKGBUILD"
mkdir -p "$tmp/lastclose"
printf '%s\n' 'pkgname=demo' 'source=("https://example.com/old.tar.gz"' '        "fix.patch")' "b2sums=('SKIP' 'SKIP')" '' 'package() {' '    :' '}' >| "$pkg"
(
    set +u
    export PATH="$okstub:$PATH"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    update_source_array_in_pkgbuild "$pkg" "https://example.com/new.tar.gz" || exit 1
    grep -qx 'source=("https://example.com/new.tar.gz")' "$pkg" || exit 1
    grep -q '^package() {' "$pkg" || exit 1
    ! grep -q 'fix.patch' "$pkg" || exit 1
)
status=$?
if (( status != 0 )); then
    echo "a source array closed on its last element dropped the lines after it"
    cat "$pkg"
    exit 1
fi
