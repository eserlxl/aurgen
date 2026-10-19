#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-remote-url.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
stub="$tmp/bin"
real_git="$(command -v git)"
mkdir -p "$stub" "$repo/aur"
printf 'hello\n' > "$repo/README.md"

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

cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF

"$real_git" -C "$repo" init -q
"$real_git" -C "$repo" config user.email "t@example.com"
"$real_git" -C "$repo" config user.name "t"
"$real_git" -C "$repo" add README.md
"$real_git" -C "$repo" commit -q -m init
"$real_git" -C "$repo" remote add origin "https://github.com/octocat/demo"

expected="url='https://github.com/octocat/demo'"
remotes=(
    "https://github.com/octocat/demo"
    "https://github.com/octocat/demo.git"
    "git@github.com:octocat/demo.git"
)

for remote in "${remotes[@]}"; do
    "$real_git" -C "$repo" remote set-url origin "$remote"
    rm -f "$repo/aur/PKGBUILD.0" "$repo/aur/PKGBUILD.HEADER"
    if ! (
        cd "$repo" || exit 1
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
        gen_pkgbuild0
    ) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
        echo "gen_pkgbuild0 failed for $remote"
        cat "$tmp/gen.err"
        exit 1
    fi
    url_line="$(grep -E '^url=' "$repo/aur/PKGBUILD.0" || true)"
    if [[ "$url_line" != "$expected" ]]; then
        echo "url for $remote: ${url_line:-<missing>}"
        exit 1
    fi
done
