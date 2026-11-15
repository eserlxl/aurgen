#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Clone is https and the push URL is ssh. Deploy drops a stale root install
# file, including when install= is gone, and does not write backup-* directories.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-aur-clone.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export LC_ALL=C
export HOME="$tmp/home"
export XDG_DATA_HOME="$tmp/xdg"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
export DEBUG_LEVEL=0
unset RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
: >| "$GIT_CONFIG_GLOBAL"
: >| "$AURGEN_ERROR_LOG"

saved_path="$PATH"
real_git="$(command -v git)"
bare="$tmp/bare.git"
"$real_git" init -q --bare "$bare"

export REAL_GIT="$real_git"
export AUR_BARE="$bare"
export GIT_CLONE_LOG="$tmp/clone-url"
: >| "$GIT_CLONE_LOG"
stub="$tmp/bin"
mkdir -p "$stub"
# An aur.archlinux.org clone stays on the local bare repo. The URL git was
# given is recorded and becomes origin, so get-url can be checked offline.
cat > "$stub/git" << 'EOF'
#!/bin/bash
if [[ "${1:-}" == clone && $# -ge 3 ]]; then
    args=("${@:2}")
    dest="${args[-1]}"
    url="${args[-2]}"
    opts=("${args[@]:0:${#args[@]}-2}")
    case "$url" in
        *aur.archlinux.org/*.git)
            printf '%s\n' "$url" >| "$GIT_CLONE_LOG"
            if [[ "${FAIL_AUR_CLONE:-0}" == 1 ]]; then
                mkdir -p "$dest/.git"
                printf 'partial\n' >| "$dest/partial.txt"
                exit 1
            fi
            "$REAL_GIT" clone "${opts[@]}" "$AUR_BARE" "$dest"
            status=$?
            if [[ "$status" -ne 0 ]]; then
                exit "$status"
            fi
            "$REAL_GIT" -C "$dest" remote set-url origin "$url"
            exit $?
            ;;
    esac
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$stub/git"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

export PATH="$stub:$saved_path"
export AUR_REPO_DIR="$tmp/aur"
if ! init_aur_repo demopkg >|"$tmp/init.out" 2>|"$tmp/init.err"; then
    echo "init_aur_repo failed"
    cat "$tmp/init.err"
    exit 1
fi
repo="$AUR_REPO_DIR/demopkg"
if ! origin=$(git -C "$repo" remote get-url origin); then
    echo "origin get-url failed"
    exit 1
fi
if ! push_url=$(git -C "$repo" remote get-url --push origin); then
    echo "push get-url failed"
    exit 1
fi
if [[ "$origin" != "https://aur.archlinux.org/demopkg.git" ]]; then
    echo "origin URL is not https: [$origin]"
    exit 1
fi
if [[ "$(cat "$GIT_CLONE_LOG")" != "https://aur.archlinux.org/demopkg.git" ]]; then
    echo "clone URL is not https: [$(cat "$GIT_CLONE_LOG")]"
    exit 1
fi
if [[ "$push_url" != "ssh://aur@aur.archlinux.org/demopkg.git" ]]; then
    echo "push URL is not ssh: [$push_url]"
    exit 1
fi

export PATH="$saved_path"
export AUR_DIR="$tmp/aurdir"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" << EOF
aur_integration:
  aur_repo_dir: $tmp/clones
  auto_push: false
  commit_message: Update to version {version}
  git_user_name: AURGen Test
  git_user_email: test@example.com
  backup_existing: true
  validate_before_push: false
EOF
load_aur_integration_config
if [[ "$AUR_REPO_DIR" != "$tmp/clones" || "$AUR_AUTO_PUSH" != "false" ]]; then
    echo "backup_existing config did not keep loading"
    exit 1
fi

export PKGBUILD="$tmp/PKGBUILD"
export SRCINFO="$tmp/.SRCINFO"
printf 'pkgbase = demopkg\n\tpkgver = 1.2.3\n\tpkgrel = 1\n' >| "$SRCINFO"

prepare_clone() {
    local dest="$1"
    mkdir -p "$dest/nested"
    git init -q -b master "$dest"
    git -C "$dest" config user.email "test@example.com"
    git -C "$dest" config user.name "AURGen Test"
    git -C "$dest" config commit.gpgsign false
    printf 'old\n' >| "$dest/old.install"
    printf 'kept\n' >| "$dest/nested/kept.install"
    git -C "$dest" add old.install nested/kept.install
    git -C "$dest" commit -q -m init
}

clone="$AUR_REPO_DIR/demopkg"
prepare_clone "$clone"
printf 'new scriptlet\n' >| "$tmp/new.install"
printf "pkgver=1.2.3\ninstall='new.install'\n" >| "$PKGBUILD"
if ! deploy_to_aur demopkg >|"$tmp/deploy.out" 2>|"$tmp/deploy.err"; then
    echo "deploy failed"
    cat "$tmp/deploy.err"
    exit 1
fi
if git -C "$clone" cat-file -e HEAD:old.install 2>/dev/null; then
    echo "old.install still in HEAD"
    exit 1
fi
if ! git -C "$clone" cat-file -e HEAD:new.install 2>/dev/null; then
    echo "new.install missing from HEAD"
    exit 1
fi
if ! git -C "$clone" cat-file -e HEAD:nested/kept.install 2>/dev/null; then
    echo "nested install file was removed"
    exit 1
fi
if [[ -n "$(find "$clone" -name 'backup-*' -print)" ]]; then
    echo "deploy wrote a backup directory"
    find "$clone" -name 'backup-*' -print
    exit 1
fi

printf 'pkgver=1.2.3\n' >| "$PKGBUILD"
if ! deploy_to_aur demopkg >|"$tmp/drop.out" 2>|"$tmp/drop.err"; then
    echo "deploy without install= failed"
    cat "$tmp/drop.err"
    exit 1
fi
if git -C "$clone" cat-file -e HEAD:new.install 2>/dev/null; then
    echo "tracked install file remained after install= was removed"
    exit 1
fi
if ! git -C "$clone" cat-file -e HEAD:nested/kept.install 2>/dev/null; then
    echo "nested install file was removed when install= was dropped"
    exit 1
fi

dry="$AUR_REPO_DIR/drypkg"
prepare_clone "$dry"
printf "pkgver=1.2.3\ninstall='new.install'\n" >| "$PKGBUILD"
before="$(git -C "$dry" rev-parse HEAD)"
before_status="$(git -C "$dry" status --porcelain)"
if ! dry_run=1 deploy_to_aur drypkg >|"$tmp/dry.out" 2>|"$tmp/dry.err"; then
    echo "dry-run deploy failed"
    cat "$tmp/dry.err"
    exit 1
fi
if ! grep -F -x -q 'deleted file: old.install' "$tmp/dry.out"; then
    echo "dry-run did not print deleted file: old.install"
    cat "$tmp/dry.out"
    exit 1
fi
if grep -F -q 'deleted file: nested/kept.install' "$tmp/dry.out"; then
    echo "dry-run named a nested install file"
    cat "$tmp/dry.out"
    exit 1
fi
after="$(git -C "$dry" rev-parse HEAD)"
after_status="$(git -C "$dry" status --porcelain)"
if [[ "$before" != "$after" || "$before_status" != "$after_status" || ! -f "$dry/old.install" ]]; then
    echo "dry-run changed the clone"
    exit 1
fi

# Atomic reinit backup/restore and non-git collision protection
cat > "$stub/ssh" << 'EOF'
#!/bin/bash
printf '%s\n' 'AUR help'
exit 0
EOF
chmod +x "$stub/ssh"

export PATH="$stub:$saved_path"
export LIB_INSTALL_DIR="$ROOT/lib"
export SILVER="" RESET="" YELLOW="" PKGNAME="demopkg"

# 1) init_aur_repo refuses an existing path before invoking git clone
: >| "$GIT_CLONE_LOG"
printf 'keep me\n' >| "$AUR_REPO_DIR/collide-file"
if init_aur_repo collide-file >|"$tmp/collide-direct.out" 2>|"$tmp/collide-direct.err"; then
    echo "init_aur_repo should reject existing destination"
    exit 1
fi
if ! grep -Fq "aurgen aur-init" "$tmp/collide-direct.err"; then
    echo "init_aur_repo collision error did not mention aurgen aur-init"
    cat "$tmp/collide-direct.err"
    exit 1
fi
if [[ -s "$GIT_CLONE_LOG" || "$(cat "$AUR_REPO_DIR/collide-file")" != "keep me" ]]; then
    echo "init_aur_repo touched existing colliding path or ran git clone"
    exit 1
fi

# 2) Failed clone cleans partial destination on fresh repo
rm -f "$AUR_REPO_DIR/collide-file"
if FAIL_AUR_CLONE=1 init_aur_repo freshfail >|"$tmp/freshfail.out" 2>|"$tmp/freshfail.err"; then
    echo "freshfail clone unexpectedly succeeded"
    exit 1
fi
if [[ -e "$AUR_REPO_DIR/freshfail" ]]; then
    echo "failed clone left partial directory behind"
    exit 1
fi

# 3) Confirmed aur-init reinitialization restores previous clone on failure
before_head="$(git -C "$clone" rev-parse HEAD)"
if (
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    have_tty() { return 0; }
    export FAIL_AUR_CLONE=1 dry_run=0
    mode_aur_init <<< "y"
) >|"$tmp/reinit-fail.out" 2>|"$tmp/reinit-fail.err"; then
    echo "aur-init should fail when replacement clone fails"
    exit 1
fi
after_head="$(git -C "$clone" rev-parse HEAD 2>/dev/null || true)"
if [[ "$after_head" != "$before_head" || ! -f "$clone/nested/kept.install" || -f "$clone/partial.txt" ]]; then
    echo "failed reinit did not restore prior clone intact"
    exit 1
fi
if [[ -n "$(find "$AUR_REPO_DIR" -maxdepth 1 -name '.aur-init-backup.*' -print)" ]]; then
    echo "failed reinit left backup directory behind"
    exit 1
fi

# 4) Confirmed aur-init reinitialization replaces clone and deletes backup on success
if ! (
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    have_tty() { return 0; }
    export FAIL_AUR_CLONE=0 dry_run=0
    mode_aur_init <<< "y"
) >|"$tmp/reinit-ok.out" 2>|"$tmp/reinit-ok.err"; then
    echo "confirmed reinit failed"
    cat "$tmp/reinit-ok.err"
    exit 1
fi
if [[ ! -d "$clone/.git" || -f "$clone/nested/kept.install" ]]; then
    echo "successful reinit did not replace clone with fresh clone"
    exit 1
fi
if [[ -n "$(find "$AUR_REPO_DIR" -maxdepth 1 -name '.aur-init-backup.*' -print)" ]]; then
    echo "successful reinit left backup directory behind"
    exit 1
fi

# 5) Colliding non-git path handled cleanly under dry-run, decline, failed clone restore, and confirmed replacement
rm -rf "$clone"
printf 'important non-git file\n' >| "$clone"
if ! (
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    have_tty() { return 0; }
    export FAIL_AUR_CLONE=0 dry_run=1
    mode_aur_init <<< "y"
) >|"$tmp/collide-dry.out" 2>|"$tmp/collide-dry.err"; then
    echo "dry-run collision check failed"
    exit 1
fi
if [[ ! -f "$clone" || "$(cat "$clone")" != "important non-git file" ]]; then
    echo "dry-run removed colliding non-git path"
    exit 1
fi
if (
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    have_tty() { return 0; }
    export FAIL_AUR_CLONE=1 dry_run=0
    mode_aur_init <<< "y"
) >|"$tmp/collide-fail.out" 2>|"$tmp/collide-fail.err"; then
    echo "collision replacement should fail when clone fails"
    exit 1
fi
if [[ ! -f "$clone" || -d "$clone" || "$(cat "$clone")" != "important non-git file" ]]; then
    echo "failed collision replacement did not restore colliding file"
    exit 1
fi
if ! (
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    have_tty() { return 0; }
    export FAIL_AUR_CLONE=0 dry_run=0
    mode_aur_init <<< "y"
) >|"$tmp/collide-ok.out" 2>|"$tmp/collide-ok.err"; then
    echo "confirmed collision replacement failed"
    cat "$tmp/collide-ok.err"
    exit 1
fi
if [[ ! -d "$clone/.git" ]]; then
    echo "confirmed collision replacement did not leave fresh git clone"
    exit 1
fi
if [[ -n "$(find "$AUR_REPO_DIR" -maxdepth 1 -name '.aur-init-backup.*' -print)" ]]; then
    echo "confirmed collision replacement left backup directory behind"
    exit 1
fi

# 6) init_aur_repo never deletes a pre-existing .git repository on clone failure
printf 'keep-repo-marker\n' >| "$clone/marker.txt"
if FAIL_AUR_CLONE=1 init_aur_repo demopkg >|"$tmp/existing-fail.out" 2>|"$tmp/existing-fail.err"; then
    echo "init_aur_repo unexpectedly succeeded on failing existing clone"
    exit 1
fi
if [[ ! -d "$clone/.git" || "$(cat "$clone/marker.txt")" != "keep-repo-marker" ]]; then
    echo "init_aur_repo deleted pre-existing repository on clone failure"
    exit 1
fi

# 7) Non-interactive mode_aur_init leaves a colliding non-git directory untouched
rm -rf "$clone"
mkdir -p "$clone"
printf 'keep-dir-file\n' >| "$clone/keep.txt"
if ! (
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    export dry_run=0
    mode_aur_init </dev/null
) >|"$tmp/collide-noninteractive.out" 2>|"$tmp/collide-noninteractive.err"; then
    echo "non-interactive colliding path check returned error"
    exit 1
fi
if [[ ! -f "$clone/keep.txt" || -d "$clone/.git" ]]; then
    echo "non-interactive mode_aur_init modified colliding directory"
    exit 1
fi

echo "PASS test-aur-clone.sh"
