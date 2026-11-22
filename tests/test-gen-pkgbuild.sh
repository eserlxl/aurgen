#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-gen-pkgbuild.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_CONFIG_FILE \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO
mkdir -p "$HOME"

repo="$tmp/repo"
pwned="$tmp/pwned"
payload='"; touch '"$pwned"'; echo "'
stub="$tmp/bin"
mkdir -p "$stub" "$repo/aur" "$repo/bin"
printf '#!/bin/bash\n' > "$repo/bin/hello"
printf 'hello project\n' > "$repo/README.md"
printf '1.0.0\n' >| "$repo/VERSION"

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
package:
  keep: [VERSION, share/help/, README.md]
EOF

git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
git -C "$repo" add README.md bin/hello VERSION
git -C "$repo" commit -q -m init
# No trailing newline: gen_pkgbuild0 rewrites this file and must keep the rule.
{
    printf '%s\n' '*.md export-ignore' 'VERSION export-ignore export-subst'
    printf 'VERSION.txt\texport-ignore\n'
    printf '%s\n' \
        'share/help/a.md export-ignore' 'share/helper/a.md export-ignore' \
        'README.md export-ignore'
    printf '*.png binary'
} >| "$repo/.gitattributes"

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
    # init.sh loads the config before gen_pkgbuild0, so package.keep is known.
    load_aurgen_config || exit 1
    gen_pkgbuild0 || exit 1
    # Repeated generation and an empty keep list leave existing attributes unchanged.
    generate_gitattributes_from_filter || exit 1
    # shellcheck disable=SC2034 # read by generate_gitattributes_from_filter
    PKG_KEEP=()
    generate_gitattributes_from_filter || exit 1
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "gen_pkgbuild0 failed"
    cat "$tmp/gen.err"
    cat "$tmp/err.log"
    exit 1
fi

{
    printf '%s\n' '*.md export-ignore' 'VERSION export-ignore export-subst'
    printf 'VERSION.txt\texport-ignore\n'
    printf '%s\n' 'share/help/a.md export-ignore' 'share/helper/a.md export-ignore' \
        'README.md export-ignore' '*.png binary' '/VERSION -export-ignore' \
        '/share/help/** -export-ignore' '/README.md -export-ignore'
} >| "$tmp/gitattributes.want"
if ! cmp -s "$tmp/gitattributes.want" "$repo/.gitattributes"; then
    echo "keep overrides are missing or existing attributes changed"
    diff -u "$tmp/gitattributes.want" "$repo/.gitattributes" || true
    exit 1
fi
got=$(git -C "$repo" check-attr export-ignore -- VERSION share/help/a.md README.md \
    VERSION.txt share/helper/a.md notes.md docs/README.md) || exit 1
if [[ "$got" != $'VERSION: export-ignore: unset\nshare/help/a.md: export-ignore: unset\nREADME.md: export-ignore: unset\nVERSION.txt: export-ignore: set\nshare/helper/a.md: export-ignore: set\nnotes.md: export-ignore: set\ndocs/README.md: export-ignore: set' ]]; then
    echo "keep overrides did not preserve export-ignore for unkept paths"
    printf '%s\n' "$got"
    exit 1
fi
if [[ "$(git -C "$repo" check-attr export-subst -- VERSION)" != 'VERSION: export-subst: set' ]]; then
    echo "keep override lost export-subst"
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

# check_pkgbuild0 accepts a description that starts with a quote, and still refuses an empty one.
check_desc() (
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AUR_DIR="$tmp/desc"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export color_enabled=0
    mkdir -p "$AUR_DIR"
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    # shellcheck source=../lib/check-pkgbuild0.sh
    source "$ROOT/lib/check-pkgbuild0.sh"
    {
        printf '%s\n' 'pkgname=demo' 'pkgver=1.0.0' 'pkgrel=1'
        printf 'pkgdesc=%s\n' "$(pkgbuild_squote "$1")"
        printf '%s\n' "url='https://github.com/example/demo'" "license=('MIT')" "source=('demo.tar.gz')"
    } >| "$AUR_DIR/PKGBUILD.0"
    check_pkgbuild0
)
if ! check_desc "'x' tool" >"$tmp/desc.out" 2>&1; then
    echo "check_pkgbuild0 refused a description that starts with a quote"
    cat "$tmp/desc.out"
    exit 1
