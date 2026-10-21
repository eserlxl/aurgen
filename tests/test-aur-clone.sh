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
tmp="$(mktemp -d /tmp/aurgen-aur-clone.XXXXXX)"
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
