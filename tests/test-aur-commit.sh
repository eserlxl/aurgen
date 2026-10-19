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

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GIT_ARGV_LOG"
args=("$@")
if [[ "${args[0]}" == "-C" ]]; then
    args=("${args[@]:2}")
fi
case "${args[0]}" in
    commit)
        exit 1
        ;;
    diff)
        exit "$GIT_DIFF_STATUS"
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$stub/git"

export PATH="$stub:$PATH"
export GIT_ARGV_LOG="$tmp/argv"
export GIT_DIFF_STATUS=1
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
export SILVER=""
export RESET=""
export LIB_INSTALL_DIR="$ROOT/lib"
export AUR_DIR="$tmp/aurdir"
export PKGNAME="demopkg"
export PKGVER="1.0.0"
export PKGBUILD="$tmp/PKGBUILD"
export SRCINFO="$tmp/.SRCINFO"
: > "$GIT_ARGV_LOG"
: > "$AURGEN_ERROR_LOG"
printf 'pkgver=%s\n' "$PKGVER" > "$PKGBUILD"
printf 'pkgbase=%s\n' "$PKGNAME" > "$SRCINFO"
mkdir -p "$AUR_DIR" "$tmp/aur/$PKGNAME/.git"
cat > "$AUR_DIR/aurgen.install.yaml" << EOF
aur_integration:
  aur_repo_dir: $tmp/aur
  auto_push: true
  commit_message: Update to version {version}
  backup_existing: false
  validate_before_push: false
EOF

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/modes/aur-deploy.sh
source "$ROOT/lib/modes/aur-deploy.sh"

if mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "failing commit was treated as success"
    exit 1
fi
if grep -F -q "Successfully deployed" "$tmp/out"; then
    echo "failing commit printed a success message"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q "has been pushed" "$tmp/out"; then
    echo "failing commit reported a push"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "failing commit still pushed"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "diff --cached --quiet" "$GIT_ARGV_LOG"; then
    echo "failing commit did not check the index"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

: > "$GIT_ARGV_LOG"
: > "$tmp/out"
export GIT_DIFF_STATUS=0
if ! mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "empty index was treated as a commit failure"
    cat "$tmp/mode.err"
    exit 1
fi
if grep -F -q "has been pushed" "$tmp/out"; then
    echo "empty index reported a push"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q "Successfully deployed" "$tmp/out"; then
    echo "empty index reported a successful deploy"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "empty index still pushed"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

printf "pkgver=%s\ninstall='demo.install'\n" "$PKGVER" > "$PKGBUILD"
printf 'post_install() { :; }\n' > "$AUR_DIR/demo.install"
: > "$GIT_ARGV_LOG"
mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err" || true
if ! cmp -s "$AUR_DIR/demo.install" "$tmp/aur/$PKGNAME/demo.install"; then
    echo "install file was not copied"
    exit 1
fi
if ! grep -F -q "add PKGBUILD .SRCINFO demo.install" "$GIT_ARGV_LOG"; then
    echo "git add did not name the install file"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

printf "pkgver=%s\ninstall='missing.install'\n" "$PKGVER" > "$PKGBUILD"
: > "$GIT_ARGV_LOG"
: > "$tmp/mode.err"
if mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "missing install file was deployed"
    exit 1
fi
if ! grep -F -q "install file not found" "$tmp/mode.err"; then
    echo "missing install file did not report an error"
    cat "$tmp/mode.err"
    exit 1
fi
if grep -F -q "add PKGBUILD .SRCINFO missing.install" "$GIT_ARGV_LOG"; then
    echo "missing install file was staged"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
