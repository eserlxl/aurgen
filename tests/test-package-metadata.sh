#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-package-metadata.XXXXXX)"
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
    git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
    printf 'all:\n\t@true\n' > "$repo/Makefile"
    printf 'hello\n' > "$repo/README.md"
    git -C "$repo" add Makefile README.md
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

run_gen() {
    local repo="$1"
    (
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
        load_aurgen_config
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"
}

count_field() {
    local file="$1"
    local field="$2"
    grep -c "^${field}=" "$file" || true
}

repo="$(new_repo meta)"
cat > "$repo/aur/demo.install" <<'EOF'
post_install() {
    true
}
EOF
cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  name: testpkg
  install: demo.install
  depends:
    - bash
    - git
  optdepends:
    - "bash: the shell"
  makedepends:
    - make
    - gcc
  conflicts:
    - testpkg-old
  provides:
    - testpkg-git
  backup:
    - etc/testpkg/config
EOF

if ! run_gen "$repo"; then
    echo "gen_pkgbuild0 failed with metadata set"
    cat "$tmp/gen.err"
    exit 1
fi

pkgbuild="$repo/aur/PKGBUILD.0"
[[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 was not written"

for field in depends optdepends conflicts provides backup install makedepends; do
    n="$(count_field "$pkgbuild" "$field")"
    if [[ "$n" != 1 ]]; then
        echo "$field appears $n times"
        cat "$pkgbuild"
        exit 1
    fi
done

if ! grep -F -x -q "optdepends=('bash: the shell')" "$pkgbuild"; then
    echo "optdepends item with ': ' was not kept"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "install='demo.install'" "$pkgbuild"; then
    echo "install= was not quoted"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "depends=('bash' 'git')" "$pkgbuild"; then
    echo "depends was not quoted from PKG_DEPENDS"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "conflicts=('testpkg-old')" "$pkgbuild"; then
    echo "conflicts missing"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "provides=('testpkg-git')" "$pkgbuild"; then
    echo "provides missing"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "backup=('etc/testpkg/config')" "$pkgbuild"; then
    echo "backup missing"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "makedepends=('make' 'gcc')" "$pkgbuild"; then
    echo "makedepends did not merge PKG_MAKEDEPENDS without duplicates"
    cat "$pkgbuild"
    exit 1
fi

if ! bash -n "$pkgbuild"; then
    echo "bash -n failed"
    cat "$pkgbuild"
    exit 1
fi

# errexit does not apply inside an if condition, so every check exits explicitly.
# shellcheck disable=SC2154 # the fields come from the sourced PKGBUILD
if ! (
    # shellcheck disable=SC1090
    source "$pkgbuild" || exit 1
    [[ "${optdepends[0]}" == "bash: the shell" ]] || exit 1
    [[ "${depends[0]}" == "bash" && "${depends[1]}" == "git" ]] || exit 1
    [[ "${install}" == "demo.install" ]] || exit 1
    make_count=0
    for dep in "${makedepends[@]}"; do
        [[ "$dep" == "make" ]] && make_count=$((make_count + 1))
    done
    [[ "$make_count" -eq 1 ]] || exit 1
) >"$tmp/src.out" 2>"$tmp/src.err"; then
    echo "sourcing PKGBUILD.0 failed or a field is wrong"
    cat "$tmp/src.err"
    cat "$pkgbuild"
    exit 1
fi

bare="$(new_repo bare)"
printf 'executables:\n  source: bin\n  destination: usr/bin\n  permissions: "755"\n' > "$bare/aur/aurgen.install.yaml"
if ! run_gen "$bare"; then
    echo "gen_pkgbuild0 failed with no package metadata"
    cat "$tmp/gen.err"
    exit 1
fi
bare_pkg="$bare/aur/PKGBUILD.0"
for field in depends optdepends conflicts provides backup install; do
    n="$(count_field "$bare_pkg" "$field")"
    if [[ "$n" != 0 ]]; then
        echo "unset $field was written"
        cat "$bare_pkg"
        exit 1
    fi
done

missing="$(new_repo missing)"
printf 'package:\n  install: gone.install\n' > "$missing/aur/aurgen.install.yaml"
if run_gen "$missing"; then
    echo "missing install file did not fail"
    cat "$missing/aur/PKGBUILD.0"
    exit 1
fi
if ! grep -F -q "gone.install" "$tmp/gen.err"; then
    echo "missing install failure did not name the file"
    cat "$tmp/gen.err"
    exit 1
fi

# A guarded tool the config lists in optdepends is not a makedepend.
optional="$(new_repo optional)"
mkdir -p "$optional/bin"
printf '#!/bin/bash\nif command -v gh >/dev/null; then\n    gh release view v1\nfi\n' > "$optional/bin/tool.sh"
git -C "$optional" add bin/tool.sh
git -C "$optional" commit -q -m tool
printf 'package:\n  optdepends:\n    - "github-cli: release uploads"\n' > "$optional/aur/aurgen.install.yaml"
if ! run_gen "$optional"; then
    echo "gen_pkgbuild0 failed with optdepends"
    cat "$tmp/gen.err"
    exit 1
fi
md_line="$(grep '^makedepends=' "$optional/aur/PKGBUILD.0")"
if [[ "$md_line" == *"'github-cli'"* ]]; then
    echo "makedepends should drop the optional github-cli, got: $md_line"
    exit 1
fi


# Words in prose are not build dependencies: "high " is not gh, "aur" and "git" in
# a README do not need pacman-contrib or git to build a release tarball.
prose="$(new_repo prose)"
printf 'This license applies to high quality software.\n' > "$prose/LICENSE"
printf 'Install from the AUR, or clone it with git.\n' > "$prose/README.md"
git -C "$prose" add LICENSE README.md
git -C "$prose" commit -q -m prose
printf 'package:\n  source: release\n' > "$prose/aur/aurgen.install.yaml"
if ! run_gen "$prose"; then
    echo "gen_pkgbuild0 failed for the prose repo"
    cat "$tmp/gen.err"
    exit 1
fi
md_line="$(grep '^makedepends=' "$prose/aur/PKGBUILD.0")"
for word in github-cli pacman-contrib git; do
    if [[ "$md_line" == *"'$word'"* ]]; then
        echo "makedepends took $word from prose: $md_line"
        exit 1
    fi
done
