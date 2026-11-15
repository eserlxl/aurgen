#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-config-mode.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
# bin/aurgen truncates the logs under its state dir; keep them in tmp.
export XDG_STATE_HOME="$tmp/state"
export GNUPGHOME="$tmp/gnupg"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
mkdir -m 700 "$GNUPGHOME"
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CONFIG_FILE AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS
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

# Config mode must allow repair of invalid package fields; other modes must refuse them.
for key in source name; do
    if [[ "$key" == source ]]; then
        value=bogus
        diagnostic='package.source must be release, archive, or signed-tag'
        init_diagnostic="$diagnostic"
    else
        value=-bad
        diagnostic='Invalid package.name'
        init_diagnostic='Invalid package name'
    fi
    gitrepo="$tmp/gitrepo-$key"
    mkdir -p "$gitrepo"
    git -C "$gitrepo" init -q -b main
    git -C "$gitrepo" remote add origin "https://github.com/example/demo.git"
    mkdir -p "$gitrepo/aur"
    printf 'package:\n  %s: %s\n' "$key" "$value" >| "$gitrepo/aur/aurgen.install.yaml"

    # Untracked, ignored and staged files must not be reset.
    assert_reset_refused "$gitrepo"
    printf 'aur/aurgen.install.yaml\n' >| "$gitrepo/.gitignore"
    assert_reset_refused "$gitrepo"
    rm -f "$gitrepo/.gitignore"
    git -C "$gitrepo" add aur/aurgen.install.yaml || exit 1
    assert_reset_refused "$gitrepo"
    git -C "$gitrepo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
        commit -q -m 'Add config fixture' || exit 1

    if (cd "$gitrepo" && "$ROOT/bin/aurgen" -n config validate) >|"$tmp/val.out" 2>|"$tmp/val.err"; then
        echo "config validate succeeded on package.$key: $value"
        exit 1
    fi
    if ! grep -Fq "$diagnostic" "$tmp/val.err"; then
        echo "config validate did not report the invalid package.$key"
        cat "$tmp/val.err"
        exit 1
    fi
    if ! grep -q "config mode continues so you can fix it" "$tmp/val.out"; then
        echo "config mode aborted during init"
        cat "$tmp/val.out"
        cat "$tmp/val.err"
        exit 1
    fi

    if (cd "$gitrepo" && "$ROOT/bin/aurgen" -n --dry-run git) >|"$tmp/git.out" 2>|"$tmp/git.err"; then
        echo "git mode succeeded on package.$key: $value"
        exit 1
    fi
    if ! grep -Fq "$init_diagnostic" "$tmp/git.err"; then
        echo "git mode did not fail on the invalid package.$key"
        cat "$tmp/git.err"
        exit 1
    fi
    if grep -q 'Running in "git" mode' "$tmp/git.out"; then
        echo "git mode continued after an invalid config"
        exit 1
    fi

    if ! (cd "$gitrepo" && EDITOR=true "$ROOT/bin/aurgen" -n config edit) >|"$tmp/edit.out" 2>|"$tmp/edit.err"; then
        echo "config edit failed on an invalid package.$key"
        cat "$tmp/edit.err"
        exit 1
    fi

    if ! (cd "$gitrepo" && "$ROOT/bin/aurgen" -n config reset) >|"$tmp/reset.out" 2>|"$tmp/reset.err"; then
        echo "config reset failed on an invalid config"
        cat "$tmp/reset.err"
        exit 1
    fi
    if grep -q "$key: $value" "$gitrepo/aur/aurgen.install.yaml"; then
        echo "config reset left package.$key: $value in place"
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
done

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

# config validate must check package.install, package.install_vars, and package.gpg_key while keeping edit/reset usable.
valrepo="$tmp/valrepo"
mkdir -p "$valrepo/aur"
git -C "$valrepo" init -q -b main
git -C "$valrepo" config user.name test
git -C "$valrepo" config user.email test@example.com
git -C "$valrepo" config commit.gpgsign false
git -C "$valrepo" remote add origin "https://github.com/example/demo.git"

cat > "$valrepo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: demo
  install: demo.install
  install_vars: [UNITDIR=/usr/lib/systemd/system, BINDIR=/usr/bin]
  gpg_key: 0123456789ABCDEF
