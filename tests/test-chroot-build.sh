#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -euo pipefail
set -o noclobber

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-chroot.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1" >&2
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub" "$tmp/chroot dir/root" "$tmp/PKGDEST dir"
export AURGEN_CHROOT_DIR="$tmp/chroot dir"
export CHROOT_TRACE="$tmp/chroot-args"
export MAKEPKG_TRACE="$tmp/makepkg-args"
export NAMCAP_TRACE="$tmp/namcap-args"
export PACMAN_TRACE="$tmp/pacman-args"
export BUILT="$tmp/PKGDEST dir/demo-1.0-1-any.pkg.tar.zst"
export SPLIT="$tmp/PKGDEST dir/demo-docs-1.0-1-any.pkg.tar.zst"
export PKGNAME=demo
export color_enabled=0
export dry_run=0
export DEBUG_LEVEL=0
unset TEST_LOG_FILE TEST_ERRORS BUILD_STATUS LIST_STATUS NAMCAP_LEVEL

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
init_error_trap

cat >| "$stub/makechrootpkg" <<'EOF'
#!/bin/bash
printf '<%s>\n' "$@" >> "$CHROOT_TRACE"
if (( ${BUILD_STATUS:-0} )); then
    exit "$BUILD_STATUS"
fi
printf 'pkg\n' >| "$BUILT"
printf 'pkg\n' >| "$SPLIT"
EOF
cat >| "$stub/makepkg" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MAKEPKG_TRACE"
case "$1" in
    --packagelist)
        if (( ${LIST_STATUS:-0} )); then
            exit "$LIST_STATUS"
        fi
        printf '%s\n' "$BUILT" "$SPLIT"
        ;;
    -sf|-sif)
        printf 'pkg\n' >| "$BUILT"
        printf 'pkg\n' >| "$SPLIT"
        ;;
    -i) ;;
    *) exit 99 ;;
esac
EOF
cat >| "$stub/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$NAMCAP_TRACE"
printf '%s %s: stub finding\n' "$1" "${NAMCAP_LEVEL:-W}"
EOF
cat >| "$stub/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$PACMAN_TRACE"
exit 99
EOF
chmod +x "$stub/makechrootpkg" "$stub/makepkg" "$stub/namcap" "$stub/pacman"

reset_trace() {
    : >| "$CHROOT_TRACE"
    : >| "$MAKEPKG_TRACE"
    : >| "$NAMCAP_TRACE"
    : >| "$PACMAN_TRACE"
}

run_local() {
    (
        # Only stubs are reachable, including when an optional tool is absent.
        export PATH="$stub"
        install_pkg local
    ) >| "$tmp/out" 2>| "$tmp/err"
}

cd "$tmp"
reset_trace
run_local || fail "chroot build failed"
[[ "$(cat "$CHROOT_TRACE")" == "<-c>"$'\n'"<-r>"$'\n'"<$AURGEN_CHROOT_DIR>" ]] || fail "chroot path must be one argument"
[[ "$(cat "$MAKEPKG_TRACE")" == '--packagelist' ]] || fail "chroot mode must only list packages on the host"
[[ "$(cat "$NAMCAP_TRACE")" == "$BUILT"$'\n'"$SPLIT" ]] || fail "namcap must check the listed packages"
[[ ! -s "$PACMAN_TRACE" ]] || fail "chroot mode must not install with pacman"

reset_trace
status=0
BUILD_STATUS=23 run_local || status=$?
[[ "$status" == 23 ]] || fail "chroot build status must propagate"
[[ ! -s "$MAKEPKG_TRACE" && ! -s "$NAMCAP_TRACE" && ! -s "$PACMAN_TRACE" ]] || fail "failed build must stop before host commands"

reset_trace
if AURGEN_CHROOT_DIR="$tmp/missing" run_local; then
    fail "missing root must be refused"
fi
grep -F 'Chroot root directory missing' "$tmp/err" >/dev/null || fail "missing root error not shown"
[[ ! -s "$CHROOT_TRACE" && ! -s "$MAKEPKG_TRACE" && ! -s "$PACMAN_TRACE" ]] || fail "missing root must not build or install"

mv "$stub/makechrootpkg" "$tmp/makechrootpkg"
reset_trace
if run_local; then
    fail "missing makechrootpkg must be refused"
fi
grep -F 'makechrootpkg is required' "$tmp/err" >/dev/null || fail "missing tool error not shown"
[[ ! -s "$MAKEPKG_TRACE" && ! -s "$NAMCAP_TRACE" && ! -s "$PACMAN_TRACE" ]] || fail "missing tool must not fall back to host build"

reset_trace
AURGEN_CHROOT_DIR="$tmp/missing" dry_run=1 run_local || fail "dry run must skip chroot validation"
[[ ! -s "$CHROOT_TRACE" && ! -s "$MAKEPKG_TRACE" && ! -s "$NAMCAP_TRACE" && ! -s "$PACMAN_TRACE" ]] || fail "dry run must skip all commands"
mv "$tmp/makechrootpkg" "$stub/makechrootpkg"

reset_trace
if NAMCAP_LEVEL=E run_local; then
    fail "namcap errors must fail chroot mode"
fi
[[ "$(cat "$MAKEPKG_TRACE")" == '--packagelist' && ! -s "$PACMAN_TRACE" ]] || fail "namcap errors must not install"

reset_trace
if LIST_STATUS=17 run_local; then
    fail "package listing failure must fail chroot mode"
fi
grep -F 'makepkg --packagelist failed' "$tmp/err" >/dev/null || fail "package listing error not shown"
[[ ! -s "$NAMCAP_TRACE" && ! -s "$PACMAN_TRACE" ]] || fail "failed listing must stop before checks or install"

mv "$stub/namcap" "$tmp/namcap"
reset_trace
run_local || fail "chroot build without namcap failed"
[[ -s "$CHROOT_TRACE" && ! -s "$MAKEPKG_TRACE" && ! -s "$PACMAN_TRACE" ]] || fail "chroot without namcap must not install"

reset_trace
unset AURGEN_CHROOT_DIR
run_local || fail "host build without namcap failed"
[[ ! -s "$CHROOT_TRACE" && "$(cat "$MAKEPKG_TRACE")" == '-sif' ]] || fail "unset chroot must keep makepkg -sif"

mv "$tmp/namcap" "$stub/namcap"
reset_trace
run_local || fail "host build with namcap failed"
[[ ! -s "$CHROOT_TRACE" && "$(cat "$MAKEPKG_TRACE")" == $'-sf\n--packagelist\n-i' ]] || fail "unset chroot must keep build, check, install"

reset_trace
AURGEN_CHROOT_DIR='' run_local || fail "empty chroot must use host build"
[[ ! -s "$CHROOT_TRACE" && "$(cat "$MAKEPKG_TRACE")" == $'-sf\n--packagelist\n-i' ]] || fail "empty chroot must keep host behavior"
