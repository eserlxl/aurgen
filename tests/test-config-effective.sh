#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config-effective.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/aur"

cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []

libraries:
  source: lib
  destination: usr/lib/$pkgname
  permissions: read-only
  exclude: [test, temp]

package:
  name: demo-pkg
  description: "A demo: package"
  install: demo.install
  check: "makepkg -e"
  source: archive
  gpg_key: 0123456789ABCDEF
  arch: [x86_64, any]
  depends: ["bash", "git"]
  optdepends:
    - "bash: the shell"
  makedepends: [make]
  conflicts: [demo-old]
  provides: [demo]
  backup: ["etc/demo/config"]
  install_vars: ["UNITDIR=/usr/lib/systemd/system"]
  license: ["GPL-3.0-or-later", MIT]
  post_package:
    - "echo done"
  install_messages:
    post_install:
      - "Run demo --setup"
    pre_remove:
      - "Stopping demo"

aur_integration:
  aur_repo_dir: /srv/aur
  auto_push: false
EOF

run_mode() {
    local out="$1"
    local err="$2"
    shift 2
    if ! (
        cd "$repo"
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
        # shellcheck source=../lib/config.sh
        source "$ROOT/lib/config.sh"
        # shellcheck source=../lib/modes/config.sh
        source "$ROOT/lib/modes/config.sh"
        mode_config "$@" || exit 1
    ) >"$out" 2>"$err"; then
        echo "mode_config $* failed"
        cat "$err"
        exit 1
    fi
}

run_mode "$tmp/effective.out" "$tmp/effective.err" show effective

cat > "$tmp/effective.want" <<'EOF'
name: demo-pkg
description: A demo: package
install: demo.install
check: makepkg -e
source: archive
gpg_key: 0123456789ABCDEF
arch:
  - x86_64
  - any
depends:
  - bash
  - git
optdepends:
  - bash: the shell
makedepends:
  - make
conflicts:
  - demo-old
provides:
  - demo
backup:
  - etc/demo/config
install_vars:
  - UNITDIR=/usr/lib/systemd/system
license:
  - GPL-3.0-or-later
  - MIT
post_package:
  - echo done
install_messages:
  post_install:
    - Run demo --setup
  pre_remove:
    - Stopping demo
copy:
  - bin:usr/bin:755
  - lib:usr/lib/$pkgname:644:test, temp
aur_integration:
  aur_repo_dir: /srv/aur
  auto_push: false
  validate_before_push: true
  commit_message: Update to version {version}
EOF

if ! cmp -s "$tmp/effective.out" "$tmp/effective.want"; then
    echo "effective config did not match parsed fields"
    diff -u "$tmp/effective.want" "$tmp/effective.out" || true
    exit 1
fi

run_mode "$tmp/show.out" "$tmp/show.err" show

{
    echo "---"
    cat "$repo/aur/aurgen.install.yaml"
} > "$tmp/show.want"

if ! cmp -s "$tmp/show.out" "$tmp/show.want"; then
    echo "plain config show changed"
    diff -u "$tmp/show.want" "$tmp/show.out" || true
    exit 1
fi
if ! grep -q '"bash: the shell"' "$tmp/show.out"; then
    echo "plain config show dropped the quoted optdepends"
    exit 1
fi