EOF
git -C "$valrepo" add aur/aurgen.install.yaml || exit 1
git -C "$valrepo" commit -q -m 'Valid package fields' || exit 1
if ! (cd "$valrepo" && "$ROOT/bin/aurgen" -n config validate) >|"$tmp/val-ok.out" 2>|"$tmp/val-ok.err"; then
    echo "config validate rejected valid package.install, install_vars, and gpg_key"
    cat "$tmp/val-ok.err"
    exit 1
fi

for bad_case in \
    "install: ../bad.install|Invalid package.install" \
    "install: .hidden.install|Invalid package.install" \
    "install_vars: [UNITDIR=/usr/lib;touch]|Unsafe install variable" \
    "install_vars: [1BAD=/usr/lib]|Unsafe install variable" \
    "gpg_key: not-a-hex-key|Invalid package.gpg_key" \
    "gpg_key: 12345678|Invalid package.gpg_key"; do
    field="${bad_case%%|*}"
    expect_diag="${bad_case#*|}"
    printf 'package:\n  %s\n' "$field" >| "$valrepo/aur/aurgen.install.yaml"
    git -C "$valrepo" add aur/aurgen.install.yaml || exit 1
    git -C "$valrepo" commit -q -m "Bad $field" || exit 1
    if (cd "$valrepo" && "$ROOT/bin/aurgen" -n config validate) >|"$tmp/val-bad.out" 2>|"$tmp/val-bad.err"; then
        echo "config validate accepted invalid $field"
        exit 1
    fi
    if ! grep -Fq "$expect_diag" "$tmp/val-bad.err"; then
        echo "config validate did not report '$expect_diag' for $field"
        cat "$tmp/val-bad.err"
        exit 1
    fi
    if ! (cd "$valrepo" && EDITOR=true "$ROOT/bin/aurgen" -n config edit) >|"$tmp/val-edit.out" 2>|"$tmp/val-edit.err"; then
        echo "config edit failed on invalid $field"
        cat "$tmp/val-edit.err"
        exit 1
    fi
done
if ! (cd "$valrepo" && "$ROOT/bin/aurgen" -n config reset) >|"$tmp/val-reset.out" 2>|"$tmp/val-reset.err"; then
    echo "config reset failed after invalid package field checks"
    cat "$tmp/val-reset.err"
    exit 1
fi

# config validate and config show effective must reject invalid or unknown aur_integration entries.
for bad_aur in \
    "auto_push: no|Invalid configuration value for auto_push" \
    "autopush: false|Unknown aur_integration key 'autopush'" \
    "auto-push: false|Unknown aur_integration key 'auto-push'"; do
    aur_line="${bad_aur%%|*}"
    aur_diag="${bad_aur#*|}"
    printf 'aur_integration:\n  %s\n' "$aur_line" >| "$valrepo/aur/aurgen.install.yaml"
    if (cd "$valrepo" && "$ROOT/bin/aurgen" -n config validate) >|"$tmp/aur-val.out" 2>|"$tmp/aur-val.err"; then
        echo "config validate accepted invalid aur_integration line: $aur_line"
        exit 1
    fi
    if ! grep -Fq "$aur_diag" "$tmp/aur-val.err"; then
        echo "config validate did not report '$aur_diag' for $aur_line"
        cat "$tmp/aur-val.err"
        exit 1
    fi
    if (cd "$valrepo" && "$ROOT/bin/aurgen" -n config show effective) >|"$tmp/aur-eff.out" 2>|"$tmp/aur-eff.err"; then
        echo "config show effective accepted invalid aur_integration line: $aur_line"
        exit 1
    fi
    if ! grep -Fq "$aur_diag" "$tmp/aur-eff.err"; then
        echo "config show effective did not report '$aur_diag' for $aur_line"
        cat "$tmp/aur-eff.err"
        exit 1
    fi
done

# config edit passes flags in EDITOR for both existing and newly generated configs.
ed_stub_dir="$tmp/editor-bin"
mkdir -p "$ed_stub_dir"
ed_log="$tmp/editor.argv"
cat > "$ed_stub_dir/myeditor" << 'EOF'
#!/bin/bash
printf '%s\n' "$@" >| "$EDITOR_ARGV_LOG"
EOF
chmod +x "$ed_stub_dir/myeditor"
export EDITOR_ARGV_LOG="$ed_log"

