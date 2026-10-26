#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# --dry-run must not rewrite lib/tool-mapping.sh.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-update-mapping.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

repo="$tmp/repo"
stub="$tmp/bin"
mkdir -p "$repo" "$stub"
cp -a "$ROOT/scripts" "$repo/scripts"
cp -a "$ROOT/lib" "$repo/lib"

# A real expand queries packages. Stubs keep that off the host if dry-run regresses.
cat > "$stub/pacman" << 'EOF'
#!/bin/bash
printf '/usr/bin/%s is owned by core/dryrun-pkg 1.0-1\n' "${2##*/}"
EOF
cat > "$stub/expac" << 'EOF'
#!/bin/bash
printf 'dryrun-pkg\n'
EOF
# The expand path also queries the AUR RPC.
cat > "$stub/curl" << 'EOF'
#!/bin/bash
echo "curl stub: $*" >&2
exit 1
EOF
chmod +x "$stub/pacman" "$stub/expac" "$stub/curl"

mapping="$repo/lib/tool-mapping.sh"
before="$tmp/before"
cp "$mapping" "$before"

shared="/tmp/aurgen-mapping"
shared_before=0
if [[ -e "$shared" ]]; then
    shared_before=1
fi
export TMPDIR="$tmp"

run_dry() {
    local command="$1"
    if ! (
        export PATH="$stub:$PATH"
        "$repo/scripts/update-mapping" --dry-run "$command"
    ) >"$tmp/out" 2>"$tmp/err"; then
        fail "dry-run $command failed" "$tmp/err"
    fi
    if ! grep -q 'DRY RUN' "$tmp/out"; then
        fail "dry-run $command did not say what it would run" "$tmp/out"
    fi
    if ! cmp -s "$before" "$mapping"; then
        fail "dry-run $command modified lib/tool-mapping.sh"
    fi
}

run_dry expand
run_dry workflow

if "$repo/scripts/update-mapping" clean >| "$tmp/out" 2>| "$tmp/err"; then
    fail "clean was accepted as a command" "$tmp/out"
fi
grep -q '^Unknown option: clean$' "$tmp/err" || fail "clean was not rejected as unknown" "$tmp/err"

if ! "$repo/scripts/update-mapping" --help >"$tmp/help" 2>"$tmp/err"; then
    fail "help failed" "$tmp/err"
fi
if grep -q -- '--force' "$tmp/help"; then
    fail "usage still documents --force"
fi

shared_after=0
if [[ -e "$shared" ]]; then
    shared_after=1
fi
if [[ "$shared_before" -ne "$shared_after" ]]; then
    fail "test changed /tmp/aurgen-mapping"
fi
if [[ ! -d "$tmp/aurgen-mapping" ]]; then
    fail "mapping scratch is missing from the test temp dir"
fi
scratch="$(realpath "$tmp/aurgen-mapping")"
root_tmp="$(realpath "$tmp")"
case "$scratch" in
    "$root_tmp"/*) ;;
    *) fail "mapping scratch is outside the trapped dir" ;;
esac

# bootctl and kernel-install ship in systemd and ukify in systemd-ukify; Arch has no systemd-boot.
for pair in bootctl:systemd kernel-install:systemd ukify:systemd-ukify; do
    got=$(bash -c 'source "$1/lib/tool-mapping.sh"; map_tool_to_package "$2"' _ "$repo" "${pair%%:*}") ||
        fail "map_tool_to_package ${pair%%:*} failed"
    [[ "$got" == "${pair#*:}" ]] || fail "${pair%%:*} maps to [$got], want ${pair#*:}"
done

# Applying an expanded list keeps tool names with +; the apply works on the copied repo.
if ! (
    export TMPDIR="$tmp/apply-tmp"
    mkdir -p "$TMPDIR"
    # shellcheck source=/dev/null
    source "$repo/lib/expand-mapping.sh" || exit 1
    printf '%s\n' 'g++:gcc' 'clang++:clang' >| "$MAPPING_OUTPUT"
    apply_expanded_mapping
) >"$tmp/apply.out" 2>&1; then
    fail "apply_expanded_mapping failed" "$tmp/apply.out"
fi
grep -q '^ *g++) echo "gcc" ;;' "$repo/lib/tool-mapping.sh" || fail "apply dropped the g++ arm"
grep -q '^ *clang++) echo "clang" ;;' "$repo/lib/tool-mapping.sh" || fail "apply dropped the clang++ arm"

# The standalone entrypoint must keep ASCII i and I in mapping names under Turkish LC_ALL.
if locale -a 2>/dev/null | grep -qix 'tr_TR\.utf-\?8'; then
    mkdir -p "$tmp/tr-home" "$tmp/tr-tmp"
    if ! HOME="$tmp/tr-home" TMPDIR="$tmp/tr-tmp" LC_ALL=tr_TR.UTF-8 bash -c '
        source "$1/scripts/update-mapping" --dry-run expand || exit 1
        printf "%s\n" "aurgen-i:pkg-i" "aurgen-I:pkg-I" >| "$MAPPING_OUTPUT"
        apply_expanded_mapping
    ' _ "$repo" >| "$tmp/tr.out" 2>&1; then
        fail "update-mapping failed under Turkish LC_ALL" "$tmp/tr.out"
    fi
    grep -q '^ *aurgen-i) echo "pkg-i" ;;' "$mapping" || fail "Turkish LC_ALL dropped the i mapping"
    grep -q '^ *aurgen-I) echo "pkg-I" ;;' "$mapping" || fail "Turkish LC_ALL dropped the I mapping"
else
    printf '%s\n' 'SKIP: tr_TR.UTF-8 is unavailable'
fi

# A planted ${TMPDIR}/aurgen-mapping (here a symlink to another dir) is refused, never written through.
planted="$tmp/planted"
target="$tmp/planted-target"
mkdir -p "$planted" "$target"
ln -s "$target" "$planted/aurgen-mapping"
if (
    export PATH="$stub:$PATH"
    export TMPDIR="$planted"
    "$repo/scripts/update-mapping" --dry-run expand
) >"$tmp/planted.out" 2>&1; then
    fail "update-mapping ran with a symlinked work directory" "$tmp/planted.out"
fi
grep -q 'is a symlink or not a directory you own' "$tmp/planted.out" || fail "the planted directory was not named" "$tmp/planted.out"
[[ -z "$(ls -A "$target")" ]] || fail "update-mapping wrote into the symlink target"

# Statistics include punctuation in tool names and print empty categories once.
cat >| "$mapping" << 'EOF'
map_tool_to_package() {
    case "$1" in
        g++) echo "gcc" ;;
        clang++) echo "clang" ;;
        tool.name) echo "pkg" ;;
    esac
}
EOF
if ! "$repo/scripts/update-mapping" status >| "$tmp/stats" 2>| "$tmp/err"; then
    fail "mapping statistics failed" "$tmp/err"
fi
grep -qx '  Total mappings: 3' "$tmp/stats" || fail "statistics missed punctuation in tool names" "$tmp/stats"
grep -qx '  Compilers/Languages: 2' "$tmp/stats" || fail "compiler statistics missed mappings" "$tmp/stats"
grep -qx '  Build tools: 0' "$tmp/stats" || fail "empty category did not report zero" "$tmp/stats"
if grep -qx '0' "$tmp/stats"; then
    fail "empty categories printed an extra zero" "$tmp/stats"
fi
