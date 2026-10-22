#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-pkgname.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

stub="$tmp/bin"
real_git="$(command -v git)"
mkdir -p "$stub"

cat > "$stub/git" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "ls-remote" ]]; then
    exit 1
fi
exec "$real_git" "\$@"
EOF
chmod +x "$stub/git"

cat > "$stub/gh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$stub/gh"

printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
chmod +x "$stub/makepkg"

prepare_repo() {
    local repo="$1"
    mkdir -p "$repo"
    "$real_git" -C "$repo" init -q -b main
    "$real_git" -C "$repo" config user.email "t@example.com"
    "$real_git" -C "$repo" config user.name "t"
    printf 'hello\n' > "$repo/README.md"
    "$real_git" -C "$repo" add README.md
    "$real_git" -C "$repo" commit -q -m init
    "$real_git" -C "$repo" remote add origin "https://github.com/example/tmpCleaner.git"
}

# Fresh repos have no PKGBUILD.0 yet, so aurgen_init generates and validates it.
generate() {
    local repo="$1"
    local label="$2"
    (
        cd "$repo" || exit 1
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export AURGEN_ERROR_LOG="$tmp/${label}.errlog"
        export AURGEN_LOG="$tmp/${label}.log"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export DEBUG_LEVEL=0
        export color_enabled=0
        unset PKGNAME
        unset REPO_NAME
        # shellcheck source=../lib/init.sh
        source "$ROOT/lib/init.sh"
        aurgen_init
    ) >"$tmp/${label}.out" 2>"$tmp/${label}.err"
}

assert_pkg() {
    local repo="$1"
    local label="$2"
    local expect_name="$3"
    local pkgbuild="$repo/aur/PKGBUILD.0"
    local url_line name_line
    if [[ ! -f "$pkgbuild" ]]; then
        fail "$label: PKGBUILD.0 was not written" "$tmp/${label}.err"
    fi
    name_line="$(grep -E '^pkgname=' "$pkgbuild" || true)"
    url_line="$(grep -E '^url=' "$pkgbuild" || true)"
    if [[ "$name_line" != "pkgname=${expect_name}" ]]; then
        fail "$label: pkgname should be ${expect_name}, got ${name_line:-<missing>}" "$pkgbuild"
    fi
    if [[ "$url_line" != "url='https://github.com/example/tmpCleaner'" ]]; then
        fail "$label: url should keep the repo name tmpCleaner, got ${url_line:-<missing>}" "$pkgbuild"
    fi
}

plain="$tmp/plain"
prepare_repo "$plain"
generate "$plain" plain || fail "aurgen_init failed on a fresh repo" "$tmp/plain.err"
assert_pkg "$plain" plain tmpcleaner

named="$tmp/named"
prepare_repo "$named"
mkdir -p "$named/aur"
cat > "$named/aur/aurgen.install.yaml" <<'EOF'
package:
  name: linux-tmpcleaner
EOF
generate "$named" named || fail "aurgen_init failed with package.name" "$tmp/named.err"
assert_pkg "$named" named linux-tmpcleaner

# Git clone URL and pkgver() cd into the repository, not the package name.
(
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$named"
    export AUR_DIR="$named/aur"
    export PKGBUILD0="$named/aur/PKGBUILD.0"
    export PKGBUILD="$named/aur/PKGBUILD"
    export SRCINFO="$named/aur/.SRCINFO"
    export AURGEN_ERROR_LOG="$tmp/git.errlog"
    export AURGEN_LOG="$tmp/git.log"
    export color_enabled=0
    export dry_run=1
    export PKGNAME=linux-tmpcleaner
    export REPO_NAME=tmpCleaner
    export GH_USER=example
    : > "$AURGEN_ERROR_LOG"
    : > "$AURGEN_LOG"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/modes/git.sh
    source "$ROOT/lib/modes/git.sh"
    mode_git
) >"$tmp/git.out" 2>"$tmp/git.err" || fail "mode_git failed for a package name that differs from the repo" "$tmp/git.err"

git_pkg="$named/aur/PKGBUILD"
grep -qFx 'pkgname=linux-tmpcleaner-git' "$git_pkg" || fail "git pkgname should stay the configured name" "$git_pkg"
grep -qF 'git+https://github.com/example/tmpCleaner.git#branch=' "$git_pkg" || fail "git source URL should use the repo name" "$git_pkg"
sed -n '/^pkgver() {/,/^}/p' "$git_pkg" | grep -qF 'cd "$srcdir/tmpCleaner"' || fail "pkgver() should cd into the repo clone" "$git_pkg"

# package.name ends up in file paths, so a traversal name must be refused.
dotted="$tmp/dotted"
prepare_repo "$dotted"
mkdir -p "$dotted/aur"
printf 'package:\n  name: ..\n' > "$dotted/aur/aurgen.install.yaml"
if generate "$dotted" dotted; then
    fail "aurgen_init accepted package.name '..'" "$tmp/dotted.err"
fi
grep -q "Invalid package name" "$tmp/dotted.err" || fail "missing invalid-name message" "$tmp/dotted.err"