ed_repo="$tmp/editor-repo"
mkdir -p "$ed_repo/aur"
git init -q "$ed_repo"
git -C "$ed_repo" remote add origin https://github.com/example/demo.git
: >| "$ed_log"
if ! (cd "$ed_repo" && PATH="$ed_stub_dir:$PATH" EDITOR="myeditor --wait -n" "$ROOT/bin/aurgen" -n config edit) >|"$tmp/ed-new.out" 2>|"$tmp/ed-new.err"; then
    echo "config edit with EDITOR flags failed on missing config"
    cat "$tmp/ed-new.err"
    exit 1
fi
[[ -f "$ed_repo/aur/aurgen.install.yaml" ]] || { echo "config edit did not generate missing config"; exit 1; }
expected_new=$'--wait\n-n\n'"$ed_repo/aur/aurgen.install.yaml"
if [[ "$(cat "$ed_log")" != "$expected_new" ]]; then
    echo "config edit did not preserve EDITOR flags on newly generated config"
    cat "$ed_log"
    exit 1
fi

: >| "$ed_log"
if ! (cd "$ed_repo" && PATH="$ed_stub_dir:$PATH" EDITOR="myeditor --reuse-window" "$ROOT/bin/aurgen" -n config edit) >|"$tmp/ed-cur.out" 2>|"$tmp/ed-cur.err"; then
    echo "config edit with EDITOR flags failed on existing config"
    cat "$tmp/ed-cur.err"
    exit 1
fi
expected_cur=$'--reuse-window\n'"$ed_repo/aur/aurgen.install.yaml"
if [[ "$(cat "$ed_log")" != "$expected_cur" ]]; then
    echo "config edit did not preserve EDITOR flags on existing config"
    cat "$ed_log"
    exit 1
fi

# Empty or whitespace-only EDITOR without fallback editors reports No suitable editor found.
empty_path="$tmp/empty-bin"
mkdir -p "$empty_path"
if (
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$ed_repo/aur"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export DEBUG_LEVEL=0
    export color_enabled=0
    export EDITOR="   "
    export PATH="$empty_path"
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config edit
) >|"$tmp/noed.out" 2>|"$tmp/noed.err"; then
    echo "config edit succeeded with no editor available"
    exit 1
fi
grep -Fq 'Error: No suitable editor found.' "$tmp/noed.err" || {
    echo "config edit missing-editor diagnostic mismatch"
    cat "$tmp/noed.err"
    exit 1
}

# --config overrides default aur/aurgen.install.yaml in config generate, show, validate
cfg_opt_repo="$tmp/cfg-opt-repo"
mkdir -p "$cfg_opt_repo/bin"
printf '#!/bin/bash\necho ok\n' > "$cfg_opt_repo/bin/demo"
chmod +x "$cfg_opt_repo/bin/demo"
(
    cd "$cfg_opt_repo" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name Tester
    git remote add origin https://github.com/example/cfg-opt-repo.git
    git add bin/demo
    git commit -q -m "init"
)

if ! (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/override.yaml config generate) >|"$tmp/cfg-gen.out" 2>|"$tmp/cfg-gen.err"; then
    echo "config generate with --config failed"
    cat "$tmp/cfg-gen.err"
    exit 1
fi
[[ -f "$cfg_opt_repo/custom/override.yaml" ]] || {
    echo "config generate with --config did not write target file"
    exit 1
}
[[ ! -e "$cfg_opt_repo/aur/aurgen.install.yaml" ]] || {
    echo "config generate with --config unexpectedly created aur/aurgen.install.yaml"
    exit 1
}

cat > "$cfg_opt_repo/custom/override.yaml" <<'EOF'
package:
  name: custom-mode-pkg
bin:
  source: bin
  destination: usr/bin
  permissions: executable
EOF
if ! (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/override.yaml config show) >|"$tmp/cfg-show.out" 2>|"$tmp/cfg-show.err"; then
    echo "config show with --config failed"
    cat "$tmp/cfg-show.err"
    exit 1
