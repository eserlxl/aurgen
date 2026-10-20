#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$stub" "$repo"
cat > "$stub/nano" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" > "${AURGEN_EDITOR_LOG:?}"
EOF
chmod +x "$stub/nano"

if ! (
    cd "$repo"
    unset EDITOR
    export PATH="$stub:$PATH"
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
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config generate
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "config generate failed"
    cat "$tmp/gen.err"
    exit 1
fi

if [[ ! -f "$repo/aur/aurgen.install.yaml" ]]; then
    echo "aur/aurgen.install.yaml was not created"
    exit 1
fi
if [[ -e "$repo/generate" || -e "$repo/aur/generate" ]]; then
    echo "config generate wrote a file named generate"
    exit 1
fi

if ! (
    cd "$repo"
    unset EDITOR
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$repo/aur"
    export AURGEN_EDITOR_LOG="$tmp/editor.log"
    export AURGEN_ERROR_LOG="$tmp/err-edit.log"
    export AURGEN_MODE=test
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config edit
) >"$tmp/edit.out" 2>"$tmp/edit.err"; then
    echo "config edit failed with EDITOR unset"
    cat "$tmp/edit.err"
    exit 1
fi
if [[ ! -f "$tmp/editor.log" ]]; then
    echo "config edit did not open an editor with EDITOR unset"
    cat "$tmp/edit.err"
    exit 1
fi
if [[ "$(cat "$tmp/editor.log")" != "$repo/aur/aurgen.install.yaml" ]]; then
    echo "config edit opened the wrong file: $(cat "$tmp/editor.log")"
    exit 1
fi

mkdir -p "$tmp/noeol"
printf 'package:\n  name: demo-noeol' > "$tmp/noeol/aurgen.install.yaml"
if ! (
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$tmp/noeol"
    export AURGEN_ERROR_LOG="$tmp/err-noeol.log"
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
    load_aurgen_config || exit 1
    [[ "$PKG_NAME" == "demo-noeol" ]] || exit 1
) >"$tmp/noeol.out" 2>"$tmp/noeol.err"; then
    echo "unterminated last config line was dropped"
    cat "$tmp/noeol.err"
    exit 1
fi
