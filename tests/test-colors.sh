#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-colors.XXXXXX")"
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

# Same terminal, but NO_COLOR is set. Redirect alone is not what clears colour.
export NO_COLOR=1
export OUT="$tmp/term.nocolor"
python3 - <<'PY' || exit 1
import os
import pty
import subprocess

env = os.environ.copy()
env["NO_COLOR"] = "1"
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
            printf '%s%s' "$RED" "$RESET" >"$OUT"
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
if [[ ! -f "$OUT" ]] || grep -q $'\033' "$OUT" || grep -Fq '\e[' "$OUT" || grep -Fq '\033[' "$OUT"; then
    echo "NO_COLOR=1 on a terminal should print no escape sequence"
    exit 1
fi

# Terminals with TERM=dumb, unset TERM, or unknown terminfo must not trip set -e / ERR trap.
# TERM=dumb and an unset TERM get no escapes at all; an unknown terminfo falls back to real
# ESC bytes rather than literal '\e[' text.
unset NO_COLOR
for term_mode in "dumb" "aurgen-nonexistent-term-999" "__UNSET__"; do
    export TERM_MODE="$term_mode"
    export OUT="$tmp/term.fallback.$term_mode"
    python3 - <<'PY' || exit 1
import os
import pty
import subprocess

env = os.environ.copy()
env.pop("NO_COLOR", None)
env["color_enabled"] = "1"
mode = env["TERM_MODE"]
if mode == "__UNSET__":
    env.pop("TERM", None)
else:
    env["TERM"] = mode

master, slave = pty.openpty()
try:
    proc = subprocess.run(
        [
            "bash",
            "-c",
            """
            set -euo pipefail
            source "$ROOT/lib/helpers.sh"
            init_error_trap
            source "$ROOT/lib/colors.sh"
            color_enabled=1
            init_colors
            printf '%s|%s|%s|%s' "$RED" "$YELLOW" "$CYAN" "$RESET" >"$OUT"
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
    if ! python3 - "$OUT" "$term_mode" <<'PY'; then
import sys

data = open(sys.argv[1], "rb").read()
parts = data.split(b"|")
if sys.argv[2] in ("dumb", "__UNSET__"):
    raise SystemExit(0 if parts == [b"", b"", b"", b""] else 1)
if len(parts) != 4 or not all(p.startswith(b"\x1b[") for p in parts):
    raise SystemExit(1)
if b"\\e[" in data or b"\\033[" in data:
    raise SystemExit(1)
PY
        echo "terminal ($term_mode) got the wrong colors: no escapes expected for dumb/unset TERM, real ESC sequences for unknown terminfo"
        exit 1
    fi
done