fi
if check_desc "" >"$tmp/desc-empty.out" 2>&1; then
    echo "check_pkgbuild0 accepted an empty description"
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

# A destination that climbs out of $pkgdir is refused and leaves no PKGBUILD.0.
cat > "$repo/aur/aurgen.install.yaml" <<'YAML'
executables:
  source: bin
  destination: ../outside
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
) >"$tmp/gen-dotdot.out" 2>"$tmp/gen-dotdot.err"; then
    echo "gen_pkgbuild0 accepted a copy destination that climbs out of the package"
    exit 1
fi
if [[ -e "$repo/aur/PKGBUILD.0" ]]; then
    echo "a refused copy rule left a partial PKGBUILD.0"
    exit 1
fi
if ! grep -F -q 'Unsafe copy rule' "$tmp/gen-dotdot.err"; then
    echo "a climbing copy destination was not reported as an unsafe copy rule"
    cat "$tmp/gen-dotdot.err"
    exit 1
fi

# $pkgname stays a package-time expansion in an otherwise normal destination.
cat > "$repo/aur/aurgen.install.yaml" <<'YAML'
executables:
  source: bin
  destination: usr/lib/$pkgname
  permissions: executable
YAML
rm -f "$repo/aur/PKGBUILD.0"
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
    gen_pkgbuild0 || exit 1
) >"$tmp/gen-pkgname.out" 2>"$tmp/gen-pkgname.err"; then
    echo "gen_pkgbuild0 refused a destination that contains \$pkgname"
    cat "$tmp/gen-pkgname.err"
    exit 1
fi
if ! grep -F 'copy_tree' "$repo/aur/PKGBUILD.0" | grep -F -q '"usr/lib/$pkgname"'; then
    echo "\$pkgname was not kept in the copy destination"
    cat "$repo/aur/PKGBUILD.0"
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
    gen_pkgbuild0 || exit 1
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

# A tracked name with shell metacharacters is not a release source entry.
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
    gen_pkgbuild0 || exit 1
) >"$tmp/gen4.out" 2>"$tmp/gen4.err"; then
    echo "gen_pkgbuild0 failed for a metacharacter source name"
    cat "$tmp/gen4.err"
    exit 1
fi
pkgbuild="$repo/aur/PKGBUILD.0"
if grep -F -q -- "$trick" "$pkgbuild"; then
    echo "release source array included a tracked filename"
    cat "$pkgbuild"
    exit 1
fi
if ! grep -F -x -q 'source=("$pkgname-$pkgver.tar.gz")' "$pkgbuild"; then
    echo "release PKGBUILD.0 should have one source entry"
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
    gen_pkgbuild0 || exit 1
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
tracked=$(git -C "$repo" ls-files | wc -l)
source_lines=$(grep -c -E '^source=' "$pkgbuild" || true)
if (( tracked < 2 )) || [[ "$source_lines" != 1 ]] || ! grep -F -x -q 'source=("$pkgname-$pkgver.tar.gz")' "$pkgbuild"; then
    echo "release PKGBUILD.0 should have one source entry"
    echo "tracked=$tracked source_lines=$source_lines"
    cat "$pkgbuild"
    exit 1
fi

