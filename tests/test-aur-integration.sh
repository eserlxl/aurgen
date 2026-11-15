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

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$GIT_ARGV_LOG"
exit 0
EOF
chmod +x "$stub/git"

export PATH="$stub:$PATH"
export GIT_ARGV_LOG="$tmp/argv"
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
: > "$GIT_ARGV_LOG"
: > "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

log() { :; }
warn() { :; }

export AUR_REPO_DIR="$tmp/aur"
export AUR_VALIDATE_BEFORE_PUSH="false"
AUR_SSH_KEY="$tmp"'/"; touch '"$tmp"'/pwned; echo "'
mkdir -p -- "$(dirname "$AUR_SSH_KEY")"
touch -- "$AUR_SSH_KEY"

expect_key_as_data() {
    local label="$1"
    local expected
    expected="core.sshCommand=ssh -i $(printf %q "$AUR_SSH_KEY")"
    if [[ -e "$tmp/pwned" ]]; then
        echo "$label: hostile ssh_key created $tmp/pwned"
        exit 1
    fi
    if ! grep -F -x -q -- "$expected" "$GIT_ARGV_LOG"; then
        echo "$label: ssh_key was not passed as one git -c argument"
        printf 'argv:\n'
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
}

if ! init_aur_repo "demopkg"; then
    echo "init_aur_repo failed"
    exit 1
fi
if [[ -e "$tmp/pwned" ]]; then
    echo "init_aur_repo: hostile ssh_key created $tmp/pwned"
    exit 1
fi
if ! grep -F -x -q clone "$GIT_ARGV_LOG"; then
    echo "init_aur_repo did not run git clone"
    exit 1
fi
if grep -F -q 'core.sshCommand' "$GIT_ARGV_LOG"; then
    echo "init_aur_repo passed ssh_key to clone"
    printf 'argv:\n'
    cat "$GIT_ARGV_LOG"
    exit 1
fi

: > "$GIT_ARGV_LOG"
if ! push_to_aur "demopkg"; then
    echo "push_to_aur failed"
    exit 1
fi
expect_key_as_data "push_to_aur"
if ! grep -F -x -q -- "HEAD:master" "$GIT_ARGV_LOG"; then
    echo "push_to_aur should push HEAD:master"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

AUR_SSH_KEY="$tmp/missing key"
: > "$GIT_ARGV_LOG"
warn() { printf '%s\n' "$*"; }
if ! push_to_aur "demopkg" > "$tmp/missing.out" 2> "$tmp/missing.err"; then
    echo "push_to_aur with missing spaced ssh_key failed"
    cat "$tmp/missing.err"
    exit 1
fi
if grep -F -q 'core.sshCommand' "$GIT_ARGV_LOG" || grep -F -q -- '-i' "$GIT_ARGV_LOG"; then
    echo "missing spaced ssh_key passed -i or core.sshCommand"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "[aur-integration] ssh_key $AUR_SSH_KEY does not exist; using the ssh configuration" "$tmp/missing.out"; then
    echo "missing spaced ssh_key did not warn"
    cat "$tmp/missing.out"
    exit 1
fi
