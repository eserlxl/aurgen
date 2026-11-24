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
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_CONFIG_ACTION AURGEN_DOCTOR_ONLINE \
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
grep -Fq "doctor" <<< "$usage_out" || fail "--usage does not list doctor" "$usage_out"
for bad_flag in --build-only --diff --deploy --nocheck; do
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

mkdir -p "$XDG_DATA_HOME/aurgen/aur/ready-demo"
git -C "$XDG_DATA_HOME/aurgen/aur/ready-demo" init -q
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
grep -Fxq "Next: aurgen -d local" "$tmp/ready.out" || fail "a configured ready repo should point at aurgen -d local" "$tmp/ready.out"
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
grep -Fq "Run 'aurgen config init'" "$tmp/fresh.out" || fail "a fresh repo should be pointed at aurgen config init" "$tmp/fresh.out"
grep -Fxq "Next: aurgen config init" "$tmp/fresh.out" || fail "a fresh repo should name aurgen config init as the next command" "$tmp/fresh.out"
mkdir -p "$fresh_repo/aur" && printf 'pkgname=fresh-demo\n' > "$fresh_repo/aur/PKGBUILD"
(cd "$fresh_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" --json doctor) >|"$tmp/fresh-import.json" 2>|"$tmp/fresh-import.err" || true
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["next"] == "aurgen config import", d["next"]' "$tmp/fresh-import.json" || fail "an aur/PKGBUILD without config should name aurgen config import as next in --json" "$tmp/fresh-import.json"
rm -rf "$fresh_repo/aur"
# aur/PKGBUILD next to a config without package: (config generate) still needs config import.
mkdir -p "$fresh_repo/aur" && printf 'pkgname=fresh-demo\n' > "$fresh_repo/aur/PKGBUILD"
printf 'aur_integration:\n  auto_push: false\n' > "$fresh_repo/aur/aurgen.install.yaml"
(cd "$fresh_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/fresh-unimported.out" 2>|"$tmp/fresh-unimported.err" || true
grep -Fxq "Next: aurgen config import" "$tmp/fresh-unimported.out" || fail "an unimported aur/PKGBUILD should name aurgen config import as next" "$tmp/fresh-unimported.out"
rm -rf "$fresh_repo/aur"
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

# GitHub's ssh.github.com host is a GitHub origin for doctor too.
ssh_repo="$tmp/ssh-repo"
mkdir -p "$ssh_repo"
git -C "$ssh_repo" init -q -b main
git -C "$ssh_repo" remote add origin "git@ssh.github.com:example/demo.git"
(cd "$ssh_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/ssh.out" 2>|"$tmp/ssh.err" || true
if grep -Fq "[FAIL] GitHub origin:" "$tmp/ssh.out"; then
    fail "doctor refused an ssh.github.com origin" "$tmp/ssh.out"
fi
grep -Eq '\[PASS\][[:space:]]+GitHub origin:.*ssh\.github\.com' "$tmp/ssh.out" || fail "doctor did not accept the ssh.github.com origin" "$tmp/ssh.out"

# 7. Invalid config, missing -c config, missing install scriptlet, and unmatched gpg_key fail cleanly
bad_cfg="$tmp/bad-cfg.yaml"
printf 'package:\n  unknown_key: bogus\n' > "$bad_cfg"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n -c "$bad_cfg" doctor) >|"$tmp/badcfg.out" 2>|"$tmp/badcfg.err"; then
    fail "doctor should exit 1 for invalid config" "$tmp/badcfg.out"
fi
grep -Fq "[FAIL] Configuration:" "$tmp/badcfg.out" || fail "missing invalid config FAIL" "$tmp/badcfg.out"

# With debug logging on, the hint is still the error line, not the loader's [DEBUG] line.
epoch_cfg="$tmp/epoch-cfg.yaml"
printf 'package:\n  epoch: 0\n' > "$epoch_cfg"
(cd "$ready_repo" && PATH="$base_bin" DEBUG_LEVEL=1 "$ROOT/bin/aurgen" -n -c "$epoch_cfg" doctor) >|"$tmp/dbgcfg.out" 2>|"$tmp/dbgcfg.err" || true
grep -Fq "Invalid package.epoch '0'" "$tmp/dbgcfg.out" || fail "doctor hint did not name the epoch error under DEBUG_LEVEL=1" "$tmp/dbgcfg.out"
# Parser messages carry no [ERROR] prefix; the hint must still be that message.
(cd "$ready_repo" && PATH="$base_bin" DEBUG_LEVEL=1 "$ROOT/bin/aurgen" -n -c "$bad_cfg" doctor) >|"$tmp/dbgkey.out" 2>|"$tmp/dbgkey.err" || true
grep -Fq "unknown_key" "$tmp/dbgkey.out" || fail "doctor hint did not name the unknown key under DEBUG_LEVEL=1" "$tmp/dbgkey.out"

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
grep -Eq '\[INFO\][[:space:]]+Copy directories:[[:space:]]+none configured$' "$tmp/mincfg.out" || fail "doctor should report none configured when config has zero copy sections" "$tmp/mincfg.out"
if grep -Eq 'Copy directories:[[:space:]]+present:.*(bin|include)' "$tmp/mincfg.out"; then
    fail "doctor reported unconfigured directories on a zero-copy config" "$tmp/mincfg.out"
fi

# Explicit copy rule limits Copy directories strictly to configured sections and omits unconfigured include/
cat > "$min_cfg_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: min-demo
executables:
  source: bin
  destination: usr/bin
  permissions: executable
EOF
(cd "$min_cfg_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor >"$tmp/expcfg.out" 2>"$tmp/expcfg.err") || fail "doctor failed on explicit copy config" "$tmp/expcfg.err"
grep -Eq '\[INFO\][[:space:]]+Copy directories:[[:space:]]+present: bin; absent: none$' "$tmp/expcfg.out" || fail "doctor did not report exact configured copy directory" "$tmp/expcfg.out"

# Invalid config and missing explicit -c skip Copy directories instead of guessing defaults
printf 'bad_section:\n  source: bin\n' > "$min_cfg_repo/aur/aurgen.install.yaml"
if (cd "$min_cfg_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor >"$tmp/badcfg.out" 2>"$tmp/badcfg.err"); then
    fail "doctor should exit non-zero on invalid config"
fi
grep -Fq 'skipped (invalid configuration)' "$tmp/badcfg.out" || fail "doctor fell back to phantom copy directories on invalid config" "$tmp/badcfg.out"

if (cd "$min_cfg_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n -c does-not-exist.yaml doctor >"$tmp/missc.out" 2>"$tmp/missc.err"); then
    fail "doctor should exit non-zero on missing explicit -c config"
fi
grep -Fq 'skipped (configuration file not found)' "$tmp/missc.out" || fail "doctor fell back to phantom copy directories on missing -c config" "$tmp/missc.out"

cat > "$min_cfg_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: min-demo
EOF
chmod 000 "$min_cfg_repo/aur/aurgen.install.yaml"
if [[ ! -r "$min_cfg_repo/aur/aurgen.install.yaml" ]]; then
    if (cd "$min_cfg_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor >"$tmp/unreadcfg.out" 2>"$tmp/unreadcfg.err"); then
        chmod 644 "$min_cfg_repo/aur/aurgen.install.yaml"
        fail "doctor should exit non-zero on unreadable config"
    fi
    grep -Eq '\[FAIL\][[:space:]]+Configuration:[[:space:]]+invalid' "$tmp/unreadcfg.out" || {
        chmod 644 "$min_cfg_repo/aur/aurgen.install.yaml"
        fail "doctor did not fail on unreadable config" "$tmp/unreadcfg.out"
    }
    grep -Fq 'not readable' "$tmp/unreadcfg.out" || {
        chmod 644 "$min_cfg_repo/aur/aurgen.install.yaml"
        fail "doctor hint omitted unreadable config reason" "$tmp/unreadcfg.out"
    }
    grep -Fq 'skipped (invalid configuration)' "$tmp/unreadcfg.out" || {
        chmod 644 "$min_cfg_repo/aur/aurgen.install.yaml"
        fail "doctor fell back to copy directories on unreadable config" "$tmp/unreadcfg.out"
    }
fi
chmod 644 "$min_cfg_repo/aur/aurgen.install.yaml"

# 5. AUR clone diagnostics (dirty, unpushed, broken .git, non-git collision) & incomplete aur/PKGBUILD
export DOCTOR_TEST_GPG_FPR="0123456789ABCDEF0123456789ABCDEF01234567"
ready_clone="$XDG_DATA_HOME/aurgen/aur/ready-demo"
aur_upstream="$tmp/aur-upstream.git"
git init --bare -q "$aur_upstream"
git -C "$ready_clone" config user.name "Tester"
git -C "$ready_clone" config user.email "test@example.com"
git -C "$ready_clone" branch -M master
git -C "$ready_clone" remote add origin "$aur_upstream"
printf 'pkgname=ready-demo\n' > "$ready_clone/PKGBUILD"
git -C "$ready_clone" add PKGBUILD
git -C "$ready_clone" commit -q -m "initial aur"
git -C "$ready_clone" push -q -u origin master

# Ahead of upstream (clean clone with unpushed commit)
printf 'pkgname=ready-demo\npkgrel=2\n' > "$ready_clone/PKGBUILD"
git -C "$ready_clone" commit -q -am "local deploy commit"
if ! (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/ahead.out" 2>|"$tmp/ahead.err"; then
    fail "doctor should succeed on clean clone with unpushed commits" "$tmp/ahead.out"
fi
grep -Eq '\[INFO\][[:space:]]+AUR clone:.*1 unpushed commit\(s\)' "$tmp/ahead.out" || fail "doctor missing unpushed commit count" "$tmp/ahead.out"
grep -Fq "aurgen aur-push" "$tmp/ahead.out" || fail "doctor missing aur-push hint for unpushed commits" "$tmp/ahead.out"
grep -Fq "aurgen aur-deploy --rollback" "$tmp/ahead.out" || fail "doctor missing --rollback hint for unpushed commits" "$tmp/ahead.out"

# A leftover index.lock and the anonymous https push URL make the clone not ready.
: >| "$ready_clone/.git/index.lock"
git -C "$ready_clone" config remote.origin.pushurl https://aur.archlinux.org/ready-demo.git
lock_rc=0
(cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/lock.out" 2>|"$tmp/lock.err" || lock_rc=$?
(( lock_rc != 0 )) || fail "doctor passed a clone with an index.lock and an https push URL" "$tmp/lock.out"
grep -Eq '\[FAIL\][[:space:]]+AUR clone lock:.*index\.lock is left over' "$tmp/lock.out" || fail "doctor did not report the index.lock" "$tmp/lock.out"
grep -Eq '\[FAIL\][[:space:]]+AUR push URL:[[:space:]]+https://aur\.archlinux\.org/ready-demo\.git' "$tmp/lock.out" || fail "doctor did not report the https push URL" "$tmp/lock.out"
rm -f "$ready_clone/.git/index.lock"
git -C "$ready_clone" config --unset remote.origin.pushurl

# Dirty working tree in AUR clone (+ incomplete aur/PKGBUILD without .SRCINFO)
printf '# dirty\n' >> "$ready_clone/PKGBUILD"
printf 'pkgname=ready-demo\n' > "$ready_repo/aur/PKGBUILD"
if ! (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/dirty.out" 2>|"$tmp/dirty.err"; then
    fail "doctor should exit 0 on dirty clone warning without failures" "$tmp/dirty.out"
fi
grep -Eq '\[WARN\][[:space:]]+AUR clone:[[:space:]]+working tree has uncommitted changes' "$tmp/dirty.out" || fail "doctor missing dirty AUR clone warning" "$tmp/dirty.out"
grep -Fq "1 unpushed commit(s)" "$tmp/dirty.out" || fail "doctor dirty clone warning omitted unpushed commit count" "$tmp/dirty.out"
grep -Fq "aurgen aur-deploy --rollback" "$tmp/dirty.out" || fail "doctor missing --rollback hint for dirty clone" "$tmp/dirty.out"
grep -Eq '\[WARN\][[:space:]]+AUR artifacts:[[:space:]]+aur/PKGBUILD exists without aur/\.SRCINFO' "$tmp/dirty.out" || fail "doctor missing orphaned aur/PKGBUILD warning" "$tmp/dirty.out"
grep -Fq "# dirty" "$ready_clone/PKGBUILD" || fail "doctor mutated dirty AUR clone"
rm -f "$ready_repo/aur/PKGBUILD"

# Broken .git directory
rm -rf "$ready_clone"
mkdir -p "$ready_clone/.git"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/broken.out" 2>|"$tmp/broken.err"; then
    fail "doctor should fail on broken .git clone directory" "$tmp/broken.out"
fi
grep -Eq '\[FAIL\][[:space:]]+AUR clone:[[:space:]]+broken git repository' "$tmp/broken.out" || fail "doctor missing broken git repository FAIL" "$tmp/broken.out"
grep -Fq "aurgen aur-init" "$tmp/broken.out" || fail "doctor missing aur-init hint for broken clone" "$tmp/broken.out"

# Colliding non-git path
rm -rf "$ready_clone"
mkdir -p "$ready_clone"
printf 'stray\n' > "$ready_clone/notes.txt"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/collide.out" 2>|"$tmp/collide.err"; then
    fail "doctor should fail on colliding non-git AUR path" "$tmp/collide.out"
fi
grep -Eq '\[FAIL\][[:space:]]+AUR clone:[[:space:]]+non-git path blocks clone location:' "$tmp/collide.out" || fail "doctor missing non-git collision FAIL" "$tmp/collide.out"
grep -Fq "aurgen aur-init" "$tmp/collide.out" || fail "doctor missing aur-init hint for collision" "$tmp/collide.out"
[[ -f "$ready_clone/notes.txt" ]] || fail "doctor deleted colliding path contents"

# .SRCINFO pkgbase (-git package) selects the matching AUR clone path
rm -rf "$ready_clone"
aur_git_upstream="$tmp/aur-git-upstream.git"
git init --bare -q "$aur_git_upstream"
git_clone="$XDG_DATA_HOME/aurgen/aur/ready-demo-git"
mkdir -p "$git_clone"
git -C "$git_clone" init -q
git -C "$git_clone" config user.name "Tester"
git -C "$git_clone" config user.email "test@example.com"
git -C "$git_clone" branch -M master
git -C "$git_clone" remote add origin "$aur_git_upstream"
printf 'pkgname=ready-demo-git\n' > "$git_clone/PKGBUILD"
git -C "$git_clone" add PKGBUILD
git -C "$git_clone" commit -q -m "initial git aur"
git -C "$git_clone" push -q -u origin master
printf 'pkgname=ready-demo-git\npkgrel=2\n' > "$git_clone/PKGBUILD"
git -C "$git_clone" commit -q -am "local git deploy commit"
printf 'pkgbase = ready-demo-git\n\tpkgname = ready-demo-git\n' > "$ready_repo/aur/.SRCINFO"
if ! (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/git-ahead.out" 2>|"$tmp/git-ahead.err"; then
    fail "doctor should succeed on clean -git clone with unpushed commits" "$tmp/git-ahead.out"
fi
grep -Fq "ready-demo-git (1 unpushed commit(s))" "$tmp/git-ahead.out" || fail "doctor did not resolve -git clone via aur/.SRCINFO" "$tmp/git-ahead.out"
grep -Fq "aurgen aur-deploy --rollback" "$tmp/git-ahead.out" || fail "doctor missing --rollback hint for -git clone" "$tmp/git-ahead.out"

rm -rf "$git_clone"
mkdir -p "$git_clone/.git"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/git-broken.out" 2>|"$tmp/git-broken.err"; then
    fail "doctor should fail on broken -git clone selected by aur/.SRCINFO" "$tmp/git-broken.out"
fi
grep -Eq '\[FAIL\][[:space:]]+AUR clone:[[:space:]]+broken git repository at .*ready-demo-git$' "$tmp/git-broken.out" || fail "doctor did not fail on broken -git clone" "$tmp/git-broken.out"

printf 'pkgver = 1.0.0\n' > "$ready_repo/aur/.SRCINFO"
if ! (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/bad-srcinfo.out" 2>|"$tmp/bad-srcinfo.err"; then
    fail "doctor should fall back cleanly when aur/.SRCINFO lacks pkgbase/pkgname" "$tmp/bad-srcinfo.out"
fi
grep -Eq '\[WARN\][[:space:]]+AUR artifacts:[[:space:]]+aur/\.SRCINFO is missing valid pkgbase/pkgname' "$tmp/bad-srcinfo.out" || fail "doctor missing invalid aur/.SRCINFO warning" "$tmp/bad-srcinfo.out"
rm -rf "$git_clone" "$ready_repo/aur/.SRCINFO"

# 6. --json doctor output (ready, warnings, failures, non-git, pure stdout under RELEASE=0)
json_ready_rc=0
(cd "$ready_repo" && RELEASE=0 PATH="$base_bin" "$ROOT/bin/aurgen" --json doctor) >|"$tmp/json-ready.out" 2>|"$tmp/json-ready.err" || json_ready_rc=$?
(( json_ready_rc == 0 )) || fail "--json doctor failed on ready repo (rc=$json_ready_rc)" "$tmp/json-ready.err"
grep -Fq 'DEVELOPMENT mode' "$tmp/json-ready.err" || fail "--json doctor did not route RELEASE=0 dev info to stderr" "$tmp/json-ready.err"
python3 - "$tmp/json-ready.out" <<'PY' || fail "--json doctor ready output invalid" "$tmp/json-ready.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["ready"] is True, d
assert d["result"] == "ready", d
assert d["summary"]["failures"] == 0, d
assert d["summary"]["warnings"] == 0, d
assert d["summary"]["passed"] > 0, d
labels = {c["label"]: c for c in d["checks"]}
assert labels["Bash"]["level"] == "PASS"
assert labels["Git repository"]["section"] == "Git & Remote"
assert labels["Package name"]["detail"] == "ready-demo"
assert labels["GPG signing"]["level"] == "PASS"
PY

# Warnings: dirty AUR clone + orphaned aur/PKGBUILD -> ready=true, result="ready with warnings", exit 0
git -C "$tmp" init -q "$ready_clone"
git -C "$ready_clone" config user.name "Tester"
git -C "$ready_clone" config user.email "test@example.com"
git -C "$ready_clone" branch -M master
git -C "$ready_clone" remote add origin "$aur_upstream"
printf 'pkgname=ready-demo\n' > "$ready_clone/PKGBUILD"
git -C "$ready_clone" add PKGBUILD
git -C "$ready_clone" commit -q -m "initial aur"
printf '# dirty\n' >> "$ready_clone/PKGBUILD"
printf 'pkgname=ready-demo\n' > "$ready_repo/aur/PKGBUILD"
json_warn_rc=0
(cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" --json doctor) >|"$tmp/json-warn.out" 2>|"$tmp/json-warn.err" || json_warn_rc=$?
(( json_warn_rc == 0 )) || fail "--json doctor should exit 0 with warnings only (rc=$json_warn_rc)" "$tmp/json-warn.err"
python3 - "$tmp/json-warn.out" <<'PY' || fail "--json doctor warning output invalid" "$tmp/json-warn.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["ready"] is True, d
assert d["result"] == "ready with warnings", d
assert d["summary"]["failures"] == 0, d
assert d["summary"]["warnings"] >= 2, d
warns = [c for c in d["checks"] if c["level"] == "WARN"]
assert any(c["label"] == "AUR clone" and any("--rollback" in h for h in c["hints"]) for c in warns), warns
assert any(c["label"] == "AUR artifacts" for c in warns), warns
PY
rm -f "$ready_repo/aur/PKGBUILD"
rm -rf "$ready_clone"

# Failure outside git repo -> ready=false, result="not ready", exit 1, valid JSON
nongit_dir="$tmp/no-git"
mkdir -p "$nongit_dir"
json_nongit_rc=0
(cd "$nongit_dir" && RELEASE=0 PATH="$base_bin" "$ROOT/bin/aurgen" --json doctor) >|"$tmp/json-nongit.out" 2>|"$tmp/json-nongit.err" || json_nongit_rc=$?
(( json_nongit_rc == 1 )) || fail "--json doctor outside git repo should exit 1 (got $json_nongit_rc)" "$tmp/json-nongit.err"
python3 - "$tmp/json-nongit.out" <<'PY' || fail "--json doctor non-git output invalid" "$tmp/json-nongit.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["ready"] is False, d
assert d["result"] == "not ready", d
assert d["summary"]["failures"] >= 1, d
git_check = [c for c in d["checks"] if c["label"] == "Git repository"]
assert len(git_check) == 1 and git_check[0]["level"] == "FAIL" and len(git_check[0]["hints"]) >= 1, git_check
PY

unset DOCTOR_TEST_GPG_FPR

# 7. Online GitHub auth and AUR SSH auth checks (AURGEN_DOCTOR_ONLINE=1 vs default offline)
export DOCTOR_TEST_GPG_FPR="0123456789ABCDEF0123456789ABCDEF01234567"
mkdir -p "$ready_clone"
git -C "$ready_clone" init -q
export DOCTOR_ARGV_LOG="$tmp/doctor-online-argv.log"

cat > "$base_bin/gh" <<'EOF'
#!/bin/bash
if [[ -n "${DOCTOR_ARGV_LOG:-}" ]]; then
    printf 'gh %s\n' "$*" >> "$DOCTOR_ARGV_LOG"
fi
if [[ "${DOCTOR_GH_STATE:-ok}" == "ok" ]]; then
    exit 0
fi
printf 'You are not logged into any GitHub hosts.\n' >&2
exit 1
EOF
chmod +x "$base_bin/gh"

cat > "$base_bin/ssh" <<'EOF'
#!/bin/bash
if [[ -n "${DOCTOR_ARGV_LOG:-}" ]]; then
    printf 'ssh %s\n' "$*" >> "$DOCTOR_ARGV_LOG"
fi
case "${DOCTOR_SSH_STATE:-ok}" in
    ok)
        printf 'Commands:\n  help\n'
        exit 0
        ;;
    denied)
        printf 'aur@aur.archlinux.org: Permission denied (publickey).\n' >&2
        exit 255
        ;;
    hostkey)
        printf 'Host key verification failed.\n' >&2
        exit 255
        ;;
    unreachable)
        printf 'ssh: connect to host aur.archlinux.org port 22: Network is unreachable\n' >&2
        exit 255
        ;;
esac
exit 0
EOF
chmod +x "$base_bin/ssh"

# 7a. Default offline doctor makes no ssh or gh call
: > "$DOCTOR_ARGV_LOG"
if ! (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/offline-net.out" 2>|"$tmp/offline-net.err"; then
    fail "offline doctor failed" "$tmp/offline-net.out"
fi
[[ ! -s "$DOCTOR_ARGV_LOG" ]] || fail "offline doctor invoked ssh or gh" "$DOCTOR_ARGV_LOG"
if grep -Fq "AUR SSH auth:" "$tmp/offline-net.out" || grep -Fq "GitHub auth:" "$tmp/offline-net.out"; then
    fail "offline doctor emitted online auth checks" "$tmp/offline-net.out"
fi

# 7b. AURGEN_DOCTOR_ONLINE=1 with ok ssh and ok gh (text + JSON)
: > "$DOCTOR_ARGV_LOG"
if ! (cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=1 DOCTOR_GH_STATE=ok DOCTOR_SSH_STATE=ok PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/online-ok.out" 2>|"$tmp/online-ok.err"; then
    fail "online doctor (ok) failed" "$tmp/online-ok.out"
fi
grep -Fq "gh auth status --hostname github.com" "$DOCTOR_ARGV_LOG" || fail "online doctor did not call gh auth status" "$DOCTOR_ARGV_LOG"
grep -Fq "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes aur@aur.archlinux.org help" "$DOCTOR_ARGV_LOG" || fail "online doctor did not call ssh probe" "$DOCTOR_ARGV_LOG"
grep -Eq '\[PASS\][[:space:]]+GitHub auth:' "$tmp/online-ok.out" || fail "online doctor missing GitHub auth PASS" "$tmp/online-ok.out"
grep -Eq '\[PASS\][[:space:]]+AUR SSH auth:' "$tmp/online-ok.out" || fail "online doctor missing AUR SSH auth PASS" "$tmp/online-ok.out"

: > "$DOCTOR_ARGV_LOG"
if ! (cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=1 DOCTOR_GH_STATE=ok DOCTOR_SSH_STATE=ok PATH="$base_bin" "$ROOT/bin/aurgen" --json doctor) >|"$tmp/online-ok.json" 2>|"$tmp/online-ok-json.err"; then
    fail "online --json doctor (ok) failed" "$tmp/online-ok.json"
fi
python3 - "$tmp/online-ok.json" <<'PY' || fail "online --json doctor (ok) invalid" "$tmp/online-ok.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["ready"] is True, d
labels = {c["label"]: c for c in d["checks"]}
assert labels["GitHub auth"]["level"] == "PASS", labels["GitHub auth"]
assert labels["AUR SSH auth"]["level"] == "PASS", labels["AUR SSH auth"]
PY

# 7c. AURGEN_DOCTOR_ONLINE=1 with denied ssh and denied gh (text + JSON)
: > "$DOCTOR_ARGV_LOG"
if ! (cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=1 DOCTOR_GH_STATE=denied DOCTOR_SSH_STATE=denied PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/online-denied.out" 2>|"$tmp/online-denied.err"; then
    fail "online doctor (denied) should exit 0 with warnings" "$tmp/online-denied.out"
fi
grep -Eq '\[WARN\][[:space:]]+GitHub auth:' "$tmp/online-denied.out" || fail "online doctor missing GitHub auth WARN" "$tmp/online-denied.out"
grep -Fq "gh auth login --hostname github.com" "$tmp/online-denied.out" || fail "online doctor missing gh auth login hint" "$tmp/online-denied.out"
grep -Eq '\[WARN\][[:space:]]+AUR SSH auth:.*permission denied' "$tmp/online-denied.out" || fail "online doctor missing AUR SSH auth WARN" "$tmp/online-denied.out"
grep -Fq "https://aur.archlinux.org/account" "$tmp/online-denied.out" || fail "online doctor missing AUR account hint" "$tmp/online-denied.out"
grep -Fq "ssh-add" "$tmp/online-denied.out" || fail "online doctor missing ssh-add hint" "$tmp/online-denied.out"

: > "$DOCTOR_ARGV_LOG"
if ! (cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=1 DOCTOR_GH_STATE=denied DOCTOR_SSH_STATE=denied PATH="$base_bin" "$ROOT/bin/aurgen" --json doctor) >|"$tmp/online-denied.json" 2>|"$tmp/online-denied-json.err"; then
    fail "online --json doctor (denied) should exit 0 with warnings" "$tmp/online-denied.json"
fi
python3 - "$tmp/online-denied.json" <<'PY' || fail "online --json doctor (denied) invalid" "$tmp/online-denied.json"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["ready"] is True, d
assert d["result"] == "ready with warnings", d
labels = {c["label"]: c for c in d["checks"]}
gh_c = labels["GitHub auth"]
ssh_c = labels["AUR SSH auth"]
assert gh_c["level"] == "WARN", gh_c
assert any("gh auth login --hostname github.com" in h for h in gh_c["hints"]), gh_c
assert ssh_c["level"] == "WARN", ssh_c
assert any("https://aur.archlinux.org/account" in h and "ssh-add" in h for h in ssh_c["hints"]), ssh_c
PY

# 7d. Direct unit check of aur_probe_ssh setting AUR_SSH_PROBE across verdicts without changing messages or rc
(
    export PATH="$base_bin"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/aur-integration.sh
    source "$ROOT/lib/aur-integration.sh"
    for v in ok denied hostkey unreachable; do
        export DOCTOR_SSH_STATE="$v"
        out="$(aur_probe_ssh 2>&1)" || exit 1
        DOCTOR_SSH_STATE="$v" aur_probe_ssh >/dev/null 2>&1 || exit 1
        [[ "$AUR_SSH_PROBE" == "$v" ]] || { echo "expected AUR_SSH_PROBE=$v, got $AUR_SSH_PROBE"; exit 1; }
        case "$v" in
            ok) [[ "$out" == *"AUR SSH: ok"* ]] || exit 1 ;;
            denied) [[ "$out" == *"AUR SSH: permission denied: add your public key at https://aur.archlinux.org/account, or load the key into ssh-agent (ssh-add)"* ]] || exit 1 ;;
            hostkey) [[ "$out" == *"AUR SSH: host key verification failed: connect once with ssh aur@aur.archlinux.org to verify the key"* ]] || exit 1 ;;
            unreachable) [[ "$out" == *"AUR SSH: unreachable:"* ]] || exit 1 ;;
        esac
    done
) || fail "aur_probe_ssh AUR_SSH_PROBE verdict check failed"

unset DOCTOR_TEST_GPG_FPR DOCTOR_ARGV_LOG

# 7e. An invalid AURGEN_DOCTOR_ONLINE stops aurgen instead of silently running offline.
if (cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=true PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/online-bad.out" 2>|"$tmp/online-bad.err"; then
    fail "AURGEN_DOCTOR_ONLINE=true was accepted" "$tmp/online-bad.out"
fi
grep -Fq "Invalid AURGEN_DOCTOR_ONLINE: true" "$tmp/online-bad.err" || fail "invalid AURGEN_DOCTOR_ONLINE was not named" "$tmp/online-bad.err"

# 7f. Online doctor without gh lists the GitHub auth check as skipped.
nogh_bin="$tmp/nogh-bin"
mkdir -p "$nogh_bin"
for tool in "$base_bin"/*; do
    [[ "$(basename "$tool")" == gh ]] || ln -sf "$tool" "$nogh_bin/$(basename "$tool")"
done
(cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=1 DOCTOR_SSH_STATE=ok PATH="$nogh_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/online-nogh.out" 2>|"$tmp/online-nogh.err" || true
grep -Eq '\[INFO\][[:space:]]+GitHub auth:.*skipped: gh not installed' "$tmp/online-nogh.out" || fail "online doctor without gh did not report a skipped GitHub auth check" "$tmp/online-nogh.out"

# 7g. --online is the same as AURGEN_DOCTOR_ONLINE=1, and only valid with doctor.
(cd "$ready_repo" && DOCTOR_TEST_GPG_FPR=0123456789ABCDEF0123456789ABCDEF01234567 DOCTOR_GH_STATE=ok DOCTOR_SSH_STATE=ok PATH="$base_bin" "$ROOT/bin/aurgen" -n --online doctor) >|"$tmp/online-flag.out" 2>|"$tmp/online-flag.err" || fail "aurgen --online doctor failed" "$tmp/online-flag.out"
grep -Eq '\[PASS\][[:space:]]+GitHub auth:' "$tmp/online-flag.out" || fail "--online did not run the GitHub auth check" "$tmp/online-flag.out"
grep -Eq '\[PASS\][[:space:]]+AUR SSH auth:' "$tmp/online-flag.out" || fail "--online did not run the AUR SSH auth check" "$tmp/online-flag.out"
if (cd "$ready_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n --online lint) >|"$tmp/online-lint.out" 2>|"$tmp/online-lint.err"; then
    fail "--online was accepted with lint" "$tmp/online-lint.out"
fi
grep -Fq -- "--online is only valid with doctor" "$tmp/online-lint.err" || fail "--online with lint was not refused clearly" "$tmp/online-lint.err"

# 7h. Only doctor reads AURGEN_DOCTOR_ONLINE: other modes ignore a bad value, and --online wins over it.
(cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=true PATH="$base_bin" "$ROOT/bin/aurgen" --version) >|"$tmp/online-ver.out" 2>|"$tmp/online-ver.err" || fail "a bad AURGEN_DOCTOR_ONLINE blocked aurgen --version" "$tmp/online-ver.err"
(cd "$ready_repo" && AURGEN_DOCTOR_ONLINE=true DOCTOR_TEST_GPG_FPR=0123456789ABCDEF0123456789ABCDEF01234567 DOCTOR_GH_STATE=ok DOCTOR_SSH_STATE=ok PATH="$base_bin" "$ROOT/bin/aurgen" -n --online doctor) >|"$tmp/online-wins.out" 2>|"$tmp/online-wins.err" || fail "--online did not win over a bad AURGEN_DOCTOR_ONLINE" "$tmp/online-wins.err"
grep -Eq '\[PASS\][[:space:]]+GitHub auth:' "$tmp/online-wins.out" || fail "--online over a bad AURGEN_DOCTOR_ONLINE skipped the online checks" "$tmp/online-wins.out"

# 8. archive and signed-tag build from the version tag: doctor says when it is missing or unsigned.
tag_repo="$tmp/tag-repo"
mkdir -p "$tag_repo/aur"
git -C "$tag_repo" init -q -b main
git -C "$tag_repo" config user.name "Tester"
git -C "$tag_repo" config user.email "test@example.com"
git -C "$tag_repo" config commit.gpgsign false
git -C "$tag_repo" config tag.gpgsign false
git -C "$tag_repo" remote add origin "https://github.com/example/tag-demo.git"
printf '1.2.3\n' > "$tag_repo/VERSION"
git -C "$tag_repo" add VERSION
git -C "$tag_repo" commit -q -m init
printf 'package:\n  source: archive\n' > "$tag_repo/aur/aurgen.install.yaml"
(cd "$tag_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/tag-none.out" 2>|"$tmp/tag-none.err" || true
grep -Eq '\[WARN\][[:space:]]+Release tag:.*no local tag v1\.2\.3' "$tmp/tag-none.out" || fail "archive without a tag should warn about the release tag" "$tmp/tag-none.out"
grep -Fq "git tag -a v1.2.3 -m 'v1.2.3'" "$tmp/tag-none.out" || fail "archive without a tag should hint git tag -a" "$tmp/tag-none.out"
git -C "$tag_repo" tag -a v1.2.3 -m v1.2.3
(cd "$tag_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/tag-ok.out" 2>|"$tmp/tag-ok.err" || true
grep -Eq '\[PASS\][[:space:]]+Release tag:[[:space:]]+v1\.2\.3' "$tmp/tag-ok.out" || fail "archive with its tag should pass the release tag check" "$tmp/tag-ok.out"
printf 'package:\n  source: signed-tag\n' >| "$tag_repo/aur/aurgen.install.yaml"
unsigned_rc=0
(cd "$tag_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/tag-unsigned.out" 2>|"$tmp/tag-unsigned.err" || unsigned_rc=$?
(( unsigned_rc != 0 )) || fail "doctor exited 0 with an unsigned tag for signed-tag" "$tmp/tag-unsigned.out"
grep -Eq '\[FAIL\][[:space:]]+Release tag:.*v1\.2\.3 is not signed' "$tmp/tag-unsigned.out" || fail "signed-tag with an unsigned tag should fail the release tag check" "$tmp/tag-unsigned.out"
# A lightweight tag on a commit that carries a gpgsig header is not a signed tag either.
git -C "$tag_repo" tag -d v1.2.3 >/dev/null
fake_commit="$(printf 'tree %s\nparent %s\nauthor T <t@example.com> 1700000000 +0000\ncommitter T <t@example.com> 1700000000 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n -----END PGP SIGNATURE-----\n\nsigned\n' "$(git -C "$tag_repo" rev-parse 'HEAD^{tree}')" "$(git -C "$tag_repo" rev-parse HEAD)" | git -C "$tag_repo" hash-object -t commit -w --stdin)"
git -C "$tag_repo" tag v1.2.3 "$fake_commit"
light_rc=0
(cd "$tag_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/tag-light.out" 2>|"$tmp/tag-light.err" || light_rc=$?
(( light_rc != 0 )) || fail "doctor exited 0 with a lightweight tag for signed-tag" "$tmp/tag-light.out"
grep -Eq '\[FAIL\][[:space:]]+Release tag:.*v1\.2\.3 is not signed' "$tmp/tag-light.out" || fail "signed-tag with a lightweight tag on a signed commit should fail the release tag check" "$tmp/tag-light.out"

# 9. Context-aware Next: command at the end of local, git, and aur (dry-run and real run, with and without AUR clone)
next_bin="$tmp/next-bin"
cp -a "$base_bin" "$next_bin"
cat > "$next_bin/makepkg" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--printsrcinfo"* ]]; then
    pkg_name="ready-demo"
    if [[ -f PKGBUILD ]]; then
        pkg_name="$(awk -F= '/^[[:space:]]*pkgname[[:space:]]*=/ { gsub(/[[:space:]"'\'']/, "", $2); print $2; exit }' PKGBUILD)"
        [[ -n "$pkg_name" ]] || pkg_name="ready-demo"
    fi
    printf 'pkgbase = %s\n\tpkgver = 1.2.3\n\tpkgrel = 1\n\tpkgname = %s\n' "$pkg_name" "$pkg_name"
    exit 0
fi
if [[ "$*" == *"--packagelist"* ]]; then
    pkg="$PWD/ready-demo-1.2.3-1-any.pkg.tar.zst"
    : > "$pkg"
    printf '%s\n' "$pkg"
    exit 0
fi
exit 0
EOF
chmod +x "$next_bin/makepkg"
for tool in tar gzip cmp diff flock timeout perl wc date stat touch xargs mktemp ls; do
    tool_path="$(command -v "$tool" || true)"
    [[ -n "$tool_path" ]] && ln -sf "$tool_path" "$next_bin/$tool"
done

rm -rf "$XDG_DATA_HOME/aurgen/aur/ready-demo" "$XDG_DATA_HOME/aurgen/aur/ready-demo-git"

# local --dry-run -> Next: aurgen local
if ! (cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n --dry-run local) >|"$tmp/next-local-dry.out" 2>|"$tmp/next-local-dry.err"; then
    fail "--dry-run local failed" "$tmp/next-local-dry.err"
fi
grep -Fxq "Next: aurgen local" "$tmp/next-local-dry.out" || fail "--dry-run local should print Next: aurgen local" "$tmp/next-local-dry.out"
[[ "$(grep -c '^Next: ' "$tmp/next-local-dry.out")" -eq 1 ]] || fail "--dry-run local should print Next: once" "$tmp/next-local-dry.out"

# local real run -> Next: aurgen aur (or aurgen git)
if ! (cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n local) >|"$tmp/next-local-real.out" 2>|"$tmp/next-local-real.err"; then
    fail "local failed" "$tmp/next-local-real.err"
fi
grep -Exq "Next: aurgen (aur|git)" "$tmp/next-local-real.out" || fail "local should print Next: aurgen aur (or aurgen git)" "$tmp/next-local-real.out"
[[ "$(grep -c '^Next: ' "$tmp/next-local-real.out")" -eq 1 ]] || fail "local should print Next: once" "$tmp/next-local-real.out"

# git --dry-run -> Next: aurgen git (the real run comes next)
if ! (cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n --dry-run git) >|"$tmp/next-git-dry-nocln.out" 2>|"$tmp/next-git-dry-nocln.err"; then
    fail "--dry-run git (no clone) failed" "$tmp/next-git-dry-nocln.err"
fi
grep -Fxq "Next: aurgen git" "$tmp/next-git-dry-nocln.out" || fail "--dry-run git should print Next: aurgen git" "$tmp/next-git-dry-nocln.out"
[[ "$(grep -c '^Next: ' "$tmp/next-git-dry-nocln.out")" -eq 1 ]] || fail "--dry-run git without clone should print Next: once" "$tmp/next-git-dry-nocln.out"

# aur --dry-run -> Next: aurgen aur (and no static block)
if ! (cd "$ready_repo" && GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN PATH="$next_bin" "$ROOT/bin/aurgen" -n --dry-run aur) >|"$tmp/next-aur-dry-nocln.out" 2>|"$tmp/next-aur-dry-nocln.err"; then
    fail "--dry-run aur (no clone) failed" "$tmp/next-aur-dry-nocln.err"
fi
grep -Fxq "Next: aurgen aur" "$tmp/next-aur-dry-nocln.out" || fail "--dry-run aur should print Next: aurgen aur" "$tmp/next-aur-dry-nocln.out"
[[ "$(grep -c '^Next: ' "$tmp/next-aur-dry-nocln.out")" -eq 1 ]] || fail "--dry-run aur without clone should print Next: once" "$tmp/next-aur-dry-nocln.out"
if grep -Fq "=== AUR Integration Available ===" "$tmp/next-aur-dry-nocln.out"; then
    fail "mode_aur still printed static AUR Integration Available block" "$tmp/next-aur-dry-nocln.out"
fi

# A real git run without an AUR clone -> Next: aurgen aur-init
if ! (cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n git) >|"$tmp/next-git-real-nocln.out" 2>|"$tmp/next-git-real-nocln.err"; then
    fail "git (no clone) failed" "$tmp/next-git-real-nocln.err"
fi
grep -Fxq "Next: aurgen aur-init" "$tmp/next-git-real-nocln.out" || fail "git without clone should print Next: aurgen aur-init" "$tmp/next-git-real-nocln.out"

# Initialize AUR clones for ready-demo and ready-demo-git -> Next: aurgen aur-deploy
mkdir -p "$XDG_DATA_HOME/aurgen/aur/ready-demo" "$XDG_DATA_HOME/aurgen/aur/ready-demo-git"
git -C "$XDG_DATA_HOME/aurgen/aur/ready-demo" init -q
git -C "$XDG_DATA_HOME/aurgen/aur/ready-demo-git" init -q

if ! (cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n --dry-run git) >|"$tmp/next-git-dry-cln.out" 2>|"$tmp/next-git-dry-cln.err"; then
    fail "--dry-run git (with clone) failed" "$tmp/next-git-dry-cln.err"
fi
grep -Fxq "Next: aurgen git" "$tmp/next-git-dry-cln.out" || fail "--dry-run git with clone should print Next: aurgen git" "$tmp/next-git-dry-cln.out"

if ! (cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n git) >|"$tmp/next-git-real-cln.out" 2>|"$tmp/next-git-real-cln.err"; then
    fail "git (with clone) failed" "$tmp/next-git-real-cln.err"
fi
grep -Fxq "Next: aurgen aur-deploy" "$tmp/next-git-real-cln.out" || fail "git with clone should print Next: aurgen aur-deploy" "$tmp/next-git-real-cln.out"

if ! (cd "$ready_repo" && GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN PATH="$next_bin" "$ROOT/bin/aurgen" -n --dry-run aur) >|"$tmp/next-aur-dry-cln.out" 2>|"$tmp/next-aur-dry-cln.err"; then
    fail "--dry-run aur (with clone) failed" "$tmp/next-aur-dry-cln.err"
fi
grep -Fxq "Next: aurgen aur" "$tmp/next-aur-dry-cln.out" || fail "--dry-run aur with clone should print Next: aurgen aur" "$tmp/next-aur-dry-cln.out"

if ! (cd "$ready_repo" && GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN PATH="$next_bin" "$ROOT/bin/aurgen" -n --no-wait aur) >|"$tmp/next-aur-real-cln.out" 2>|"$tmp/next-aur-real-cln.err"; then
    fail "aur (with clone) failed" "$tmp/next-aur-real-cln.err"
fi
grep -Fxq "Next: aurgen aur-deploy" "$tmp/next-aur-real-cln.out" || fail "aur with clone should print Next: aurgen aur-deploy" "$tmp/next-aur-real-cln.out"

# 10. A -c config is kept in the suggested next command (doctor and a dry run).
cp "$ready_repo/aur/aurgen.install.yaml" "$tmp/alt-config.yaml" 2>/dev/null || printf 'package:\n  name: ready-demo\n' > "$tmp/alt-config.yaml"
(cd "$ready_repo" && DOCTOR_TEST_GPG_FPR=0123456789ABCDEF0123456789ABCDEF01234567 PATH="$base_bin" "$ROOT/bin/aurgen" -n -c "$tmp/alt-config.yaml" doctor) >|"$tmp/next-c-doctor.out" 2>|"$tmp/next-c-doctor.err" || true
grep -Fxq "Next: aurgen -c $(printf '%q' "$tmp/alt-config.yaml") -d local" "$tmp/next-c-doctor.out" || fail "doctor -c should keep -c in its Next: command" "$tmp/next-c-doctor.out"
(cd "$ready_repo" && PATH="$next_bin" "$ROOT/bin/aurgen" -n -c "$tmp/alt-config.yaml" --dry-run local) >|"$tmp/next-c-local.out" 2>|"$tmp/next-c-local.err" || true
grep -Fxq "Next: aurgen -c $(printf '%q' "$tmp/alt-config.yaml") local" "$tmp/next-c-local.out" || fail "a -c dry-run local should keep -c in its Next: command" "$tmp/next-c-local.out"

# 11. Next: is the last line of a real aur run, after the PKGBUILD-changed hint.
printf '# edited by hand\n' >> "$ready_repo/aur/PKGBUILD"
(cd "$ready_repo" && GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN PATH="$next_bin" "$ROOT/bin/aurgen" -n --no-wait aur) >|"$tmp/next-aur-last.out" 2>|"$tmp/next-aur-last.err" || fail "aur after a PKGBUILD edit failed" "$tmp/next-aur-last.err"
grep -Fq "Changes since the previous PKGBUILD" "$tmp/next-aur-last.out" || fail "aur after a PKGBUILD edit did not print the changes hint" "$tmp/next-aur-last.out"
[[ "$(grep -v '^[[:space:]]*$' "$tmp/next-aur-last.out" | tail -n 1)" == "Next: aurgen aur-deploy" ]] || fail "Next: should be the last line of an aur run" "$tmp/next-aur-last.out"

# 12. VERSION ahead of the latest version tag: the tag still wins, so doctor warns.
vc_bin="$tmp/vercmp-bin"
cp -a "$base_bin" "$vc_bin"
ln -sf "$(command -v vercmp)" "$vc_bin/vercmp"
printf 'package:\n  source: archive\n' >| "$tag_repo/aur/aurgen.install.yaml"
git -C "$tag_repo" tag -f -a v1.2.3 -m v1.2.3 >/dev/null 2>&1
printf '1.3.0\n' >| "$tag_repo/VERSION"
(cd "$tag_repo" && PATH="$vc_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/ver-ahead.out" 2>|"$tmp/ver-ahead.err" || true
grep -Eq '\[WARN\][[:space:]]+Version:.*1\.2\.3 \(tag\); VERSION says 1\.3\.0' "$tmp/ver-ahead.out" || fail "VERSION ahead of the tag was not reported" "$tmp/ver-ahead.out"
grep -Fq "git tag -a v1.3.0 -m 'v1.3.0'" "$tmp/ver-ahead.out" || fail "VERSION ahead of the tag did not hint the tag command" "$tmp/ver-ahead.out"
printf '1.2.3\n' >| "$tag_repo/VERSION"
(cd "$tag_repo" && PATH="$vc_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/ver-same.out" 2>|"$tmp/ver-same.err" || true
grep -Eq '\[PASS\][[:space:]]+Version:.*1\.2\.3 \(tag\)' "$tmp/ver-same.out" || fail "a VERSION equal to the tag should pass" "$tmp/ver-same.out"

# 13. --online checks that the release tag of an archive source is on origin (a local bare repo).
ln -sf "$(command -v timeout)" "$vc_bin/timeout"
tag_origin="$tmp/tag-origin.git"
git init -q --bare -b main "$tag_origin"
git -C "$tag_repo" remote set-url origin "$tag_origin"
git -C "$tag_repo" push -q origin HEAD:main 2>/dev/null
(cd "$tag_repo" && GIT_ALLOW_PROTOCOL=file DOCTOR_SSH_STATE=ok PATH="$vc_bin" "$ROOT/bin/aurgen" -n --online doctor) >|"$tmp/rtag-missing.out" 2>|"$tmp/rtag-missing.err" || true
grep -Eq '\[WARN\][[:space:]]+Remote tag:.*v1\.2\.3 is not on origin' "$tmp/rtag-missing.out" || fail "an unpushed release tag was not reported" "$tmp/rtag-missing.out"
grep -Fq "git push origin v1.2.3" "$tmp/rtag-missing.out" || fail "an unpushed release tag did not hint git push" "$tmp/rtag-missing.out"
git -C "$tag_repo" push -q origin v1.2.3 2>/dev/null
(cd "$tag_repo" && GIT_ALLOW_PROTOCOL=file DOCTOR_SSH_STATE=ok PATH="$vc_bin" "$ROOT/bin/aurgen" -n --online doctor) >|"$tmp/rtag-ok.out" 2>|"$tmp/rtag-ok.err" || true
grep -Eq '\[PASS\][[:space:]]+Remote tag:.*v1\.2\.3 is on origin' "$tmp/rtag-ok.out" || fail "a pushed release tag was not reported" "$tmp/rtag-ok.out"
(cd "$tag_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/rtag-offline.out" 2>|"$tmp/rtag-offline.err" || true
if grep -Fq "Remote tag" "$tmp/rtag-offline.out"; then
    fail "offline doctor checked the remote tag" "$tmp/rtag-offline.out"
fi
grep -Eq '\[PASS\][[:space:]]+Release tag:[[:space:]]+v1\.2\.3' "$tmp/rtag-offline.out" || fail "offline doctor did not reach the release tag check" "$tmp/rtag-offline.out"

# A VERSION that is not a valid pkgver fails doctor before a build would.
badver_repo="$tmp/badver-repo"
cp -a "$ready_repo" "$badver_repo"
printf '1.0.1-rc1\n' >| "$badver_repo/VERSION"
badver_rc=0
(cd "$badver_repo" && PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/badver.out" 2>|"$tmp/badver.err" || badver_rc=$?
(( badver_rc != 0 )) || fail "doctor passed an invalid pkgver" "$tmp/badver.out"
grep -Eq '\[FAIL\][[:space:]]+Version:[[:space:]]+1\.0\.1-rc1 \(version-file\) is not a valid pkgver' "$tmp/badver.out" || fail "doctor did not name the invalid pkgver" "$tmp/badver.out"

# GPG_KEY_ID follows select_gpg_key: a 0x key id matches, a one-digit suffix does not.
(cd "$ready_repo" && DOCTOR_TEST_GPG_FPR=0123456789ABCDEF0123456789ABCDEF01234567 GPG_KEY_ID=0x89abcdef01234567 PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/keyid.out" 2>|"$tmp/keyid.err" || true
grep -Eq '\[PASS\][[:space:]]+GPG signing:[[:space:]]+GPG_KEY_ID matched' "$tmp/keyid.out" || fail "doctor did not match a 0x key id" "$tmp/keyid.out"
(cd "$ready_repo" && DOCTOR_TEST_GPG_FPR=0123456789ABCDEF0123456789ABCDEF01234567 GPG_KEY_ID=7 PATH="$base_bin" "$ROOT/bin/aurgen" -n doctor) >|"$tmp/keyid-short.out" 2>|"$tmp/keyid-short.err" || true
grep -Eq '\[FAIL\][[:space:]]+GPG signing:' "$tmp/keyid-short.out" || fail "doctor matched a one-digit GPG_KEY_ID" "$tmp/keyid-short.out"

echo "PASS test-doctor.sh"