# An unknown build system with release sources still produces a valid template.
unknown_repo="$tmp/unknown-repo"
mkdir -p "$unknown_repo/lib" "$tmp/unknown-aur"
printf 'int main(void) { return 0; }\n' >| "$unknown_repo/lib/unknown.c"
printf '1.0.0\n' >| "$unknown_repo/VERSION"
git -C "$unknown_repo" init -q
git -C "$unknown_repo" remote add origin "https://github.com/testuser/unknownpkg.git"
git -C "$unknown_repo" add lib/unknown.c VERSION
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$unknown_repo"
    export AUR_DIR="$tmp/unknown-aur"
    export PKGNAME=unknownpkg
    export AURGEN_ERROR_LOG="$tmp/err-unknown.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="unknown project"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    # shellcheck source=../lib/check-pkgbuild0.sh
    source "$ROOT/lib/check-pkgbuild0.sh"
    export PKG_SOURCE=release
    gen_pkgbuild0 || exit 1
    grep -F -q '# Add your build steps here' "$AUR_DIR/PKGBUILD.0" || exit 1
    bash -n "$AUR_DIR/PKGBUILD.0" || exit 1
    check_pkgbuild0 || exit 1
) >| "$tmp/gen-unknown.out" 2>| "$tmp/gen-unknown.err"; then
    echo "gen_pkgbuild0 produced an invalid template for an unknown build system"
    cat "$tmp/gen-unknown.err"
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
    gen_pkgbuild0 || exit 1
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
    gen_pkgbuild0 || exit 1
) >"$tmp/gen-fresh.out" 2>"$tmp/gen-fresh.err"; then
    echo "gen_pkgbuild0 failed without .gitattributes"
    cat "$tmp/gen-fresh.err"
    exit 1
fi
if [[ -e "$fresh/.gitattributes" ]]; then
    echo "gen_pkgbuild0 created .gitattributes in a project that had none"
    exit 1
fi


# The project's remote and tags come from PROJECT_ROOT, not from the cwd.
elsewhere="$tmp/elsewhere"
mkdir -p "$elsewhere"
git -C "$elsewhere" init -q
git -C "$elsewhere" config user.email "o@example.com"
git -C "$elsewhere" config user.name "o"
git -C "$elsewhere" remote add origin "https://github.com/other/unrelated.git"
git -C "$elsewhere" commit -q --allow-empty -m init
git -C "$elsewhere" tag v9.9.9
git -C "$fresh" remote set-url origin "https://github.com/fixture/testpkg.git"
if ! (
    cd "$elsewhere" || exit 1
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$fresh"
    export AUR_DIR="$fresh/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err-cwd.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="cwd"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 || exit 1
) >"$tmp/gen-cwd.out" 2>"$tmp/gen-cwd.err"; then
    echo "gen_pkgbuild0 failed from another cwd"
    cat "$tmp/gen-cwd.err"
    exit 1
fi
if ! grep -F -q "url='https://github.com/fixture/testpkg'" "$fresh/aur/PKGBUILD.0"; then
    echo "gen_pkgbuild0 read the remote of the cwd, not PROJECT_ROOT"
    grep '^url=' "$fresh/aur/PKGBUILD.0"
    exit 1
fi
if grep -q '^pkgver=9\.9\.9$' "$fresh/aur/PKGBUILD.0"; then
    echo "gen_pkgbuild0 took the version from the cwd's tag"
    exit 1
fi

# filter_pkgbuild_sources decides what ships; every other test stubs it with cat.
got=$(
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AURGEN_ERROR_LOG="$tmp/err-filter.log"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    printf '%s\n' node_modules/x.sh src/a.pyc .env doc/guide.md notes.md VERSION \
        LICENSE.md docs/LICENSE.md bin/tool lib/x.sh share/data.csv share/help/a.md | filter_pkgbuild_sources
) || { echo "filter_pkgbuild_sources failed"; exit 1; }
if [[ "$got" != $'LICENSE.md\nbin/tool\nlib/x.sh' ]]; then
    echo "filter_pkgbuild_sources kept the wrong files:"
    printf '%s\n' "$got"
    exit 1
fi

got=$(
    export LIB_INSTALL_DIR="$ROOT/lib"
    export AURGEN_ERROR_LOG="$tmp/err-filter-keep.log"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    # shellcheck disable=SC2034 # read by filter_pkgbuild_sources
    PKG_KEEP=(VERSION share/help/)
    printf '%s\n' VERSION VERSION.txt share/help/a.md share/help/nested/b.csv \
        share/helper/a.md notes.md | filter_pkgbuild_sources
) || { echo "filter_pkgbuild_sources with keep failed"; exit 1; }
if [[ "$got" != $'VERSION\nshare/help/a.md\nshare/help/nested/b.csv' ]]; then
    echo "filter_pkgbuild_sources did not honour exact paths and directory prefixes:"
    printf '%s\n' "$got"
    exit 1
