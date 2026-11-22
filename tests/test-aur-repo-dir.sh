#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aur_repo_dir: XDG data default, ~ expansion, a relative path anchored at
# PROJECT_ROOT, and a readable error when the directory cannot be created.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
unset XDG_DATA_HOME AURGEN_CONFIG_FILE AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
: > "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

log() { :; }
debug() { :; }

export AUR_DIR="$tmp/project/aur"
mkdir -p "$AUR_DIR"

load_with() {
    local body="$1"
    printf '%s' "$body" >| "$AUR_DIR/aurgen.install.yaml"
    load_aur_integration_config
}

load_with $'package:\n  name: demo\n'
[[ "$AUR_REPO_DIR" == "$HOME/.local/share/aurgen/aur" ]] || { echo "default: got [$AUR_REPO_DIR]"; exit 1; }

XDG_DATA_HOME="$tmp/xdg" load_with $'package:\n  name: demo\n'
[[ "$AUR_REPO_DIR" == "$tmp/xdg/aurgen/aur" ]] || { echo "XDG_DATA_HOME default: got [$AUR_REPO_DIR]"; exit 1; }

load_with $'aur_integration:\n  aur_repo_dir: ~/clones\n'
[[ "$AUR_REPO_DIR" == "$HOME/clones" ]] || { echo "tilde: got [$AUR_REPO_DIR]"; exit 1; }

load_with $'aur_integration:\n  aur_repo_dir: /srv/aur\n'
[[ "$AUR_REPO_DIR" == "/srv/aur" ]] || { echo "absolute: got [$AUR_REPO_DIR]"; exit 1; }

# ~user is refused: replacing only the ~ would give "$HOME"bob/clones.
if err_out="$(load_with $'aur_integration:\n  aur_repo_dir: ~bob/clones\n' 2>&1)"; then
    echo "aur_repo_dir ~bob/clones should be refused, got [$AUR_REPO_DIR]"
    exit 1
fi
[[ "$err_out" == *"aur_repo_dir"* ]] || { echo "missing aur_repo_dir error: [$err_out]"; exit 1; }

# Resolved against PROJECT_ROOT, not the shell cwd (later steps cd into aur/).
export PROJECT_ROOT
PROJECT_ROOT="$(realpath -m -- "$tmp/project")"
load_with $'aur_integration:\n  aur_repo_dir: ./clones\n'
[[ "$AUR_REPO_DIR" == "$PROJECT_ROOT/clones" ]] || { echo "relative: got [$AUR_REPO_DIR]"; exit 1; }

# An empty key inside aur_integration must not close the section; a later
# setting still takes effect and a following top-level section closes it.
load_with $'aur_integration:\n  git_user_name:\n  auto_push: false\n'
[[ "$AUR_AUTO_PUSH" == "false" ]] || { echo "empty key: got auto_push [$AUR_AUTO_PUSH]"; exit 1; }
[[ "$AUR_GIT_USER_NAME" == "" ]] || { echo "empty key: got git_user_name [$AUR_GIT_USER_NAME]"; exit 1; }

# An empty aur_repo_dir keeps the default instead of putting clones under /.
XDG_DATA_HOME="$tmp/xdg" load_with $'aur_integration:\n  aur_repo_dir:\n'
[[ "$AUR_REPO_DIR" == "$tmp/xdg/aurgen/aur" ]] || { echo "empty repo dir: got [$AUR_REPO_DIR]"; exit 1; }

load_with $'aur_integration:\n  auto_push: false\npackage:\n  auto_push: true\n'
[[ "$AUR_AUTO_PUSH" == "false" ]] || { echo "following section: got auto_push [$AUR_AUTO_PUSH]"; exit 1; }

