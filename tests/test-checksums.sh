#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
# Scratch-repo commits must never sign with the user's key (commit.gpgsign in ~/.gitconfig).
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/updpkgsums" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$stub/updpkgsums"
cat > "$stub/gh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$stub/gh"

write_pkgbuild() {
    local dest="$1"
    local source_entry="$2"
    cat > "$dest" <<EOF
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=("${source_entry}")
b2sums=('SKIP')
EOF
}

init_git_repo() {
    local repo="$1"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    printf 'x\n' > "$repo/payload.txt"
    git -C "$repo" add payload.txt
    git -C "$repo" commit -q -m init
    write_pkgbuild "$repo/aur/PKGBUILD.0" "https://example.com/demo-1.0.0.tar.gz"
}

source_libs() {
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
}

fail() {
    echo "$1"
    exit 1
}

# updpkgsums failure must propagate for a tarball source.
(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/unit"
    export PKGBUILD="$tmp/unit/aur/PKGBUILD"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export color_enabled=0
    export dry_run=0
    mkdir -p "$tmp/unit/aur"
    write_pkgbuild "$PKGBUILD" "https://example.com/demo-1.0.0.tar.gz"
    source_libs
    update_checksums
)
status=$?
if (( status == 0 )); then
    fail "update_checksums should fail when updpkgsums fails for a tarball"
fi

# Dry-run keeps SKIP and does not treat the stub failure as fatal.
(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/dry"
    export PKGBUILD="$tmp/dry/aur/PKGBUILD"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export color_enabled=0
    export dry_run=1
    mkdir -p "$tmp/dry/aur"
    write_pkgbuild "$PKGBUILD" "https://example.com/demo-1.0.0.tar.gz"
    source_libs
    update_checksums
)
status=$?
if (( status != 0 )); then
    fail "dry-run update_checksums should succeed, got $status"
fi
if ! grep -q "b2sums=(\"SKIP\")" "$tmp/dry/aur/PKGBUILD"; then
    fail "dry-run should keep b2sums SKIP"
fi

# VCS sources may keep SKIP without calling updpkgsums.
(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/vcs"
    export PKGBUILD="$tmp/vcs/aur/PKGBUILD"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export color_enabled=0
    export dry_run=0
    mkdir -p "$tmp/vcs/aur"
    write_pkgbuild "$PKGBUILD" "git+https://github.com/example/demo.git"
    source_libs
    update_checksums
)
status=$?
if (( status != 0 )); then
    fail "VCS update_checksums should keep SKIP and succeed, got $status"
fi
if ! grep -q "b2sums=('SKIP')" "$tmp/vcs/aur/PKGBUILD"; then
    fail "VCS source should keep b2sums SKIP"
fi

run_mode() {
    local mode="$1"
    local dry="$2"
    local repo="$tmp/mode-$mode-$dry"
    init_git_repo "$repo"
    (
        set +u
        export PATH="$stub:$PATH"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$repo/aur/PKGBUILD"
        export SRCINFO="$repo/aur/.SRCINFO"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        export DEBUG_LEVEL=1
        export dry_run="$dry"
        export no_wait=1
        export PKGNAME=demo
        export GH_USER=example
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        : > "$AURGEN_ERROR_LOG"
        : > "$AURGEN_LOG"
        source_libs
        # shellcheck source=../lib/modes/local.sh
        source "$ROOT/lib/modes/$mode.sh"
        # Avoid makepkg; the real helper validates the rewrite with it.
        update_source_array_in_pkgbuild() {
            local pkgbuild_file="$1"
            local tarball_url="$2"
            # Like the real helper, list the signature after the tarball when one is given.
            local entries="\"$tarball_url\""
            if [[ -n "${3:-}" ]]; then
                entries+=" \"$3\""
            fi
            awk -v entries="$entries" '
                BEGIN { in_source = 0 }
                /^[[:space:]]*source[[:space:]]*=[[:space:]]*\(/ {
                    in_source = 1
                    print "source=(" entries ")"
                    if ($0 ~ /\)[[:space:]]*$/) {
                        in_source = 0
                    }
                    next
                }
                in_source && /^[[:space:]]*\)/ { in_source = 0; next }
                in_source { next }
                { print }
            ' "$pkgbuild_file" > "$pkgbuild_file.tmp"
            mv "$pkgbuild_file.tmp" "$pkgbuild_file"
        }
        filter_pkgbuild_sources() { cat; }
        export -f filter_pkgbuild_sources
        generate_srcinfo() { echo generate_srcinfo >> "$repo/trace"; }
        install_pkg() { echo install_pkg >> "$repo/trace"; }
        if [[ "$mode" == "aur" ]]; then
            mode_aur
        else
            mode_local
        fi
    )
}