fi

# copy_tree recreates symlinks alongside regular files in copied directories.
symrepo="$tmp/sym-repo"
mkdir -p "$symrepo/bin" "$symrepo/aur"
printf '#!/bin/bash\nexit 0\n' > "$symrepo/bin/tool"
chmod +x "$symrepo/bin/tool"
ln -s tool "$symrepo/bin/alias"
cat > "$symrepo/aur/aurgen.install.yaml" <<'YAML'
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
YAML
git -C "$symrepo" init -q
git -C "$symrepo" config user.email "t@example.com"
git -C "$symrepo" config user.name "t"
git -C "$symrepo" remote add origin "https://example.com/testuser/testpkg.git"
git -C "$symrepo" add bin/tool bin/alias aur/aurgen.install.yaml
git -C "$symrepo" commit -q -m "symlinks in copy rule"
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$symrepo"
    export AUR_DIR="$symrepo/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err-symlink.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="symlink"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 || exit 1
) >"$tmp/gen-symlink.out" 2>"$tmp/gen-symlink.err"; then
    echo "gen_pkgbuild0 failed for symlink repo"
    cat "$tmp/gen-symlink.err"
    exit 1
fi

pkgdir="$tmp/sym-pkgdir"
mkdir -p "$pkgdir"
if ! (
    cd "$symrepo" || exit 1
    export pkgdir
    export pkgname=testpkg
    # shellcheck disable=SC1090,SC2154
    source "$symrepo/aur/PKGBUILD.0" || exit 1
    package || exit 1
) >"$tmp/package-symlink.out" 2>"$tmp/package-symlink.err"; then
    echo "generated package() copy_tree failed"
    cat "$tmp/package-symlink.err"
    exit 1
fi
if [[ ! -f "$pkgdir/usr/bin/tool" || -L "$pkgdir/usr/bin/tool" ]]; then
    echo "tool missing or is a symlink in pkgdir"
    exit 1
fi
if [[ ! -L "$pkgdir/usr/bin/alias" ]]; then
    echo "alias missing or not a symlink in pkgdir"
    exit 1
fi
if [[ "$(readlink "$pkgdir/usr/bin/alias")" != "tool" ]]; then
    echo "alias symlink does not point to tool"
    exit 1
fi

# generate_gitattributes_from_filter must match kept paths literally (not as regexes).
litrepo="$tmp/literal-gitattr"
mkdir -p "$litrepo/bin" "$litrepo/docs" "$litrepo/aur"
printf '#!/bin/bash\nexit 0\n' > "$litrepo/bin/[draft]+1.sh"
printf 'keep me\n' >| "$litrepo/docs/[draft]+1.txt"
printf 'ignore me\n' >| "$litrepo/docs/temp.log"
: > "$litrepo/.gitattributes"
cat > "$litrepo/aur/aurgen.install.yaml" <<'YAML'
executables:
  source: bin
  destination: usr/bin
  permissions: executable
YAML
git -C "$litrepo" init -q
git -C "$litrepo" config user.email "t@example.com"
git -C "$litrepo" config user.name "t"
git -C "$litrepo" add 'bin/[draft]+1.sh' 'docs/[draft]+1.txt' docs/temp.log aur/aurgen.install.yaml .gitattributes
git -C "$litrepo" commit -q -m "literal path test"
if ! (
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$litrepo"
    export AUR_DIR="$litrepo/aur"
    export AURGEN_ERROR_LOG="$tmp/err-literal.log"
    export AURGEN_MODE=test
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config || exit 1
    generate_gitattributes_from_filter || exit 1
) >"$tmp/lit.out" 2>"$tmp/lit.err"; then
    echo "generate_gitattributes_from_filter failed on regex-metachar paths"
    cat "$tmp/lit.err"
    exit 1
fi
for kept_path in 'bin/[draft]+1.sh' 'docs/[draft]+1.txt'; do
    if grep -Fqx "$kept_path export-ignore" "$litrepo/.gitattributes"; then
        echo "kept path $kept_path was wrongly marked export-ignore:"
        cat "$litrepo/.gitattributes"
        exit 1
    fi
