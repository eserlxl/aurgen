#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.
#
# Shipped scripts contribute depends: the interpreter, mapped commands, and
# configured entries. Unmapped commands, the stdlib, and tests/doc trees do not.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-runtime-deps.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
# Scratch-repo commits must never sign with the user's key (commit.gpgsign in ~/.gitconfig).
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

fail() {
    echo "$1"
    exit 1
}

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$stub" "$repo/bin" "$repo/tests" "$repo/test" "$repo/docs" "$repo/doc" "$repo/aur"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"

# Inside a case arm, $(...) and subshells run; only the arm's pattern is stripped.
# An array, a function definition, an =~ group and (( )) are not commands.
repo9="$tmp/repo-case-subshell"
mkdir -p "$repo9"
cat >| "$repo9/run.sh" <<'EOF'
#!/bin/bash
case "$1" in
    fetch)
        out=$(wget https://example.com)
        (cd dir && tar xf a.tar)
        ;;
    (a|b)
        ;;
esac
EOF
cat >| "$repo9/shapes.sh" <<'EOF'
#!/bin/bash
deps=(jq tar)
sort() { :; }
build() {
    make
}
if [[ $f =~ (gzip|xz) ]]; then :; fi
(( i++ ))
(( (i++) | (j++) ))
if [[ $f =~ (gzip|(xz)) ]]; then :; fi
if [[ $f =~ (gzip|tar|xz) ]]; then :; fi
if [[ $f =~ (gzip|(tar|xz)) ]]; then :; fi
if [[ $f =~ [[:space:]](gzip|tar|xz) ]]; then :; fi
if [[ $f =~ [[:space:]](gzip|(tar|xz)) ]]; then :; fi
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo9/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q wget <<< "$cmds" || exit 1
    grep -F -x -q cd <<< "$cmds" || exit 1
    grep -F -x -q tar <<< "$cmds" || exit 1
    ! grep -F -x -q fetch <<< "$cmds" || exit 1
    ! grep -F -x -q a <<< "$cmds" || exit 1
    ! grep -F -x -q b <<< "$cmds" || exit 1
    plain="$(_shell_commands "$repo9/shapes.sh")" || exit 1
    printf '%s\n' "$plain"
    [[ "$plain" == make ]] || exit 1
    exit 0
) >|"$tmp/src9.out" 2>|"$tmp/src9.err"; then
    echo 'commands inside $(...) or subshells in a case branch were lost, or patterns were kept'
    cat "$tmp/src9.out"
    cat "$tmp/src9.err"
    exit 1
fi

# Test operands hide regex separators, but substitution and pipeline bodies run.
cat >| "$tmp/test-substitutions.sh" <<'EOF'
[[ $(printf x | jq .) =~ (gzip|tar|xz) ]]
[[ "$(printf x | sed -n p)" =~ (gzip|(tar|xz)) ]]
[[ `printf x | curl -T -` =~ (gzip|tar|xz) ]]
[[ "`printf x | wget -i -`" =~ (gzip|(tar|xz)) ]]
printf x | rsync host:
out=$(date | sort)
out=`uname | uniq`
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$tmp/test-substitutions.sh")" || exit 1
    [[ "$cmds" == $'printf\njq\nprintf\nsed\nprintf\ncurl\nprintf\nwget\nprintf\nrsync\ndate\nsort\nuname\nuniq' ]] || exit 1
    exit 0
) >|"$tmp/src-test-substitutions.out" 2>|"$tmp/src-test-substitutions.err"; then
    echo "test operands became commands or substitutions and pipelines were lost"
    cat "$tmp/src-test-substitutions.out"
    cat "$tmp/src-test-substitutions.err"
    exit 1
fi

# A closing subshell parenthesis is not part of a command or guarded name.
cat >| "$tmp/subshell.sh" <<'EOF'
(cd /tmp && jq)
if (command -v tar); then tar xf a; fi
( (jq))
:; (jq)
: | (jq)
: && (jq)
: || (jq)
(
    jq)
