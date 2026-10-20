#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-gen-pkgbuild.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
pwned="$tmp/pwned"
payload='"; touch '"$pwned"'; echo "'
stub="$tmp/bin"
mkdir -p "$stub" "$repo/aur" "$repo/bin"
printf '#!/bin/bash\n' > "$repo/bin/hello"
printf 'hello project\n' > "$repo/README.md"

cat > "$stub/gh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
    printf '%s\n' "${AURGEN_TEST_DESC}"
    exit 0
fi
exit 0
EOF
chmod +x "$stub/gh"

cat > "$repo/aur/aurgen.install.yaml" <<EOF
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: [${payload}]
EOF

git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
git -C "$repo" add README.md bin/hello
git -C "$repo" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="$payload"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "gen_pkgbuild0 failed"
    cat "$tmp/gen.err"
    cat "$tmp/err.log"
    exit 1
fi

pkgbuild="$repo/aur/PKGBUILD.0"
if [[ ! -f "$pkgbuild" ]]; then
    echo "PKGBUILD.0 was not written"
    exit 1
fi
if [[ -e "$pwned" ]]; then
    echo "payload executed during generation"
    exit 1
fi
if ! grep -F -x -q -- "pkgdesc='${payload}'" "$pkgbuild"; then
    echo "pkgdesc was not emitted as a single-quoted value"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F "copy_tree" "$pkgbuild" | grep -F -q -- "'${payload}'"; then
    echo "exclude pattern was not emitted as a single-quoted argument"
    cat "$pkgbuild"
    exit 1
fi
if grep -E '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)' "$pkgbuild" >/dev/null; then
    echo "PKGBUILD.0 still evals a command string"
    exit 1
fi
if ! bash -n "$pkgbuild"; then
    echo "bash -n failed"
    cat "$pkgbuild"
    exit 1
fi

(
    cd "$repo" || exit
    pkgdir="$tmp/pkgroot"
    mkdir -p "$pkgdir"
    # shellcheck disable=SC1090
    source "$pkgbuild"
    package
) >"$tmp/src.out" 2>"$tmp/src.err"
status=$?
if [[ -e "$pwned" ]]; then
    echo "payload executed while sourcing PKGBUILD.0"
    exit 1
fi
if (( status != 0 )); then
    echo "sourcing PKGBUILD.0 failed: $status"
    cat "$tmp/src.err"
    cat "$pkgbuild"
    exit 1
fi

# A copy destination that breaks out of its double quotes is refused.
cat > "$repo/aur/aurgen.install.yaml" <<YAML
executables:
  source: bin
  destination: usr/bin${payload}
  permissions: executable
YAML
rm -f "$repo/aur/PKGBUILD.0"
if (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="demo"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen2.out" 2>"$tmp/gen2.err"; then
    echo "gen_pkgbuild0 accepted an unsafe copy destination"
    exit 1
fi
if [[ -e "$repo/aur/PKGBUILD.0" ]]; then
    echo "a refused copy rule left a partial PKGBUILD.0"
    exit 1
fi

# Bracket lists keep a leading space and optional quotes on later items.
cat > "$repo/aur/aurgen.install.yaml" <<'YAML'
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: [test, "temp"]
YAML
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="demo"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen3.out" 2>"$tmp/gen3.err"; then
    echo "gen_pkgbuild0 failed for bracketed exclusions"
    cat "$tmp/gen3.err"
    exit 1
fi
pkgbuild="$repo/aur/PKGBUILD.0"
matched=0
while IFS= read -r copy_line; do
    if [[ "$copy_line" == *" 'test' 'temp'" ]]; then
        matched=1
    fi
done < <(grep -F 'copy_tree' "$pkgbuild")
if (( matched != 1 )); then
    echo "copy_tree line does not end with 'test' 'temp'"
    cat "$pkgbuild"
    exit 1
fi

# A tracked name with shell metacharacters stays data in the fallback source array.
trick='a$(touch pwned)b.txt'
printf 'x\n' > "$repo/$trick"
git -C "$repo" add -- "$trick"
git -C "$repo" commit -q -m "track metacharacter name"
git -C "$repo" remote remove origin
rm -f "$repo/aur/PKGBUILD.0" "$repo/pwned"
if ! (
    cd "$repo" || exit 1
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo"
    export AUR_DIR="$repo/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="demo"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen4.out" 2>"$tmp/gen4.err"; then
    echo "gen_pkgbuild0 failed for a metacharacter source name"
    cat "$tmp/gen4.err"
    exit 1
fi
pkgbuild="$repo/aur/PKGBUILD.0"
if ! grep -F -x -q -- "  '${trick}'" "$pkgbuild"; then
    echo "fallback source name was not single-quoted"
    cat "$pkgbuild"
    exit 1
fi
if ! bash -n "$pkgbuild"; then
    echo "bash -n failed for a metacharacter source name"
    cat "$pkgbuild"
    exit 1
fi
(
    cd "$repo" || exit 1
    # shellcheck disable=SC1090
    source "$pkgbuild"
) >"$tmp/src4.out" 2>"$tmp/src4.err"
status=$?
if [[ -e "$repo/pwned" ]]; then
    echo "metacharacter source name executed while sourcing PKGBUILD.0"
    exit 1
fi
if (( status != 0 )); then
    echo "sourcing PKGBUILD.0 with a metacharacter source name failed: $status"
    cat "$tmp/src4.err"
    exit 1
fi
