#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Lockfile-pinned Rust/Node builds, active Node runtime depends, and
# Cargo.toml/package.json pkgdesc fallback edge cases.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-manifest-locks.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export LC_ALL=C
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export HOME="$tmp/home"
export XDG_DATA_HOME="$tmp/xdg"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_MODE AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_CONFIG_ACTION \
    AURGEN_TEST_DESC AURGEN_TEST_GH_DESC \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT ALLOW_DIRTY SOURCE_DATE_EPOCH nocheck build_only COLOR NO_COLOR CI DEBUG_LEVEL \
    PKG_NAME PKG_DESCRIPTION PKG_GPG_KEY PKG_INSTALL PKG_CHECK PKG_SOURCE \
    PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS PKG_DEPENDS PKG_OPTDEPENDS PKG_MAKEDEPENDS \
    PKG_CONFLICTS PKG_PROVIDES PKG_BACKUP PKG_ARCH PKG_LICENSE PKG_INSTALL_VARS PKG_POST_PACKAGE PKG_KEEP \
    PROJECT_ROOT AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"

run_gen() {
    local repo="$1" lc="${2:-C}"
    rm -f "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD.HEADER"
    if ! (
        cd "$repo" || exit 1
        export LC_ALL="$lc"
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=demo
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config
        gen_pkgbuild0 || exit 1
        # shellcheck source=../lib/check-pkgbuild0.sh
        source "$ROOT/lib/check-pkgbuild0.sh"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        check_pkgbuild0 || exit 1
    ) >|"$tmp/gen.out" 2>|"$tmp/gen.err"; then
        echo "gen_pkgbuild0 failed for $repo"
        cat "$tmp/gen.err"
        exit 1
    fi
    if ! bash -n "$repo/aur/PKGBUILD.0"; then
        echo "bash -n failed for $repo/aur/PKGBUILD.0"
        cat "$repo/aur/PKGBUILD.0"
        exit 1
    fi
}