done
grep -Fqx 'docs/temp.log export-ignore' "$litrepo/.gitattributes" || {
    echo "non-kept path docs/temp.log should be marked export-ignore:"
    cat "$litrepo/.gitattributes"
    exit 1
}

# gen_pkgbuild0 must preserve caller nounset state across both validation errors and success.
nounset_repo="$tmp/nounset-repo"
mkdir -p "$nounset_repo/aur"
printf '#!/bin/bash\nexit 0\n' > "$nounset_repo/run.sh"
chmod +x "$nounset_repo/run.sh"
git -C "$nounset_repo" init -q
git -C "$nounset_repo" config user.email "t@example.com"
git -C "$nounset_repo" config user.name "t"
git -C "$nounset_repo" remote add origin "https://example.com/testuser/nounsetpkg.git"
git -C "$nounset_repo" add run.sh
git -C "$nounset_repo" commit -q -m init

if ! (
    set -u
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$nounset_repo"
    export AUR_DIR="$nounset_repo/aur"
    export AURGEN_ERROR_LOG="$tmp/err-nounset.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="nounset test"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"

    PKGNAME="Bad Name"
    if gen_pkgbuild0 2>/dev/null; then
        echo "gen_pkgbuild0 should fail on invalid PKGNAME"
        exit 1
    fi
    [[ "$-" == *u* ]] || { echo "nounset was cleared after invalid PKGNAME failure"; exit 1; }

    PKGNAME="nounsetpkg"
    # shellcheck disable=SC2034 # checked by gen_pkgbuild0
    PKG_INSTALL="../escape.install"
    if gen_pkgbuild0 2>/dev/null; then
        echo "gen_pkgbuild0 should fail on path-traversal PKG_INSTALL"
        exit 1
    fi
    [[ "$-" == *u* ]] || { echo "nounset was cleared after invalid PKG_INSTALL failure"; exit 1; }

    # shellcheck disable=SC2034 # checked by gen_pkgbuild0
    PKG_INSTALL=""
    gen_pkgbuild0 > /dev/null 2>&1 || { echo "gen_pkgbuild0 failed under set -u"; exit 1; }
    [[ "$-" == *u* ]] || { echo "nounset was cleared after gen_pkgbuild0 success"; exit 1; }
); then
    echo "gen_pkgbuild0 nounset preservation test failed"
    exit 1
fi

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$nounset_repo"
    export AUR_DIR="$nounset_repo/aur"
    export PKGNAME="nounsetpkg"
    export AURGEN_ERROR_LOG="$tmp/err-nou.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="no-nounset test"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    set +u
    gen_pkgbuild0 > /dev/null 2>&1 || exit 1
    [[ "$-" != *u* ]] || { echo "gen_pkgbuild0 enabled nounset on a set +u caller"; exit 1; }
); then
    echo "gen_pkgbuild0 set +u preservation test failed"
    exit 1
fi

