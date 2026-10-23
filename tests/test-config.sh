#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-config.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$stub" "$repo"
cat > "$stub/nano" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" > "${AURGEN_EDITOR_LOG:?}"
EOF
chmod +x "$stub/nano"

if ! (
    cd "$repo"
    unset EDITOR
    export PATH="$stub:$PATH"
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
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    mode_config generate
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "config generate failed"
    cat "$tmp/gen.err"
    exit 1
fi

if [[ ! -f "$repo/aur/aurgen.install.yaml" ]]; then
    echo "aur/aurgen.install.yaml was not created"
    exit 1
fi
if [[ -e "$repo/generate" || -e "$repo/aur/generate" ]]; then
    echo "config generate wrote a file named generate"
    exit 1
fi

if ! (
    cd "$repo"
    unset EDITOR
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$repo/aur"
    export AURGEN_EDITOR_LOG="$tmp/editor.log"
    export AURGEN_ERROR_LOG="$tmp/err-edit.log"
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
    mode_config edit
) >"$tmp/edit.out" 2>"$tmp/edit.err"; then
    echo "config edit failed with EDITOR unset"
    cat "$tmp/edit.err"
    exit 1
fi
if [[ ! -f "$tmp/editor.log" ]]; then
    echo "config edit did not open an editor with EDITOR unset"
    cat "$tmp/edit.err"
    exit 1
fi
if [[ "$(cat "$tmp/editor.log")" != "$repo/aur/aurgen.install.yaml" ]]; then
    echo "config edit opened the wrong file: $(cat "$tmp/editor.log")"
    exit 1
fi

mkdir -p "$tmp/noeol"
printf 'package:\n  name: demo-noeol' > "$tmp/noeol/aurgen.install.yaml"
if ! (
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$tmp/noeol"
    export AURGEN_ERROR_LOG="$tmp/err-noeol.log"
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
    load_aurgen_config || exit 1
    # shellcheck disable=SC2153 # PKG_NAME is set by load_aurgen_config
    [[ "$PKG_NAME" == "demo-noeol" ]] || exit 1
) >"$tmp/noeol.out" 2>"$tmp/noeol.err"; then
    echo "unterminated last config line was dropped"
    cat "$tmp/noeol.err"
    exit 1
fi

# Invalid copy rules must fail without emitting defaults or diagnostics on stdout.
mkdir -p "$tmp/rules/aur"
cat > "$tmp/rules/aur/aurgen.install.yaml" <<'EOF2'
executables:
  source: bin
  destination: usr/bin
  permissions: rwx
  exclude: []
EOF2
if (
    export AUR_DIR="$tmp/rules/aur"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export DEBUG_LEVEL=1
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    get_copy_directories
) >"$tmp/rules.out" 2>"$tmp/rules.err"; then
    echo "get_copy_directories accepted invalid permissions"
    exit 1
fi
if [[ -s "$tmp/rules.out" ]]; then
    echo "get_copy_directories emitted output for an invalid rule"
    cat "$tmp/rules.out"
    exit 1
fi
if ! grep -q "Invalid permissions 'rwx' for bin" "$tmp/rules.err"; then
    echo "an invalid copy rule should report the rule on stderr"
    cat "$tmp/rules.err"
    exit 1
fi

# Four-digit octal permissions are as valid as three-digit ones.
sed -i 's/permissions: rwx/permissions: 0755/' "$tmp/rules/aur/aurgen.install.yaml"
if ! (
    export AUR_DIR="$tmp/rules/aur"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    get_copy_directories
) >"$tmp/rules4.out" 2>"$tmp/rules4.err"; then
    echo "get_copy_directories failed for 0755"
    cat "$tmp/rules4.err"
    exit 1
fi
if ! grep -qE '^bin:usr/bin:0755:?$' "$tmp/rules4.out"; then
    echo "a 0755 copy rule should survive validation unchanged"
    cat "$tmp/rules4.out" "$tmp/rules4.err"
    exit 1
fi

# A source outside the eight fixed names is a copy rule. The fixed eight stay
# in their original order; extra sources follow in config order. data is not
# the last section (saved when the next header starts); scripts/hooks is last
# (saved when the file ends).
mkdir -p "$tmp/extra/aur"
cat > "$tmp/extra/aur/aurgen.install.yaml" <<'EOF'
payload:
  source: data
  destination: usr/share/demo
  permissions: read-only
  exclude: []
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
libraries:
  source: lib
  destination: usr/lib/demo
  permissions: read-only
  exclude: []
config_files:
  source: etc
  destination: etc/demo
  permissions: read-only
  exclude: []
shared_data:
  source: share
  destination: usr/share/demo-share
  permissions: read-only
  exclude: []
headers:
  source: include
  destination: usr/include/demo
  permissions: read-only
  exclude: []
local_data:
  source: local
  destination: usr/local/demo
  permissions: read-only
  exclude: []
variable_data:
  source: var
  destination: var/demo
  permissions: read-only
  exclude: []
optional_data:
  source: opt
  destination: opt/demo
  permissions: read-only
  exclude: []
hooks:
  source: scripts/hooks
  destination: usr/lib/demo
  permissions: 755
  exclude: []
EOF
if ! (
    export AUR_DIR="$tmp/extra/aur"
    export AURGEN_ERROR_LOG="$tmp/err-extra.log"
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    get_copy_directories
) >"$tmp/extra.out" 2>"$tmp/extra.err"; then
    echo "get_copy_directories failed for a data source"
    cat "$tmp/extra.err"
    exit 1
fi
cat > "$tmp/extra.expected" <<'EOF'
bin:usr/bin:755
lib:usr/lib/demo:644
etc:etc/demo:644
share:usr/share/demo-share:644
include:usr/include/demo:644
local:usr/local/demo:644
var:var/demo:644
opt:opt/demo:644
data:usr/share/demo:644
scripts/hooks:usr/lib/demo:755
EOF
if ! cmp -s "$tmp/extra.out" "$tmp/extra.expected"; then
    echo "extra copy source was dropped or a fixed source changed"
    echo "--- got ---"
    cat "$tmp/extra.out"
    echo "--- expected ---"
    cat "$tmp/extra.expected"
    cat "$tmp/extra.err"
    exit 1
fi

# Only an extra source: the eight defaults must not come back. After the file
# is removed, a second read must keep the in-memory rule. Empty fixed rules
# are not "configuration not loaded" while an extra rule is set.
mkdir -p "$tmp/dataonly/aur"
cat > "$tmp/dataonly/aur/aurgen.install.yaml" <<'EOF'
payload:
  source: data
  destination: usr/share/demo
  permissions: read-only
  exclude: []
EOF
if ! (
    export AUR_DIR="$tmp/dataonly/aur"
    export AURGEN_ERROR_LOG="$tmp/err-dataonly.log"
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    get_copy_directories >"$tmp/dataonly.out"
    rm -f "$AUR_DIR/aurgen.install.yaml"
    get_copy_directories
) >"$tmp/dataonly-kept.out" 2>"$tmp/dataonly.err"; then
    echo "a data-only copy rule failed to load"
    cat "$tmp/dataonly.err"
    exit 1
fi
if [[ "$(cat "$tmp/dataonly.out")" != "data:usr/share/demo:644" ]]; then
    echo "a data-only copy rule was dropped or replaced by the defaults"
    cat "$tmp/dataonly.out"
    cat "$tmp/dataonly.err"
    exit 1
fi
if [[ "$(cat "$tmp/dataonly-kept.out")" != "data:usr/share/demo:644" ]]; then
    echo "an in-memory extra copy rule was discarded when the fixed rules were empty"
    cat "$tmp/dataonly-kept.out"
    cat "$tmp/dataonly.err"
    exit 1
fi

# ../x is not the last section, so the in-loop save must refuse it.
mkdir -p "$tmp/dotdot/aur"
cat > "$tmp/dotdot/aur/aurgen.install.yaml" <<'EOF'
bad:
  source: ../x
  destination: usr/share/x
  permissions: read-only
  exclude: []
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
if (
    export AUR_DIR="$tmp/dotdot/aur"
    export AURGEN_ERROR_LOG="$tmp/err-dotdot.log"
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    load_aurgen_config
) >"$tmp/dotdot.out" 2>"$tmp/dotdot.err"; then
    echo "source ../x was accepted"
    exit 1
fi
if ! grep -q "Invalid copy source: ../x" "$tmp/dotdot.err"; then
    echo "source ../x was not reported"
    cat "$tmp/dotdot.err"
    exit 1
fi

# /abs is the last section, so the end-of-file save must refuse it.
mkdir -p "$tmp/abs/aur"
cat > "$tmp/abs/aur/aurgen.install.yaml" <<'EOF'
bad:
  source: /abs
  destination: usr/share/abs
  permissions: read-only
  exclude: []
EOF
if (
    export AUR_DIR="$tmp/abs/aur"
    export AURGEN_ERROR_LOG="$tmp/err-abs.log"
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    load_aurgen_config
) >"$tmp/abs.out" 2>"$tmp/abs.err"; then
    echo "source /abs was accepted"
    exit 1
fi
if ! grep -q "Invalid copy source: /abs" "$tmp/abs.err"; then
    echo "source /abs was not reported"
    cat "$tmp/abs.err"
    exit 1
fi

# Trailing comments are dropped; a # inside quotes or inside a word is kept.
mkdir -p "$tmp/comments/aur"
cat > "$tmp/comments/aur/aurgen.install.yaml" <<'EOF'
executables:
  source: bin
  destination: usr/bin # where it goes
  permissions: executable # note
package:
  arch: [any] # all
  description: "Fix #12 and don't panic" # trailing
  check: "make \"x\" #1" # escaped double quote
  install: 'don''t # panic' # doubled single quote
aur_integration:
  commit_message: "Release #{version}" # note
  validate_before_push: true # check first
EOF
if ! (
    export AUR_DIR="$tmp/comments/aur"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export DEBUG_LEVEL=0
    export color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/aur-integration.sh
    source "$ROOT/lib/aur-integration.sh"
    load_aurgen_config || exit 1
    [[ "${PKG_ARCH[*]}" == any ]] || { echo "arch: [${PKG_ARCH[*]}]"; exit 1; }
    [[ "$PKG_DESCRIPTION" == "Fix #12 and don't panic" ]] || { echo "description: [$PKG_DESCRIPTION]"; exit 1; }
    [[ "$COPY_RULES_BIN" == usr/bin:executable: ]] || { echo "bin rule: [$COPY_RULES_BIN]"; exit 1; }
    [[ "$PKG_CHECK" == 'make \"x\" #1' ]] || { echo "check: [$PKG_CHECK]"; exit 1; }
    [[ "$PKG_INSTALL" == "don''t # panic" ]] || { echo "install: [$PKG_INSTALL]"; exit 1; }
    load_aur_integration_config >/dev/null 2>&1
    [[ "$AUR_COMMIT_MESSAGE" == 'Release #{version}' ]] || { echo "commit_message: [$AUR_COMMIT_MESSAGE]"; exit 1; }
    [[ "$AUR_VALIDATE_BEFORE_PUSH" == true ]] || { echo "validate_before_push: [$AUR_VALIDATE_BEFORE_PUSH]"; exit 1; }
) >"$tmp/comments.out" 2>&1; then
    echo "trailing YAML comments were kept in values"
    cat "$tmp/comments.out"
    exit 1
fi

# A block-list exclude gives the same rule as the inline form, before or after destination.
for order in after before; do
    mkdir -p "$tmp/block-$order/aur"
    if [[ "$order" == after ]]; then
        printf 'executables:\n  source: bin\n  destination: usr/bin\n  permissions: executable\n  exclude:\n    - test\n    - "tmp"\n' > "$tmp/block-$order/aur/aurgen.install.yaml"
    else
        printf 'executables:\n  source: bin\n  exclude:\n    - test\n    - "tmp"\n  destination: usr/bin\n  permissions: executable\n' > "$tmp/block-$order/aur/aurgen.install.yaml"
    fi
    got="$(
        export AUR_DIR="$tmp/block-$order/aur"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export DEBUG_LEVEL=0
        export color_enabled=0
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/config.sh
        source "$ROOT/lib/config.sh"
        load_aurgen_config >/dev/null 2>&1 || exit 1
        printf '%s' "$COPY_RULES_BIN"
    )"
    if [[ "$got" != 'usr/bin:executable:test, "tmp"' ]]; then
        echo "block-list exclude ($order destination) gave: [$got]"
        exit 1
    fi
