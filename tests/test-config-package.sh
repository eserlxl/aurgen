#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-config-package.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
unset AURGEN_CONFIG_FILE AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

fail() {
    echo "$1"
    # A second argument names a file with the captured output that explains the failure.
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
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
    local bad="" name
    # Every variable _reset_package_vars clears; PKG_INSTALL_MESSAGES resets to 0.
    for name in PKG_NAME PKG_INSTALL PKG_CHECK PKG_GPG_KEY PKG_DESCRIPTION PKG_URL PKG_EPOCH PKG_SOURCE; do
        [[ -n "${!name:-}" ]] && bad+=" $name=[${!name}]"
    done
    for name in PKG_ARCH PKG_DEPENDS PKG_OPTDEPENDS PKG_MAKEDEPENDS PKG_CHECKDEPENDS PKG_CONFLICTS \
        PKG_PROVIDES PKG_BACKUP PKG_INSTALL_VARS PKG_KEEP PKG_EXCLUDE PKG_LICENSE PKG_GROUPS \
        PKG_REPLACES PKG_OPTIONS PKG_CMAKE_ARGS PKG_POST_PACKAGE PKG_PREPARE PKG_POST_INSTALL \
        PKG_POST_UPGRADE PKG_PRE_REMOVE; do
        local -n arr="$name"
        (( ${#arr[@]} )) && bad+=" $name=[${arr[*]}]"
        unset -n arr
    done
    [[ "${PKG_INSTALL_MESSAGES:-0}" == 0 ]] || bad+=" PKG_INSTALL_MESSAGES=[$PKG_INSTALL_MESSAGES]"
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
  checkdepends:
    - bats
    - 'python-pytest>=8'
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
  keep:
    - VERSION
    - share/help/
  exclude:
    - examples/
    - tests/fixtures/run.sh
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
  checkdepends: [bats, "python-pytest>=8"]
  conflicts: [demo-old]
  provides: [demo]
  backup: ["etc/demo/config", "etc/demo/other"]
  install_vars: [pkgname, pkgver]
  keep: [VERSION, share/help/]
  exclude: [examples/, tests/fixtures/run.sh]
$copy_rules
EOF

cat > "$tmp/norule/aurgen.install.yaml" <<EOF
$copy_rules
EOF

AUR_DIR="$tmp/block"
load_aurgen_config || fail "load block config failed"
# shellcheck disable=SC2153 # load_aurgen_config sets PKG_NAME
expect_eq "$PKG_NAME" "demo-pkg" "block PKG_NAME"
expect_eq "$PKG_INSTALL" "demo.install" "block PKG_INSTALL"
expect_eq "$PKG_CHECK" "false" "block PKG_CHECK"
expect_eq "$(csv "${PKG_CHECKDEPENDS[@]}")" "bats,python-pytest>=8" "block PKG_CHECKDEPENDS"
expect_eq "$(csv "${PKG_KEEP[@]}")" "VERSION,share/help/" "block PKG_KEEP"
expect_eq "$(csv "${PKG_EXCLUDE[@]}")" "examples/,tests/fixtures/run.sh" "block PKG_EXCLUDE"
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
expect_eq "$(csv "${PKG_CHECKDEPENDS[@]}")" "bats,python-pytest>=8" "inline PKG_CHECKDEPENDS"
expect_eq "$(csv "${PKG_KEEP[@]}")" "VERSION,share/help/" "inline PKG_KEEP"
expect_eq "$(csv "${PKG_EXCLUDE[@]}")" "examples/,tests/fixtures/run.sh" "inline PKG_EXCLUDE"
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
    if ! grep -q '^#   checkdepends:' "$f"; then
        fail "$f missing commented checkdepends"
    fi
    if ! grep -q '^#   keep:' "$f"; then
        fail "$f missing commented keep"
    fi
    if ! grep -q '^#   exclude:' "$f"; then
        fail "$f missing commented exclude"
    fi
done
if ! grep -q '^config_with_exclusions:' "$tmp/example.yaml"; then
    fail "example.yaml missing config_with_exclusions"
fi
if grep -q '^config_with_exclusions:' "$tmp/default.yaml"; then
    fail "default.yaml should not contain config_with_exclusions"
fi
if generate_default_config "$tmp/default.yaml/sub/default.yaml" >"$tmp/fail-def.out" 2>"$tmp/fail-def.err"; then
    fail "generate_default_config should fail when parent is a file"
fi
if generate_example_config "$tmp/default.yaml/sub/example.yaml" >"$tmp/fail-ex.out" 2>"$tmp/fail-ex.err"; then
    fail "generate_example_config should fail when parent is a file"
fi
mkdir -p "$tmp/unwritable.dir"
if generate_default_config "$tmp/unwritable.dir" >"$tmp/fail-def-w.out" 2>"$tmp/fail-def-w.err"; then
    fail "generate_default_config should fail on write error"
fi
if generate_example_config "$tmp/unwritable.dir" >"$tmp/fail-ex-w.out" 2>"$tmp/fail-ex-w.err"; then
    fail "generate_example_config should fail on write error"
fi

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

# Several quoted words are one shell line, not one quoted scalar: they keep their quotes.
cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  prepare:
    - "$srcdir/fix.sh" "$pkgver"
    - "plain value"
  post_package:
    - 'a' 'b'
    - 'it''s'
EOF
load_aurgen_config || fail "load multi-quoted shell lines failed"
expect_eq "${PKG_PREPARE[0]}" '"$srcdir/fix.sh" "$pkgver"' "multi-quoted PKG_PREPARE[0]"
expect_eq "${PKG_PREPARE[1]}" 'plain value' "quoted scalar PKG_PREPARE[1]"
expect_eq "${PKG_POST_PACKAGE[0]}" "'a' 'b'" "multi-quoted PKG_POST_PACKAGE[0]"
expect_eq "${PKG_POST_PACKAGE[1]}" "it's" "single-quoted scalar PKG_POST_PACKAGE[1]"

# A scalar with an inner quote still loads unquoted, as before the shell-line rule.
cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  description: 'It's fast'
EOF
load_aurgen_config || fail "load scalar with an inner quote failed"
expect_eq "$PKG_DESCRIPTION" "It's fast" "scalar PKG_DESCRIPTION with an inner quote"

# A double-quoted value decodes \" and \\ the way YAML does, so the shell sees the words written.
cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  check: "pytest -k \"not slow\""
  prepare:
    - "install -Dm644 \"a b\" \"$srcdir/x\""
    - "printf '%s\\n' done"
EOF
load_aurgen_config || fail "load double-quoted escapes failed"
expect_eq "$PKG_CHECK" 'pytest -k "not slow"' "decoded PKG_CHECK"
expect_eq "${PKG_PREPARE[0]}" 'install -Dm644 "a b" "$srcdir/x"' "decoded PKG_PREPARE[0]"
expect_eq "${PKG_PREPARE[1]}" "printf '%s\n' done" "decoded PKG_PREPARE[1]"
printf 'package:\n  description: "a\001b \\\\ c"\n' >| "$AUR_DIR/aurgen.install.yaml"
load_aurgen_config || fail "load a description with a 0x01 byte failed"
expect_eq "$PKG_DESCRIPTION" $'a\001b \\ c' "description keeps a 0x01 byte"

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

# Invalid keep entries stop loading in every list form, even before a valid item.
AUR_DIR="$tmp/bad-keep"
mkdir -p "$AUR_DIR"
for item in /VERSION ../VERSION share/../help/ 'share/*' 'share/?' 'share/[a' 'share/a]'; do
    for form in inline block scalar; do
        case "$form" in
            inline) printf 'package:\n  keep: ["%s", VERSION]\n' "$item" ;;
            block) printf 'package:\n  keep:\n    - "%s"\n    - VERSION\n' "$item" ;;
            scalar) printf 'package:\n  keep: "%s"\n' "$item" ;;
        esac >| "$AUR_DIR/aurgen.install.yaml"
        if load_aurgen_config >|"$tmp/bad-keep.out" 2>|"$tmp/bad-keep.err"; then
            fail "$form keep entry $item should fail"
        fi
        if ! grep -F -q "Invalid package.keep entry: $item" "$tmp/bad-keep.err"; then
            fail "$form keep error should name the entry: $item"
        fi
    done
done

# Invalid exclude entries stop loading in every list form, even before a valid item.
AUR_DIR="$tmp/bad-exclude"
mkdir -p "$AUR_DIR"
for item in /examples ../examples share/../examples/ 'examples/*' 'examples/?' 'examples/[a' 'examples/a]'; do
    for form in inline block scalar; do
        case "$form" in
            inline) printf 'package:\n  exclude: ["%s", examples/]\n' "$item" ;;
            block) printf 'package:\n  exclude:\n    - "%s"\n    - examples/\n' "$item" ;;
            scalar) printf 'package:\n  exclude: "%s"\n' "$item" ;;
        esac >| "$AUR_DIR/aurgen.install.yaml"
        if load_aurgen_config >|"$tmp/bad-exclude.out" 2>|"$tmp/bad-exclude.err"; then
            fail "$form exclude entry $item should fail"
        fi
        if ! grep -F -q "Invalid package.exclude entry: $item" "$tmp/bad-exclude.err"; then
            fail "$form exclude error should name the entry: $item"
        fi
    done
