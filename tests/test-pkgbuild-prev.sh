#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-pkgbuild-prev.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
export GNUPGHOME="$tmp/gnupg"
export AURGEN_LOG="$tmp/aurgen.log"
export AURGEN_ERROR_LOG="$tmp/aurgen-error.log"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
mkdir -m 700 "$GNUPGHOME"

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 1\n' > "$stub/gh"
chmod +x "$stub/gh"
export PATH="$stub:$PATH"

unset GIT_CONFIG GIT_CONFIG_PARAMETERS AURGEN_KEEP_PREV RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO

export AUR_DIR="$tmp/aur"
export TEST_DIR="$tmp/test"
export GOLDEN_DIR="$tmp/golden"
export PKGNAME=example
export AURGEN_MODE=test
export DEBUG_LEVEL=0
export color_enabled=0
export GREEN=""
export RESET=""
mkdir -p "$AUR_DIR" "$TEST_DIR" "$GOLDEN_DIR"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/clean.sh
source "$ROOT/lib/modes/clean.sh"

printf 'old pkgbuild\n' > "$AUR_DIR/PKGBUILD"
printf 'stale prev\n' > "$AUR_DIR/PKGBUILD.prev"
printf 'old srcinfo\n' > "$AUR_DIR/.SRCINFO"

cleanup

if [[ -f "$AUR_DIR/PKGBUILD" ]]; then
    echo "cleanup left PKGBUILD in place"
    exit 1
fi
if [[ ! -f "$AUR_DIR/PKGBUILD.prev" ]]; then
    echo "cleanup did not write PKGBUILD.prev"
    exit 1
fi
if ! cmp -s "$AUR_DIR/PKGBUILD.prev" <(printf 'old pkgbuild\n'); then
    echo "PKGBUILD.prev does not hold the replaced PKGBUILD"
    exit 1
fi
if [[ -f "$AUR_DIR/.SRCINFO" ]]; then
    echo "cleanup left .SRCINFO in place"
    exit 1
fi
if ! cmp -s "$AUR_DIR/.SRCINFO.prev" <(printf 'old srcinfo\n'); then
    echo ".SRCINFO.prev does not hold the replaced .SRCINFO"
    exit 1
fi

printf 'second pkgbuild\n' > "$AUR_DIR/PKGBUILD"
export AURGEN_KEEP_PREV=1
cleanup
unset AURGEN_KEEP_PREV

if [[ -f "$AUR_DIR/PKGBUILD" ]]; then
    echo "keep-prev cleanup left PKGBUILD in place"
    exit 1
fi
if ! cmp -s "$AUR_DIR/PKGBUILD.prev" <(printf 'old pkgbuild\n'); then
    echo "AURGEN_KEEP_PREV=1 changed PKGBUILD.prev"
    exit 1
fi

mkdir -p "$AUR_DIR/dry-run"
printf 'source scriptlet\n' >| "$AUR_DIR/x.install"
printf 'stale scriptlet\n' >| "$AUR_DIR/dry-run/x.install"
OUT_DIR="$AUR_DIR/dry-run" cleanup
if [[ -e "$AUR_DIR/dry-run/x.install" ]]; then
    echo "cleanup left the dry-run scriptlet behind"
    exit 1
fi
if ! cmp -s "$AUR_DIR/x.install" <(printf 'source scriptlet\n'); then
    echo "cleanup changed the source scriptlet"
    exit 1
fi
printf 'template pkgbuild0\n' > "$AUR_DIR/PKGBUILD.0"
printf 'template yaml\n' > "$AUR_DIR/aurgen.install.yaml"
printf 'stale scriptlet\n' >| "$AUR_DIR/dry-run/x.install"
printf 'dry pkgbuild\n' > "$AUR_DIR/dry-run/PKGBUILD"
printf 'dry srcinfo\n' > "$AUR_DIR/dry-run/.SRCINFO"
printf 'dry pkgbuild0\n' > "$AUR_DIR/dry-run/PKGBUILD.0"
printf 'dry pkgbuild0 bak\n' > "$AUR_DIR/dry-run/PKGBUILD.0.bak"
printf 'dry stamp\n' > "$AUR_DIR/dry-run/.PKGBUILD.0.stamp"
printf 'dry header\n' > "$AUR_DIR/dry-run/PKGBUILD.HEADER"
printf 'dry yaml\n' > "$AUR_DIR/dry-run/aurgen.install.yaml"
printf 'dry example\n' > "$AUR_DIR/dry-run/aurgen.install.yaml.example"
: > "$AUR_DIR/dry-run/example-1.0.0.tar.gz"
: > "$AUR_DIR/dry-run/example-1.0.0.tar.gz.sig"
# An idle dry-run lock goes with the rest, so aur/dry-run disappears.
: > "$AUR_DIR/dry-run/.aurgen.lock"
# A build dir holding another one: find must not descend into what it removed.
mkdir -p "$AUR_DIR/example-1.0/sub/example-1.0"

