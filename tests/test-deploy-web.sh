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

export HOME="$tmp/home"
mkdir -p "$HOME"

export color_enabled=0
export DEBUG_LEVEL=0

# Both modes source $LIB_INSTALL_DIR/aur-integration.sh on every call, so the stubs live there.
LIB_INSTALL_DIR="$tmp/lib"
mkdir -p "$LIB_INSTALL_DIR"
cat >| "$LIB_INSTALL_DIR/aur-integration.sh" << 'EOF'
load_aur_integration_config() { :; }
aur_package_name() { echo demopkg; }
deploy_to_aur() { AUR_PUSH_SUCCEEDED="$STUB_PUSHED"; }
check_aur_repo_exists() { :; }
push_to_aur() { return "${STUB_PUSH_RC:-0}"; }
aur_web_version() { echo "WEB-MARKER $1 ${2-}"; }
EOF

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur-deploy.sh
source "$ROOT/lib/modes/aur-deploy.sh"

log() { :; }
# The placeholder PKGBUILD is empty; .SRCINFO regeneration is covered in test-deploy-e2e.sh.
generate_srcinfo() { :; }
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

# Report an existing upstream and one local commit without touching a real clone.
git() { echo 1; }
if ! mode_aur_push >|"$tmp/push.out" 2>&1; then
    echo "aur-push with a successful push failed"
    cat "$tmp/push.out"
    exit 1
fi
if ! grep -F -q 'WEB-MARKER demopkg just-pushed' "$tmp/push.out"; then
    echo "successful aur-push did not print the AUR web version"
    cat "$tmp/push.out"
    exit 1
fi

export STUB_PUSH_RC=23
push_rc=0
mode_aur_push >|"$tmp/failed-push.out" 2>&1 || push_rc=$?
if (( push_rc != 23 )); then
    echo "failed aur-push did not preserve the push exit status: $push_rc"
    exit 1
fi
if grep -F -q 'WEB-MARKER' "$tmp/failed-push.out"; then
    echo "failed aur-push printed the AUR web version"
    cat "$tmp/failed-push.out"
    exit 1
fi
unset -f git

# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"
mkdir -p "$tmp/bin"
install_curl_stub() {
    printf '%s\n' '#!/bin/bash' "$1" >| "$tmp/bin/curl"
    chmod +x "$tmp/bin/curl"
}
install_curl_stub "printf '%s\n' '{\"resultcount\":0,\"results\":[]}'"
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

install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\",\"OutOfDate\":1609459200,\"Maintainer\":\"alice\"}]}'"
web_line=$(aur_web_version demopkg)
if [[ "$web_line" != "AUR web: 1.2.3-1 (flagged out of date since 2021-01-01)" ]]; then
    echo "flagged package used the wrong wording: [$web_line]"
    exit 1
fi

install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\",\"OutOfDate\":null,\"Maintainer\":null}]}'"
web_line=$(aur_web_version demopkg)
if [[ "$web_line" != "AUR web: 1.2.3-1 (orphaned)" ]]; then
    echo "orphaned package used the wrong wording: [$web_line]"
    exit 1
fi

install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\"}]}'"
web_line=$(aur_web_version demopkg)
if [[ "$web_line" != "AUR web: 1.2.3-1" ]]; then
    echo "package with neither flag field used the wrong wording: [$web_line]"
    exit 1
fi

# A failing mktemp must not fail the caller under the runtime ERR trap.
mkdir -p "$tmp/nomktemp"
printf '#!/bin/bash\nexit 1\n' > "$tmp/nomktemp/mktemp"
chmod +x "$tmp/nomktemp/mktemp"
# Not inside if or ||: bash ignores errexit and the ERR trap there, subshells included.
web_line=$(PATH="$tmp/nomktemp:$PATH"; set -eE; trap 'exit 1' ERR; aur_web_version demopkg)
web_rc=$?
if (( web_rc != 0 )); then
    echo "a failing mktemp failed aur_web_version"
    exit 1
fi
if [[ "$web_line" != "AUR web: unavailable" ]]; then
    echo "a failing mktemp used the wrong wording: [$web_line]"
    exit 1
fi

echo "deploy web version tests passed"