# filter_pkgbuild_sources must keep go.mod and nested */go.mod while still skipping other *.mod and excluded paths.
go_repo="$tmp/go-repo"
mkdir -p "$go_repo/aur" "$go_repo/cmd/tool" "$go_repo/doc" "$go_repo/.cache"
printf 'module example.com/gopkga\n\ngo 1.22\n' > "$go_repo/go.mod"
printf 'module example.com/gopkga/cmd/tool\n\ngo 1.22\n' > "$go_repo/cmd/tool/go.mod"
printf 'package main\nfunc main() {}\n' > "$go_repo/main.go"
printf 'kernel-module\n' > "$go_repo/extra.mod"
printf 'doc-module\n' > "$go_repo/doc/go.mod"
printf 'aur-module\n' > "$go_repo/aur/go.mod"
printf 'cache-module\n' > "$go_repo/.cache/go.mod"
printf 'hidden-module\n' > "$go_repo/.go.mod"
printf 'Go test project\n' > "$go_repo/README.md"
: > "$go_repo/.gitattributes"
git -C "$go_repo" init -q
git -C "$go_repo" config user.email "t@example.com"
git -C "$go_repo" config user.name "t"
git -C "$go_repo" remote add origin "https://example.com/testuser/gopkga.git"
git -C "$go_repo" add go.mod cmd/tool/go.mod main.go extra.mod doc/go.mod aur/go.mod .cache/go.mod .go.mod README.md .gitattributes
git -C "$go_repo" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$go_repo"
    export AUR_DIR="$go_repo/aur"
    export PKGNAME=gopkga
    export AURGEN_ERROR_LOG="$tmp/go.err"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export AURGEN_TEST_DESC="go source filter test"
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"

    filtered=$(git -C "$go_repo" ls-files | filter_pkgbuild_sources)
    grep -Fqx 'go.mod' <<< "$filtered" || { echo "filter_pkgbuild_sources dropped go.mod"; exit 1; }
    grep -Fqx 'cmd/tool/go.mod' <<< "$filtered" || { echo "filter_pkgbuild_sources dropped cmd/tool/go.mod"; exit 1; }
    grep -Fqx 'main.go' <<< "$filtered" || { echo "filter_pkgbuild_sources dropped main.go"; exit 1; }
    for dropped in extra.mod doc/go.mod aur/go.mod .cache/go.mod .go.mod; do
        if grep -Fqx "$dropped" <<< "$filtered"; then
            echo "filter_pkgbuild_sources unexpectedly kept $dropped"
            exit 1
        fi
    done

    gen_pkgbuild0 > /dev/null 2>&1 || { echo "gen_pkgbuild0 failed on Go repo"; exit 1; }
    generate_gitattributes_from_filter > /dev/null 2>&1 || { echo "generate_gitattributes_from_filter failed on Go repo"; exit 1; }
    # shellcheck disable=SC2154 # populated by PKGBUILD.0
    (
        # shellcheck source=/dev/null
        source "$go_repo/aur/PKGBUILD.0"
        if [[ ${#source[@]} -ne 1 || "${source[0]}" != "$pkgname-$pkgver.tar.gz" ]]; then
            echo "release PKGBUILD.0 should have one source entry"
            printf '%s\n' "${source[@]}"
            exit 1
        fi
    ) || exit 1

    for kept in go.mod cmd/tool/go.mod; do
        if grep -Fqx "$kept export-ignore" "$go_repo/.gitattributes"; then
            echo "$kept was wrongly marked export-ignore"
            exit 1
        fi
    done
    for ignored in extra.mod doc/go.mod aur/go.mod .cache/go.mod .go.mod; do
        grep -Fqx "$ignored export-ignore" "$go_repo/.gitattributes" || {
            echo "$ignored was not marked export-ignore"
            exit 1
        }
    done

    stamp_before=$(pkgbuild0_input_stamp)
    printf '\n// updated\n' >> "$go_repo/go.mod"
    git -C "$go_repo" add go.mod
    stamp_after=$(pkgbuild0_input_stamp)
    [[ "$stamp_before" != "$stamp_after" ]] || { echo "go.mod edit did not invalidate pkgbuild0_input_stamp"; exit 1; }
); then
    echo "Go go.mod source filter regression test failed"
    cat "$tmp/go.err" 2>/dev/null || true
    exit 1
fi

# lib/project-metadata.sh rejects direct execution and exposes inspection helpers standalone and via gen-pkgbuild0.sh.
if bash "$ROOT/lib/project-metadata.sh" >"$tmp/meta-direct.out" 2>"$tmp/meta-direct.err"; then
    echo "direct execution of lib/project-metadata.sh should exit non-zero"
    exit 1
fi
grep -Fq 'This script is a library and must be sourced, not executed.' "$tmp/meta-direct.err" || {
    echo "lib/project-metadata.sh direct execution guard message missing"
    cat "$tmp/meta-direct.err"
    exit 1
}

(
    set -euo pipefail
    unset PKG_KEEP
    source "$ROOT/lib/project-metadata.sh"
    for fn in detect_license_spdx filter_pkgbuild_sources generate_gitattributes_from_filter detect_buildsys project_compiles default_check_command pkgbuild0_input_stamp makefile_default_goal detect_project_version detect_project_description detect_project_license is_base_devel_package; do
        declare -F "$fn" >/dev/null || { echo "missing $fn in standalone project-metadata.sh"; exit 1; }
    done
    is_base_devel_package gcc || { echo "is_base_devel_package missed gcc"; exit 1; }
    ! is_base_devel_package ripgrep || { echo "is_base_devel_package accepted ripgrep"; exit 1; }
    echo "main.c" | filter_pkgbuild_sources | grep -Fqx "main.c" || { echo "standalone filter_pkgbuild_sources failed"; exit 1; }
) || exit 1

(
    set -euo pipefail
    export LIB_INSTALL_DIR="$ROOT/lib"
    source "$ROOT/lib/gen-pkgbuild0.sh"
    for fn in gen_pkgbuild0 gen_pkgbuild_header generate_install_scriptlet detect_project_version filter_pkgbuild_sources; do
        declare -F "$fn" >/dev/null || { echo "missing $fn after sourcing gen-pkgbuild0.sh"; exit 1; }
    done
) || exit 1

# Detect unknown build systems without counting aur/ and .git
# A repo with only main.c and no manifest generates BUILDSYS "unknown" (placeholder build steps)
# A repo with only a non-executable *.py still counts as a script payload (BUILDSYS "none")
unknown_prune_repo="$tmp/unknown-prune-repo"
mkdir -p "$unknown_prune_repo/aur"
printf 'int main() { return 0; }\n' > "$unknown_prune_repo/main.c"
git -C "$unknown_prune_repo" init -q
git -C "$unknown_prune_repo" config user.email "t@example.com"
git -C "$unknown_prune_repo" config user.name "t"
git -C "$unknown_prune_repo" remote add origin "https://example.com/testuser/unknownprune.git"
git -C "$unknown_prune_repo" add main.c
git -C "$unknown_prune_repo" commit -q -m init

# First test: only main.c -> unknown
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$unknown_prune_repo"
    export AUR_DIR="$unknown_prune_repo/aur"
    export PKGNAME=unknownprune
    export AURGEN_ERROR_LOG="$tmp/err-prune1.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 > "$tmp/out-prune1.log" 2> "$tmp/err-prune1.log" || exit 1
    grep -F -q "(unknown)" "$tmp/out-prune1.log" || grep -F -q "placeholder build steps" "$tmp/err-prune1.log"
) ; then
    echo "Failed: repo with only main.c did not result in BUILDSYS unknown"
    cat "$tmp/out-prune1.log"
    cat "$tmp/err-prune1.log"
    exit 1
fi

# Second test: add non-executable .py -> none (script payload)
printf 'print("hello")\n' > "$unknown_prune_repo/main.py"
chmod -x "$unknown_prune_repo/main.py"
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$unknown_prune_repo"
    export AUR_DIR="$unknown_prune_repo/aur"
    export PKGNAME=unknownprune
    export AURGEN_ERROR_LOG="$tmp/err-prune2.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 > "$tmp/out-prune2.log" 2> "$tmp/err-prune2.log" || exit 1
    grep -F -q "(no-build project)" "$tmp/out-prune2.log"
) ; then
    echo "Failed: repo with non-executable .py did not result in BUILDSYS none"
    cat "$tmp/out-prune2.log"
    cat "$tmp/err-prune2.log"
    exit 1
