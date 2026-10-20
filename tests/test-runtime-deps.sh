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

fail() {
    echo "$1"
    exit 1
}

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$stub" "$repo/bin" "$repo/tests" "$repo/test" "$repo/docs" "$repo/doc" "$repo/aur"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"

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
if find /tmp -maxdepth 1 -name 'aurgen-rtdep-*' -print | grep -q .; then
    echo "runtime dependency temp dir was left behind"
    find /tmp -maxdepth 1 -name 'aurgen-rtdep-*' -print
    exit 1
fi

# "$(...)" and backticks run; the words of a plain double-quoted string do not.
repo3="$tmp/repo-subst"
mkdir -p "$repo3/bin" "$repo3/aur"
cat > "$repo3/bin/fetch.sh" <<'EOF'
#!/bin/bash
response="$(curl https://example.com)"
msg="$(jq -r .a f)"
stamp="`date -u`"
EOF
cat > "$repo3/aur/aurgen.install.yaml" <<'EOF'
package:
  name: fetch
EOF
git -C "$repo3" init -q
git -C "$repo3" config user.email "t@example.com"
git -C "$repo3" config user.name "t"
git -C "$repo3" remote add origin "https://example.com/testuser/fetch.git"
git -C "$repo3" add bin/fetch.sh
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
    [[ "${depends[*]}" == "bash coreutils curl jq" ]] || exit 1
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
