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

# gen_pkgbuild0 lists secret keys, so tests would read the user's keyring and
# pick a real key. Tests that need keys set their own GNUPGHOME.
gnupg_home="$(mktemp -d)"
trap 'gpgconf --homedir "$gnupg_home" --kill gpg-agent >/dev/null 2>&1; rm -rf "$gnupg_home"' EXIT
chmod 700 "$gnupg_home"
export GNUPGHOME="$gnupg_home"
# With that empty keyring, commit.gpgsign or tag.gpgsign from ~/.gitconfig makes
# every scratch-repo commit fail, and a test then runs against a repo with no commit.
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