(type -p tar)
(hash tar)
(which tar)
! (jq)
{ (jq); }
if ! (command -v jq); then :; fi
if false; then :; elif ! (command -v jq); then :; fi
while ! (command -v jq); do :; done
until ! (command -v jq); do :; done
for d in a; do (cd "$d" && make); done
if true; then (tar xf a); else (gzip); fi
if true; then (xz); fi
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$tmp/subshell.sh")" || exit 1
    [[ "$(grep -F -x -c jq <<< "$cmds")" == 9 ]] || exit 1
    [[ "$(grep -F -x -c tar <<< "$cmds")" == 2 ]] || exit 1
    grep -F -x -q make <<< "$cmds" || exit 1
    grep -F -x -q gzip <<< "$cmds" || exit 1
    grep -F -x -q xz <<< "$cmds" || exit 1
    cmds="$(_shell_guarded_commands "$tmp/subshell.sh")" || exit 1
    [[ "$cmds" == $'tar\ntar\ntar\ntar\njq\njq\njq\njq' ]] || exit 1
    exit 0
) >|"$tmp/src-subshell.out" 2>|"$tmp/src-subshell.err"; then
    echo "closing subshell parenthesis hid a command or guarded name"
    cat "$tmp/src-subshell.out"
    cat "$tmp/src-subshell.err"
    exit 1
fi

cat > "$repo/bin/run.sh" <<'EOF'
#!/bin/bash
find . -type f
for file in *; do echo "$file"; done
sed -n '1p' hostname
systemctl status example.service
EOF

cat > "$repo/bin/app.py" <<'EOF'
#!/usr/bin/env python3
import json
import requests
EOF

# Not shipped: a mapped command here must not become a runtime dependency.
cat > "$repo/tests/hidden.sh" <<'EOF'
#!/bin/bash
curl https://example.invalid
EOF
cat > "$repo/test/hidden.sh" <<'EOF'
#!/bin/bash
wget https://example.invalid
EOF
cat > "$repo/docs/hidden.sh" <<'EOF'
#!/bin/bash
jq .
EOF
cat > "$repo/doc/hidden.sh" <<'EOF'
#!/bin/bash
tar -cf out.tar hostname
EOF

cat > "$repo/aur/aurgen.install.yaml" <<'EOF'
package:
  depends:
    - systemd>=249
    - git
EOF

git -C "$repo" init -q
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
git -C "$repo" add bin/run.sh bin/app.py tests/hidden.sh test/hidden.sh docs/hidden.sh doc/hidden.sh
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
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen.out" 2>"$tmp/gen.err"; then
    echo "gen_pkgbuild0 failed"
    cat "$tmp/gen.err"
    exit 1
fi

pkgbuild="$repo/aur/PKGBUILD.0"
[[ -f "$pkgbuild" ]] || fail "PKGBUILD.0 was not written"

expected="depends=('systemd>=249' 'git' 'bash' 'findutils' 'python' 'python-requests' 'sed')"
if ! grep -F -x -q "$expected" "$pkgbuild"; then
    echo "depends missing interpreter, mapped commands, or configured entries"
    cat "$pkgbuild"
    exit 1
fi

if ! bash -n "$pkgbuild"; then
    echo "bash -n failed"
    cat "$pkgbuild"
    exit 1
fi

# errexit does not apply inside an if condition, so every check exits explicitly.
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild" || exit 1
    # Configured entries first, then the detected set: interpreters, the packages of
    # find and sed, and the mapped third-party import.
    [[ "${depends[0]}" == "systemd>=249" ]] || exit 1
    [[ "${depends[1]}" == "git" ]] || exit 1
    [[ "${depends[*]:2}" == "bash findutils python python-requests sed" ]] || exit 1
    for dep in "${depends[@]}"; do
        case "$dep" in
            file|find|json|python-json|curl|wget|jq|tar|systemd) exit 1 ;;
        esac
    done
    for dep in "${makedepends[@]}"; do
        base="${dep%%>=*}"
        base="${base%%<=*}"
        base="${base%%=*}"
        base="${base%%>*}"
        base="${base%%<*}"
        [[ "$base" == "bash" ]] && exit 1
    done
    exit 0
) >"$tmp/src.out" 2>"$tmp/src.err"; then
    echo "sourced depends lost a runtime package or kept an unmapped one"
    cat "$tmp/src.err"
    cat "$pkgbuild"
    exit 1
fi