done

# Exercise the same invalid rules through loading, config mode and generation.
repair_repo="$tmp/repair"
mkdir -p "$repair_repo/aur" "$repair_repo/data"
printf 'demo project\n' >| "$repair_repo/README.md"
printf 'payload\n' >| "$repair_repo/data/payload.txt"
git -C "$repair_repo" init -q
git -C "$repair_repo" remote add origin https://github.com/example/demo.git
git -C "$repair_repo" add README.md data/payload.txt
printf '#!/bin/bash\nexit 1\n' >| "$stub/gh"
chmod +x "$stub/gh"

copy_rule_action() (
    cd "$repair_repo" || exit 1
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repair_repo"
    export AUR_DIR="$repair_repo/aur"
    export AURGEN_ERROR_LOG="$tmp/repair.err.log"
    export AURGEN_MODE=test
    export PKGNAME=demo
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export DEBUG_LEVEL=0
    export color_enabled=0
    export LC_ALL=C
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    # shellcheck source=../lib/modes/config.sh
    source "$ROOT/lib/modes/config.sh"
    case "$1" in
        load) load_aurgen_config ;;
        rules) get_copy_directories ;;
        validate) mode_config validate ;;
        effective) mode_config show effective ;;
        generate) gen_pkgbuild0 ;;
    esac
)