run_mode local 0
status=$?
if (( status == 0 )); then
    fail "local mode should stop when updpkgsums fails"
fi
if [[ -f "$tmp/mode-local-0/trace" ]]; then
    fail "local mode continued after a failed checksum update"
fi

run_mode local 1
status=$?
if (( status != 0 )); then
    fail "local dry-run should continue past checksums, got $status"
fi
if ! grep -q generate_srcinfo "$tmp/mode-local-1/trace"; then
    fail "local dry-run should reach generate_srcinfo"
fi
if ! grep -q 'b2sums=("SKIP")' "$tmp/mode-local-1/aur/PKGBUILD"; then
    fail "local dry-run should keep b2sums SKIP"
fi

run_mode aur 0
status=$?
if (( status == 0 )); then
    fail "aur mode should stop when updpkgsums fails"
fi
if [[ -f "$tmp/mode-aur-0/trace" ]]; then
    fail "aur mode continued after a failed checksum update"
fi

run_mode aur 1
status=$?
if (( status != 0 )); then
    fail "aur dry-run should continue past checksums, got $status"
fi
if ! grep -q generate_srcinfo "$tmp/mode-aur-1/trace"; then
    fail "aur dry-run should reach generate_srcinfo"
fi
if ! grep -q 'b2sums=("SKIP" "SKIP")' "$tmp/mode-aur-1/aur/PKGBUILD"; then
    fail "aur dry-run should keep b2sums SKIP"
fi

