#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-gitignore.XXXXXX)"
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
# PKGBUILD.0 generation asks gh for the repo description; never reach GitHub.
printf '#!/bin/bash\nexit 1\n' > "$stub/gh"
chmod +x "$stub/gh"

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

run_init() {
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

fresh="$tmp/fresh"
prepare_repo "$fresh"
run_init "$fresh" fresh || fail "aurgen_init failed on a fresh repo" "$tmp/fresh.err"

ignore="$fresh/aur/.gitignore"
if [[ ! -f "$ignore" ]]; then
    fail "fresh repo: aur/.gitignore was not written" "$tmp/fresh.err"
fi

printf 'pkg\n' > "$fresh/aur/PKGBUILD"
printf 'blob\n' > "$fresh/aur/pkg.tar.gz"

if ! "$real_git" -C "$fresh" check-ignore -q -- aur/pkg.tar.gz; then
    fail "fresh repo: tarball should be ignored" "$ignore"
fi
if ! "$real_git" -C "$fresh" check-ignore -q -- aur/PKGBUILD; then
    fail "fresh repo: generated PKGBUILD should be ignored" "$ignore"
fi
printf 'package:\n' > "$fresh/aur/aurgen.install.yaml"
# check-ignore exits 1 for a path it does not ignore; 128 is a git error, not "tracked".
rc=0
"$real_git" -C "$fresh" check-ignore -q -- aur/aurgen.install.yaml || rc=$?
if (( rc != 1 )); then
    fail "fresh repo: aurgen.install.yaml should be tracked (check-ignore exit $rc)" "$ignore"
fi

# A file written by an older aurgen (which kept PKGBUILD, .SRCINFO and *.install) is upgraded.
legacy="$tmp/legacy"
prepare_repo "$legacy"
mkdir -p "$legacy/aur"
printf '%s\n' '*' '!.gitignore' '!PKGBUILD' '!.SRCINFO' '!*.install' '!aurgen.install.yaml' > "$legacy/aur/.gitignore"
run_init "$legacy" legacy || fail "aurgen_init failed on the old aur/.gitignore" "$tmp/legacy.err"
printf 'pkg\n' > "$legacy/aur/PKGBUILD"
if ! "$real_git" -C "$legacy" check-ignore -q -- aur/PKGBUILD; then
    fail "old aur/.gitignore was not upgraded" "$legacy/aur/.gitignore"
fi

custom="$tmp/custom"
prepare_repo "$custom"
mkdir -p "$custom/aur"
printf 'keep-me\n' > "$custom/aur/.gitignore"
run_init "$custom" custom || fail "aurgen_init failed when aur/.gitignore already exists" "$tmp/custom.err"
if [[ "$(cat "$custom/aur/.gitignore")" != "keep-me" ]]; then
    fail "existing aur/.gitignore was overwritten" "$custom/aur/.gitignore"
fi