# The install scan runs make install inside bubblewrap and is skipped without it
# (detect-deps warns), so these checks would fail or pass vacuously there.
if command -v bwrap >/dev/null 2>&1; then
# An install target ships only what `make install` copies. Scripts left out of
# that tree, awk program text, and presence checks are not hard depends.
repo2="$tmp/repo-install"
mkdir -p "$repo2/bin" "$repo2/aur"
cat > "$repo2/bin/tool" <<'EOF'
#!/bin/bash
find . -type f
awk '
{
    close(file)
    file
}
' "$1"
if command -v notify-send >/dev/null 2>&1; then
    notify-send done
fi
EOF
cat > "$repo2/test_tool.sh" <<'EOF'
#!/bin/bash
npm install
EOF
# The second recipe line writes outside DESTDIR; the sandbox must keep that from landing.
printf '%s\n' 'install:' $'\tinstall -Dm755 bin/tool "$(DESTDIR)$(PREFIX)/bin/tool"' \
    $'\t-touch '"$tmp/escaped" $'\tsleep 9.271 >/dev/null 2>&1 &' > "$repo2/Makefile"
cat > "$repo2/aur/aurgen.install.yaml" <<'EOF'
package:
  name: tool
EOF
git -C "$repo2" init -q
git -C "$repo2" config user.email "t@example.com"
git -C "$repo2" config user.name "t"
git -C "$repo2" remote add origin "https://example.com/testuser/testpkg.git"
git -C "$repo2" add bin/tool test_tool.sh Makefile
git -C "$repo2" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo2"
    export AUR_DIR="$repo2/aur"
    export PKGNAME=testpkg
    export AURGEN_ERROR_LOG="$tmp/err2.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen2.out" 2>"$tmp/gen2.err"; then
    echo "install-target gen_pkgbuild0 failed"
    cat "$tmp/gen2.err"
    exit 1
fi

pkgbuild2="$repo2/aur/PKGBUILD.0"
[[ -f "$pkgbuild2" ]] || fail "install-target PKGBUILD.0 was not written"
[[ ! -e "$tmp/escaped" ]] || fail "make install wrote outside its sandbox"
# A process the recipe leaves in the background must die with the sandbox.
if pgrep -x -f 'sleep 9.271' >/dev/null; then
    pkill -x -f 'sleep 9.271' || true
    fail "a background process from make install outlived the sandbox"
fi
if ! grep -F -q '[detect_runtime_deps] source: installed files' "$tmp/gen2.err"; then
    echo "install scan was not the dependency source"
    cat "$tmp/gen2.err"
    exit 1
fi
if ! grep -F -q '[detect_runtime_deps] optdepends suggestion: libnotify notify-send' "$tmp/gen2.err"; then
    echo "notify-send was not suggested as an optdepend"
    cat "$tmp/gen2.err"
    exit 1
fi
# shellcheck disable=SC1090
if ! (
    source "$pkgbuild2" || exit 1
    [[ "${depends[*]}" == "bash findutils gawk" ]] || exit 1
    for dep in "${depends[@]}"; do
        case "$dep" in
            npm|file|libnotify) exit 1 ;;
        esac
    done
    exit 0
) >"$tmp/src2.out" 2>"$tmp/src2.err"; then
    echo "installed files kept npm, file, or libnotify, or lost a shipped command"
    cat "$tmp/src2.err"
    cat "$pkgbuild2"
    exit 1
fi
# No pipe: under pipefail an early grep -q exit can SIGPIPE find and hide the leak.
leaked=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'aurgen-rtdep-*' -print)
if [[ -n "$leaked" ]]; then
    echo "runtime dependency temp dir was left behind"
    echo "$leaked"
    exit 1
fi

else
    echo "SKIP: install-scan checks need bubblewrap (bwrap)"
fi

