#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-doctor.XXXXXX")"
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
unset GIT_CONFIG GIT_CONFIG_SYSTEM GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_CONFIG_ACTION \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT ALLOW_DIRTY SOURCE_DATE_EPOCH nocheck build_only COLOR NO_COLOR CI DEBUG_LEVEL \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    AURGEN_TEST_DESC AURGEN_TEST_GH_DESC \
    PKG_NAME PKG_DESCRIPTION PKG_GPG_KEY PKG_INSTALL PKG_CHECK PKG_SOURCE \
    PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS \
    PKG_DEPENDS PKG_OPTDEPENDS PKG_MAKEDEPENDS PKG_CONFLICTS PKG_PROVIDES \
    PKG_BACKUP PKG_ARCH PKG_LICENSE PKG_INSTALL_VARS PKG_POST_PACKAGE PKG_KEEP \
    PROJECT_ROOT

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

# 1. Library execution guard
if bash "$ROOT/lib/modes/doctor.sh" >|"$tmp/guard.out" 2>|"$tmp/guard.err"; then
    fail "direct execution of lib/modes/doctor.sh should fail"
fi
grep -Fq 'must be sourced, not executed' "$tmp/guard.err" || fail "missing guard message" "$tmp/guard.err"

# Controlled PATH with minimal base tools + stubs (works on Arch and minimal CI).
base_bin="$tmp/base-bin"
mkdir -p "$base_bin"
for tool in bash git getopt awk tr sed grep find basename dirname realpath mkdir rm cp mv cat chmod env cut sort tail head; do
    tool_path="$(command -v "$tool" || true)"
    [[ -n "$tool_path" ]] || fail "required host helper missing: $tool"
    ln -sf "$tool_path" "$base_bin/$tool"
done
for fake in curl jq makepkg updpkgsums gh shellcheck namcap bwrap; do
    printf '#!/bin/bash\nexit 0\n' > "$base_bin/$fake"
    chmod +x "$base_bin/$fake"
done
cat > "$base_bin/gpg" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--list-secret-keys"* ]]; then
    if [[ -n "${DOCTOR_TEST_GPG_FPR:-}" ]]; then
        printf 'sec:u:4096:1:%s:1700000000:::u:::scESC:\n' "${DOCTOR_TEST_GPG_FPR: -16}"
        printf 'fpr:::::::::%s:\n' "$DOCTOR_TEST_GPG_FPR"
        printf 'uid:u::::1700000000::0::Tester <test@example.com>::::::::::\n'
    fi
    exit 0
fi
exit 0
EOF
chmod +x "$base_bin/gpg"

# --usage and option rejections
usage_out="$("$ROOT/bin/aurgen" --usage 2>&1)" || fail "--usage failed"
echo "$usage_out" | grep -Fq "doctor" || fail "--usage does not list doctor" "$usage_out"
for bad_flag in --build-only --json --diff --deploy --nocheck; do
    if "$ROOT/bin/aurgen" "$bad_flag" doctor >|"$tmp/bad-$bad_flag.out" 2>|"$tmp/bad-$bad_flag.err"; then
        fail "$bad_flag doctor unexpectedly succeeded"
    fi
done

# 2. Clean ready repository (exits 0, creates nothing in aur/)
ready_repo="$tmp/ready-repo"
mkdir -p "$ready_repo/bin" "$ready_repo/aur"
printf '#!/bin/bash\necho ok\n' > "$ready_repo/bin/demo"
chmod +x "$ready_repo/bin/demo"
printf '1.2.3\n' > "$ready_repo/VERSION"
printf 'A clean demo tool.\n' > "$ready_repo/README.md"
printf 'SPDX-License-Identifier: MIT\n' > "$ready_repo/LICENSE"
cat > "$ready_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: ready-demo
  gpg_key: 0123456789ABCDEF0123456789ABCDEF01234567
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
git -C "$ready_repo" init -q -b main
git -C "$ready_repo" config user.name "Tester"
git -C "$ready_repo" config user.email "test@example.com"
git -C "$ready_repo" config commit.gpgsign false
git -C "$ready_repo" remote add origin "https://github.com/example/ready-demo.git"
git -C "$ready_repo" add -A
git -C "$ready_repo" commit -q -m init

mkdir -p "$XDG_DATA_HOME/aurgen/aur/ready-demo/.git"
export DOCTOR_TEST_GPG_FPR="0123456789ABCDEF0123456789ABCDEF01234567"