fi
grep -Fq "name: custom-mode-pkg" "$tmp/cfg-show.out" || {
    echo "config show with --config did not display custom file"
    cat "$tmp/cfg-show.out"
    exit 1
}

if ! (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/override.yaml config show effective) >|"$tmp/cfg-eff.out" 2>|"$tmp/cfg-eff.err"; then
    echo "config show effective with --config failed"
    cat "$tmp/cfg-eff.err"
    exit 1
fi
grep -Fq "name: custom-mode-pkg" "$tmp/cfg-eff.out" || {
    echo "config show effective with --config did not use custom file"
    cat "$tmp/cfg-eff.out"
    exit 1
}

if ! (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/override.yaml config validate) >|"$tmp/cfg-val.out" 2>|"$tmp/cfg-val.err"; then
    echo "config validate with --config failed"
    cat "$tmp/cfg-val.err"
    exit 1
fi

for missing_action in show "show effective" validate; do
    # shellcheck disable=SC2086
    if (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/missing.yaml config $missing_action) >|"$tmp/cfg-miss.out" 2>|"$tmp/cfg-miss.err"; then
        echo "config $missing_action with missing --config unexpectedly succeeded"
        exit 1
    fi
done

unreadable_cfg="$cfg_opt_repo/custom/unreadable.yaml"
printf 'package:\n  name: custom-unreadable\n' > "$unreadable_cfg"
chmod 000 "$unreadable_cfg"
if [[ ! -r "$unreadable_cfg" ]]; then
    for unreadable_action in show "show effective" validate detect; do
        # shellcheck disable=SC2086
        if (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/unreadable.yaml config $unreadable_action) >|"$tmp/cfg-unreadable.out" 2>|"$tmp/cfg-unreadable.err"; then
            chmod 644 "$unreadable_cfg"
            echo "config $unreadable_action with unreadable --config unexpectedly succeeded"
            exit 1
        fi
        if ! grep -Fq "not readable" "$tmp/cfg-unreadable.err"; then
            chmod 644 "$unreadable_cfg"
            echo "config $unreadable_action with unreadable --config did not report unreadable file"
            cat "$tmp/cfg-unreadable.err"
            exit 1
        fi
        if [[ "$unreadable_action" == "show" ]] && grep -Fq -- "---" "$tmp/cfg-unreadable.out"; then
            chmod 644 "$unreadable_cfg"
            echo "config show with unreadable --config wrote separator to stdout"
            cat "$tmp/cfg-unreadable.out"
            exit 1
        fi
    done
    if (
        set -euo pipefail
        export LIB_INSTALL_DIR="$ROOT/lib"
        export AURGEN_CONFIG_FILE="$unreadable_cfg"
        export AURGEN_ERROR_LOG="$tmp/aur-int-unreadable.err.log"
        export AURGEN_MODE=config
        export DEBUG_LEVEL=0
        export color_enabled=0
        # shellcheck source=../lib/colors.sh
        source "$ROOT/lib/colors.sh"
        init_colors
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/aur-integration.sh
        source "$ROOT/lib/aur-integration.sh"
        load_aur_integration_config
    ) >|"$tmp/aur-int-unreadable.out" 2>|"$tmp/aur-int-unreadable.err"; then
        chmod 644 "$unreadable_cfg"
        echo "load_aur_integration_config unexpectedly succeeded on unreadable config"
        exit 1
    fi
    if ! grep -Fq "not readable" "$tmp/aur-int-unreadable.err"; then
        chmod 644 "$unreadable_cfg"
        echo "load_aur_integration_config did not report unreadable config"
        cat "$tmp/aur-int-unreadable.err"
        exit 1
    fi
fi
chmod 644 "$unreadable_cfg"

cat > "$cfg_opt_repo/custom/meta-valid.yaml" <<'EOF'
package:
  url: https://example.org/custom
  epoch: 3
  replaces: [old-pkg]
  options: ["!lto"]
bin:
  source: bin
  destination: usr/bin
  permissions: executable
EOF
if ! (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/meta-valid.yaml config validate) >|"$tmp/meta-val.out" 2>|"$tmp/meta-val.err"; then
    echo "config validate failed for valid url/epoch/replaces/options"
    cat "$tmp/meta-val.err"
    exit 1
fi

