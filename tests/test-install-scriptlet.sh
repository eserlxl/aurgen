#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-install-scriptlet.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1" >&2
    exit 1
}

export LIB_INSTALL_DIR="$ROOT/lib"
export PROJECT_ROOT="$tmp/project"
export AUR_DIR="$PROJECT_ROOT/aur"
export OUT_DIR="$tmp/output"
export AURGEN_ERROR_LOG="$tmp/error.log"
export color_enabled=0
mkdir -p "$AUR_DIR" "$OUT_DIR"
printf 'install:\n\t@true\n' > "$PROJECT_ROOT/Makefile"
printf 'package:\n  source: archive\n' > "$AUR_DIR/aurgen.install.yaml"
: > "$AUR_DIR/aurgen.install.yaml.example"
: > "$AUR_DIR/PKGBUILD.HEADER"
cd "$PROJECT_ROOT"

# shellcheck source=../lib/gen-pkgbuild0.sh
source "$ROOT/lib/gen-pkgbuild0.sh"
set -o noclobber

# Keep metadata and the install operation local; exercise the real scan/report path.
git() {
    case "$*" in
        'config --get remote.origin.url') printf '%s\n' https://github.com/example/demo.git ;;
        'describe --tags --abbrev=0') printf '%s\n' v1.0 ;;
        *) return 1 ;;
    esac
}
gh() { :; }
generate_gitattributes_from_filter() { :; }
detect_makedepends() { :; }
unit_paths=(usr/lib/systemd/system/demo.timer usr/lib/systemd/user/watch.timer
    usr/lib/systemd/system/demo.service usr/lib/systemd/user/watch.service
    usr/lib/systemd/system/nested/ignored.timer usr/share/ignored.timer)
_runtime_try_install() {
    local path
    _RUNTIME_DEST="$(mktemp -d "$tmp/installed.XXXXXX")"
    printf 'scan\n' >> "$tmp/scans"
    for path in "${unit_paths[@]}"; do
        mkdir -p "$_RUNTIME_DEST/$(dirname "$path")"
        : > "$_RUNTIME_DEST/$path"
        _RUNTIME_FILES+=("$_RUNTIME_DEST/$path")
    done
}

generate() {
    load_aurgen_config
    # shellcheck disable=SC2034 # gen_pkgbuild0 consumes PKGNAME
    PKGNAME=demo
    gen_pkgbuild0 >| "$tmp/generate.out" 2>| "$tmp/generate.err"
    bash -n "$AUR_DIR/PKGBUILD.0"
}

# Generated next to PKGBUILD.0, like the template it belongs to.
scriptlet="$AUR_DIR/demo.install"
run_hook() {
    bash -n "$scriptlet"
    (
        cd "$tmp"
        systemctl() { fail 'scriptlet ran systemctl'; }
        sudo() { fail 'scriptlet ran sudo'; }
        # shellcheck disable=SC1090
        source "$scriptlet"
        "$1"
    )
}

generate
grep -Fxq "install='demo.install'" "$AUR_DIR/PKGBUILD.0" || fail 'missing install='
[[ "$(wc -l < "$tmp/scans")" -eq 1 ]] || fail 'install scanned more than once'
[[ "$(run_hook post_install)" == $'==> demo: nothing was enabled.\nsudo systemctl enable --now demo.timer\nsystemctl --user enable --now watch.timer' ]] || fail 'automatic timer enable hints'
[[ "$(run_hook pre_remove)" == $'sudo systemctl disable --now demo.timer\nsystemctl --user disable --now watch.timer' ]] || fail 'automatic timer disable hints'

# Services are used only when no timer is shipped.
unit_paths=(usr/lib/systemd/system/demo.service usr/lib/systemd/user/watch.service)
generate
[[ "$(run_hook post_install)" == $'==> demo: nothing was enabled.\nsudo systemctl enable --now demo.service\nsystemctl --user enable --now watch.service' ]] || fail 'service fallback'

cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  source: archive
  install_messages:
    post_install:
      - '  literal, with: spaces  '
      - '$(touch x)'
      - 'AURGEN_MESSAGES'
      - 'AURGEN_MESSAGES_'
      - ''
      - 'last line'
    post_upgrade:
      - 'upgrade $HOME `touch x`'
    pre_remove:
      - 'remove only after review'
  depends:
    - bash