fi

# Third test: verify aur/aurgen.install.yaml doesn't trigger has_configs
rm "$unknown_prune_repo/main.py"
# We already have aur/aurgen.install.yaml because gen_pkgbuild0 creates it.
if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$unknown_prune_repo"
    export AUR_DIR="$unknown_prune_repo/aur"
    export PKGNAME=unknownprune
    export AURGEN_ERROR_LOG="$tmp/err-prune3.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 > "$tmp/out-prune3.log" 2> "$tmp/err-prune3.log" || exit 1
    grep -F -q "(unknown)" "$tmp/out-prune3.log" || grep -F -q "placeholder build steps" "$tmp/err-prune3.log"
) ; then
    echo "Failed: repo with main.c and aur/aurgen.install.yaml resulted in BUILDSYS none (aur/ not pruned)"
    cat "$tmp/out-prune3.log"
    cat "$tmp/err-prune3.log"
    exit 1
fi

# Fourth test: README.md + src/main.c gives unknown (compiled sources not overridden by docs)
compiled_doc_repo="$tmp/compiled-doc-repo"
mkdir -p "$compiled_doc_repo/src" "$compiled_doc_repo/aur"
printf '# project\n' > "$compiled_doc_repo/README.md"
printf 'int main() { return 0; }\n' > "$compiled_doc_repo/src/main.c"
git -C "$compiled_doc_repo" init -q
git -C "$compiled_doc_repo" config user.email "t@example.com"
git -C "$compiled_doc_repo" config user.name "t"
git -C "$compiled_doc_repo" remote add origin "https://example.com/testuser/compiledoc.git"
git -C "$compiled_doc_repo" add README.md src/main.c
git -C "$compiled_doc_repo" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$compiled_doc_repo"
    export AUR_DIR="$compiled_doc_repo/aur"
    export PKGNAME=compiledoc
    export AURGEN_ERROR_LOG="$tmp/err-compiledoc.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 > "$tmp/out-compiledoc.log" 2> "$tmp/err-compiledoc.log" || exit 1
    grep -F -q "placeholder build steps" "$tmp/err-compiledoc.log" || grep -F -q "(unknown)" "$tmp/out-compiledoc.log"
    ! grep -F -q "(no-build project)" "$tmp/out-compiledoc.log"
) ; then
    echo "Failed: repo with README.md + src/main.c did not result in BUILDSYS unknown"
    cat "$tmp/out-compiledoc.log"
    cat "$tmp/err-compiledoc.log"
    exit 1
