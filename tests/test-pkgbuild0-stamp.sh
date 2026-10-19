#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-pkgbuild0-stamp.XXXXXX)"
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
    mkdir -p "$repo/aur"
    "$real_git" -C "$repo" init -q -b main
    "$real_git" -C "$repo" config user.email "t@example.com"
    "$real_git" -C "$repo" config user.name "t"
    printf 'hello\n' > "$repo/README.md"
    "$real_git" -C "$repo" add README.md
    "$real_git" -C "$repo" commit -q -m init
    "$real_git" -C "$repo" remote add origin "https://github.com/example/tmpCleaner.git"
}

write_config() {
    local repo="$1"
    local description="$2"
    cat > "$repo/aur/aurgen.install.yaml" <<EOF
package:
  description: ${description}
EOF
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

pkgdesc_of() {
    grep -E '^pkgdesc=' "$1" || true
}

repo="$tmp/repo"
prepare_repo "$repo"
write_config "$repo" "alpha desc"
run_init "$repo" first || fail "first aurgen_init failed" "$tmp/first.err"

pkg="$repo/aur/PKGBUILD.0"
[[ -f "$pkg" ]] || fail "PKGBUILD.0 was not written" "$tmp/first.err"
[[ -f "$repo/aur/.PKGBUILD.0.stamp" ]] || fail "stamp was not written" "$tmp/first.err"
[[ "$(pkgdesc_of "$pkg")" == "pkgdesc='alpha desc'" ]] || fail "first pkgdesc should be alpha desc" "$pkg"
[[ ! -e "$repo/aur/PKGBUILD.0.bak" ]] || fail "first run should not write PKGBUILD.0.bak"

before=$(sha256sum "$pkg")
run_init "$repo" same || fail "unchanged aurgen_init failed" "$tmp/same.err"
after=$(sha256sum "$pkg")
[[ "$before" == "$after" ]] || fail "unchanged config regenerated PKGBUILD.0" "$pkg"
[[ ! -e "$repo/aur/PKGBUILD.0.bak" ]] || fail "unchanged config wrote PKGBUILD.0.bak"

write_config "$repo" "beta desc"
run_init "$repo" changed || fail "aurgen_init after description change failed" "$tmp/changed.err"
[[ "$(pkgdesc_of "$pkg")" == "pkgdesc='beta desc'" ]] || fail "pkgdesc should follow the new description" "$pkg"
[[ -f "$repo/aur/PKGBUILD.0.bak" ]] || fail "changed config should back up PKGBUILD.0"
grep -qF "pkgdesc='alpha desc'" "$repo/aur/PKGBUILD.0.bak" || fail "backup should keep the previous pkgdesc" "$repo/aur/PKGBUILD.0.bak"
grep -qF "backed up as PKGBUILD.0.bak" "$tmp/changed.out" || fail "missing regeneration warning" "$tmp/changed.out"

printf '\n# stamp-header-marker\n' >> "$repo/aur/PKGBUILD.HEADER"
run_init "$repo" header || fail "aurgen_init after header change failed" "$tmp/header.err"
grep -qF 'stamp-header-marker' "$pkg" || fail "changed header should be copied into PKGBUILD.0" "$pkg"
grep -qF "pkgdesc='beta desc'" "$repo/aur/PKGBUILD.0.bak" || fail "header change should back up the previous PKGBUILD.0" "$repo/aur/PKGBUILD.0.bak"

plain="$tmp/plain"
prepare_repo "$plain"
write_config "$plain" "kept desc"
run_init "$plain" plain || fail "stamp-less setup aurgen_init failed" "$tmp/plain.err"
rm -f "$plain/aur/.PKGBUILD.0.stamp"
write_config "$plain" "replaced desc"
run_init "$plain" nostamp || fail "aurgen_init with no stamp failed" "$tmp/nostamp.err"
[[ "$(pkgdesc_of "$plain/aur/PKGBUILD.0")" == "pkgdesc='kept desc'" ]] || fail "stamp-less PKGBUILD.0 was regenerated" "$plain/aur/PKGBUILD.0"
[[ ! -e "$plain/aur/PKGBUILD.0.bak" ]] || fail "stamp-less PKGBUILD.0 was backed up"
[[ ! -e "$plain/aur/.PKGBUILD.0.stamp" ]] || fail "stamp-less PKGBUILD.0 gained a stamp"