done

# A misspelled package key stops loading and names the key and its line.
AUR_DIR="$tmp/bad-inline"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF'
# misspelled depends
package:
  depend: [git]
EOF
if load_aurgen_config >"$tmp/bad-inline.out" 2>"$tmp/bad-inline.err"; then
    fail "inline unknown key depend should fail"
fi
if ! grep -F -q "Unknown package key 'depend' in $AUR_DIR/aurgen.install.yaml:3; known keys:" "$tmp/bad-inline.err"; then
    fail "inline unknown key should name the key and line: $(cat "$tmp/bad-inline.err")"
fi

AUR_DIR="$tmp/bad-block"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  name: demo-pkg

  depend:
    - git
EOF
if load_aurgen_config >"$tmp/bad-block.out" 2>"$tmp/bad-block.err"; then
    fail "block unknown key depend should fail"
fi
if ! grep -F -q "Unknown package key 'depend' in $AUR_DIR/aurgen.install.yaml:4; known keys:" "$tmp/bad-block.err"; then
    fail "block unknown key should name the key and line: $(cat "$tmp/bad-block.err")"
fi

# Malformed package keys stop loading in inline and block forms.
AUR_DIR="$tmp/bad-key"
mkdir -p "$AUR_DIR"
for key in check-depends check.depends 'check depends' 1depends; do
    for form in inline block; do
        case "$form" in
            inline) printf 'package:\n  %s: [bats]\n' "$key" ;;
            block) printf 'package:\n  %s:\n    - bats\n' "$key" ;;
        esac >| "$AUR_DIR/aurgen.install.yaml"
        if load_aurgen_config >|"$tmp/bad-key.out" 2>|"$tmp/bad-key.err"; then
            fail "$form malformed key $key should fail"
        fi
        if ! grep -F -q "Unknown package key '$key' in $AUR_DIR/aurgen.install.yaml:2; known keys:" "$tmp/bad-key.err"; then
            fail "$form malformed key error should name the key and line: $key"
        fi
    done