cat > "$cfg_opt_repo/custom/meta-bad.yaml" <<'EOF'
package:
  epoch: 0
  options: ["!BAD"]
bin:
  source: bin
  destination: usr/bin
  permissions: executable
EOF
if (cd "$cfg_opt_repo" && "$ROOT/bin/aurgen" -n -c custom/meta-bad.yaml config validate) >|"$tmp/meta-bad.out" 2>|"$tmp/meta-bad.err"; then
    echo "config validate accepted invalid epoch/options"
    exit 1
fi

for subcmd in show validate; do
    missing_rc=0
    (
        set -euo pipefail
        cd "$repo"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export AUR_DIR="$repo/aur"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=config
        export DEBUG_LEVEL=0
        export color_enabled=0
        export AURGEN_CONFIG_FILE="$tmp/does-not-exist.yaml"
        # shellcheck source=../lib/colors.sh
        source "$ROOT/lib/colors.sh"
        init_colors
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/config.sh
        source "$ROOT/lib/config.sh"
        # shellcheck source=../lib/modes/config.sh
        source "$ROOT/lib/modes/config.sh"
        mode_config "$subcmd"
    ) >|"$tmp/missing-$subcmd.out" 2>|"$tmp/missing-$subcmd.err" || missing_rc=$?
    if [[ "$missing_rc" -ne 1 ]]; then
        echo "mode_config $subcmd on missing AURGEN_CONFIG_FILE exited $missing_rc (expected 1)"
        cat "$tmp/missing-$subcmd.err"
        exit 1
    fi
    if ! grep -F -q "[ERROR] [config] Configuration file not found: $tmp/does-not-exist.yaml" "$tmp/missing-$subcmd.err"; then
        echo "mode_config $subcmd missing [ERROR] message"
        cat "$tmp/missing-$subcmd.err"
        exit 1
    fi
    if grep -F -q "command not found" "$tmp/missing-$subcmd.err"; then
        echo "mode_config $subcmd triggered undefined command error"
        cat "$tmp/missing-$subcmd.err"
        exit 1
    fi
done

# Non-mutating config subcommands and external -c targets must not create aur/ or aur/.gitignore.
clean_cfg_repo="$tmp/clean-cfg-side-effects"
mkdir -p "$clean_cfg_repo/bin" "$clean_cfg_repo/custom"
git -C "$clean_cfg_repo" init -q -b main
git -C "$clean_cfg_repo" config user.name test
git -C "$clean_cfg_repo" config user.email t@example.com
git -C "$clean_cfg_repo" remote add origin "https://github.com/example/clean-cfg.git"
printf '#!/bin/sh\necho ok\n' >| "$clean_cfg_repo/bin/tool"
cat >| "$clean_cfg_repo/custom/existing.yaml" <<'EOF'
package:
  name: clean-cfg
executables:
  source: bin
  destination: usr/bin
  permissions: executable
EOF
git -C "$clean_cfg_repo" add bin/tool custom/existing.yaml
git -C "$clean_cfg_repo" commit -q -m init

# Run exact non-mutating and out-of-aur -c cases directly
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n config help) >|"$tmp/clean-help.out" 2>|"$tmp/clean-help.err" || { echo "config help failed"; exit 1; }
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n config show) >|"$tmp/clean-show.out" 2>|"$tmp/clean-show.err" || { echo "config show failed"; exit 1; }
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n config show effective) >|"$tmp/clean-eff.out" 2>|"$tmp/clean-eff.err" || { echo "config show effective failed"; exit 1; }
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n config validate) >|"$tmp/clean-val.out" 2>|"$tmp/clean-val.err" || { echo "config validate failed"; exit 1; }
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n -c custom/existing.yaml config show) >|"$tmp/clean-cshow.out" 2>|"$tmp/clean-cshow.err" || { echo "-c config show failed"; exit 1; }
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n -c custom/existing.yaml config validate) >|"$tmp/clean-cval.out" 2>|"$tmp/clean-cval.err" || { echo "-c config validate failed"; exit 1; }
if (cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n config) >|"$tmp/clean-bare.out" 2>|"$tmp/clean-bare.err"; then
    echo "bare config unexpectedly succeeded"
    exit 1