# "$(...)" and backticks run; the words of a plain double-quoted string do not.
repo3="$tmp/repo-subst"
mkdir -p "$repo3/bin" "$repo3/aur"
cat > "$repo3/bin/fetch.sh" <<'EOF'
#!/bin/bash
response="$(curl https://example.com)"
msg="$(jq -r .a f)"
stamp="`date -u`"
STAMP=x"$(date)" git status
EOF
# Copy rules reach files at any depth; this one is six levels below bin/.
mkdir -p "$repo3/bin/a/b/c/d/e"
printf '#!/bin/bash\nrsync -a src dst\n' > "$repo3/bin/a/b/c/d/e/deep.sh"
cat > "$repo3/aur/aurgen.install.yaml" <<'EOF'
package:
  name: fetch
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []
EOF
git -C "$repo3" init -q
git -C "$repo3" config user.email "t@example.com"
git -C "$repo3" config user.name "t"
git -C "$repo3" remote add origin "https://example.com/testuser/fetch.git"
git -C "$repo3" add bin/fetch.sh bin/a/b/c/d/e/deep.sh
git -C "$repo3" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo3"
    export AUR_DIR="$repo3/aur"
    export PKGNAME=fetch
    export AURGEN_ERROR_LOG="$tmp/err3.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen3.out" 2>"$tmp/gen3.err"; then
    echo "quoted-substitution gen_pkgbuild0 failed"
    cat "$tmp/gen3.err"
    exit 1
fi

pkgbuild3="$repo3/aur/PKGBUILD.0"
[[ -f "$pkgbuild3" ]] || fail "substitution PKGBUILD.0 was not written"
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild3" || exit 1
    [[ "${depends[*]}" == "bash coreutils curl git jq rsync" ]] || exit 1
    exit 0
) >"$tmp/src3.out" 2>"$tmp/src3.err"; then
    echo "commands inside double-quoted substitutions were not dependencies"
    cat "$tmp/src3.err"
    cat "$pkgbuild3"
    exit 1
fi

repo4="$tmp/repo-quoted"
mkdir -p "$repo4/bin" "$repo4/aur"
cat > "$repo4/bin/mention.sh" <<'EOF'
#!/bin/bash
echo "curl is not run here"
EOF
cat > "$repo4/aur/aurgen.install.yaml" <<'EOF'
package:
  name: mention
EOF
git -C "$repo4" init -q
git -C "$repo4" config user.email "t@example.com"
git -C "$repo4" config user.name "t"
git -C "$repo4" remote add origin "https://example.com/testuser/mention.git"
git -C "$repo4" add bin/mention.sh
git -C "$repo4" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo4"
    export AUR_DIR="$repo4/aur"
    export PKGNAME=mention
    export AURGEN_ERROR_LOG="$tmp/err4.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen4.out" 2>"$tmp/gen4.err"; then
    echo "quoted-text gen_pkgbuild0 failed"
    cat "$tmp/gen4.err"
    exit 1
fi

pkgbuild4="$repo4/aur/PKGBUILD.0"
[[ -f "$pkgbuild4" ]] || fail "quoted-text PKGBUILD.0 was not written"
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild4" || exit 1
    [[ "${depends[*]}" == "bash" ]] || exit 1
    for dep in "${depends[@]}"; do
        [[ "$dep" == curl ]] && exit 1
    done
    exit 0
) >"$tmp/src4.out" 2>"$tmp/src4.err"; then
    echo "a word inside double quotes was detected as a command"
    cat "$tmp/src4.err"
    cat "$pkgbuild4"
    exit 1
fi

# Case-arm patterns and here-document bodies are not commands. A command after
# the pattern and a command after the here-document still are.
repo5="$tmp/repo-case-heredoc"
mkdir -p "$repo5/bin" "$repo5/aur"
cat > "$repo5/bin/arms.sh" <<'SCRIPT'
#!/bin/bash
case "$x" in gcc|sudo|which) printf ok ;; esac
case "$x" in
a) curl -s x ;;
esac
cat <<'EOF'
npm install
cmake -B build
EOF
cat <<EOF
go build
EOF
jq -n .
n="$((10#08 + 1))"
list=()
printf '%s\n' "$n" "${list[@]}" | xz -c
words=(
    linux gnu
    sudo
)
local -a more=(
    npm
)
SCRIPT
cat > "$repo5/aur/aurgen.install.yaml" <<'EOF'
package:
  name: arms
EOF
git -C "$repo5" init -q
git -C "$repo5" config user.email "t@example.com"
git -C "$repo5" config user.name "t"
git -C "$repo5" remote add origin "https://example.com/testuser/arms.git"
git -C "$repo5" add bin/arms.sh
git -C "$repo5" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo5"
    export AUR_DIR="$repo5/aur"
    export PKGNAME=arms
    export AURGEN_ERROR_LOG="$tmp/err5.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen5.out" 2>"$tmp/gen5.err"; then
    echo "case/heredoc gen_pkgbuild0 failed"
    cat "$tmp/gen5.err"
    exit 1
