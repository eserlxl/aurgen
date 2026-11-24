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
unset RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO

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
    # gen_pkgbuild0 calls git -C <root> ...; match the subcommand wherever it sits.
    case "$*" in
        *'config --get remote.origin.url') printf '%s\n' https://github.com/example/demo.git ;;
        *'describe --tags --abbrev=0'*) printf '%s\n' v1.0 ;;
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
    grep -Fxq 'pkgver=1.0' "$AUR_DIR/PKGBUILD.0"
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
        # Printed into the compared output, so a failing hook never matches.
        "$1" || echo "hook $1 exited $?"
    )
}

generate
grep -Fxq "install='demo.install'" "$AUR_DIR/PKGBUILD.0" || fail 'missing install='
[[ "$(wc -l < "$tmp/scans")" -eq 1 ]] || fail 'install scanned more than once'
[[ "$(run_hook post_install)" == $'==> demo: nothing was enabled.\nsudo systemctl enable --now demo.timer\nsystemctl --user enable --now watch.timer' ]] || fail 'automatic timer enable hints'
[[ "$(run_hook pre_remove)" == $'==> demo: disable the units you enabled before removing:\nsudo systemctl disable --now demo.timer\nsystemctl --user disable --now watch.timer' ]] || fail 'automatic timer disable hints'

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

# A unit-less package with only post_upgrade configured writes no post_install hook.
cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  source: archive
  install_messages:
    post_upgrade:
      - 'upgrade notice'
EOF
unit_paths=()
rm -f "$scriptlet"
generate
grep -Fxq "install='demo.install'" "$AUR_DIR/PKGBUILD.0" || fail 'missing install='
[[ "$(run_hook post_upgrade)" == 'upgrade notice' ]] || fail 'post_upgrade hook'
grep -Fq 'post_upgrade()' "$scriptlet" || fail 'post_upgrade missing from scriptlet'
if grep -q 'post_install' "$scriptlet"; then
    fail 'unexpected post_install hook'
fi
rm -f "$scriptlet"

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

# install= may name the file through $pkgname, as hand-written PKGBUILDs often do.
for value in '$pkgname.install' '"${pkgname}.install"' "'demo.install'"; do
    printf 'pkgname=demo\ninstall=%s\n' "$value" >| "$tmp/PKGBUILD.var"
    got=$(pkgbuild_install_file "$tmp/PKGBUILD.var")
    [[ "$got" == demo.install ]] || fail "install=$value resolved to [$got]"
done
printf 'pkgname=demo\n' >| "$tmp/PKGBUILD.var"
[[ -z "$(pkgbuild_install_file "$tmp/PKGBUILD.var")" ]] || fail 'no install= should print nothing'

printf 'pkgname=demo # (pkg)\ninstall=demo.install # (scriptlet)\n' >| "$tmp/PKGBUILD.comment"
got=$(pkgbuild_install_file "$tmp/PKGBUILD.comment")
[[ "$got" == demo.install ]] || fail "commented install= resolved to [$got]"

printf "pkgname='demo' # pkg\ninstall='\$pkgname.install' # inline note\n" >| "$tmp/PKGBUILD.comment-q"
got=$(pkgbuild_install_file "$tmp/PKGBUILD.comment-q")
[[ "$got" == demo.install ]] || fail "commented quoted install= resolved to [$got]"

printf 'pkgname="demo" # note\ninstall="${pkgname}#1.install" # trailing comment\n' >| "$tmp/PKGBUILD.hash"
got=$(pkgbuild_install_file "$tmp/PKGBUILD.hash")
[[ "$got" == 'demo#1.install' ]] || fail "quoted hash install= resolved to [$got]"

printf 'pkgname=demo\ninstall= # empty\n' >| "$tmp/PKGBUILD.empty-comment"
[[ -z "$(pkgbuild_install_file "$tmp/PKGBUILD.empty-comment")" ]] || fail 'empty commented install= should print nothing'

echo 'install scriptlet tests passed'

# A generated scriptlet (install_messages) in the dry-run output is never replaced from aur/;
# a hand-written one (package.install) always is, whatever the mtimes.
cp_dir="$tmp/cp-install"
mkdir -p "$cp_dir/aur/dry-run"
printf "pkgname=x\ninstall='x.install'\n" >| "$cp_dir/aur/dry-run/PKGBUILD"
printf 'old aur copy\n' >| "$cp_dir/aur/x.install"
printf 'generated this run\n' >| "$cp_dir/aur/dry-run/x.install"
touch -d '2030-01-01' "$cp_dir/aur/x.install"
# shellcheck disable=SC2034 # PKGBUILD0 and PKG_* are read by copy_install_for_makepkg
(AUR_DIR="$cp_dir/aur" OUT_DIR="$cp_dir/aur/dry-run" PKGBUILD0="$cp_dir/aur/dry-run/PKGBUILD.0" PKG_POST_INSTALL=("hello"); copy_install_for_makepkg "$cp_dir/aur/dry-run/PKGBUILD") || fail "copy_install_for_makepkg failed"
grep -Fxq 'generated this run' "$cp_dir/aur/dry-run/x.install" || fail "aur/ replaced a generated dry-run scriptlet" "$cp_dir/aur/dry-run/x.install"
# A dry run that reuses aur/PKGBUILD.0 generates no scriptlet of its own: copy it from aur/.
rm -f -- "$cp_dir/aur/dry-run/x.install"
# shellcheck disable=SC2034 # PKGBUILD0 and PKG_* are read by copy_install_for_makepkg
(AUR_DIR="$cp_dir/aur" OUT_DIR="$cp_dir/aur/dry-run" PKGBUILD0="$cp_dir/aur/PKGBUILD.0" PKG_POST_INSTALL=("hello"); copy_install_for_makepkg "$cp_dir/aur/dry-run/PKGBUILD") || fail "copy_install_for_makepkg failed"
grep -Fxq 'old aur copy' "$cp_dir/aur/dry-run/x.install" || fail "a dry run reusing aur/PKGBUILD.0 did not get the aur/ scriptlet" "$cp_dir/aur/dry-run/x.install"
printf 'edited by hand\n' >| "$cp_dir/aur/x.install"
touch -d '2001-01-01' "$cp_dir/aur/x.install"
(AUR_DIR="$cp_dir/aur" OUT_DIR="$cp_dir/aur/dry-run" PKG_POST_INSTALL=() PKG_POST_UPGRADE=() PKG_PRE_REMOVE=(); copy_install_for_makepkg "$cp_dir/aur/dry-run/PKGBUILD") || fail "copy_install_for_makepkg failed"
grep -Fxq 'edited by hand' "$cp_dir/aur/dry-run/x.install" || fail "an older hand-written aur/ scriptlet did not reach the dry run" "$cp_dir/aur/dry-run/x.install"
