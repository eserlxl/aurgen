#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# PEP 517/621 pyproject.toml build system, metadata, makedepends, and runtime depends.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-pyproject.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_MODE AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_CONFIG_ACTION \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT ALLOW_DIRTY SOURCE_DATE_EPOCH nocheck build_only COLOR NO_COLOR CI DEBUG_LEVEL \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    PKG_NAME PKG_DESCRIPTION PKG_GPG_KEY PKG_INSTALL PKG_CHECK PKG_SOURCE \
    PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/gh" <<'EOF'
#!/bin/bash
if [[ "${1:-} ${2:-}" == "repo view" && -n "${AURGEN_TEST_GH_DESC:-}" ]]; then
    printf '%s\n' "$AURGEN_TEST_GH_DESC"
fi
exit 0
EOF
chmod +x "$stub/gh"

new_repo() {
    local name="$1"
    local repo="$tmp/$name"
    mkdir -p "$repo/aur" "$repo/src/demo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" remote add origin "https://github.com/testuser/${name}.git"
    printf 'def main():\n    pass\n' > "$repo/src/demo/__init__.py"
    printf '# Demo\n\nFallback README description.\n' > "$repo/README.md"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

run_gen() {
    local repo="$1"
    local gh_desc="${2:-}"
    local run_lc="${3:-C}"
    (
        cd "$repo" || exit 1
        export PATH="$stub:$PATH"
        export LC_ALL="$run_lc"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=demo
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export AURGEN_TEST_GH_DESC="$gh_desc"
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"
}

array_contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

check_pkg_vars() {
    local pkgbuild="$1"
    [[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 missing: $pkgbuild"
    bash -n "$pkgbuild" || fail "bash -n failed: $pkgbuild" "$pkgbuild"
}

# 1. PEP 621 [project] without explicit build-backend defaults to python-setuptools,
#    parses multi-line TOML arrays, normalizes PEP 508 names, skips Windows/macOS markers,
#    ignores [project.optional-dependencies], and falls back cleanly to [project] description.
pwned="$tmp/pwned"
repo_pep621="$(new_repo pep621)"
cat > "$repo_pep621/pyproject.toml" <<EOF
[project]
name = "demo"
version = "0.1.0"
classifiers = [
  "Topic :: [Python]",
]
description = "Tool \"A\" uses 'quotes' & \$(touch $pwned) # kept" # trailing comment
dependencies = [
  "Requests [socks] >= 2.28 ; python_version >= '3.8'", # inline comment
  'Pillow>=10.0',
  "certifi",
  "unmapped-pypi-pkg >= 1.0",
  "pywin32>=300; sys_platform == 'win32'",
  "pyobjc; platform_system == 'Darwin'",
]

[project.optional-dependencies]
dev = ["pytest", "numpy"]
EOF
git -C "$repo_pep621" add pyproject.toml
git -C "$repo_pep621" commit -q -m add-pyproject

run_gen "$repo_pep621" "" || fail "gen_pkgbuild0 failed for pep621" "$tmp/gen.err"
[[ ! -e "$pwned" ]] || fail "pyproject description payload executed"
pkg="$repo_pep621/aur/PKGBUILD.0"
check_pkg_vars "$pkg"
(
    pkgdesc=""
    arch=()
    makedepends=()
    depends=()
    # shellcheck disable=SC1090
    source "$pkg" || exit 1
    [[ "$pkgdesc" == "Tool \"A\" uses 'quotes' & \$(touch $pwned) # kept" ]] || {
        printf 'unexpected pkgdesc: %s\n' "$pkgdesc"
        exit 1
    }
    [[ "${arch[*]}" == "any" ]] || { printf 'unexpected arch: %s\n' "${arch[*]}"; exit 1; }
    for md in python-build python-installer python-wheel python-setuptools; do
        array_contains "$md" "${makedepends[@]}" || { printf 'missing makedepend: %s\n' "$md"; exit 1; }
    done
    for dep in python python-requests python-pillow python-certifi; do
        array_contains "$dep" "${depends[@]}" || { printf 'missing runtime depend: %s\n' "$dep"; exit 1; }
    done
    for bad in python-unmapped-pypi-pkg python-pywin32 python-pyobjc python-numpy python-pytest; do
        if array_contains "$bad" "${depends[@]}"; then
            printf 'unexpected runtime depend: %s\n' "$bad"
            exit 1
        fi
    done
) || fail "pep621 PKGBUILD assertions failed" "$pkg"
grep -Fq 'python -m build --wheel --no-isolation' "$pkg" || fail "missing PEP 517 build command" "$pkg"
grep -Fq 'python -m installer --destdir="$pkgdir" dist/*.whl' "$pkg" || fail "missing PEP 517 install command" "$pkg"

# Running build() and package() with a python stub records exact PEP 517 commands.
mkdir -p "$repo_pep621/dist"
: > "$repo_pep621/dist/demo-0.1.0-py3-none-any.whl"
cat > "$stub/python" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$PY_LOG"
exit 0
EOF
chmod +x "$stub/python"
export PY_LOG="$tmp/py.log"
: > "$PY_LOG"
(
    cd "$repo_pep621" || exit 1
    export PATH="$stub:$PATH"
    pkgdir="$tmp/pkgroot"
    mkdir -p "$pkgdir"
    # shellcheck disable=SC1090
    source "$pkg" || exit 1
    build || exit 1
    package || exit 1
) || fail "running generated build/package failed"
grep -Fxq -- '-m build --wheel --no-isolation' "$PY_LOG" || fail "build() did not run python -m build" "$PY_LOG"
grep -Fxq -- "-m installer --destdir=$tmp/pkgroot dist/demo-0.1.0-py3-none-any.whl" "$PY_LOG" || fail "package() did not run python -m installer" "$PY_LOG"

# 2. Precedence: gh repo description beats pyproject description, and package.description beats both.
run_gen "$repo_pep621" "From GitHub repo." || fail "gen_pkgbuild0 failed with gh description" "$tmp/gen.err"
(
    pkgdesc=""
    # shellcheck disable=SC1090
    source "$pkg" || exit 1
    [[ "$pkgdesc" == "From GitHub repo." ]] || exit 1
) || fail "gh description did not override pyproject description" "$pkg"

cat > "$repo_pep621/aur/aurgen.install.yaml" <<'EOF'
package:
  description: From config override
  optdepends:
    - "python-requests: HTTP support"
  depends:
    - "python-certifi>=2024.0"
EOF
run_gen "$repo_pep621" "From GitHub repo." || fail "gen_pkgbuild0 failed with config overrides" "$tmp/gen.err"
(
    pkgdesc=""
    depends=()
    # shellcheck disable=SC1090
    source "$pkg" || exit 1
    [[ "$pkgdesc" == "From config override" ]] || exit 1
    array_contains "python-certifi>=2024.0" "${depends[@]}" || exit 1
    ! array_contains "python-certifi" "${depends[@]}" || exit 1
    ! array_contains "python-requests" "${depends[@]}" || exit 1
) || fail "config overrides did not take precedence over pyproject detection" "$pkg"

# 3. [tool.*]-only pyproject.toml stays legacy setup.py when setup.py exists, or no-build alone.
repo_tool_setup="$(new_repo tool-only-with-setup)"
printf '[tool.ruff]\nline-length = 100\n' > "$repo_tool_setup/pyproject.toml"
printf 'from setuptools import setup\nsetup()\n' > "$repo_tool_setup/setup.py"
git -C "$repo_tool_setup" add pyproject.toml setup.py
git -C "$repo_tool_setup" commit -q -m add-setup
run_gen "$repo_tool_setup" "" || fail "gen_pkgbuild0 failed for tool-only + setup.py" "$tmp/gen.err"
grep -Fq 'python setup.py build' "$repo_tool_setup/aur/PKGBUILD.0" || fail "tool-only pyproject broke legacy setup.py build" "$repo_tool_setup/aur/PKGBUILD.0"
grep -Fq 'python setup.py install --root="$pkgdir" --optimize=1 --skip-build' "$repo_tool_setup/aur/PKGBUILD.0" || fail "tool-only pyproject broke legacy setup.py install" "$repo_tool_setup/aur/PKGBUILD.0"

repo_tool_only="$(new_repo tool-only)"
printf '[tool.ruff]\nline-length = 100\n' > "$repo_tool_only/pyproject.toml"
git -C "$repo_tool_only" add pyproject.toml
git -C "$repo_tool_only" commit -q -m add-tool-toml
run_gen "$repo_tool_only" "" || fail "gen_pkgbuild0 failed for tool-only pyproject" "$tmp/gen.err"
grep -Fq '# No build steps required' "$repo_tool_only/aur/PKGBUILD.0" || fail "tool-only pyproject unexpectedly triggered build steps" "$repo_tool_only/aur/PKGBUILD.0"

# 4. Backends: pure-Python (hatchling, flit_core, poetry.core, pdm.backend) vs compiled (maturin, scikit-build-core, meson-python).
check_backend() {
    local name="$1" backend="$2" requires="$3" extra_marker="$4" want_arch="$5"
    shift 5
    local repo pkgbuild
    repo="$(new_repo "be-$name")"
    cat > "$repo/pyproject.toml" <<EOF
[build-system]
requires = [$requires]
build-backend = "$backend"

[project]
name = "be-$name"
description = "Backend test $name"
EOF
    [[ -n "$extra_marker" ]] && printf 'stub\n' > "$repo/$extra_marker"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m init-backend
    run_gen "$repo" "" || fail "gen_pkgbuild0 failed for backend $name" "$tmp/gen.err"
    pkgbuild="$repo/aur/PKGBUILD.0"
    check_pkg_vars "$pkgbuild"
    (
        arch=()
        makedepends=()
        # shellcheck disable=SC1090
        source "$pkgbuild" || exit 1
        [[ "${arch[*]}" == "$want_arch" ]] || { printf 'arch=%s want=%s\n' "${arch[*]}" "$want_arch"; exit 1; }
        local want_md
        for want_md in "$@"; do
            array_contains "$want_md" "${makedepends[@]}" || { printf 'missing makedepend %s in (%s)\n' "$want_md" "${makedepends[*]}"; exit 1; }
        done
    ) || fail "backend assertions failed for $name" "$pkgbuild"
}

check_backend hatchling "hatchling.build" '"hatchling>=1.18"' "" "any" python-build python-installer python-wheel python-hatchling
check_backend flit "flit_core.buildapi" '"flit_core>=3.8"' "" "any" python-build python-installer python-wheel python-flit-core
check_backend poetry "poetry.core.masonry.api" '"poetry-core"' "" "any" python-build python-installer python-wheel python-poetry-core
check_backend pdm "pdm.backend" '"pdm-backend"' "" "any" python-build python-installer python-wheel python-pdm-backend
check_backend maturin "maturin" '"maturin>=1.0"' "Cargo.toml" "x86_64 aarch64" python-build python-installer python-wheel maturin rust
check_backend scikit "scikit_build_core.build" '"scikit-build-core"' "CMakeLists.txt" "x86_64 aarch64" python-build python-installer python-wheel python-scikit-build-core cmake ninja
check_backend mesonpy "mesonpy" '"meson-python"' "meson.build" "x86_64 aarch64" python-build python-installer python-wheel meson-python meson ninja

# 5. Turkish locale safety for ASCII case folding on [BUILD-SYSTEM] and PILLOW.
tr_loc="$(locale -a 2>/dev/null | grep -im1 '^tr_TR\.utf-\?8$' || true)"
if [[ -n "$tr_loc" ]]; then
    repo_tr="$(new_repo turkish)"
    cat > "$repo_tr/pyproject.toml" <<'EOF'
[build-system]
requires = ["HATCHLING"]
build-backend = "hatchling.build"

[project]
name = "turkish"
dependencies = ["PILLOW", "CERTIFI"]
EOF
    git -C "$repo_tr" add pyproject.toml
    git -C "$repo_tr" commit -q -m init-tr
    run_gen "$repo_tr" "" "$tr_loc" || fail "gen_pkgbuild0 failed under $tr_loc" "$tmp/gen.err"
    (
        makedepends=()
        depends=()
        # shellcheck disable=SC1090
        source "$repo_tr/aur/PKGBUILD.0" || exit 1
        array_contains python-hatchling "${makedepends[@]}" || exit 1
        array_contains python-pillow "${depends[@]}" || exit 1
        array_contains python-certifi "${depends[@]}" || exit 1
    ) || fail "Turkish locale broke pyproject case folding" "$repo_tr/aur/PKGBUILD.0"
else
    printf 'SKIP: tr_TR.UTF-8 unavailable\n'
fi