done

# Every documented package key still loads.
AUR_DIR="$tmp/allkeys"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  name: demo-pkg
  description: "quoted description"
  url: https://example.org/demo
  epoch: 2
  gpg_key: 89abcdef01234567
  install: demo.install
  check: false
  source: archive
  install_messages:
    post_install:
      - installed
    post_upgrade:
      - upgraded
    pre_remove:
      - removed
  arch: [any]
  depends: [bash]
  optdepends:
    - "git: version control"
  makedepends: [make]
  checkdepends: [bats]
  conflicts: [demo-old]
  groups: [demo-tools]
  provides: [demo]
  replaces: [demo-legacy]
  options: ["!lto", "!debug"]
  backup: [etc/demo/config]
  install_vars: [pkgname]
  keep: [VERSION, share/help/]
  exclude: [examples/, bench/]
  license: [MIT]
  post_package:
    - echo done
EOF
load_aurgen_config || fail "load every documented package key failed"
expect_eq "$PKG_NAME" "demo-pkg" "all PKG_NAME"
expect_eq "$PKG_DESCRIPTION" "quoted description" "all PKG_DESCRIPTION"
expect_eq "$PKG_URL" "https://example.org/demo" "all PKG_URL"
expect_eq "$PKG_EPOCH" "2" "all PKG_EPOCH"
expect_eq "$PKG_GPG_KEY" "89abcdef01234567" "all PKG_GPG_KEY"
expect_eq "$PKG_INSTALL" "demo.install" "all PKG_INSTALL"
expect_eq "$PKG_CHECK" "false" "all PKG_CHECK"
expect_eq "$PKG_SOURCE" "archive" "all PKG_SOURCE"
expect_eq "$PKG_INSTALL_MESSAGES" "1" "all PKG_INSTALL_MESSAGES"
expect_eq "$(csv "${PKG_POST_INSTALL[@]}")" "installed" "all PKG_POST_INSTALL"
expect_eq "$(csv "${PKG_POST_UPGRADE[@]}")" "upgraded" "all PKG_POST_UPGRADE"
expect_eq "$(csv "${PKG_PRE_REMOVE[@]}")" "removed" "all PKG_PRE_REMOVE"
expect_eq "$(csv "${PKG_ARCH[@]}")" "any" "all PKG_ARCH"
expect_eq "$(csv "${PKG_DEPENDS[@]}")" "bash" "all PKG_DEPENDS"
expect_eq "$(csv "${PKG_OPTDEPENDS[@]}")" "git: version control" "all PKG_OPTDEPENDS"
expect_eq "$(csv "${PKG_MAKEDEPENDS[@]}")" "make" "all PKG_MAKEDEPENDS"
expect_eq "$(csv "${PKG_CHECKDEPENDS[@]}")" "bats" "all PKG_CHECKDEPENDS"
expect_eq "$(csv "${PKG_CONFLICTS[@]}")" "demo-old" "all PKG_CONFLICTS"
expect_eq "$(csv "${PKG_GROUPS[@]}")" "demo-tools" "all PKG_GROUPS"
expect_eq "$(csv "${PKG_PROVIDES[@]}")" "demo" "all PKG_PROVIDES"
expect_eq "$(csv "${PKG_REPLACES[@]}")" "demo-legacy" "all PKG_REPLACES"
expect_eq "$(csv "${PKG_OPTIONS[@]}")" "!lto,!debug" "all PKG_OPTIONS"
expect_eq "$(csv "${PKG_BACKUP[@]}")" "etc/demo/config" "all PKG_BACKUP"
expect_eq "$(csv "${PKG_INSTALL_VARS[@]}")" "pkgname" "all PKG_INSTALL_VARS"
expect_eq "$(csv "${PKG_KEEP[@]}")" "VERSION,share/help/" "all PKG_KEEP"
expect_eq "$(csv "${PKG_EXCLUDE[@]}")" "examples/,bench/" "all PKG_EXCLUDE"
expect_eq "$(csv "${PKG_LICENSE[@]}")" "MIT" "all PKG_LICENSE"
expect_eq "$(csv "${PKG_POST_PACKAGE[@]}")" "echo done" "all PKG_POST_PACKAGE"