for bad_rule in traversal absolute permissions; do
    case "$bad_rule" in
        traversal) copy_source=../x; copy_perms=read-only; diagnostic='Invalid copy source: ../x' ;;
        absolute) copy_source=/abs; copy_perms=read-only; diagnostic='Invalid copy source: /abs' ;;
        permissions) copy_source=data; copy_perms=rwx; diagnostic="Invalid permissions 'rwx' for data" ;;
    esac
    cat >| "$repair_repo/aur/aurgen.install.yaml" <<EOF
payload:
  source: $copy_source
  destination: usr/share/demo
  permissions: $copy_perms
EOF
    for action in rules validate effective generate; do
        if copy_rule_action "$action" >| "$tmp/repair.out" 2>| "$tmp/repair.err"; then
            echo "$action accepted an invalid $bad_rule copy rule"
            exit 1
        fi
        if ! grep -Fq "$diagnostic" "$tmp/repair.err"; then
            echo "$action did not name the invalid $bad_rule copy rule"
            cat "$tmp/repair.err"
            exit 1
        fi
        if [[ "$action" == rules && -s "$tmp/repair.out" ]]; then
            echo "invalid extra copy rules emitted defaults"
            exit 1
        fi
    done
    if [[ "$bad_rule" != permissions ]] && copy_rule_action load >| "$tmp/repair.out" 2>| "$tmp/repair.err"; then
        echo "load_aurgen_config accepted an invalid $bad_rule source"
        exit 1
    fi
    if [[ -e "$repair_repo/aur/PKGBUILD.0" ]]; then
        echo "invalid extra copy rules left a partial PKGBUILD.0"
        exit 1
    fi
