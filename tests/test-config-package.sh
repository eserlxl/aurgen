#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config-package.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    exit 1
}

csv() {
    local IFS=','
    printf '%s' "$*"
}

expect_eq() {
    local got="$1"
    local want="$2"
    local msg="$3"
    if [[ "$got" != "$want" ]]; then
        echo "$msg"
        echo "got: [$got]"
        echo "want: [$want]"
        exit 1
    fi
}

assert_copy_rules() {
    expect_eq "$COPY_RULES_BIN" "usr/bin:executable:test, temp" "COPY_RULES_BIN"
    expect_eq "$COPY_RULES_LIB" 'usr/lib/$pkgname:read-only:' "COPY_RULES_LIB"
    expect_eq "$COPY_RULES_ETC" "" "COPY_RULES_ETC"
    expect_eq "$COPY_RULES_SHARE" "" "COPY_RULES_SHARE"
    expect_eq "$COPY_RULES_INCLUDE" "" "COPY_RULES_INCLUDE"
    expect_eq "$COPY_RULES_LOCAL" "" "COPY_RULES_LOCAL"
    expect_eq "$COPY_RULES_VAR" "" "COPY_RULES_VAR"
    expect_eq "$COPY_RULES_OPT" "" "COPY_RULES_OPT"
}

assert_package_empty() {
    local bad=""
    [[ -n "$PKG_NAME" ]] && bad+=" PKG_NAME=[$PKG_NAME]"
    [[ -n "$PKG_INSTALL" ]] && bad+=" PKG_INSTALL=[$PKG_INSTALL]"
    [[ -n "$PKG_CHECK" ]] && bad+=" PKG_CHECK=[$PKG_CHECK]"
    (( ${#PKG_ARCH[@]} )) && bad+=" PKG_ARCH=[${PKG_ARCH[*]}]"
    (( ${#PKG_DEPENDS[@]} )) && bad+=" PKG_DEPENDS=[${PKG_DEPENDS[*]}]"
    (( ${#PKG_OPTDEPENDS[@]} )) && bad+=" PKG_OPTDEPENDS=[${PKG_OPTDEPENDS[*]}]"
    (( ${#PKG_MAKEDEPENDS[@]} )) && bad+=" PKG_MAKEDEPENDS=[${PKG_MAKEDEPENDS[*]}]"
    (( ${#PKG_CONFLICTS[@]} )) && bad+=" PKG_CONFLICTS=[${PKG_CONFLICTS[*]}]"
    (( ${#PKG_PROVIDES[@]} )) && bad+=" PKG_PROVIDES=[${PKG_PROVIDES[*]}]"
    (( ${#PKG_BACKUP[@]} )) && bad+=" PKG_BACKUP=[${PKG_BACKUP[*]}]"
    (( ${#PKG_INSTALL_VARS[@]} )) && bad+=" PKG_INSTALL_VARS=[${PKG_INSTALL_VARS[*]}]"
    [[ -n "$PKG_GPG_KEY" ]] && bad+=" PKG_GPG_KEY=[$PKG_GPG_KEY]"
    if [[ -n "$bad" ]]; then
        fail "package vars should be empty:$bad"
    fi
}

assert_lists() {
    local arch="$1"
    local depends="$2"
    local optdepends="$3"
    local makedepends="$4"
    local conflicts="$5"
    local provides="$6"
    local backup="$7"
    local install_vars="$8"
    expect_eq "$(csv "${PKG_ARCH[@]}")" "$arch" "PKG_ARCH"
    expect_eq "$(csv "${PKG_DEPENDS[@]}")" "$depends" "PKG_DEPENDS"
    expect_eq "$(csv "${PKG_OPTDEPENDS[@]}")" "$optdepends" "PKG_OPTDEPENDS"
    expect_eq "$(csv "${PKG_MAKEDEPENDS[@]}")" "$makedepends" "PKG_MAKEDEPENDS"
    expect_eq "$(csv "${PKG_CONFLICTS[@]}")" "$conflicts" "PKG_CONFLICTS"
    expect_eq "$(csv "${PKG_PROVIDES[@]}")" "$provides" "PKG_PROVIDES"
    expect_eq "$(csv "${PKG_BACKUP[@]}")" "$backup" "PKG_BACKUP"
    expect_eq "$(csv "${PKG_INSTALL_VARS[@]}")" "$install_vars" "PKG_INSTALL_VARS"
}

export AURGEN_ERROR_LOG="$tmp/err.log"
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

copy_rules='
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: [test, temp]

libraries:
  source: lib
  destination: usr/lib/$pkgname
  permissions: read-only
  exclude: []
'

mkdir -p "$tmp/block" "$tmp/inline" "$tmp/norule"

cat > "$tmp/block/aurgen.install.yaml" <<EOF
$copy_rules
package:
  name: "demo-pkg"
  install: "demo.install"
  check: false
  arch:
    - x86_64
    - any
  depends:
    - bash
    - git
  optdepends:
    - "bash: the shell"
    - 'git: version control'
  makedepends:
    - make
    - gcc
  conflicts:
    - demo-old
  provides:
    - demo
  backup:
    - etc/demo/config
    - "etc/demo/other"
  install_vars:
    - pkgname
    - pkgver
EOF

cat > "$tmp/inline/aurgen.install.yaml" <<EOF
package:
  name: demo-pkg
  install: demo.install
  check: "makepkg -e"
  arch: [x86_64, any]
  depends: ["bash", "git"]
  optdepends: ["bash: the shell", "git: version control"]
  makedepends: [make, gcc]
  conflicts: [demo-old]
  provides: [demo]
  backup: ["etc/demo/config", "etc/demo/other"]
  install_vars: [pkgname, pkgver]
$copy_rules
EOF

cat > "$tmp/norule/aurgen.install.yaml" <<EOF
$copy_rules
EOF

AUR_DIR="$tmp/block"
load_aurgen_config || fail "load block config failed"
expect_eq "$PKG_NAME" "demo-pkg" "block PKG_NAME"
expect_eq "$PKG_INSTALL" "demo.install" "block PKG_INSTALL"
expect_eq "$PKG_CHECK" "false" "block PKG_CHECK"
assert_lists \
    "x86_64,any" \
    "bash,git" \
    "bash: the shell,git: version control" \
    "make,gcc" \
    "demo-old" \
    "demo" \
    "etc/demo/config,etc/demo/other" \
    "pkgname,pkgver"
assert_copy_rules

AUR_DIR="$tmp/inline"
load_aurgen_config || fail "load inline config failed"
expect_eq "$PKG_NAME" "demo-pkg" "inline PKG_NAME"
expect_eq "$PKG_INSTALL" "demo.install" "inline PKG_INSTALL"
expect_eq "$PKG_CHECK" "makepkg -e" "inline PKG_CHECK"
assert_lists \
    "x86_64,any" \
    "bash,git" \
    "bash: the shell,git: version control" \
    "make,gcc" \
    "demo-old" \
    "demo" \
    "etc/demo/config,etc/demo/other" \
    "pkgname,pkgver"
assert_copy_rules

AUR_DIR="$tmp/norule"
load_aurgen_config || fail "load config without package section failed"
assert_package_empty
assert_copy_rules

generate_default_config "$tmp/default.yaml" >"$tmp/gen.out" 2>"$tmp/gen.err" || fail "generate_default_config failed"
generate_example_config "$tmp/example.yaml" >"$tmp/ex.out" 2>"$tmp/ex.err" || fail "generate_example_config failed"
for f in "$tmp/default.yaml" "$tmp/example.yaml"; do
    if ! grep -q '^# package:' "$f"; then
        fail "$f missing commented package section"
    fi
    if ! grep -q '^#   optdepends:' "$f"; then
        fail "$f missing commented optdepends"
    fi
done

AUR_DIR="$tmp/generated"
mkdir -p "$AUR_DIR"
cp "$tmp/default.yaml" "$AUR_DIR/aurgen.install.yaml"
load_aurgen_config || fail "load generated default failed"
assert_package_empty
expect_eq "$COPY_RULES_BIN" "$DEFAULT_COPY_RULES_BIN" "generated COPY_RULES_BIN"
expect_eq "$COPY_RULES_LIB" "$DEFAULT_COPY_RULES_LIB" "generated COPY_RULES_LIB"
expect_eq "$COPY_RULES_OPT" "$DEFAULT_COPY_RULES_OPT" "generated COPY_RULES_OPT"

# A post_package shell line that ends with a quote keeps it.
AUR_DIR="$tmp/postpkg"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  description: 'quoted description'
  post_package:
    - echo "$pkgver" > "$pkgdir/usr/lib/$pkgname/VERSION"
EOF
load_aurgen_config || fail "load post_package config failed"
expect_eq "${PKG_POST_PACKAGE[0]}" 'echo "$pkgver" > "$pkgdir/usr/lib/$pkgname/VERSION"' "PKG_POST_PACKAGE[0]"
expect_eq "$PKG_DESCRIPTION" "quoted description" "PKG_DESCRIPTION"

# gpg_key loads quoted and unquoted.
AUR_DIR="$tmp/gpgkey"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF2'
package:
  gpg_key: "0123456789ABCDEF0123456789ABCDEF01234567"
EOF2
load_aurgen_config || fail "load quoted gpg_key config failed"
expect_eq "$PKG_GPG_KEY" "0123456789ABCDEF0123456789ABCDEF01234567" "quoted PKG_GPG_KEY"
cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF2'
package:
  gpg_key: 89abcdef01234567
EOF2
load_aurgen_config || fail "load unquoted gpg_key config failed"
expect_eq "$PKG_GPG_KEY" "89abcdef01234567" "unquoted PKG_GPG_KEY"

# A scalar list value is a one-item list, not dropped.
AUR_DIR="$tmp/scalar"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  license: MIT
  depends: 'bash'
  arch:
    - any
EOF
load_aurgen_config || fail "load scalar list config failed"
expect_eq "$(csv "${PKG_LICENSE[@]}")" "MIT" "scalar license"
expect_eq "$(csv "${PKG_DEPENDS[@]}")" "bash" "scalar depends"
expect_eq "$(csv "${PKG_ARCH[@]}")" "any" "block arch"
