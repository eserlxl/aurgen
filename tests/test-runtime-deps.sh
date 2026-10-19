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

expected="depends=('systemd>=249' 'git' 'bash' 'python' 'python-requests')"
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
    [[ "${depends[0]}" == "systemd>=249" ]] || exit 1
    [[ "${depends[1]}" == "git" ]] || exit 1
    [[ "${depends[2]}" == "bash" ]] || exit 1
    [[ "${depends[3]}" == "python" ]] || exit 1
    [[ "${depends[4]}" == "python-requests" ]] || exit 1
    for dep in "${depends[@]}"; do
        case "$dep" in
            find|sed|json|python-json|curl|wget|jq|tar|systemd) exit 1 ;;
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
