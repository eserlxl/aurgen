#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-arch.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"

fail() {
    echo "$1"
    exit 1
}

new_repo() {
    local repo="$tmp/$1"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    printf '%s\n' "$repo"
}

run_gen() {
    local repo="$1"
    if ! (
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=testpkg
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        if [[ -f "$repo/aur/aurgen.install.yaml" ]]; then
            load_aurgen_config
        fi
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
        echo "gen_pkgbuild0 failed for $repo"
        cat "$tmp/gen.err"
        exit 1
    fi
}

expect_arch() {
    local repo="$1"
    local want="$2"
    local pkgbuild="$repo/aur/PKGBUILD.0"
    local got
    if [[ ! -f "$pkgbuild" ]]; then
        fail "PKGBUILD.0 missing for $repo"
    fi
    got="$(grep -E '^arch=' "$pkgbuild" || true)"
    if [[ "$got" != "$want" ]]; then
        echo "arch mismatch for $repo"
        echo "got: [$got]"
        echo "want: [$want]"
        exit 1
    fi
}

script_repo="$(new_repo script)"
printf 'all:\n\t@true\n' > "$script_repo/Makefile"
printf '#!/bin/bash\necho hi\n' > "$script_repo/hello.sh"
git -C "$script_repo" add Makefile hello.sh
git -C "$script_repo" commit -q -m init
run_gen "$script_repo"
expect_arch "$script_repo" "arch=('any')"

c_repo="$(new_repo compiled)"
printf 'all:\n\tcc -o main main.c\n' > "$c_repo/Makefile"
printf 'int main(void){return 0;}\n' > "$c_repo/main.c"
git -C "$c_repo" add Makefile main.c
git -C "$c_repo" commit -q -m init
run_gen "$c_repo"
expect_arch "$c_repo" "arch=('x86_64' 'aarch64')"

override_script="$(new_repo override-script)"
printf 'all:\n\t@true\n' > "$override_script/Makefile"
printf '#!/bin/bash\necho hi\n' > "$override_script/hello.sh"
git -C "$override_script" add Makefile hello.sh
git -C "$override_script" commit -q -m init
cat > "$override_script/aur/aurgen.install.yaml" <<'EOF'
package:
  arch: [riscv64]
EOF
run_gen "$override_script"
expect_arch "$override_script" "arch=('riscv64')"

override_c="$(new_repo override-compiled)"
printf 'all:\n\tcc -o main main.c\n' > "$override_c/Makefile"
printf 'int main(void){return 0;}\n' > "$override_c/main.c"
git -C "$override_c" add Makefile main.c
git -C "$override_c" commit -q -m init
cat > "$override_c/aur/aurgen.install.yaml" <<'EOF'
package:
  arch: [riscv64]
EOF
run_gen "$override_c"
expect_arch "$override_c" "arch=('riscv64')"
