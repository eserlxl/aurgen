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
export HOME="$tmp/home"
mkdir -p "$HOME"
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

# AUR integration booleans are checked by config validate before deployment.
mkdir -p "$tmp/aur-validation"
for auto_push in tru true false; do
    cp "$config_file" "$tmp/aur-validation/aurgen.install.yaml" || exit 1
    printf '\naur_integration:\n  auto_push: %s\n' "$auto_push" >> "$tmp/aur-validation/aurgen.install.yaml"
    status=0
    (
        cd "$repo" || exit 1
        export LIB_INSTALL_DIR="$ROOT/lib"
        export AUR_DIR="$tmp/aur-validation"
        export AURGEN_ERROR_LOG="$tmp/aur-validation-error.log"
        export AURGEN_MODE=test
        export DEBUG_LEVEL=0
        export color_enabled=0
        # shellcheck source=../lib/colors.sh
        source "$ROOT/lib/colors.sh"
        init_colors
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/modes/config.sh
        source "$ROOT/lib/modes/config.sh"
        mode_config validate
    ) >|"$tmp/aur-validation.out" 2>|"$tmp/aur-validation.err" || status=$?
    if [[ "$auto_push" == tru ]]; then
        if [[ "$status" == 0 ]] || ! grep -q 'Invalid configuration value for auto_push' "$tmp/aur-validation.err"; then
            echo "config validate must reject auto_push: tru and name the key"
            cat "$tmp/aur-validation.err"
            exit 1
        fi
    elif [[ "$status" != 0 ]] || ! grep -q 'Configuration is valid' "$tmp/aur-validation.err"; then
        echo "config validate rejected auto_push: $auto_push"
        cat "$tmp/aur-validation.err"
        exit 1
    fi
done

reset_config() (
    cd "$1" || exit 1
    export PROJECT_ROOT="$1"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$1/aur"
    export AURGEN_ERROR_LOG="$tmp/reset-error.log"
    export AURGEN_MODE=test
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config reset
)

assert_reset_refused() {
    local target="$1" status=0 before
    before=$(cksum "$target/aur/aurgen.install.yaml")
    reset_config "$target" >|"$tmp/refused.out" 2>|"$tmp/refused.err" || status=$?
    if [[ "$status" != 1 ]] || [[ "$before" != "$(cksum "$target/aur/aurgen.install.yaml")" ]]; then
        echo "config reset must exit 1 and preserve the existing file: $target"
        exit 1
    fi
    if ! grep -q 'Commit the file or delete it by hand' "$tmp/refused.err"; then
        echo "config reset did not explain how to preserve the file"
        cat "$tmp/refused.err"
        exit 1
    fi
    [[ ! -e "$target/aur/aurgen.install.yaml.bak" ]] || { echo "refused reset created a backup"; exit 1; }
}

# Existing files outside a Git work tree must also be preserved.
assert_reset_refused "$repo"

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

# Untracked, ignored and staged files must not be reset.
assert_reset_refused "$gitrepo"
printf 'aur/aurgen.install.yaml\n' >| "$gitrepo/.gitignore"
assert_reset_refused "$gitrepo"
rm -f "$gitrepo/.gitignore"
git -C "$gitrepo" add aur/aurgen.install.yaml || exit 1
assert_reset_refused "$gitrepo"
git -C "$gitrepo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
    commit -q -m 'Add config fixture' || exit 1

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
[[ ! -e "$gitrepo/aur/aurgen.install.yaml.bak" ]] || { echo "config reset created a backup"; exit 1; }
if ! grep -q 'git checkout --' "$tmp/reset.err"; then
    echo "config reset did not explain how to restore the committed version"
    exit 1
fi

# Reset changed the committed config; a second reset must preserve those changes.
assert_reset_refused "$gitrepo"
git -C "$gitrepo" add aur/aurgen.install.yaml || exit 1
assert_reset_refused "$gitrepo"

# A missing config still generates defaults, even outside a Git work tree.
missing="$tmp/missing"
mkdir -p "$missing"
if ! reset_config "$missing" >|"$tmp/missing.out" 2>|"$tmp/missing.err"; then
    echo "config reset failed on a missing config"
    cat "$tmp/missing.err"
    exit 1
fi
if ! grep -q 'AURGen Configuration File' "$missing/aur/aurgen.install.yaml" ||
    [[ -e "$missing/aur/aurgen.install.yaml.bak" ]]; then
    echo "config reset did not generate defaults without a backup"
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
    make install DESTDIR="\$pkgdir" PREFIX=/usr
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

# A config that cannot be written fails generate, and edit (which generates a
# missing config first), instead of reporting success.
ro="$tmp/readonly"
mkdir -p "$ro/aur"
chmod 0555 "$ro/aur"
for action in generate edit; do
    if (
        cd "$ro"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export AUR_DIR="$ro/aur"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export DEBUG_LEVEL=0
        export color_enabled=0
        export EDITOR=true
        # shellcheck source=../lib/colors.sh
        source "$ROOT/lib/colors.sh"
        init_colors
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/config.sh
        source "$ROOT/lib/config.sh"
        # shellcheck source=../lib/modes/config.sh
        source "$ROOT/lib/modes/config.sh"
        mode_config "$action"
    ) >"$tmp/ro.out" 2>&1; then
        chmod 0755 "$ro/aur"
        echo "config $action succeeded on a read-only aur/"
        cat "$tmp/ro.out"
        exit 1
    fi
    if grep -q 'generated successfully' "$tmp/ro.out"; then
        chmod 0755 "$ro/aur"
        echo "config $action reported success on a read-only aur/"
        exit 1
    fi
done
chmod 0755 "$ro/aur"