done

# An install target must not bypass copy-rule validation.
printf 'install:\n\t:\n' >| "$repair_repo/Makefile"
if copy_rule_action generate >| "$tmp/repair.out" 2>| "$tmp/repair.err"; then
    echo "a Makefile install target bypassed invalid copy rules"
    exit 1
fi
if ! grep -Fq "Invalid permissions 'rwx' for data" "$tmp/repair.err" || [[ -e "$repair_repo/aur/PKGBUILD.0" ]]; then
    echo "Makefile generation did not reject the invalid rule cleanly"
    cat "$tmp/repair.err"
    exit 1
fi
rm -f "$repair_repo/Makefile"

# Missing fields in extra entries use the same validation as fixed rules.
for incomplete_rule in 'data::read-only:' 'data:usr/share/demo::'; do
    if (
        export AUR_DIR="$repair_repo/aur"
        export color_enabled=0
        # shellcheck source=../lib/helpers.sh
        source "$ROOT/lib/helpers.sh"
        # shellcheck source=../lib/config.sh
        source "$ROOT/lib/config.sh"
        # shellcheck disable=SC2034 # read by validate_config
        COPY_RULES_EXTRA=("$incomplete_rule")
        validate_config
    ) >| "$tmp/repair.out" 2>| "$tmp/repair.err"; then
        echo "validate_config accepted an incomplete extra rule"
        exit 1
    fi
    if ! grep -Fq 'Invalid configuration rule for data: missing destination or permissions' "$tmp/repair.err"; then
        echo "an incomplete extra rule was not named"
        cat "$tmp/repair.err"
        exit 1
    fi
done

cat >| "$repair_repo/aur/aurgen.install.yaml" <<'EOF'
payload:
  source: data
  destination: usr/share/demo
  permissions: 0644
EOF
if ! copy_rule_action validate >| "$tmp/repair.out" 2>| "$tmp/repair.err"; then
    echo "config validate rejected a valid extra rule"
    cat "$tmp/repair.err"
    exit 1
fi
if ! grep -Fxq '  data: usr/share/demo (0644)' "$tmp/repair.out"; then
    echo "config validate did not list the extra rule"
    cat "$tmp/repair.out"
    exit 1
fi
if ! copy_rule_action generate >| "$tmp/repair.out" 2>| "$tmp/repair.err"; then
    echo "generation rejected a valid extra rule"
    cat "$tmp/repair.err"
    exit 1
fi
if ! grep -Fxq '    copy_tree "data" "usr/share/demo" "0644"' "$repair_repo/aur/PKGBUILD.0"; then
    echo "generation changed the valid extra rule"
    exit 1
fi
if [[ "$(grep -c '^    copy_tree "' "$repair_repo/aur/PKGBUILD.0")" -ne 1 ]]; then
    echo "generation added default copy rules to a valid extra-only config"
    exit 1
fi