for key in auto_push validate_before_push; do
    for value in true false True False TRUE FALSE; do
        load_with $'aur_integration:\n'"  $key: $value"$'\n'
        case "$key" in
            auto_push) actual="$AUR_AUTO_PUSH" ;;
            validate_before_push) actual="$AUR_VALIDATE_BEFORE_PUSH" ;;
        esac
        [[ "$actual" == "${value,,}" ]] || { echo "$key: got [$actual] for [$value]"; exit 1; }
    done
    # An empty value keeps the default (true), like every other aur_integration key.
    load_with $'aur_integration:\n'"  $key:"$'\n'
    case "$key" in
        auto_push) actual="$AUR_AUTO_PUSH" ;;
        validate_before_push) actual="$AUR_VALIDATE_BEFORE_PUSH" ;;
    esac
    [[ "$actual" == true ]] || { echo "$key: empty value should keep the default, got [$actual]"; exit 1; }
    for value in Maybe yes no; do
        if err_out="$(load_with $'aur_integration:\n'"  $key: $value"$'\n' 2>&1)"; then
            echo "$key should reject [$value]"
            exit 1
        fi
        [[ "$err_out" == *"Invalid configuration"*"$key"* ]] || { echo "missing config error for $key: [$err_out]"; exit 1; }
    done
done

# Only a top-level aur_integration: opens the section; an indented one inside package: is a
# package key, so a later invalid-looking value there is not parsed as an integration setting.
load_with $'package:\n  aur_integration:\n  auto_push: maybe\n' || { echo "indented aur_integration: was parsed as the section"; exit 1; }
[[ "$AUR_AUTO_PUSH" == "true" ]] || { echo "indented aur_integration: changed auto_push to [$AUR_AUTO_PUSH]"; exit 1; }

# An unwritable parent must fail init with a hint, not a bare mkdir error.
mkdir -p "$tmp/ro"
chmod 0555 "$tmp/ro"
AUR_REPO_DIR="$tmp/ro/aur"
# If mkdir is not blocked (root, or a regressed guard), the clone must not reach the AUR.
mkdir -p "$tmp/bin"
printf '#!/bin/bash\necho "git stub: $*" >&2\nexit 1\n' > "$tmp/bin/git"
chmod +x "$tmp/bin/git"
if err_out="$(PATH="$tmp/bin:$PATH" init_aur_repo demo 2>&1)"; then
    echo "init_aur_repo should fail for an unwritable directory"
    exit 1
fi
[[ "$err_out" == *"Cannot create $tmp/ro/aur"*"aur_repo_dir"* ]] || { echo "missing hint: [$err_out]"; exit 1; }

# Invalid aur_integration (auto_push: maybe) must fail a dry run of aur before any tarball or signature is created.
dry_repo="$tmp/dry-aur"
mkdir -p "$dry_repo/aur" "$tmp/dry-bin" "$tmp/state"
for tool in makepkg updpkgsums curl gpg jq gh; do
    printf '#!/bin/bash\nexit 0\n' >| "$tmp/dry-bin/$tool"
    chmod +x "$tmp/dry-bin/$tool"
done
git -C "$dry_repo" init -q -b main
git -C "$dry_repo" config user.email "t@example.com"
git -C "$dry_repo" config user.name "t"
git -C "$dry_repo" config commit.gpgsign false
git -C "$dry_repo" config tag.gpgsign false
git -C "$dry_repo" remote add origin "https://github.com/example/demo.git"
printf '#!/bin/bash\necho ok\n' >| "$dry_repo/demo"
chmod +x "$dry_repo/demo"
git -C "$dry_repo" add demo
git -C "$dry_repo" commit -q -m init
git -C "$dry_repo" tag v1.0.0
cat >| "$dry_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: demo
aur_integration:
  auto_push: maybe
EOF
if err_out="$(cd "$dry_repo" && PATH="$tmp/dry-bin:$PATH" XDG_STATE_HOME="$tmp/state" GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$ROOT/bin/aurgen" -n --dry-run aur 2>&1)"; then
    echo "dry-run aur should fail when aur_integration.auto_push is maybe"
    exit 1
fi
[[ "$err_out" == *"Invalid configuration value for auto_push"* ]] || { echo "missing auto_push error from aur dry run: [$err_out]"; exit 1; }
tarballs="$(find "$dry_repo/aur" -type f \( -name '*.tar.gz' -o -name '*.sig' -o -name '*.asc' \) -print)"
[[ -z "$tarballs" ]] || { echo "dry-run aur created archive artifacts before rejecting auto_push: [$tarballs]"; exit 1; }