# Multi-line b2sums and sha256sums arrays in PKGBUILD.0 must be rewritten cleanly on dry runs
# without leaving orphaned array elements or leftover sha256sums arrays.
(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/dry-multiline"
    export PKGBUILD="$tmp/dry-multiline/aur/PKGBUILD"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export color_enabled=0
    export dry_run=1
    mkdir -p "$tmp/dry-multiline/aur"
    cat > "$PKGBUILD" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=(
  "https://example.com/demo-1.0.0.tar.gz"
  "https://example.com/demo-1.0.0.tar.gz.sig"
)
sha256sums=(
  '0123456789abcdef'
  'fedcba9876543210'
)
b2sums=(
  'aaaa'
  'bbbb'
)

package() {
    :
}
EOF
    source_libs
    update_checksums
) || fail "dry-run update_checksums failed on multi-line checksum arrays"
bash -n "$tmp/dry-multiline/aur/PKGBUILD" || fail "multi-line dry-run PKGBUILD failed bash -n"
sourced_multi=$(bash --noprofile --norc -c '
    source "$1" || exit 1
    printf "b2=%s|sha256=%s" "${b2sums[*]}" "${sha256sums[*]:-}"
' bash "$tmp/dry-multiline/aur/PKGBUILD") || fail "sourcing multi-line dry-run PKGBUILD failed"
[[ "$sourced_multi" == "b2=SKIP SKIP|sha256=" ]] || fail "unexpected dry-run sums: $sourced_multi"
grep -qx 'b2sums=("SKIP" "SKIP")' "$tmp/dry-multiline/aur/PKGBUILD" || fail "expected single b2sums=(\"SKIP\" \"SKIP\") line"

# Commented single-line and parenthesized-comment multi-line *sums arrays must not orphan elements or drop functions.
(
    set +u
    export PATH="$stub:$PATH"
    export PROJECT_ROOT="$tmp/dry-commented"
    export PKGBUILD="$tmp/dry-commented/aur/PKGBUILD"
    export AURGEN_ERROR_LOG="$tmp/err.log"
    export color_enabled=0
    export dry_run=1
    mkdir -p "$tmp/dry-commented/aur"
    cat > "$PKGBUILD" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=("https://example.com/demo-1.0.0.tar.gz")
sha256sums=('0123456789abcdef') # pinned upstream (v1)
b2sums=( # blake2 (all files)
  'aaaa' # tarball (1)
  'bbbb' # extra (2)
) # end b2sums
package() {
    (true)
}
EOF
    source_libs
    update_checksums
) || fail "dry-run update_checksums failed on commented checksum arrays"
bash -n "$tmp/dry-commented/aur/PKGBUILD" || fail "commented dry-run PKGBUILD failed bash -n"
grep -qx 'package() {' "$tmp/dry-commented/aur/PKGBUILD" || fail "commented checksum arrays dropped package()" "$tmp/dry-commented/aur/PKGBUILD"
if grep -q 'bbbb' "$tmp/dry-commented/aur/PKGBUILD"; then
    fail "parenthesized comment on inner b2sums line closed skipping early" "$tmp/dry-commented/aur/PKGBUILD"
fi

for mode_case in local aur; do
    repo_multi="$tmp/multi-$mode_case"
    init_git_repo "$repo_multi"
    cat > "$repo_multi/aur/PKGBUILD.0" <<'EOF'
pkgname=demo
pkgver=1.0.0
pkgrel=1
source=(
  "https://example.com/demo-1.0.0.tar.gz"
)
sha256sums=(
  '0123456789abcdef'
)

package() {
    :
}
EOF
    (
        set +u
        export PATH="$stub:$PATH"
        export PROJECT_ROOT="$repo_multi"
        export AUR_DIR="$repo_multi/aur"
        export PKGBUILD0="$repo_multi/aur/PKGBUILD.0"
        export PKGBUILD="$repo_multi/aur/PKGBUILD"
        export SRCINFO="$repo_multi/aur/.SRCINFO"
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export color_enabled=0
        export DEBUG_LEVEL=1
        export dry_run=1
        export no_wait=1
        export PKGNAME=demo
        export GH_USER=example
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        source_libs
        # shellcheck source=../lib/modes/local.sh
        source "$ROOT/lib/modes/$mode_case.sh"
        update_source_array_in_pkgbuild() {
            local pkgbuild_file="$1"
            local entries="\"$2\""
            [[ -n "${3:-}" ]] && entries+=" \"$3\""
            awk -v entries="$entries" '
                BEGIN { in_source = 0 }
                /^[[:space:]]*source[[:space:]]*=[[:space:]]*\(/ {
                    in_source = 1
                    print "source=(" entries ")"
                    if ($0 ~ /\)[[:space:]]*$/) in_source = 0
                    next
                }
                in_source && /^[[:space:]]*\)/ { in_source = 0; next }
                in_source { next }
                { print }
            ' "$pkgbuild_file" > "$pkgbuild_file.tmp" && mv "$pkgbuild_file.tmp" "$pkgbuild_file"
        }
        filter_pkgbuild_sources() { cat; }
        export -f filter_pkgbuild_sources
        generate_srcinfo() { bash -n "$PKGBUILD" && bash --noprofile --norc -c 'source "$1"' bash "$PKGBUILD"; }
        install_pkg() { :; }
        if [[ "$mode_case" == "aur" ]]; then
            mode_aur
        else
            mode_local
        fi
    ) || fail "$mode_case dry-run failed on multi-line sha256sums PKGBUILD.0"
    if grep -q '^sha256sums=' "$repo_multi/aur/PKGBUILD"; then
        fail "$mode_case dry-run left sha256sums behind"
    fi
done