fi

pkgbuild5="$repo5/aur/PKGBUILD.0"
[[ -f "$pkgbuild5" ]] || fail "case/heredoc PKGBUILD.0 was not written"
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild5" || exit 1
    [[ "${depends[*]}" == "bash coreutils curl jq xz" ]] || exit 1
    for dep in "${depends[@]}"; do
        case "$dep" in
            gcc|sudo|which|npm|cmake|go|linux) exit 1 ;;
        esac
    done
    exit 0
) >"$tmp/src5.out" 2>"$tmp/src5.err"; then
    echo "case patterns or heredoc bodies became runtime dependencies"
    cat "$tmp/src5.err"
    cat "$pkgbuild5"
    exit 1
fi

# << inside $(( )) or (( )) is a shift, not a here-document: the lines after it still run.
repo6="$tmp/repo-shift"
mkdir -p "$repo6/bin" "$repo6/aur"
cat > "$repo6/bin/shift.sh" <<'EOF'
#!/bin/bash
n=3
mask=$((1<<n))
(( mask << 1 ))
curl https://example.com
EOF
cat > "$repo6/aur/aurgen.install.yaml" <<'EOF'
package:
  name: shift
EOF
git -C "$repo6" init -q
git -C "$repo6" config user.email "t@example.com"
git -C "$repo6" config user.name "t"
git -C "$repo6" remote add origin "https://example.com/testuser/shift.git"
git -C "$repo6" add bin/shift.sh
git -C "$repo6" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo6"
    export AUR_DIR="$repo6/aur"
    export PKGNAME=shift
    export AURGEN_ERROR_LOG="$tmp/err6.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen6.out" 2>"$tmp/gen6.err"; then
    echo "arithmetic-shift gen_pkgbuild0 failed"
    cat "$tmp/gen6.err"
    exit 1
fi
pkgbuild6="$repo6/aur/PKGBUILD.0"
[[ -f "$pkgbuild6" ]] || fail "arithmetic-shift PKGBUILD.0 was not written"
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild6" || exit 1
    [[ " ${depends[*]} " == *" curl "* ]] || exit 1
    exit 0
) >"$tmp/src6.out" 2>"$tmp/src6.err"; then
    echo "an arithmetic << hid the commands after it"
    cat "$pkgbuild6"
    exit 1
fi

# Quoted, empty, and keyword-preceded assignments still leave the command after them visible.
repo7="$tmp/repo-assign"
mkdir -p "$repo7/bin" "$repo7/aur"
cat > "$repo7/bin/assign.sh" <<'EOF'
#!/bin/bash
DESTDIR="$pkgdir" cmake --install build
IFS= read -r line
if LC_ALL=C grep -q pat file; then :; fi
EOF
cat > "$repo7/aur/aurgen.install.yaml" <<'EOF'
package:
  name: assign
EOF
git -C "$repo7" init -q
git -C "$repo7" config user.email "t@example.com"
git -C "$repo7" config user.name "t"
git -C "$repo7" remote add origin "https://example.com/testuser/assign.git"
git -C "$repo7" add bin/assign.sh
git -C "$repo7" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo7"
    export AUR_DIR="$repo7/aur"
    export PKGNAME=assign
    export AURGEN_ERROR_LOG="$tmp/err7.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen7.out" 2>"$tmp/gen7.err"; then
    echo "assignment-prefix gen_pkgbuild0 failed"
    cat "$tmp/gen7.err"
    exit 1
fi
pkgbuild7="$repo7/aur/PKGBUILD.0"
[[ -f "$pkgbuild7" ]] || fail "assignment-prefix PKGBUILD.0 was not written"
# shellcheck disable=SC1090,SC2154
if ! (
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo7/bin/assign.sh")" || exit 1
    grep -F -x -q cmake <<< "$cmds" || exit 1
    grep -F -x -q grep <<< "$cmds" || exit 1
    source "$pkgbuild7" || exit 1
    [[ "${depends[*]}" == "bash cmake grep" ]] || exit 1
    exit 0
) >"$tmp/src7.out" 2>"$tmp/src7.err"; then
    echo "quoted, empty, or keyword-preceded assignments hid the commands after them"
    cat "$tmp/src7.err"
    cat "$pkgbuild7"
    exit 1