fi
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n -c custom/out.yaml config init) >|"$tmp/clean-cinit.out" 2>|"$tmp/clean-cinit.err" || { echo "-c config init failed"; cat "$tmp/clean-cinit.err"; exit 1; }
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n -c custom/gen.yaml config generate) >|"$tmp/clean-cgen.out" 2>|"$tmp/clean-cgen.err" || { echo "-c config generate failed"; cat "$tmp/clean-cgen.err"; exit 1; }
[[ -f "$clean_cfg_repo/custom/out.yaml" && -f "$clean_cfg_repo/custom/gen.yaml" ]] || { echo "-c config init/generate did not write external target"; exit 1; }
if [[ -e "$clean_cfg_repo/aur" || -e "$clean_cfg_repo/aur/.gitignore" ]]; then
    echo "non-mutating or external -c config invocation created stray aur/ or aur/.gitignore"
    ls -la "$clean_cfg_repo/aur" || true
    exit 1
fi

# Default target config init still creates aur/.gitignore alongside aur/aurgen.install.yaml.
(cd "$clean_cfg_repo" && "$ROOT/bin/aurgen" -n config init) >|"$tmp/def-init.out" 2>|"$tmp/def-init.err" || { echo "default config init failed"; cat "$tmp/def-init.err"; exit 1; }
[[ -f "$clean_cfg_repo/aur/aurgen.install.yaml" && -f "$clean_cfg_repo/aur/.gitignore" ]] || { echo "default config init did not initialize aur/.gitignore"; exit 1; }

# config edit must support pre-edit backup, editor abort rollback, and invalid edit recovery.
edit_rec_dir="$tmp/edit-recovery"
mkdir -p "$edit_rec_dir/bin" "$edit_rec_dir/repo/bin" "$edit_rec_dir/repo/custom" "$edit_rec_dir/state"
printf '#!/bin/bash\necho ok\n' > "$edit_rec_dir/repo/bin/tool"
chmod +x "$edit_rec_dir/repo/bin/tool"
(
    cd "$edit_rec_dir/repo" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name Tester
    git config commit.gpgsign false
    git remote add origin https://github.com/example/edit-rec.git
    git add bin/tool
    git commit -q -m "init"
) || exit 1
if ! (cd "$edit_rec_dir/repo" && "$ROOT/bin/aurgen" -n -c custom/app.yaml config generate) >|"$tmp/erec-gen.out" 2>|"$tmp/erec-gen.err"; then
    echo "recovery setup config generate failed"
    cat "$tmp/erec-gen.err"
    exit 1
fi
orig_cfg="$(cat "$edit_rec_dir/repo/custom/app.yaml")"

cat > "$edit_rec_dir/bin/abort-editor" << 'EOF'
#!/bin/bash
printf 'broken: [\n' >| "$1"
exit 1
EOF
cat > "$edit_rec_dir/bin/bad-editor" << 'EOF'
#!/bin/bash
printf 'package:\n  name: demo\naur_integration:\n  auto_push: maybe\n' >| "$1"
exit 0
EOF
cat > "$edit_rec_dir/bin/good-editor" << 'EOF'
#!/bin/bash
cat >| "$1" << 'YAML'
package:
  name: custom-ok
bin:
  source: bin
  destination: usr/bin
  permissions: executable
aur_integration:
  auto_push: false
YAML
exit 0
EOF
cat > "$edit_rec_dir/bin/delete-editor" << 'EOF'
#!/bin/bash
rm -f -- "$1"
exit 0
EOF
chmod +x "$edit_rec_dir/bin/abort-editor" "$edit_rec_dir/bin/bad-editor" "$edit_rec_dir/bin/good-editor" "$edit_rec_dir/bin/delete-editor"

# Case 1: editor abort restores pre-existing custom config and leaves no stray files.
if (cd "$edit_rec_dir/repo" && XDG_STATE_HOME="$edit_rec_dir/state" PATH="$edit_rec_dir/bin:$PATH" EDITOR=abort-editor "$ROOT/bin/aurgen" -n -c custom/app.yaml config edit </dev/null) >|"$tmp/erec-abort.out" 2>|"$tmp/erec-abort.err"; then
    echo "config edit succeeded when editor exited non-zero"
    exit 1
