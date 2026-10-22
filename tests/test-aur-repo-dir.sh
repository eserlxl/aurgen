#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aur_repo_dir: XDG data default, ~ expansion, and a readable error when the
# directory cannot be created.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
unset XDG_DATA_HOME
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