fi

# Fifth test: bin/app.py with --maxdepth 1 still gives none (MAXDEPTH does not alter classification)
maxdepth_script_repo="$tmp/maxdepth-script-repo"
mkdir -p "$maxdepth_script_repo/bin" "$maxdepth_script_repo/aur"
printf 'print("hello")\n' > "$maxdepth_script_repo/bin/app.py"
git -C "$maxdepth_script_repo" init -q
git -C "$maxdepth_script_repo" config user.email "t@example.com"
git -C "$maxdepth_script_repo" config user.name "t"
git -C "$maxdepth_script_repo" remote add origin "https://example.com/testuser/maxdepthscript.git"
git -C "$maxdepth_script_repo" add bin/app.py
git -C "$maxdepth_script_repo" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$maxdepth_script_repo"
    export AUR_DIR="$maxdepth_script_repo/aur"
    export PKGNAME=maxdepthscript
    export AURGEN_ERROR_LOG="$tmp/err-maxdepth.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    export MAXDEPTH=1
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    gen_pkgbuild0 > "$tmp/out-maxdepth.log" 2> "$tmp/err-maxdepth.log" || exit 1
    grep -F -q "(no-build project)" "$tmp/out-maxdepth.log"
) ; then
    echo "Failed: repo with bin/app.py and MAXDEPTH=1 did not result in BUILDSYS none"
    cat "$tmp/out-maxdepth.log"
    cat "$tmp/err-maxdepth.log"
    exit 1
fi

# detect_project_description must query gh from the given root, not the caller cwd.
desc_root="$tmp/desc-root"
other_cwd="$tmp/other-cwd"
gh_cwd_stub="$tmp/gh-cwd"
mkdir -p "$desc_root" "$other_cwd" "$gh_cwd_stub"
cat > "$gh_cwd_stub/gh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
    pwd
    exit 0
fi
exit 0
EOF
chmod +x "$gh_cwd_stub/gh"
if ! (
    set -euo pipefail
    export PATH="$gh_cwd_stub:$PATH"
    export AURGEN_ERROR_LOG="$tmp/err-desc-cwd.log"
    # shellcheck source=../lib/project-metadata.sh
    source "$ROOT/lib/project-metadata.sh"
    mapfile -t desc_lines < <(cd "$other_cwd" && detect_project_description "$desc_root" somepkg 1)
    [[ "${desc_lines[0]}" == github ]]
    [[ "$(realpath "${desc_lines[1]}")" == "$(realpath "$desc_root")" ]]
); then
    echo "detect_project_description queried gh outside the given root"
    exit 1
fi