EOF
generate
[[ "${PKG_DEPENDS[*]}" == bash ]] || fail 'message mapping swallowed adjacent metadata'
[[ "$(run_hook post_install)" == $'  literal, with: spaces  \n$(touch x)\nAURGEN_MESSAGES\nAURGEN_MESSAGES_\n\nlast line' ]] || fail 'configured lines changed or auto hints retained'
[[ "$(run_hook post_upgrade)" == 'upgrade $HOME `touch x`' ]] || fail 'upgrade text expanded'
[[ "$(run_hook pre_remove)" == 'remove only after review' ]] || fail 'remove override'
[[ ! -e "$tmp/x" && ! -e "$PROJECT_ROOT/x" ]] || fail 'message executed a command'

# Configured messages also generate a scriptlet without any installed units.
unit_paths=()
generate
[[ "$(run_hook pre_remove)" == 'remove only after review' ]] || fail 'messages require units'

# A missing hand file can be replaced by generated messages.
printf '\n  install: missing.install\n' >> "$AUR_DIR/aurgen.install.yaml"
generate
grep -Fxq "install='demo.install'" "$AUR_DIR/PKGBUILD.0" || fail 'missing file blocked generation'

# An explicit existing file wins and must not be rewritten.
printf '\n  install: hand.install\n' >> "$AUR_DIR/aurgen.install.yaml"
printf '%s\n' 'post_install() { echo hand; }' > "$AUR_DIR/hand.install"
rm "$scriptlet"
generate
grep -Fxq "install='hand.install'" "$AUR_DIR/PKGBUILD.0" || fail 'existing file not referenced'
[[ "$(cat "$AUR_DIR/hand.install")" == 'post_install() { echo hand; }' ]] || fail 'hand scriptlet changed'
[[ ! -e "$scriptlet" ]] || fail 'generated file despite existing install'

printf 'package:\n  install_messages:\n    post_install: echo unsafe\n' >| "$AUR_DIR/aurgen.install.yaml"
if load_aurgen_config 2>| "$tmp/invalid.err"; then
    fail 'non-list message accepted'
fi

# An unrelated package gets no scriptlet, and parsing resets all message fields.
printf 'package:\n  source: archive\n' >| "$AUR_DIR/aurgen.install.yaml"
generate
[[ "$PKG_INSTALL_MESSAGES" == 0 && ${#PKG_POST_INSTALL[@]} == 0 && ${#PKG_POST_UPGRADE[@]} == 0 && ${#PKG_PRE_REMOVE[@]} == 0 ]] || fail 'message fields were not reset'
if grep -q '^install=' "$AUR_DIR/PKGBUILD.0"; then
    fail 'install= on unrelated package'
fi

# Preview deployment finds the generated file beside PKGBUILD, before AUR_DIR.
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"
PKGBUILD="$OUT_DIR/PKGBUILD"
SRCINFO="$OUT_DIR/.SRCINFO"
printf "install='demo.install'\n" > "$PKGBUILD"
printf 'pkgver = 1.0\npkgrel = 1\n' > "$SRCINFO"
printf 'output scriptlet\n' > "$OUT_DIR/demo.install"
printf 'stale scriptlet\n' > "$AUR_DIR/demo.install"
export AUR_REPO_DIR="$tmp/checkout"
export AUR_COMMIT_MESSAGE='Update to version {version}'
export dry_run=1
deploy_to_aur demo > "$tmp/deploy.out"
grep -Fxq '+output scriptlet' "$tmp/deploy.out" || fail 'deploy missed output scriptlet'
if grep -Fq '+stale scriptlet' "$tmp/deploy.out"; then
    fail 'deploy used stale scriptlet'
fi
rm "$OUT_DIR/demo.install"
deploy_to_aur demo >| "$tmp/deploy.out"
grep -Fxq '+stale scriptlet' "$tmp/deploy.out" || fail 'deploy lost existing file fallback'

echo 'install scriptlet tests passed'
