#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config-mode.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
# bin/aurgen truncates the logs under its state dir; keep them in tmp.
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$XDG_STATE_HOME"
# PKGBUILD.0 generation asks gh for the repo description; never reach GitHub.
mkdir -p "$tmp/bin"
printf '#!/bin/bash\nexit 1\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

repo="$tmp/repo"
mkdir -p "$repo"

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
    mode_config generate || exit 1
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "config generate failed on a missing file"
    cat "$tmp/gen.err"
    exit 1
fi

config_file="$repo/aur/aurgen.install.yaml"
if [[ ! -f "$config_file" ]]; then
    echo "aur/aurgen.install.yaml was not created"
    exit 1
fi

before="$(cksum "$config_file")"

if (
    cd "$repo"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$repo/aur"
    export AURGEN_ERROR_LOG="$tmp/err-again.log"
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
    mode_config generate
) >"$tmp/again.out" 2>"$tmp/again.err"; then
    echo "config generate succeeded when the file already existed"
    exit 1
fi

after="$(cksum "$config_file")"
if [[ "$before" != "$after" ]]; then
    echo "existing configuration file was modified"
    exit 1
fi
if ! grep -q "Configuration file already exists" "$tmp/again.out"; then
    echo "existing-file warning was not printed"
    cat "$tmp/again.out"
    exit 1
fi

# A value load_aurgen_config rejects. config mode must still run; other modes must not.
gitrepo="$tmp/gitrepo"
mkdir -p "$gitrepo"
git -C "$gitrepo" init -q -b main
git -C "$gitrepo" remote add origin "https://github.com/example/demo.git"
mkdir -p "$gitrepo/aur"
cat > "$gitrepo/aur/aurgen.install.yaml" <<'EOF'
package:
  source: bogus
EOF

if (cd "$gitrepo" && "$ROOT/bin/aurgen" -n config validate) >"$tmp/val.out" 2>"$tmp/val.err"; then
    echo "config validate succeeded on package.source: bogus"
    exit 1
fi
if ! grep -q "package.source must be release, archive, or signed-tag" "$tmp/val.err"; then
    echo "config validate did not report the invalid source"
    cat "$tmp/val.err"
    exit 1
fi
if ! grep -q "config mode continues so you can fix it" "$tmp/val.out"; then
    echo "config mode aborted during init"
    cat "$tmp/val.out"
    cat "$tmp/val.err"
    exit 1
fi

if (cd "$gitrepo" && "$ROOT/bin/aurgen" -n --dry-run git) >"$tmp/git.out" 2>"$tmp/git.err"; then
    echo "git mode succeeded on package.source: bogus"
    exit 1
fi
if ! grep -q "package.source must be release, archive, or signed-tag" "$tmp/git.err"; then
    echo "git mode did not fail on the invalid source"
    cat "$tmp/git.err"
    exit 1
fi
if grep -q 'Running in "git" mode' "$tmp/git.out"; then
    echo "git mode continued after an invalid config"
    exit 1
fi

if ! (cd "$gitrepo" && "$ROOT/bin/aurgen" -n config reset) >"$tmp/reset.out" 2>"$tmp/reset.err"; then
    echo "config reset failed on an invalid config"
    cat "$tmp/reset.err"
    exit 1
fi
if grep -q 'source: bogus' "$gitrepo/aur/aurgen.install.yaml"; then
    echo "config reset left package.source: bogus in place"
    exit 1
fi
if ! grep -q 'AURGen Configuration File' "$gitrepo/aur/aurgen.install.yaml"; then
    echo "config reset did not restore the default configuration"
    exit 1
fi

# With no config yet, config import must import the named PKGBUILD, not aur/PKGBUILD.
imprepo="$tmp/imprepo"
mkdir -p "$imprepo/aur" "$imprepo/other"
git -C "$imprepo" init -q -b main
git -C "$imprepo" remote add origin "https://github.com/example/demo.git"
for spec in "aur:autoimported" "other:wanted"; do
    cat > "$imprepo/${spec%%:*}/PKGBUILD" <<EOF2
pkgname=${spec#*:}
pkgver=1.0.0
pkgrel=1
pkgdesc='demo'
arch=('any')
url='https://github.com/example/demo'
license=('MIT')
source=("demo-1.0.0.tar.gz")
b2sums=('SKIP')

package() {
    install -Dm644 README "\$pkgdir/usr/share/doc/demo/README"
}
EOF2
done
if ! (cd "$imprepo" && "$ROOT/bin/aurgen" -n config import other/PKGBUILD) >"$tmp/imp.out" 2>"$tmp/imp.err"; then
    echo "config import of a named PKGBUILD failed when aur/PKGBUILD exists"
    cat "$tmp/imp.out" "$tmp/imp.err"
    exit 1
fi
if ! grep -q 'wanted' "$imprepo/aur/aurgen.install.yaml" || grep -q 'autoimported' "$imprepo/aur/aurgen.install.yaml"; then
    echo "config import should import other/PKGBUILD, not aur/PKGBUILD"
    cat "$imprepo/aur/aurgen.install.yaml"
    exit 1
fi

# The README's first command: config generate on a project that has no config yet.
fresh="$tmp/fresh"
mkdir -p "$fresh"
git -C "$fresh" init -q -b main
git -C "$fresh" remote add origin "https://github.com/example/demo.git"
if ! (cd "$fresh" && "$ROOT/bin/aurgen" -n config generate) >"$tmp/fresh.out" 2>"$tmp/fresh.err"; then
    echo "config generate failed on a repository without a config"
    cat "$tmp/fresh.out" "$tmp/fresh.err"
    exit 1
fi
[[ -f "$fresh/aur/aurgen.install.yaml" ]] || { echo "config generate wrote no aur/aurgen.install.yaml"; exit 1; }

# A config that cannot be written fails generate instead of reporting success.
ro="$tmp/readonly"
mkdir -p "$ro/aur"
chmod 0555 "$ro/aur"
if (
    cd "$ro"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$ro/aur"
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
    mode_config generate
) >"$tmp/ro.out" 2>&1; then
    chmod 0755 "$ro/aur"
    echo "config generate succeeded on a read-only aur/"
    cat "$tmp/ro.out"
    exit 1
fi
chmod 0755 "$ro/aur"
if grep -q 'generated successfully' "$tmp/ro.out"; then
    echo "config generate reported success on a read-only aur/"
    exit 1
fi
