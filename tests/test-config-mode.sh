#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config-mode.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"

if ! (
    cd "$repo"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$repo/aur"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config generate || exit 1
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "config generate failed on a missing file"
    cat "$tmp/gen.err"
    exit 1
fi

config_file="$repo/aur/aurgen.install.yaml"
if [[ ! -f "$config_file" ]]; then
    echo "aur/aurgen.install.yaml was not created"
    exit 1
fi

before="$(cksum "$config_file")"

if (
    cd "$repo"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$repo/aur"
    export AURGEN_ERROR_LOG="$tmp/err-again.log"
    export AURGEN_MODE=test
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config generate
) >"$tmp/again.out" 2>"$tmp/again.err"; then
    echo "config generate succeeded when the file already existed"
    exit 1
fi

after="$(cksum "$config_file")"
if [[ "$before" != "$after" ]]; then
    echo "existing configuration file was modified"
    exit 1
fi
if ! grep -q "Configuration file already exists" "$tmp/again.out"; then
    echo "existing-file warning was not printed"
    cat "$tmp/again.out"
    exit 1
fi
