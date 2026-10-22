#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-namcap-pkg.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
trace="$tmp/makepkg-args"

export PATH="$stub:$PATH"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_LOG="$tmp/out.log"
export color_enabled=0
export DEBUG_LEVEL=0
export PKGNAME=demo
export dry_run=0 build_only=0
unset AURGEN_CHROOT_DIR
: > "$AURGEN_ERROR_LOG"
: > "$AURGEN_LOG"
: > "$trace"
pkgdest="$tmp/PKGDEST dir"
mkdir -p "$pkgdest"
built="$pkgdest/${PKGNAME}-1.0-1-any.pkg.tar.zst"
stale="$tmp/${PKGNAME}-0.9-1-any.pkg.tar.zst"
printf 'old\n' > "$stale"
: > "$tmp/namcap-args"

# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
export color_enabled=0
init_colors
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"

cat > "$stub/makepkg" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$trace"
if [[ "\$1" == "-sf" ]]; then
    printf 'pkg\\n' > "$built"
elif [[ "\$1" == "--packagelist" ]]; then
    printf '%s\\n' "$built"
fi
exit 0
EOF
chmod +x "$stub/makepkg"

cat > "$stub/namcap" <<EOF
#!/bin/bash
printf '%s\\n' "\$1" >> "$tmp/namcap-args"
printf '%s\\n' "\$1 E: missing dependency"
exit 1
EOF
chmod +x "$stub/namcap"

cd "$tmp" || exit 1
if install_pkg local >"$tmp/e.out" 2>"$tmp/e.err"; then
    fail "E: finding should stop local install"
fi
grep -Fx -- '-sf' "$trace" >/dev/null || fail "E: case should build with makepkg -sf"
if grep -Fx -- '-i' "$trace" >/dev/null; then
    fail "E: finding should stop before makepkg -i"
fi
grep -F ' E: ' "$tmp/e.err" >/dev/null || fail "E: line was not printed"
[[ "$(cat "$tmp/namcap-args")" == "$built" ]] || fail "E: namcap should see only the listed package"

: >| "$trace"
: >| "$tmp/namcap-args"
rm -f "$built"
if build_only=1 install_pkg local >|"$tmp/build-e.out" 2>|"$tmp/build-e.err"; then
    fail "E: finding should fail build-only"
fi
[[ "$(cat "$trace")" == $'-sf\n--packagelist' ]] || fail "build-only E: case should build and list without installing"
[[ "$(cat "$tmp/namcap-args")" == "$built" ]] || fail "build-only E: case should check only the listed package"
grep -F ' E: ' "$tmp/build-e.err" >/dev/null || fail "build-only E: line was not printed"

cat > "$stub/namcap" <<EOF
#!/bin/bash
printf '%s\\n' "\$1" >> "$tmp/namcap-args"
printf '%s\\n' "\$1 W: extra file"
exit 0
EOF
chmod +x "$stub/namcap"
: > "$trace"
: > "$tmp/namcap-args"
rm -f "$built"

if ! install_pkg local >"$tmp/w.out" 2>"$tmp/w.err"; then
    fail "W: findings should still install"
fi
[[ "$(cat "$trace")" == $'-sf\n--packagelist\n-i' ]] || fail "W: case should build, list, then install"
[[ "$(cat "$tmp/namcap-args")" == "$built" ]] || fail "namcap should see only the listed package"
grep -F ' W: ' "$tmp/w.out" >/dev/null || fail "W: line was not shown"
if grep -F ' E: ' "$tmp/w.out" "$tmp/w.err" >/dev/null; then
    fail "W-only namcap output should not report an error"
fi

: >| "$trace"
: >| "$tmp/namcap-args"
rm -f "$built"
if ! build_only=1 install_pkg local >|"$tmp/build-w.out" 2>|"$tmp/build-w.err"; then
    fail "W: findings should allow build-only to succeed"
fi
[[ "$(cat "$trace")" == $'-sf\n--packagelist' ]] || fail "build-only should build and list without installing"
[[ "$(cat "$tmp/namcap-args")" == "$built" ]] || fail "build-only should check only the listed package"
grep -F ' W: ' "$tmp/build-w.out" >/dev/null || fail "build-only W: line was not shown"

# A namcap that crashes prints no finding line; the package was not checked.
cat > "$stub/namcap" <<'EOF'
#!/bin/bash
printf '%s\n' 'Traceback (most recent call last):' '  File "/usr/bin/namcap", line 1' 'ImportError: no module'
exit 1
EOF
chmod +x "$stub/namcap"
: > "$trace"
rm -f "$built"
if install_pkg local >"$tmp/c.out" 2>"$tmp/c.err"; then
    fail "a namcap crash should stop local install"
fi
if grep -Fx -- '-i' "$trace" >/dev/null; then
    fail "a namcap crash should stop before makepkg -i"
fi
grep -F 'namcap failed (exit 1): Traceback' "$tmp/c.err" >/dev/null || fail "a namcap crash was not reported" "$tmp/c.err"

mv "$stub/namcap" "$tmp/namcap"
: >| "$trace"
rm -f "$built"
if ! PATH="$stub" build_only=1 install_pkg local >|"$tmp/build-no-namcap.out" 2>|"$tmp/build-no-namcap.err"; then
    fail "build-only should succeed without namcap"
fi
[[ "$(cat "$trace")" == '-sf' && -f "$built" ]] || fail "build-only without namcap should only build with makepkg -sf"
