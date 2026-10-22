#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Stubbed ssh: success, permission denied, and an unknown host key.
# The configured key is passed as -i. A dry run does not call ssh.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-aur-ssh-readiness.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export LC_ALL=C
export HOME="$tmp/home"
export XDG_DATA_HOME="$tmp/xdg"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
export AUR_DIR="$tmp/aurdir"
export AURGEN_ERROR_LOG="$tmp/err.log"
export LIB_INSTALL_DIR="$ROOT/lib"
export PKGNAME="demopkg"
export color_enabled=0
export DEBUG_LEVEL=0
export SILVER=""
export RESET=""
export YELLOW=""
export SSH_ARGV_LOG="$tmp/ssh.argv"
export GIT_ARGV_LOG="$tmp/git.argv"
export SSH_STUB_MODE="ok"
unset SRCINFO

mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$AUR_DIR"
: >| "$AURGEN_ERROR_LOG"
: >| "$SSH_ARGV_LOG"
: >| "$GIT_ARGV_LOG"

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/ssh" << 'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$SSH_ARGV_LOG"
case "${SSH_STUB_MODE:-}" in
    ok)
        printf '%s\n' 'AUR help'
        exit 0
        ;;
    denied)
        printf '%s\n' 'aur@aur.archlinux.org: Permission denied (publickey).' >&2
        exit 255
        ;;
    hostkey)
        printf '%s\n' 'No ED25519 host key is known for aur.archlinux.org and you have requested strict checking.' 'Host key verification failed.' >&2
        exit 255
        ;;
    *)
        printf '%s\n' "unexpected ssh: ${SSH_STUB_MODE:-}" >&2
        exit 99
        ;;
esac
EOF
cat > "$stub/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$GIT_ARGV_LOG"
exit 0
EOF
chmod +x "$stub/ssh" "$stub/git"
export PATH="$stub:$PATH"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"
# shellcheck source=../lib/modes/aur-init.sh
source "$ROOT/lib/modes/aur-init.sh"

expect_line() {
    local file="$1"
    local line="$2"
    if ! grep -F -x -q -- "$line" "$file"; then
        echo "missing line: $line"
        cat "$file"
        exit 1
    fi
}

expect_argv() {
    local expected="$1"
    local got
    got="$(cat "$SSH_ARGV_LOG")"
    if [[ "$got" != "$expected" ]]; then
        echo "ssh arguments did not match"
        printf 'got:\n%s\n' "$got"
        exit 1
    fi
}

run_probe() {
    : >| "$SSH_ARGV_LOG"
    if ! aur_probe_ssh >|"$tmp/probe.out" 2>|"$tmp/probe.err"; then
        echo "aur_probe_ssh returned non-zero"
        cat "$tmp/probe.out"
        cat "$tmp/probe.err"
        exit 1
    fi
}

base_argv=$'-o\nBatchMode=yes\n-o\nConnectTimeout=10\n-o\nStrictHostKeyChecking=yes\naur@aur.archlinux.org\nhelp'

AUR_SSH_KEY=""
export SSH_STUB_MODE="ok"
run_probe
expect_line "$tmp/probe.out" "AUR SSH: ok"
expect_argv "$base_argv"

export SSH_STUB_MODE="denied"
run_probe
expect_line "$tmp/probe.out" "AUR SSH: permission denied: add your public key at https://aur.archlinux.org/account"
expect_argv "$base_argv"

export SSH_STUB_MODE="hostkey"
run_probe
expect_line "$tmp/probe.out" "AUR SSH: host key verification failed: connect once with ssh aur@aur.archlinux.org to verify the key"
expect_argv "$base_argv"

key="$tmp/aur_key"
: >| "$key"
AUR_SSH_KEY="$key"
export SSH_STUB_MODE="ok"
run_probe
expect_line "$tmp/probe.out" "AUR SSH: ok"
expect_argv $'-o\nBatchMode=yes\n-o\nConnectTimeout=10\n-o\nStrictHostKeyChecking=yes\n-i\n'"$AUR_SSH_KEY"$'\naur@aur.archlinux.org\nhelp'

# A failed probe warns and aur-init still succeeds. git and ssh are stubs.
export dry_run=0
export SSH_STUB_MODE="denied"
: >| "$SSH_ARGV_LOG"
: >| "$GIT_ARGV_LOG"
if ! mode_aur_init >|"$tmp/init.out" 2>|"$tmp/init.err"; then
    echo "aur-init failed when SSH was denied"
    cat "$tmp/init.out"
    cat "$tmp/init.err"
    exit 1
fi
expect_line "$tmp/init.out" "AUR SSH: permission denied: add your public key at https://aur.archlinux.org/account"
expect_argv "$base_argv"

export dry_run=1
export SSH_STUB_MODE="unexpected"
: >| "$SSH_ARGV_LOG"
: >| "$GIT_ARGV_LOG"
if ! mode_aur_init >|"$tmp/dry.out" 2>|"$tmp/dry.err"; then
    echo "dry run failed"
    cat "$tmp/dry.out"
    cat "$tmp/dry.err"
    exit 1
fi
if [[ -s "$SSH_ARGV_LOG" ]]; then
    echo "dry run called ssh"
    cat "$SSH_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "[aur-init] Dry run: would clone https://aur.archlinux.org/demopkg.git" "$tmp/dry.out"; then
    echo "dry run did not reach the clone step"
    cat "$tmp/dry.out"
    exit 1
fi
