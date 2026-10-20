#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-deploy-web.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export color_enabled=0
export DEBUG_LEVEL=0

# mode_aur_deploy sources $LIB_INSTALL_DIR/aur-integration.sh on every call, so the stubs live there.
LIB_INSTALL_DIR="$tmp/lib"
mkdir -p "$LIB_INSTALL_DIR"
cat > "$LIB_INSTALL_DIR/aur-integration.sh" << 'EOF'
load_aur_integration_config() { :; }
aur_package_name() { echo demopkg; }
deploy_to_aur() { AUR_PUSH_SUCCEEDED="$STUB_PUSHED"; }
aur_web_version() { echo "WEB-MARKER $1 ${2-}"; }
EOF

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur-deploy.sh
source "$ROOT/lib/modes/aur-deploy.sh"

log() { :; }
# mode_aur_deploy's first log line expands these under set -u.
export SILVER="" RESET=""

export PKGBUILD="$tmp/PKGBUILD"
export SRCINFO="$tmp/.SRCINFO"
export AUR_REPO_DIR="$tmp/aur"
touch "$PKGBUILD" "$SRCINFO"
export dry_run=0

export AUR_AUTO_PUSH=true
export STUB_PUSHED=true
if ! mode_aur_deploy >|"$tmp/pushed.out" 2>&1; then
    echo "deploy with a successful push failed"
    cat "$tmp/pushed.out"
    exit 1
fi
if ! grep -F -q 'WEB-MARKER demopkg just-pushed' "$tmp/pushed.out"; then
    echo "successful push did not print the AUR web version"
    cat "$tmp/pushed.out"
    exit 1
fi

export AUR_AUTO_PUSH=false
export STUB_PUSHED=false
if ! mode_aur_deploy >|"$tmp/local.out" 2>&1; then
    echo "deploy without push failed"
    cat "$tmp/local.out"
    exit 1
fi
if grep -F -q 'WEB-MARKER' "$tmp/local.out"; then
    echo "deploy without push printed the AUR web version"
    cat "$tmp/local.out"
    exit 1
fi

# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"
mkdir -p "$tmp/bin"
printf '%s\n' '#!/bin/bash' "printf '%s\n' '{\"resultcount\":0,\"results\":[]}'" >| "$tmp/bin/curl"
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
web_line=$(aur_web_version demopkg just-pushed)
if [[ "$web_line" != "AUR web: not listed yet (the AUR index can lag a few minutes)" ]]; then
    echo "just-pushed empty index used the wrong wording: [$web_line]"
    exit 1
fi
web_line=$(aur_web_version demopkg)
if [[ "$web_line" != "AUR web: not published" ]]; then
    echo "empty index without a push used the wrong wording: [$web_line]"
    exit 1
fi

echo "deploy web version tests passed"
