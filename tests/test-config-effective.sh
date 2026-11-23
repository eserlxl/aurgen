#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-config-effective.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
unset AURGEN_CONFIG_FILE AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

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
  cmake_args: [-DCMAKE_BUILD_TYPE=Release]
  keep: [VERSION, share/help/]
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
cmake_args:
  - -DCMAKE_BUILD_TYPE=Release
keep:
  - VERSION
  - share/help/
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

cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: demo-pkg
  description: "A demo: package"
  url: https://example.org/demo
  epoch: 2
  replaces: [demo-legacy]
  options: ["!lto", "!debug"]
EOF
run_mode "$tmp/meta-eff.out" "$tmp/meta-eff.err" show effective
grep -Fxq 'url: https://example.org/demo' "$tmp/meta-eff.out" || { echo "show effective missing url"; cat "$tmp/meta-eff.out"; exit 1; }
grep -Fxq 'epoch: 2' "$tmp/meta-eff.out" || { echo "show effective missing epoch"; cat "$tmp/meta-eff.out"; exit 1; }
# The item must sit directly under the replaces: key, not anywhere in the output.
awk 'prev ~ /^[[:space:]]*replaces:[[:space:]]*$/ && $0 == "  - demo-legacy" { found = 1 } { prev = $0 } END { exit !found }' "$tmp/meta-eff.out" \
    || { echo "show effective missing replaces: followed by its item"; cat "$tmp/meta-eff.out"; exit 1; }
grep -Fxq '  - !lto' "$tmp/meta-eff.out" || { echo "show effective missing !lto option"; cat "$tmp/meta-eff.out"; exit 1; }
grep -Fxq '  - !debug' "$tmp/meta-eff.out" || { echo "show effective missing !debug option"; cat "$tmp/meta-eff.out"; exit 1; }

# --json config show effective (and aliases s, list, l) emits single-line resolved JSON
git -C "$repo" init -q -b main
git -C "$repo" remote add origin "https://github.com/example/demo-pkg.git"

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
  cmake_args: [-DCMAKE_BUILD_TYPE=Release]
  keep: [VERSION, share/help/]
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

for action_alias in show s list l; do
    if ! (cd "$repo" && "$ROOT/bin/aurgen" --json config "$action_alias" effective) >|"$tmp/eff-json-$action_alias.out" 2>|"$tmp/eff-json-$action_alias.err"; then
        echo "--json config $action_alias effective failed"
        cat "$tmp/eff-json-$action_alias.err"
        exit 1
    fi
done

for action_alias in s list l; do
    if ! cmp -s "$tmp/eff-json-show.out" "$tmp/eff-json-$action_alias.out"; then
        echo "--json config $action_alias effective differed from show"
        exit 1
    fi
done

if [[ "$(wc -l < "$tmp/eff-json-show.out")" -ne 1 ]]; then
    echo "--json config show effective did not emit a single-line JSON document"
    cat "$tmp/eff-json-show.out"
    exit 1
fi

python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
pkg = d["package"]
assert pkg["name"] == "demo-pkg", pkg
assert pkg["description"] == "A demo: package", pkg
assert pkg["url"] is None, pkg
assert pkg["epoch"] is None, pkg
assert pkg["install"] == "demo.install", pkg
assert pkg["check"] == "makepkg -e", pkg
assert pkg["source"] == "archive", pkg
assert pkg["gpg_key"] == "0123456789ABCDEF", pkg
assert pkg["arch"] == ["x86_64", "any"], pkg
assert pkg["depends"] == ["bash", "git"], pkg
assert pkg["optdepends"] == ["bash: the shell"], pkg
assert pkg["makedepends"] == ["make"], pkg
assert pkg["checkdepends"] == [], pkg
assert pkg["conflicts"] == ["demo-old"], pkg
assert pkg["groups"] == [], pkg
assert pkg["provides"] == ["demo"], pkg
assert pkg["replaces"] == [], pkg
assert pkg["options"] == [], pkg
assert pkg["backup"] == ["etc/demo/config"], pkg
assert pkg["install_vars"] == ["UNITDIR=/usr/lib/systemd/system"], pkg
assert pkg["cmake_args"] == ["-DCMAKE_BUILD_TYPE=Release"], pkg
assert pkg["keep"] == ["VERSION", "share/help/"], pkg
assert pkg["exclude"] == [], pkg
assert pkg["license"] == ["GPL-3.0-or-later", "MIT"], pkg
assert pkg["post_package"] == ["echo done"], pkg
assert pkg["prepare"] == [], pkg
assert pkg["install_messages"] == {
    "post_install": ["Run demo --setup"],
    "post_upgrade": [],
    "pre_remove": ["Stopping demo"],
}, pkg["install_messages"]
assert d["copy_rules"] == [
    {"source": "bin", "destination": "usr/bin", "permissions": "755", "excludes": []},
    {"source": "lib", "destination": "usr/lib/$pkgname", "permissions": "644", "excludes": ["test", "temp"]},
], d["copy_rules"]
aur = d["aur_integration"]
assert aur["aur_repo_dir"] == "/srv/aur", aur
assert aur["auto_push"] is False, aur
assert aur["validate_before_push"] is True, aur
assert aur["commit_message"] == "Update to version {version}", aur
assert aur["ssh_key"] is None, aur
assert aur["git_user_name"] is None, aur
assert aur["git_user_email"] is None, aur
' "$tmp/eff-json-show.out" || {
    echo "--json config show effective validation failed"
    cat "$tmp/eff-json-show.out"
    exit 1
}

# Defaults when no config file exists: unset scalars are null, booleans are true/false, default copy_rules resolved
empty_repo="$tmp/empty-repo"
mkdir -p "$empty_repo"
git -C "$empty_repo" init -q -b main
git -C "$empty_repo" remote add origin "https://github.com/example/empty-demo.git"
if ! (cd "$empty_repo" && "$ROOT/bin/aurgen" --json config show effective) >|"$tmp/eff-empty.out" 2>|"$tmp/eff-empty.err"; then
    echo "--json config show effective failed on repo without config"
    cat "$tmp/eff-empty.err"
    exit 1
fi
[[ ! -e "$empty_repo/aur" ]] || { echo "--json config show effective created aur/ on empty repo"; exit 1; }
python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
pkg = d["package"]
for key in ("name", "description", "url", "epoch", "install", "check", "source", "gpg_key"):
    assert pkg[key] is None, (key, pkg[key])
assert len(d["copy_rules"]) == 8, d["copy_rules"]
assert d["copy_rules"][0] == {"source": "bin", "destination": "usr/bin", "permissions": "755", "excludes": []}
assert d["aur_integration"]["auto_push"] is True
assert d["aur_integration"]["validate_before_push"] is True
' "$tmp/eff-empty.out" || {
    echo "--json config show effective default validation failed"
    cat "$tmp/eff-empty.out"
    exit 1
}

# --json config show without effective (or with another argument) is rejected by CLI option check
for bad_args in "show" "s" "list" "l" "show extra"; do
    # shellcheck disable=SC2086
    if (cd "$repo" && "$ROOT/bin/aurgen" --json config $bad_args) >|"$tmp/bad-json.out" 2>|"$tmp/bad-json.err"; then
        echo "--json config $bad_args unexpectedly succeeded"
        exit 1
    fi
    if ! grep -Fq -- "--json is only valid with aur-status, doctor, config detect, config show effective, lint, or test" "$tmp/bad-json.err"; then
        echo "--json config $bad_args did not report expected option error"
        cat "$tmp/bad-json.err"
        exit 1
    fi
done
