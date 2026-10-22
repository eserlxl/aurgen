#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# Run every tests/test-*.sh; exit non-zero if any of them fails.

set -uo pipefail

TESTS_DIR="$(dirname "$(realpath "$0")")"

# Children must not use the caller's user state or logs.
state_root="$(mktemp -d)" || exit 1
gnupg_home="$state_root/gnupg"
trap 'gpgconf --homedir "$gnupg_home" --kill gpg-agent >/dev/null 2>&1; rm -rf -- "$state_root"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
export AURGEN_TEST_STATE_ROOT="$state_root"
export HOME="$state_root/home"
export XDG_CONFIG_HOME="$state_root/config"
export XDG_DATA_HOME="$state_root/data"
export XDG_STATE_HOME="$state_root/state"
export XDG_CACHE_HOME="$state_root/cache"
# shortcut: literal /tmp paths remain shared until Phase 1.2 adds its private mount.
export TMPDIR="$state_root/tmp" TMP="$state_root/tmp" TEMP="$state_root/tmp"
export AURGEN_LOG="$state_root/aurgen.log"
export AURGEN_ERROR_LOG="$state_root/aurgen-error.log"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$TMPDIR" "$gnupg_home" || exit 1
export GIT_CONFIG_GLOBAL="$state_root/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL" || exit 1
unset GIT_CONFIG GIT_CONFIG_PARAMETERS SSH_AUTH_SOCK SSH_AGENT_PID GPG_TTY GPG_AGENT_INFO
# gen_pkgbuild0 lists secret keys; tests that need keys set their own GNUPGHOME.
chmod 700 "$gnupg_home"
export GNUPGHOME="$gnupg_home"
# Keep scratch-repo signing off even if test-local config enables it.
# A test that exports its own GIT_CONFIG_COUNT replaces this.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

failed=0
ran=0

for t in "$TESTS_DIR"/test-*.sh; do
    [[ -e "$t" ]] || continue
    ran=$((ran + 1))
    if bash "$t"; then
        echo "PASS ${t##*/}"
    else
        echo "FAIL ${t##*/}"
        failed=$((failed + 1))
    fi
done

echo "$ran test file(s), $failed failed"
(( failed == 0 ))
