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
# No trailing newline: gen_pkgbuild0 rewrites this file and must keep the rule.
printf '*.png binary' > "$repo/.gitattributes"

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
    source "$pkgbuild" || exit 1
    package
    [[ -f "$pkgdir/usr/bin/hello" ]] || exit 1
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

# Release kind writes the file list without asking the remote which tag exists.
real_git="$(command -v git)"
: > "$tmp/git-argv"
cat > "$stub/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$tmp/git-argv"
if [[ "\${1:-}" == "ls-remote" ]]; then
    exit 1
fi
exec "$real_git" "\$@"
EOF
chmod +x "$stub/git"
"$real_git" -C "$repo" remote add origin "https://github.com/testuser/testpkg.git"
"$real_git" -C "$repo" tag v1.2.3
rm -f "$repo/aur/PKGBUILD.0"
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
    unset PKG_SOURCE
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen5.out" 2>"$tmp/gen5.err"; then
    echo "gen_pkgbuild0 failed while a git ls-remote stub was on PATH"
    cat "$tmp/gen5.err"
    exit 1
fi
if [[ ! -s "$tmp/git-argv" ]]; then
    echo "git stub recorded no invocations"
    exit 1
fi
if grep -Eq '(^|[[:space:]])ls-remote([[:space:]]|$)' "$tmp/git-argv"; then
    echo "gen_pkgbuild0 called git ls-remote"
    cat "$tmp/git-argv"
    exit 1
fi
pkgbuild="$repo/aur/PKGBUILD.0"
if grep -F -q 'source=("git+' "$pkgbuild"; then
    echo "release kind wrote a VCS source line"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q "  'bin/hello'" "$pkgbuild"; then
    echo "release kind did not write the explicit file list"
    cat "$pkgbuild"
    exit 1
fi

# A package.json project must fail the package when its build script fails.
# --if-present still lets a project with no build script through.
node_repo="$tmp/node-repo"
mkdir -p "$node_repo/aur"
printf '%s\n' '{"name":"nodepkg","version":"1.0.0"}' > "$node_repo/package.json"
printf '%s\n' 'node project' > "$node_repo/README.md"
git -C "$node_repo" init -q
git -C "$node_repo" config user.email "t@example.com"
git -C "$node_repo" config user.name "t"
git -C "$node_repo" remote add origin "https://example.com/testuser/nodepkg.git"
git -C "$node_repo" add package.json README.md
git -C "$node_repo" commit -q -m init
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$node_repo"
    export AUR_DIR="$node_repo/aur"
    export PKGNAME=nodepkg
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="node project"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen-node.out" 2>"$tmp/gen-node.err"; then
    echo "gen_pkgbuild0 failed for a package.json project"
    cat "$tmp/gen-node.err"
    exit 1
fi
pkgbuild="$node_repo/aur/PKGBUILD.0"
build_fn="$(awk '/^build\(\)/,/^}/' "$pkgbuild")"
if ! grep -F -q 'npm run build --if-present' <<<"$build_fn"; then
    echo "node build() did not run npm with --if-present"
    printf '%s\n' "$build_fn"
    exit 1
fi
if grep -F -q '|| true' <<<"$build_fn"; then
    echo "node build() still ignores a failing build script"
    printf '%s\n' "$build_fn"
    exit 1
fi

if ! grep -qx '\*\.png binary' "$repo/.gitattributes"; then
    echo "gen_pkgbuild0 dropped the unterminated last line of .gitattributes"
    cat "$repo/.gitattributes"
    exit 1
fi

# A project without .gitattributes does not get one.
fresh="$tmp/no-attr"
mkdir -p "$fresh/bin" "$fresh/aur"
printf '#!/bin/bash\n' > "$fresh/bin/hello"
git -C "$fresh" init -q
git -C "$fresh" config user.email "t@example.com"
git -C "$fresh" config user.name "t"
git -C "$fresh" remote add origin "https://example.com/testuser/testpkg.git"
git -C "$fresh" add bin/hello
git -C "$fresh" commit -q -m init
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$fresh"
    export AUR_DIR="$fresh/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err-fresh.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="fresh"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0
) >"$tmp/gen-fresh.out" 2>"$tmp/gen-fresh.err"; then
    echo "gen_pkgbuild0 failed without .gitattributes"
    cat "$tmp/gen-fresh.err"
    exit 1
fi
if [[ -e "$fresh/.gitattributes" ]]; then
    echo "gen_pkgbuild0 created .gitattributes in a project that had none"
    exit 1
fi