fi
if [[ "$(cat "$edit_rec_dir/repo/custom/app.yaml")" != "$orig_cfg" ]]; then
    echo "config edit did not restore pre-edit config after editor abort"
    exit 1
fi

# Case 2: editor abort on missing config removes abortively generated default file.
if (cd "$edit_rec_dir/repo" && XDG_STATE_HOME="$edit_rec_dir/state" PATH="$edit_rec_dir/bin:$PATH" EDITOR=abort-editor "$ROOT/bin/aurgen" -n -c custom/new-abort.yaml config edit </dev/null) >|"$tmp/erec-newabort.out" 2>|"$tmp/erec-newabort.err"; then
    echo "config edit succeeded on missing config abort"
    exit 1
fi
if [[ -e "$edit_rec_dir/repo/custom/new-abort.yaml" ]]; then
    echo "config edit left behind newly generated config after editor abort"
    exit 1
fi

# Case 3: modified invalid config fails validation and writes recovery backup in XDG_STATE_HOME/aurgen.
if (cd "$edit_rec_dir/repo" && XDG_STATE_HOME="$edit_rec_dir/state" PATH="$edit_rec_dir/bin:$PATH" EDITOR=bad-editor "$ROOT/bin/aurgen" -n -c custom/app.yaml config edit </dev/null) >|"$tmp/erec-bad.out" 2>|"$tmp/erec-bad.err"; then
    echo "config edit accepted invalid aur_integration.auto_push edit"
    exit 1
fi
if ! grep -Fq 'Saved configuration recovery backup to:' "$tmp/erec-bad.err"; then
    echo "config edit did not report recovery backup path"
    cat "$tmp/erec-bad.err"
    exit 1
fi
rec_count=$(find "$edit_rec_dir/state/aurgen" -maxdepth 1 -type f -name 'app.yaml.recovery.*' | wc -l)
if (( rec_count < 1 )); then
    echo "config edit did not create recovery backup file in XDG_STATE_HOME/aurgen"
    exit 1
fi
if ! grep -Fq 'auto_push: maybe' "$edit_rec_dir/repo/custom/app.yaml"; then
    echo "non-interactive config edit did not keep edited file on default N"
    exit 1
fi

# Case 4: interactive 'y' on validation failure restores pre-edit valid config and still fails.
printf '%s\n' "$orig_cfg" >| "$edit_rec_dir/repo/custom/app.yaml"
if (
    cd "$edit_rec_dir/repo" || exit 1
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$edit_rec_dir/repo/aur"
    export AURGEN_ERROR_LOG="$tmp/erec-tty-err.log"
    export AURGEN_MODE=config
    export DEBUG_LEVEL=0
    export color_enabled=0
    export XDG_STATE_HOME="$edit_rec_dir/state-tty"
    export PATH="$edit_rec_dir/bin:$PATH"
    export EDITOR=bad-editor
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    have_tty() { return 0; }
    _config_edit_file "$edit_rec_dir/repo/custom/app.yaml" <<< "y"
) >|"$tmp/erec-tty.out" 2>|"$tmp/erec-tty.err"; then
    echo "interactive config edit unexpectedly succeeded on invalid edit"
    exit 1
fi
if ! grep -Fq 'Restored pre-edit configuration to' "$tmp/erec-tty.err"; then
    echo "interactive config edit did not report restore on y"
    cat "$tmp/erec-tty.err"
    exit 1
fi
if [[ "$(cat "$edit_rec_dir/repo/custom/app.yaml")" != "$orig_cfg" ]]; then
    echo "interactive config edit did not restore pre-edit config on y"
    exit 1
fi
tty_rec_count=$(find "$edit_rec_dir/state-tty/aurgen" -maxdepth 1 -type f -name 'app.yaml.recovery.*' | wc -l)
if (( tty_rec_count < 1 )); then
    echo "interactive config edit did not create recovery backup file"
    exit 1
fi

# Case 5: valid edit succeeds cleanly via -c custom.yaml.
if ! (cd "$edit_rec_dir/repo" && XDG_STATE_HOME="$edit_rec_dir/state" PATH="$edit_rec_dir/bin:$PATH" EDITOR=good-editor "$ROOT/bin/aurgen" -n -c custom/app.yaml config edit </dev/null) >|"$tmp/erec-good.out" 2>|"$tmp/erec-good.err"; then
    echo "config edit rejected valid custom config edit"
    cat "$tmp/erec-good.err"
    exit 1