fi

# An unquoted $(...) runs, and so does the command after its closing ")".
repo8="$tmp/repo-unquoted-subst"
mkdir -p "$repo8"
cat > "$repo8/run.sh" <<'EOF'
#!/bin/bash
cores=$(nproc)
STAMP=$(date) git status
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo8/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q nproc <<< "$cmds" || exit 1
    grep -F -x -q date <<< "$cmds" || exit 1
    grep -F -x -q git <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src8.out" 2>"$tmp/src8.err"; then
    echo "unquoted command substitutions hid their command and the command after them"
    cat "$tmp/src8.out"
    cat "$tmp/src8.err"
    exit 1
fi

# The ")" that closes a multi-line array in a case branch ends the array, so
# commands after esac are still scanned.
repo10="$tmp/repo-case-array"
mkdir -p "$repo10"
cat > "$repo10/run.sh" <<'EOF'
#!/bin/bash
case "$1" in
    a)
        args=(
            --verbose
        )
        ;;
esac
jq .
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo10/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    [[ "$cmds" == jq ]] || exit 1
    exit 0
) >"$tmp/src10.out" 2>"$tmp/src10.err"; then
    echo "a multi-line array in a case branch hid the commands after it"
    cat "$tmp/src10.out"
    cat "$tmp/src10.err"
    exit 1
fi

# An escaped heredoc delimiter (<<\EOF) is queued and delimiter names with
# dashes or dots are not cut short.
repo11="$tmp/repo-heredoc-delims"
mkdir -p "$repo11"
cat > "$repo11/run.sh" <<'SCRIPT'
cat <<\EOF
cmake -B build
EOF
cat <<'END-MSG'
hello
END-MSG
wget https://example.com
SCRIPT

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo11/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q wget <<< "$cmds" || exit 1
    ! grep -F -x -q cmake <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src11.out" 2>"$tmp/src11.err"; then
    echo "heredoc body was scanned as a command or dashed delimiter failed to close"
    cat "$tmp/src11.out"
    cat "$tmp/src11.err"
    exit 1
fi

# Quoted and bare copy-rule excludes leave matching subtrees out of the runtime scan.
repo12="$tmp/repo-quoted-exclude"
mkdir -p "$repo12/bin/test" "$repo12/bin/temp" "$repo12/aur"
cat > "$repo12/bin/main.sh" <<'EOF'
#!/bin/bash
curl https://example.com
EOF
cat > "$repo12/bin/test/check.sh" <<'EOF'
#!/bin/bash
wget https://example.com
EOF
cat > "$repo12/bin/temp/dev.sh" <<'EOF'
#!/bin/bash
jq .
EOF
cat > "$repo12/aur/aurgen.install.yaml" <<'EOF'
package:
  name: quoted-exclude
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: [test, "temp"]
EOF
git -C "$repo12" init -q
git -C "$repo12" config user.email "t@example.com"
git -C "$repo12" config user.name "t"
git -C "$repo12" remote add origin "https://example.com/testuser/quoted-exclude.git"
git -C "$repo12" add bin/main.sh bin/test/check.sh bin/temp/dev.sh
git -C "$repo12" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo12"
    export AUR_DIR="$repo12/aur"
    export PKGNAME=quoted-exclude
    export AURGEN_ERROR_LOG="$tmp/err12.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen12.out" 2>"$tmp/gen12.err"; then
    echo "quoted-exclude gen_pkgbuild0 failed"
    cat "$tmp/gen12.err"
    exit 1
fi

pkgbuild12="$repo12/aur/PKGBUILD.0"
[[ -f "$pkgbuild12" ]] || fail "quoted-exclude PKGBUILD.0 was not written"
if ! grep -F 'copy_tree' "$pkgbuild12" | grep -F -q -- "'test' 'temp'"; then
    echo "copy_tree did not receive unquoted test and temp exclusions"
    cat "$pkgbuild12"
    exit 1