new_repo() {
    local name="$1"
    local repo="$tmp/$name"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" remote add origin "https://github.com/example/${name}.git"
    printf 'Fallback readme summary.\n' > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

assert_array_contains() {
    local pkgbuild="$1" array_name="$2" target="$3" expect="$4"
    local found=0
    if (
        # shellcheck disable=SC2034
        makedepends=()
        # shellcheck disable=SC2034
        depends=()
        # shellcheck disable=SC1090
        source "$pkgbuild" || exit 1
        local -n vals="$array_name"
        for v in "${vals[@]}"; do
            if [[ "$v" == "$target" ]]; then
                exit 0
            fi
        done
        exit 1
    ); then
        found=1
    fi
    if (( found != expect )); then
        echo "array ${array_name} membership mismatch for '${target}' (expected ${expect}) in ${pkgbuild}"
        cat "$pkgbuild"
        exit 1
    fi
}

# 1. Rust Cargo.lock -> --locked in both build() and check(), absent -> omitted
rust_repo="$(new_repo rust-lock)"
cat > "$rust_repo/Cargo.toml" <<'EOF'
[package]
name = "demo"
version = "0.1.0"
description = """
Rust tool
with 'quotes' and $(pwn) `cmd`
"""

[[bin]]
name = "helper"
EOF
run_gen "$rust_repo"
rust_pkg="$rust_repo/aur/PKGBUILD.0"
grep -Fxq '    cargo build --release' "$rust_pkg" || { echo "rust without lockfile missing bare build"; cat "$rust_pkg"; exit 1; }
if grep -Fq -- '--locked' "$rust_pkg"; then
    echo "rust without Cargo.lock unexpectedly used --locked"
    cat "$rust_pkg"
    exit 1
fi
if ! (
    pkgdesc=""
    # shellcheck disable=SC1090
    source "$rust_pkg" || exit 1
    [[ "$pkgdesc" == "Rust tool with 'quotes' and \$(pwn) \`cmd\`" ]]
); then
    echo "multiline quoted Cargo.toml pkgdesc corrupted or expanded"
    cat "$rust_pkg"
    exit 1
fi

printf 'version = 3\n' > "$rust_repo/Cargo.lock"
git -C "$rust_repo" add Cargo.toml Cargo.lock
git -C "$rust_repo" commit -q -m lock
run_gen "$rust_repo"
grep -Fxq '    cargo build --release --locked' "$rust_pkg" || { echo "rust with Cargo.lock missing --locked build"; cat "$rust_pkg"; exit 1; }
grep -Fxq '    cargo test --release --locked' "$rust_pkg" || { echo "rust with Cargo.lock missing --locked check"; cat "$rust_pkg"; exit 1; }

# 2. [[bin]] table after [package] without description must not bleed into pkgdesc
bin_repo="$(new_repo rust-bin-bleed)"
cat > "$bin_repo/Cargo.toml" <<'EOF'
[package]
name = "demo"
version = "0.1.0"

[[bin]]
name = "helper"
description = "Do not leak bin description"
EOF
run_gen "$bin_repo"
if ! (
    pkgdesc=""
    # shellcheck disable=SC1090
    source "$bin_repo/aur/PKGBUILD.0" || exit 1
    [[ "$pkgdesc" == "Fallback readme summary." ]]
); then
    echo "[[bin]] table leaked into [package] description lookup"
    cat "$bin_repo/aur/PKGBUILD.0"
    exit 1
fi

# 3. Node lockfiles (package-lock.json and npm-shrinkwrap.json) -> npm ci, plus runtime nodejs depends
node_repo="$(new_repo node-lock)"
python3 - "$node_repo/package.json" <<'PY'
import json, sys
json.dump({
    "name": "demo",
    "version": "1.0.0",
    "description": "Node CLI\nwith 'quotes' & $(evil)"
}, open(sys.argv[1], "w"))
PY
run_gen "$node_repo"
node_pkg="$node_repo/aur/PKGBUILD.0"
grep -Fxq '    npm install' "$node_pkg" || { echo "node without lockfile missing npm install"; cat "$node_pkg"; exit 1; }
if grep -Fxq '    npm ci' "$node_pkg"; then
    echo "node without lockfile unexpectedly used npm ci"
    cat "$node_pkg"
    exit 1
fi
assert_array_contains "$node_pkg" depends nodejs 1
assert_array_contains "$node_pkg" makedepends npm 1
if ! (
    pkgdesc=""
    # shellcheck disable=SC1090
    source "$node_pkg" || exit 1
    [[ "$pkgdesc" == "Node CLI with 'quotes' & \$(evil)" ]]
); then
    echo "multiline quoted package.json pkgdesc corrupted or expanded"
    cat "$node_pkg"
    exit 1
fi

printf '{"lockfileVersion":3}\n' > "$node_repo/package-lock.json"
run_gen "$node_repo"
grep -Fxq '    npm ci' "$node_pkg" || { echo "node with package-lock.json missing npm ci"; cat "$node_pkg"; exit 1; }
grep -Fxq '    npm run build --if-present' "$node_pkg" || { echo "node build() missing npm run build --if-present"; cat "$node_pkg"; exit 1; }

rm -f "$node_repo/package-lock.json"
printf '{"lockfileVersion":3}\n' > "$node_repo/npm-shrinkwrap.json"
run_gen "$node_repo"
grep -Fxq '    npm ci' "$node_pkg" || { echo "node with npm-shrinkwrap.json missing npm ci"; cat "$node_pkg"; exit 1; }

# 4. Higher-priority build systems prevent spurious nodejs runtime depend; optdepends/depends overrides work
cat > "$node_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  optdepends:
    - nodejs
EOF
run_gen "$node_repo"
assert_array_contains "$node_pkg" depends nodejs 0

cat > "$node_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  depends:
    - nodejs-lts-iron
EOF
run_gen "$node_repo"
assert_array_contains "$node_pkg" depends nodejs-lts-iron 1

rm -f "$node_repo/aur/aurgen.install.yaml"
printf 'all:\n\t@true\n' > "$node_repo/Makefile"
run_gen "$node_repo"
assert_array_contains "$node_pkg" depends nodejs 0
rm -f "$node_repo/Makefile"

printf '[build-system]\nrequires = ["setuptools"]\nbuild-backend = "setuptools.build_meta"\n' > "$node_repo/pyproject.toml"
run_gen "$node_repo"
assert_array_contains "$node_pkg" depends nodejs 0

# 5. Placeholder invalid Cargo.toml/package.json falls back cleanly without failing; tr_TR locale check when available
bad_repo="$(new_repo bad-manifests)"
printf 'x\n' > "$bad_repo/Cargo.toml"
printf 'x\n' > "$bad_repo/package.json"
tr_loc="$(locale -a 2>/dev/null | grep -im1 '^tr_TR\.utf-\?8$' || true)"
run_gen "$bad_repo" "${tr_loc:-C}"
if ! (
    pkgdesc=""
    # shellcheck disable=SC1090
    source "$bad_repo/aur/PKGBUILD.0" || exit 1
    [[ "$pkgdesc" == "Fallback readme summary." ]]
); then
    echo "invalid manifests broke fallback description"
    cat "$bad_repo/aur/PKGBUILD.0"
    exit 1
fi