if ! (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/ready.out" 2>|"$tmp/ready.err"; then
    fail "doctor failed on ready repo" "$tmp/ready.out"
fi
grep -Fq "[PASS] GitHub origin:" "$tmp/ready.out" || fail "missing GitHub origin PASS" "$tmp/ready.out"
grep -Fq "[PASS] Configuration:" "$tmp/ready.out" || fail "missing Configuration PASS" "$tmp/ready.out"
grep -Fq "[PASS] Version:" "$tmp/ready.out" || fail "missing Version PASS" "$tmp/ready.out"
grep -Fq "[PASS] License:" "$tmp/ready.out" || fail "missing License PASS" "$tmp/ready.out"
grep -Fq "[PASS] GPG signing:" "$tmp/ready.out" || fail "missing GPG signing PASS" "$tmp/ready.out"
grep -Fq "[PASS] AUR clone:" "$tmp/ready.out" || fail "missing AUR clone PASS" "$tmp/ready.out"
grep -Fq "Result: ready." "$tmp/ready.out" || fail "missing ready result" "$tmp/ready.out"
[[ ! -e "$ready_repo/aur/.gitignore" && ! -e "$ready_repo/aur/PKGBUILD.0" && ! -e "$ready_repo/aur/aurgen.install.yaml.example" ]] || fail "doctor mutated ready_repo/aur/"
[[ -z "$(git -C "$ready_repo" status --porcelain)" ]] || fail "doctor dirtied ready_repo"

# 3. Fresh empty repo without aur/, VERSION, LICENSE, README, GPG key (exits 0 with warnings, creates no aur/)
fresh_repo="$tmp/fresh-repo"
mkdir -p "$fresh_repo"
git -C "$fresh_repo" init -q -b main
git -C "$fresh_repo" config user.name "Tester"
git -C "$fresh_repo" config user.email "test@example.com"
git -C "$fresh_repo" config commit.gpgsign false
git -C "$fresh_repo" remote add origin "https://github.com/example/fresh-demo.git"
unset DOCTOR_TEST_GPG_FPR

if ! (cd "$fresh_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/fresh.out" 2>|"$tmp/fresh.err"; then
    fail "doctor should exit 0 with warnings only" "$tmp/fresh.out"
fi
grep -Fq "[WARN] Configuration:" "$tmp/fresh.out" || fail "missing config WARN on fresh repo" "$tmp/fresh.out"
grep -Fq "aurgen config generate" "$tmp/fresh.out" || fail "missing config generate hint" "$tmp/fresh.out"
grep -Fq "[WARN] Version:" "$tmp/fresh.out" || fail "missing version WARN" "$tmp/fresh.out"
grep -Fq "[WARN] License:" "$tmp/fresh.out" || fail "missing license WARN" "$tmp/fresh.out"
grep -Fq "[WARN] GPG signing:" "$tmp/fresh.out" || fail "missing GPG signing WARN" "$tmp/fresh.out"
grep -Fq "Result: ready with warnings." "$tmp/fresh.out" || fail "missing ready-with-warnings result" "$tmp/fresh.out"
[[ ! -e "$fresh_repo/aur" ]] || fail "doctor created aur/ directory"

# 4. Unimported hand-written aur/PKGBUILD triggers migration warning without auto-importing
import_repo="$tmp/import-repo"
mkdir -p "$import_repo/aur"
printf 'pkgname=hand\npkgver=1.0.0\npkgrel=1\n' > "$import_repo/aur/PKGBUILD"
cp "$import_repo/aur/PKGBUILD" "$tmp/PKGBUILD.before"
git -C "$import_repo" init -q -b main
git -C "$import_repo" remote add origin "https://github.com/example/hand.git"

if ! (cd "$import_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/import.out" 2>|"$tmp/import.err"; then
    fail "doctor failed on unimported PKGBUILD repo" "$tmp/import.out"
fi
grep -Fq "unimported aur/PKGBUILD" "$tmp/import.out" || fail "missing unimported PKGBUILD warning" "$tmp/import.out"
grep -Fq "aurgen config import" "$tmp/import.out" || fail "missing config import hint" "$tmp/import.out"
[[ ! -e "$import_repo/aur/aurgen.install.yaml" ]] || fail "doctor auto-imported config"
cmp -s "$tmp/PKGBUILD.before" "$import_repo/aur/PKGBUILD" || fail "doctor modified aur/PKGBUILD"

# 5. Missing required tool (updpkgsums) exits 1 with pacman hint
no_upd_bin="$tmp/no-upd-bin"
cp -a "$base_bin" "$no_upd_bin"
rm -f "$no_upd_bin/updpkgsums"
if (cd "$ready_repo" && PATH="$no_upd_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/noupd.out" 2>|"$tmp/noupd.err"; then
    fail "doctor should fail when updpkgsums is missing" "$tmp/noupd.out"
fi
grep -Fq "[FAIL] updpkgsums:" "$tmp/noupd.out" || fail "missing updpkgsums FAIL" "$tmp/noupd.out"
grep -Fq "sudo pacman -S pacman-contrib" "$tmp/noupd.out" || fail "missing pacman-contrib hint" "$tmp/noupd.out"

# 6. Non-git directory, missing origin, and non-GitHub origin all exit 1 without mutating
non_git="$tmp/non-git"
mkdir -p "$non_git"
if (cd "$non_git" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/nongit.out" 2>|"$tmp/nongit.err"; then
    fail "doctor should exit 1 outside a git repo" "$tmp/nongit.out"
fi
grep -Fq "[FAIL] Git repository:" "$tmp/nongit.out" || fail "missing non-git FAIL" "$tmp/nongit.out"

no_origin="$tmp/no-origin"
mkdir -p "$no_origin"
git -C "$no_origin" init -q -b main
if (cd "$no_origin" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/noorigin.out" 2>|"$tmp/noorigin.err"; then
    fail "doctor should exit 1 without origin" "$tmp/noorigin.out"
fi
grep -Fq "[FAIL] GitHub origin:" "$tmp/noorigin.out" || fail "missing no-origin FAIL" "$tmp/noorigin.out"

gitlab_repo="$tmp/gitlab-repo"
mkdir -p "$gitlab_repo"
git -C "$gitlab_repo" init -q -b main
git -C "$gitlab_repo" remote add origin "https://gitlab.com/example/demo.git"
if (cd "$gitlab_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/gitlab.out" 2>|"$tmp/gitlab.err"; then
    fail "doctor should exit 1 for non-GitHub origin" "$tmp/gitlab.out"
fi
grep -Fq "non-GitHub URL" "$tmp/gitlab.out" || fail "missing non-GitHub FAIL detail" "$tmp/gitlab.out"
[[ ! -e "$gitlab_repo/aur" ]] || fail "doctor created aur/ on non-GitHub failure"

# 7. Invalid config, missing -c config, missing install scriptlet, and unmatched gpg_key fail cleanly
bad_cfg="$tmp/bad-cfg.yaml"
printf 'package:\n  unknown_key: bogus\n' > "$bad_cfg"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n -c "$bad_cfg" doctor) >|"$tmp/badcfg.out" 2>|"$tmp/badcfg.err"; then
    fail "doctor should exit 1 for invalid config" "$tmp/badcfg.out"
fi
grep -Fq "[FAIL] Configuration:" "$tmp/badcfg.out" || fail "missing invalid config FAIL" "$tmp/badcfg.out"

if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n -c "$tmp/does-not-exist.yaml" doctor) >|"$tmp/misscfg.out" 2>|"$tmp/misscfg.err"; then
    fail "doctor should exit 1 for missing -c config" "$tmp/misscfg.out"
fi
grep -Fq "file not found:" "$tmp/misscfg.out" || fail "missing -c not found FAIL" "$tmp/misscfg.out"

bad_inst="$tmp/bad-inst.yaml"
printf 'package:\n  install: missing.install\n  source: archive\n' > "$bad_inst"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n -c "$bad_inst" doctor) >|"$tmp/badinst.out" 2>|"$tmp/badinst.err"; then
    fail "doctor should exit 1 for missing install scriptlet" "$tmp/badinst.out"
fi
grep -Fq "[FAIL] Install scriptlet:" "$tmp/badinst.out" || fail "missing install scriptlet FAIL" "$tmp/badinst.out"

bad_gpg="$tmp/bad-gpg.yaml"
printf 'package:\n  gpg_key: FFFFFFFFFFFFFFFF\n' > "$bad_gpg"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n -c "$bad_gpg" doctor) >|"$tmp/badgpg.out" 2>|"$tmp/badgpg.err"; then
    fail "doctor should exit 1 for unmatched package.gpg_key" "$tmp/badgpg.out"
fi
grep -Fq "[FAIL] GPG signing:" "$tmp/badgpg.out" || fail "missing package.gpg_key FAIL" "$tmp/badgpg.out"

# 8. Minimal config without explicit copy sections omits inactive include/ directory
min_cfg_repo="$tmp/min-cfg-repo"
mkdir -p "$min_cfg_repo/bin" "$min_cfg_repo/include" "$min_cfg_repo/aur"
printf '#!/bin/bash\necho ok\n' > "$min_cfg_repo/bin/min"
printf '/* header */\n' > "$min_cfg_repo/include/min.h"
printf 'package:\n  name: min-demo\n' > "$min_cfg_repo/aur/aurgen.install.yaml"
git -C "$min_cfg_repo" init -q -b main
git -C "$min_cfg_repo" config user.name "Tester"
git -C "$min_cfg_repo" config user.email "test@example.com"
git -C "$min_cfg_repo" config commit.gpgsign false
git -C "$min_cfg_repo" remote add origin "https://github.com/example/min-demo.git"
git -C "$min_cfg_repo" add -A
git -C "$min_cfg_repo" commit -q -m init

export DOCTOR_TEST_GPG_FPR="0123456789ABCDEF0123456789ABCDEF01234567"
if ! (cd "$min_cfg_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/mincfg.out" 2>|"$tmp/mincfg.err"; then
    fail "doctor failed on minimal config repo" "$tmp/mincfg.out"
fi
unset DOCTOR_TEST_GPG_FPR
grep -Eq '\[INFO\][[:space:]]+Copy directories:[[:space:]]+present: bin;' "$tmp/mincfg.out" || fail "doctor missing bin in Copy directories" "$tmp/mincfg.out"
if grep -Eq 'Copy directories:[[:space:]]+present:.*include' "$tmp/mincfg.out"; then
    fail "doctor reported unconfigured include/ as an active copy directory" "$tmp/mincfg.out"
fi

echo "PASS test-doctor.sh"