cat >| "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  url: https://example.org/demo
  epoch: 2
  replaces:
    - demo-legacy<2.0
  options:
    - "!lto"
    - "!debug"
EOF
load_aurgen_config || fail "load block metadata keys failed"
expect_eq "$(csv "${PKG_REPLACES[@]}")" "demo-legacy<2.0" "block PKG_REPLACES"
expect_eq "$(csv "${PKG_OPTIONS[@]}")" "!lto,!debug" "block PKG_OPTIONS"
validate_config 2>"$tmp/allkeys-val.err" || fail "validate_config failed on valid metadata" "$tmp/allkeys-val.err"

# Reject malformed url, epoch, replaces, and options in validate_config.
for invalid_spec in \
    "  url: not-a-url|Invalid package.url" \
    "  epoch: 0|Invalid package.epoch" \
    "  epoch: abc|Invalid package.epoch" \
    "  replaces: ['Bad Pkg']|Invalid package.replaces" \
    "  groups: ['Bad Group']|Invalid package.groups" \
    "  options: ['!LTO']|Invalid package.options" \
    "  depends: ['bad pkg']|Invalid package.depends" \
    "  makedepends: ['make;rm']|Invalid package.makedepends" \
    "  checkdepends: ['Bats']|Invalid package.checkdepends" \
    "  provides: ['demo = 1']|Invalid package.provides" \
    "  conflicts: ['old demo']|Invalid package.conflicts"; do
    bad_line="${invalid_spec%%|*}"
    bad_msg="${invalid_spec#*|}"
    printf 'package:\n%s\n' "$bad_line" >| "$AUR_DIR/aurgen.install.yaml"
    load_aurgen_config || fail "load failed before validate_config for $bad_line"
    if validate_config 2>"$tmp/bad-meta.err"; then
        fail "validate_config accepted $bad_line"
    fi
    grep -Fq "$bad_msg" "$tmp/bad-meta.err" || fail "missing '$bad_msg' for $bad_line" "$tmp/bad-meta.err"