fi
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild12" || exit 1
    [[ "${depends[*]}" == "bash curl" ]] || exit 1
    for dep in "${depends[@]}"; do
        case "$dep" in
            jq|wget) exit 1 ;;
        esac
    done
    exit 0
) >"$tmp/src12.out" 2>"$tmp/src12.err"; then
    echo "quoted copy-rule exclude was still scanned for runtime dependencies"
    cat "$tmp/src12.err"
    cat "$pkgbuild12"
    exit 1
fi

# A case statement inside $(...) keeps its branch commands visible and its patterns out.
repo13="$tmp/repo-subst-case"
mkdir -p "$repo13"
cat > "$repo13/run.sh" <<'EOF'
#!/bin/bash
result="$(case "$mode" in a) jq . ;; esac)"
plain=$(case "$mode" in (b) tar -cf out.tar f ;; esac)
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo13/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q jq <<< "$cmds" || exit 1
    grep -F -x -q tar <<< "$cmds" || exit 1
    ! grep -F -x -q a <<< "$cmds" || exit 1
    ! grep -F -x -q b <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src13.out" 2>"$tmp/src13.err"; then
    echo "a case statement inside \$(...) hid its branch command or exposed its pattern"
    cat "$tmp/src13.out"
    cat "$tmp/src13.err"
    exit 1
fi

# The word case as an argument does not open a case block, so later commands stay visible.
repo13b="$tmp/repo-subst-case-arg"
mkdir -p "$repo13b"
cat > "$repo13b/run.sh" <<'EOF'
#!/bin/bash
helper="$(printf %s case)"
sed -n 1p f
exec -- tar xf a.tar
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo13b/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q printf <<< "$cmds" || exit 1
    grep -F -x -q sed <<< "$cmds" || exit 1
    grep -F -x -q tar <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src13b.out" 2>"$tmp/src13b.err"; then
    echo "the word case as an argument opened a case block and hid later commands"
    cat "$tmp/src13b.out"
    cat "$tmp/src13b.err"
    exit 1
fi

# exec replaces the shell, so the command after it is the dependency.
# Its options are not commands, and redirections alone add nothing.
repo14="$tmp/repo-exec"
mkdir -p "$repo14"
cat > "$repo14/run.sh" <<'EOF'
#!/bin/bash
exec sed -n 1p f
exec -- tar xf a.tar
exec -c -l -a showname gzip -tf a.tar
exec >log 2>&1
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo14/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q sed <<< "$cmds" || exit 1
    grep -F -x -q tar <<< "$cmds" || exit 1
    grep -F -x -q gzip <<< "$cmds" || exit 1
    ! grep -F -x -q exec <<< "$cmds" || exit 1
    ! grep -F -x -q showname <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src14.out" 2>"$tmp/src14.err"; then
    echo "exec hid the command after it, or a redirection-only exec was kept"
    cat "$tmp/src14.out"
    cat "$tmp/src14.err"
    exit 1
fi

# A quoted heredoc delimiter may contain spaces and closes on its exact line.
repo15="$tmp/repo-heredoc-quoted-spaces"
mkdir -p "$repo15"
cat > "$repo15/run.sh" <<'EOF'
cat <<'END TEXT'
hello
END TEXT
sed -n 1p f
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_commands "$repo15/run.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q sed <<< "$cmds" || exit 1
    ! grep -F -x -q hello <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src15.out" 2>"$tmp/src15.err"; then
    echo "quoted heredoc delimiter with spaces was truncated or failed to close"
    cat "$tmp/src15.out"
    cat "$tmp/src15.err"
    exit 1
fi

# type -p and type -a name an optional tool, same as type -P.
cat > "$tmp/guards.sh" <<'EOF'
#!/bin/bash
type -p jq tar
type -P curl
type -a wget
command -v gzip
EOF

if ! (
    # shellcheck source=../lib/detect-deps.sh
    source "$ROOT/lib/detect-deps.sh" || exit 1
    cmds="$(_shell_guarded_commands "$tmp/guards.sh")" || exit 1
    printf '%s\n' "$cmds"
    grep -F -x -q jq <<< "$cmds" || exit 1
    grep -F -x -q tar <<< "$cmds" || exit 1
    grep -F -x -q curl <<< "$cmds" || exit 1
    grep -F -x -q wget <<< "$cmds" || exit 1
    grep -F -x -q gzip <<< "$cmds" || exit 1
    exit 0
) >"$tmp/src-guards.out" 2>"$tmp/src-guards.err"; then
    echo "type -p, type -P, or type -a was not a presence check"
    cat "$tmp/src-guards.out"
    cat "$tmp/src-guards.err"
    exit 1