# bin/aurgen runs modes under errexit, so a failing find aborts clean there.
# errexit is ignored inside an if condition, so take the status first.
( set -e; mode_clean ) >/dev/null
clean_status=$?
if (( clean_status != 0 )); then
    echo "mode_clean failed under errexit"
    exit 1
fi
if [[ -e "$AUR_DIR/example-1.0" ]]; then
    echo "mode_clean left a build directory behind"
    exit 1
fi

if [[ -e "$AUR_DIR/dry-run" ]]; then
    echo "mode_clean left the dry-run output behind"
    exit 1
fi
if ! cmp -s "$AUR_DIR/x.install" <(printf 'source scriptlet\n'); then
    echo "mode_clean changed the source scriptlet"
    exit 1
fi

# A dry-run lock some run still holds must stay, or the next dry run flocks a new inode.
mkdir -p "$AUR_DIR/dry-run"
: > "$AUR_DIR/dry-run/.aurgen.lock"
# Hold the lock on this shell's own open file: mode_clean's flock -n opens the file
# again and must fail, exactly as with a running dry run, and nothing is left running.
exec {held_fd}>>"$AUR_DIR/dry-run/.aurgen.lock"
flock -n "$held_fd" || { echo "could not take the dry-run lock for the test"; exit 1; }
clean_rc=0
( set -e; mode_clean ) >| "$tmp/clean-held.out" 2>&1 || clean_rc=$?
kept=0
[[ -e "$AUR_DIR/dry-run/.aurgen.lock" ]] && kept=1
exec {held_fd}>&-
if (( clean_rc != 0 )); then
    echo "mode_clean failed while a dry run held its lock"
    cat "$tmp/clean-held.out"
    exit 1
fi
if (( ! kept )) || ! grep -F -q 'leaving it in place' "$tmp/clean-held.out"; then
    echo "mode_clean unlinked a dry-run lock another run holds, or did not say it kept it"
    cat "$tmp/clean-held.out"
    exit 1
fi
if ! cmp -s "$AUR_DIR/PKGBUILD.0" <(printf 'template pkgbuild0\n') || ! cmp -s "$AUR_DIR/aurgen.install.yaml" <(printf 'template yaml\n'); then
    echo "mode_clean modified aur/ templates"
    exit 1
fi

if [[ -e "$AUR_DIR/PKGBUILD.prev" || -e "$AUR_DIR/.SRCINFO.prev" ]]; then
    echo "mode_clean left .prev files behind"
    exit 1
fi

# Mid-generation failure in bin/aurgen restores prior PKGBUILD/.SRCINFO, cleans partial files
# when none existed, and keeps new artifacts once generate_srcinfo succeeds.
rec_repo="$tmp/rec-repo"
mkdir -p "$rec_repo/bin" "$rec_repo/aur"
printf '#!/bin/bash\necho ok\n' >| "$rec_repo/bin/demo"
chmod +x "$rec_repo/bin/demo"
printf 'package:\n  name: rec-demo\n  description: recovery test\n  license: GPL-3.0-or-later\n  check: false\n' >| "$rec_repo/aur/aurgen.install.yaml"
git -C "$rec_repo" init -q -b main
git -C "$rec_repo" config user.name "Tester"
git -C "$rec_repo" config user.email "test@example.com"
git -C "$rec_repo" config commit.gpgsign false
git -C "$rec_repo" remote add origin "https://github.com/example/rec-demo.git"
git -C "$rec_repo" add -A
git -C "$rec_repo" commit -q -m init

rec_stub="$tmp/rec-bin"
mkdir -p "$rec_stub"
printf '#!/bin/bash\nexit "${STUB_UPDPKGSUMS_RC:-1}"\n' >| "$rec_stub/updpkgsums"
cat >| "$rec_stub/makepkg" << 'EOF'
#!/bin/bash
if [[ "$*" == *"--printsrcinfo"* ]]; then
    printf 'pkgbase = rec-demo\n\tpkgver = 0.1.0\n\tpkgrel = 1\n\npkgname = rec-demo\n'
    exit 0
fi
exit "${STUB_MAKEPKG_BUILD_RC:-0}"
EOF
printf '#!/bin/bash\nexit 0\n' >| "$rec_stub/curl"
chmod +x "$rec_stub/updpkgsums" "$rec_stub/makepkg" "$rec_stub/curl"