done

# Version constraints, sonames and !name drops are valid dependency entries.
printf 'package:\n  depends: [bash, "python>=3.10", "!git"]\n  makedepends: ["cmake>=3.20", "!gcc"]\n  provides: ["libdemo.so=1-64", "demo=1.0"]\n  conflicts: [demo-git]\n  checkdepends: [python-pytest]\n' >| "$AUR_DIR/aurgen.install.yaml"
load_aurgen_config || fail "load failed before validate_config for valid dependency entries"
validate_config 2>"$tmp/dep-ok.err" || fail "validate_config refused valid dependency entries" "$tmp/dep-ok.err"

# Configured build constraints survive detection and replace bare package names.
repo="$tmp/versioned-makedepends"
mkdir -p "$repo/aur" || fail "create makedepends fixture failed"
git -C "$repo" init -q || fail "init makedepends fixture failed"
git -C "$repo" remote add origin https://example.com/testuser/testpkg.git || fail "set fixture remote failed"
printf 'all:\n\t@true\n' >| "$repo/Makefile"
git -C "$repo" add Makefile || fail "track fixture Makefile failed"
for build_dep in 'curl>=8.10' 'cmake>=3.24'; do
    printf "package:\n  makedepends: ['%s']\n" "$build_dep" >| "$repo/aur/aurgen.install.yaml"
    if ! (
        export LC_ALL=C
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=testpkg
        source "$ROOT/lib/gen-pkgbuild0.sh" || exit 1
        gh() { :; }
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        detect_makedepends() { printf '%s\n' "${build_dep%%>*}"; }
        detect_runtime_deps() { printf 'curl\n'; }
        load_aurgen_config || exit 1
        gen_pkgbuild0 || exit 1
        source "$AUR_DIR/PKGBUILD.0" || exit 1
        expect_eq "$(csv "${depends[@]}")" curl "detected runtime depends" || exit 1
        expect_eq "$(csv "${makedepends[@]}")" "$build_dep" "versioned makedepends" || exit 1
    ) >| "$tmp/makedepends.out" 2>| "$tmp/makedepends.err"; then
        cat "$tmp/makedepends.out" "$tmp/makedepends.err"
        fail "generation failed for $build_dep"
    fi
done

# post_package keeps the indentation after the "- " separator, so nested shell stays readable.
AUR_DIR="$tmp/postpkg-indent"
mkdir -p "$AUR_DIR"
cat > "$AUR_DIR/aurgen.install.yaml" <<'EOF'
package:
  post_package:
    - for f in a b; do
    -     echo "$f"
    - done
EOF
load_aurgen_config || fail "load indented post_package config failed"
expect_eq "${PKG_POST_PACKAGE[0]}" 'for f in a b; do' "PKG_POST_PACKAGE[0] indent"
expect_eq "${PKG_POST_PACKAGE[1]}" '    echo "$f"' "PKG_POST_PACKAGE[1] indent"
expect_eq "${PKG_POST_PACKAGE[2]}" 'done' "PKG_POST_PACKAGE[2] indent"

# A comma inside escaped quotes stays in its flow-list item.
mkdir -p "$tmp/escq"
AUR_DIR="$tmp/escq"
cat > "$tmp/escq/aurgen.install.yaml" <<'YAML'
package:
  name: demo
  optdepends: ["tool: says \"a, b\"", "git: vc"]
YAML
load_aurgen_config || fail "load escaped-quote flow list failed"
expect_eq "${#PKG_OPTDEPENDS[@]}" "2" "escaped-quote flow list item count"
expect_eq "${PKG_OPTDEPENDS[0]}" 'tool: says "a, b"' "escaped-quote flow list item"
