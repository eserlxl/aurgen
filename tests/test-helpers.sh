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

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/makepkg" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$stub/makepkg"

(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/srcinfo"
    export SRCINFO="$tmp/srcinfo/aur/.SRCINFO"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export color_enabled=0
    mkdir -p "$PROJECT_ROOT/aur"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    generate_srcinfo
)
status=$?
if (( status == 0 )); then
    echo "generate_srcinfo should fail when makepkg --printsrcinfo fails"
    exit 1
fi
if [[ -e "$tmp/srcinfo/aur/.SRCINFO" ]]; then
    echo "generate_srcinfo should remove partial .SRCINFO"
    exit 1
fi