printf '# previous good pkgbuild\n' >| "$rec_repo/aur/PKGBUILD"
printf '# previous good srcinfo\n' >| "$rec_repo/aur/.SRCINFO"
printf '# older prev\n' >| "$rec_repo/aur/PKGBUILD.prev"
printf 'earlier release tarball\n' >| "$rec_repo/aur/rec-demo-0.0.9.tar.gz"
printf 'earlier release signature\n' >| "$rec_repo/aur/rec-demo-0.0.9.tar.gz.sig"
if (cd "$rec_repo" && STUB_UPDPKGSUMS_RC=1 PATH="$rec_stub:$PATH" "$ROOT/bin/aurgen" local </dev/null) >|"$tmp/rec-a.out" 2>|"$tmp/rec-a.err"; then
    echo "local mode unexpectedly succeeded when updpkgsums failed"
    exit 1
fi
if ! grep -Fq "restored previous PKGBUILD/.SRCINFO state" "$tmp/rec-a.err" "$tmp/rec-a.out"; then
    echo "missing restore warning on mid-generation failure"
    cat "$tmp/rec-a.err"
    exit 1
fi
if ! cmp -s "$rec_repo/aur/PKGBUILD" <(printf '# previous good pkgbuild\n'); then
    echo "aur/PKGBUILD was not restored after mid-generation failure"
    cat "$rec_repo/aur/PKGBUILD"
    exit 1
fi
if ! cmp -s "$rec_repo/aur/.SRCINFO" <(printf '# previous good srcinfo\n'); then
    echo "aur/.SRCINFO was not restored after mid-generation failure"
    cat "$rec_repo/aur/.SRCINFO"
    exit 1
fi
# The failed run also leaves the older rollback copy and the earlier release files as they were.
cmp -s "$rec_repo/aur/PKGBUILD.prev" <(printf '# older prev\n') || { echo "a failed run replaced PKGBUILD.prev"; cat "$rec_repo/aur/PKGBUILD.prev"; exit 1; }
[[ ! -e "$rec_repo/aur/.SRCINFO.prev" ]] || { echo "a failed run left a new .SRCINFO.prev"; exit 1; }
cmp -s "$rec_repo/aur/rec-demo-0.0.9.tar.gz" <(printf 'earlier release tarball\n') || { echo "a failed run deleted the earlier release tarball"; exit 1; }
cmp -s "$rec_repo/aur/rec-demo-0.0.9.tar.gz.sig" <(printf 'earlier release signature\n') || { echo "a failed run deleted the earlier release signature"; exit 1; }
if compgen -G "$rec_repo/aur/.aurgen-recovery.*" >/dev/null; then echo "a failed run left its recovery directory"; exit 1; fi
rm -f "$rec_repo/aur/rec-demo-0.0.9.tar.gz" "$rec_repo/aur/rec-demo-0.0.9.tar.gz.sig"

rm -f "$rec_repo/aur/PKGBUILD" "$rec_repo/aur/.SRCINFO" "$rec_repo/aur/PKGBUILD.prev" "$rec_repo/aur/.SRCINFO.prev"
if (cd "$rec_repo" && STUB_UPDPKGSUMS_RC=1 PATH="$rec_stub:$PATH" "$ROOT/bin/aurgen" local </dev/null) >|"$tmp/rec-b.out" 2>|"$tmp/rec-b.err"; then
    echo "local mode unexpectedly succeeded without prior artifacts"
    exit 1
fi
if ! grep -Fq "removed partial generated files" "$tmp/rec-b.err" "$tmp/rec-b.out"; then
    echo "missing partial cleanup warning when no prior artifacts existed"
    cat "$tmp/rec-b.err"
    exit 1
fi
if [[ -e "$rec_repo/aur/PKGBUILD" || -e "$rec_repo/aur/.SRCINFO" ]]; then
    echo "partial PKGBUILD or .SRCINFO remained after mid-generation failure"
    exit 1
fi

printf '# stale pkgbuild\n' >| "$rec_repo/aur/PKGBUILD"
printf '# stale srcinfo\n' >| "$rec_repo/aur/.SRCINFO"
if (cd "$rec_repo" && STUB_UPDPKGSUMS_RC=0 STUB_MAKEPKG_BUILD_RC=1 PATH="$rec_stub:$PATH" "$ROOT/bin/aurgen" local </dev/null) >|"$tmp/rec-c.out" 2>|"$tmp/rec-c.err"; then
    echo "local mode unexpectedly succeeded when makepkg install failed"
    exit 1
fi
if grep -Fq "restored previous PKGBUILD/.SRCINFO state" "$tmp/rec-c.err" "$tmp/rec-c.out"; then
    echo "post-srcinfo build failure incorrectly reverted generated files"
    cat "$tmp/rec-c.err"
    exit 1
fi
if cmp -s "$rec_repo/aur/PKGBUILD" <(printf '# stale pkgbuild\n') || [[ ! -s "$rec_repo/aur/.SRCINFO" ]] || cmp -s "$rec_repo/aur/.SRCINFO" <(printf '# stale srcinfo\n'); then
    echo "post-srcinfo build failure failed to preserve newly generated PKGBUILD and .SRCINFO"
    exit 1
fi