fi

# A presence check covers only the script that contains it. An unconditional
# call in another shipped script is still a depend.
repo16="$tmp/repo-guard-scope"
mkdir -p "$repo16/bin" "$repo16/aur"
cat > "$repo16/bin/guard.sh" <<'EOF'
#!/bin/bash
if command -v jq >/dev/null 2>&1; then
    jq .
fi
EOF
cat > "$repo16/bin/report.sh" <<'EOF'
#!/bin/bash
jq .
EOF
cat > "$repo16/aur/aurgen.install.yaml" <<'EOF'
package:
  name: guard-scope
EOF
git -C "$repo16" init -q
git -C "$repo16" config user.email "t@example.com"
git -C "$repo16" config user.name "t"
git -C "$repo16" remote add origin "https://example.com/testuser/guard-scope.git"
git -C "$repo16" add bin/guard.sh bin/report.sh
git -C "$repo16" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo16"
    export AUR_DIR="$repo16/aur"
    export PKGNAME=guard-scope
    export AURGEN_ERROR_LOG="$tmp/err16.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen16.out" 2>"$tmp/gen16.err"; then
    echo "guard-scope gen_pkgbuild0 failed"
    cat "$tmp/gen16.err"
    exit 1
fi

pkgbuild16="$repo16/aur/PKGBUILD.0"
[[ -f "$pkgbuild16" ]] || fail "guard-scope PKGBUILD.0 was not written"
if ! grep -F -q '[detect_runtime_deps] optdepends suggestion: jq jq' "$tmp/gen16.err"; then
    echo "a guarded jq was not kept in the optdepends suggestions"
    cat "$tmp/gen16.err"
    exit 1
fi
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild16" || exit 1
    [[ "${depends[*]}" == "bash jq" ]] || exit 1
    exit 0
) >"$tmp/src16.out" 2>"$tmp/src16.err"; then
    echo "an unconditional jq lost its depend because another script guards jq"
    cat "$tmp/src16.err"
    cat "$pkgbuild16"
    exit 1
fi

# type -p guards the tool in that script, so jq and tar are not hard depends.
repo17="$tmp/repo-type-p"
mkdir -p "$repo17/bin" "$repo17/aur"
cat > "$repo17/bin/tool.sh" <<'EOF'
#!/bin/bash
if type -p jq tar >/dev/null; then
    jq .
    tar xf a.tar
fi
EOF
cat > "$repo17/aur/aurgen.install.yaml" <<'EOF'
package:
  name: type-p-guard
EOF
git -C "$repo17" init -q
git -C "$repo17" config user.email "t@example.com"
git -C "$repo17" config user.name "t"
git -C "$repo17" remote add origin "https://example.com/testuser/type-p-guard.git"
git -C "$repo17" add bin/tool.sh
git -C "$repo17" commit -q -m init

if ! (
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib"
    export PROJECT_ROOT="$repo17"
    export AUR_DIR="$repo17/aur"
    export PKGNAME=type-p-guard
    export AURGEN_ERROR_LOG="$tmp/err17.log"
    export AURGEN_MODE=test
    export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
    export color_enabled=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >"$tmp/gen17.out" 2>"$tmp/gen17.err"; then
    echo "type -p gen_pkgbuild0 failed"
    cat "$tmp/gen17.err"
    exit 1
fi

pkgbuild17="$repo17/aur/PKGBUILD.0"
[[ -f "$pkgbuild17" ]] || fail "type -p PKGBUILD.0 was not written"
# shellcheck disable=SC1090,SC2154
if ! (
    source "$pkgbuild17" || exit 1
    [[ "${depends[*]}" == "bash" ]] || exit 1
    for dep in "${depends[@]}"; do
        [[ "$dep" == jq || "$dep" == tar ]] && exit 1
    done
    exit 0
) >"$tmp/src17.out" 2>"$tmp/src17.err"; then
    echo "type -p jq or tar was kept as a hard depend"
    cat "$tmp/src17.err"
    cat "$pkgbuild17"
    exit 1
fi
