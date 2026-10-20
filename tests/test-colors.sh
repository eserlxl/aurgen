#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-colors.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_MODE=test
export color_enabled=1
unset NO_COLOR
# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/colors.sh
source "$ROOT/lib/colors.sh"
color_enabled=1
init_colors >"$tmp/plain.out" || exit 1
if [[ -n "$RED" || -n "$RESET" ]]; then
    echo "redirected init_colors should clear RED and RESET"
    exit 1
fi

export NO_COLOR=1
color_enabled=1
init_colors >"$tmp/nocolor.out" || exit 1
if [[ -n "$RED" || -n "$RESET" ]]; then
    echo "NO_COLOR=1 should clear RED and RESET"
    exit 1
fi

# A terminal still gets colour. The pty is stdout so [[ -t 1 ]] is true.
unset NO_COLOR
export ROOT
export OUT="$tmp/term.red"
python3 - <<'PY' || exit 1
import os
import pty
import subprocess

env = os.environ.copy()
env.pop("NO_COLOR", None)
env["color_enabled"] = "1"
env["TERM"] = "xterm-256color"
master, slave = pty.openpty()
try:
    proc = subprocess.run(
        [
            "bash",
            "-c",
            """
            set -uo pipefail
            source "$ROOT/lib/helpers.sh"
            source "$ROOT/lib/colors.sh"
            color_enabled=1
            init_colors
            printf '%s' "$RED" >"$OUT"
            """,
        ],
        env=env,
        stdout=slave,
        stderr=subprocess.DEVNULL,
        check=False,
    )
finally:
    os.close(slave)
    os.close(master)
raise SystemExit(proc.returncode)
PY
if [[ ! -s "$OUT" ]]; then
    echo "terminal init_colors should set RED"
    exit 1
fi
