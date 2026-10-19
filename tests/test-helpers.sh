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

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    require bash
)
status=$?
if (( status != 0 )); then
    echo "require bash should succeed, got $status"
    exit 1
fi

(
    set +u
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    require aurgen-missing-tool-xyz
)
status=$?
if (( status == 0 )); then
    echo "require aurgen-missing-tool-xyz should fail"
    exit 1
fi