fi
if ! grep -Fq 'name: custom-ok' "$edit_rec_dir/repo/custom/app.yaml"; then
    echo "config edit did not preserve valid edit changes"
    exit 1
fi

# Case 6: deleting the config file inside the editor fails validation and supports restore recovery.
printf '%s\n' "$orig_cfg" >| "$edit_rec_dir/repo/custom/app.yaml"
if (cd "$edit_rec_dir/repo" && XDG_STATE_HOME="$edit_rec_dir/state-del" PATH="$edit_rec_dir/bin:$PATH" EDITOR=delete-editor "$ROOT/bin/aurgen" -n -c custom/app.yaml config edit </dev/null) >|"$tmp/erec-del.out" 2>|"$tmp/erec-del.err"; then
    echo "config edit accepted deleted configuration file"
    exit 1
fi
if ! grep -Fq 'missing or unreadable' "$tmp/erec-del.err"; then
    echo "config edit did not report missing configuration after editor deletion"
    cat "$tmp/erec-del.err"
    exit 1
fi
del_rec_count=$(find "$edit_rec_dir/state-del/aurgen" -maxdepth 1 -type f -name 'app.yaml.recovery.*' | wc -l)
if (( del_rec_count < 1 )); then
    echo "config edit did not save recovery backup after editor deletion"
    exit 1
fi
printf '%s\n' "$orig_cfg" >| "$edit_rec_dir/repo/custom/app.yaml"
if (
    cd "$edit_rec_dir/repo" || exit 1
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$edit_rec_dir/repo/aur"
    export AURGEN_ERROR_LOG="$tmp/erec-del-tty-err.log"
    export AURGEN_MODE=config
    export DEBUG_LEVEL=0
    export color_enabled=0
    export XDG_STATE_HOME="$edit_rec_dir/state-del-tty"
    export PATH="$edit_rec_dir/bin:$PATH"
    export EDITOR=delete-editor
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    have_tty() { return 0; }
    _config_edit_file "$edit_rec_dir/repo/custom/app.yaml" <<< "y"
) >|"$tmp/erec-del-tty.out" 2>|"$tmp/erec-del-tty.err"; then
    echo "interactive delete recovery unexpectedly succeeded"
    exit 1
fi
if [[ "$(cat "$edit_rec_dir/repo/custom/app.yaml")" != "$orig_cfg" ]]; then
    echo "interactive delete recovery did not restore pre-edit configuration"
    exit 1
fi

# Case 7: failed backup restore preserves the temporary backup file and reports its path.
mkdir -p "$tmp/backup-fail-tmp"
if (
    cd "$edit_rec_dir/repo" || exit 1
    export TMPDIR="$tmp/backup-fail-tmp"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$edit_rec_dir/repo/aur"
    export AURGEN_ERROR_LOG="$tmp/erec-cpfail-err.log"
    export AURGEN_MODE=config
    export DEBUG_LEVEL=0
    export color_enabled=0
    export XDG_STATE_HOME="$edit_rec_dir/state-cpfail"
    export PATH="$edit_rec_dir/bin:$PATH"
    export EDITOR=abort-editor
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    init_colors
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    cp() {
        if [[ "${1:-}" == "-f" ]]; then
            return 1
        fi
        command cp "$@"
    }
    _config_edit_file "$edit_rec_dir/repo/custom/app.yaml" </dev/null
) >|"$tmp/erec-cpfail.out" 2>|"$tmp/erec-cpfail.err"; then
    echo "config edit unexpectedly succeeded on editor abort with failed restore"
    exit 1
fi
if ! grep -Fq 'backup kept at ' "$tmp/erec-cpfail.err"; then
    echo "config edit did not report preserved backup path when restore failed"
    cat "$tmp/erec-cpfail.err"
    exit 1
fi
kept_count=$(find "$tmp/backup-fail-tmp" -maxdepth 1 -type f -name 'aurgen-config-edit.*' | wc -l)
if (( kept_count < 1 )); then
    echo "failed backup restore removed the temporary backup file"
    exit 1
fi

echo "PASS test-config-mode.sh"
