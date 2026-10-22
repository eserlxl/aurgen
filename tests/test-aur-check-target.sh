#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-check-target.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

export XDG_STATE_HOME="$tmp/state"
export XDG_DATA_HOME="$tmp/data"
mkdir -p "$XDG_STATE_HOME" "$XDG_DATA_HOME"

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
printf '#!/bin/bash\nexit 0\n' > "$stub/gpg"
printf '#!/bin/bash\nexit 0\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 1\n' > "$stub/curl"
chmod +x "$stub/makepkg" "$stub/gh" "$stub/gpg" "$stub/updpkgsums" "$stub/curl"

: > "$tmp/run.out"
: > "$tmp/run.err"

fail() {
    echo "$1"
    if [[ -f "$tmp/run.out" ]]; then
        echo "--- run.out ---"
        cat "$tmp/run.out"
    fi
    if [[ -f "$tmp/run.err" ]]; then
        echo "--- run.err ---"
        cat "$tmp/run.err"
    fi
    exit 1
}

refuse_msg() {
    printf "[aur] check() runs 'make %s', but the Makefile at v1.0.0 has no '%s' target. Tag a release that contains it, or change package.check." "$1" "$1"
}

new_repo() {
    local repo="$tmp/$1"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" config commit.gpgsign false
    git -C "$repo" config tag.gpgsign false
    git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
    printf 'demo package\n' > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

# text is the Makefile body. The commit is what a following tag records.
commit_makefile() {
    local repo="$1"
    local text="$2"
    printf '%s\n' "$text" > "$repo/Makefile"
    git -C "$repo" add Makefile
    git -C "$repo" commit -q -m makefile
}

write_config() {
    local repo="$1"
    local check="$2"
    if [[ -n "$check" ]]; then
        printf 'package:\n  check: %s\n' "$check" > "$repo/aur/aurgen.install.yaml"
    else
        printf 'package:\n  name: testpkg\n' > "$repo/aur/aurgen.install.yaml"
    fi
}

run_aur() {
    local repo="$1"
    (
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGBUILD0="$repo/aur/PKGBUILD.0"
        export PKGBUILD="$repo/aur/PKGBUILD"
        export SRCINFO="$repo/aur/.SRCINFO"
        export PKGNAME=testpkg
        cd "$repo" || exit 1
        export REPO_NAME=testpkg
        export GH_USER=testuser
        export AURGEN_ERROR_LOG="$tmp/err.log"
        export AURGEN_LOG="$tmp/out.log"
        export AURGEN_MODE=aur
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        export dry_run=1
        export no_wait=1
        export ascii_armor=0
        : >| "$AURGEN_ERROR_LOG"
        : >| "$AURGEN_LOG"
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config
        gen_pkgbuild0
        # shellcheck source=../lib/modes/aur.sh
        source "$ROOT/lib/modes/aur.sh"
        mode_aur
    ) >"$tmp/run.out" 2>"$tmp/run.err"
}

# Tag v1.0.0 lacks check-package; HEAD has it. check() still runs the tag's Makefile.
repo="$(new_repo missing-at-tag)"
commit_makefile "$repo" $'all:\n\t@true\n'
git -C "$repo" tag v1.0.0
commit_makefile "$repo" $'all:\n\t@true\ncheck-package:\n\t@true\n'
write_config "$repo" "make check-package"
run_aur "$repo"
status=$?
if (( status == 0 )); then
    fail "tag v1.0.0 missing check-package should fail"
fi
msg="$(refuse_msg check-package)"
if ! grep -F -q "$msg" "$tmp/run.err"; then
    fail "tag v1.0.0 missing check-package should name check-package and v1.0.0" "$tmp/run.err"
fi

# The same target at the tag is enough.
repo="$(new_repo present-at-tag)"
commit_makefile "$repo" $'all:\n\t@true\ncheck-package:\n\t@true\n'
git -C "$repo" tag v1.0.0
write_config "$repo" "make check-package"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "tag Makefile with check-package should succeed, got $status"
fi
if grep -F -q "has no 'check-package' target" "$tmp/run.err"; then
    fail "tag Makefile with check-package should not refuse" "$tmp/run.err"
fi

# No package.check: the generator's make check matches check: at the tag.
repo="$(new_repo default-check)"
commit_makefile "$repo" $'all:\n\t@true\ncheck:\n\t@true\n'
git -C "$repo" tag v1.0.0
write_config "$repo" ""
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "default make check should succeed, got $status"
fi
if grep -F -q "has no 'check' target" "$tmp/run.err"; then
    fail "default make check should not refuse" "$tmp/run.err"
fi

# .PHONY lists prerequisites; it does not define them.
repo="$(new_repo phony-only)"
commit_makefile "$repo" $'.PHONY: check-package\nall:\n\t@true\n'
git -C "$repo" tag v1.0.0
write_config "$repo" "make check-package"
run_aur "$repo"
status=$?
if (( status == 0 )); then
    fail ".PHONY check-package without a rule should fail"
fi
msg="$(refuse_msg check-package)"
if ! grep -F -q "$msg" "$tmp/run.err"; then
    fail ".PHONY check-package without a rule should name check-package and v1.0.0" "$tmp/run.err"
fi

# check: false omits check(), so a missing target is not an error.
repo="$(new_repo check-false)"
commit_makefile "$repo" $'all:\n\t@true\n'
git -C "$repo" tag v1.0.0
write_config "$repo" "false"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "check: false should succeed, got $status"
fi
if grep -q '^check()' "$repo/aur/PKGBUILD.0"; then
    fail "check: false should omit check()" "$repo/aur/PKGBUILD.0"
fi
if grep -F -q "has no '" "$tmp/run.err"; then
    fail "check: false should not refuse" "$tmp/run.err"
fi

# include may define the target in a file this read does not expand.
repo="$(new_repo include-file)"
commit_makefile "$repo" $'include extra.mk\nall:\n\t@true\n'
git -C "$repo" tag v1.0.0
write_config "$repo" "make check-package"
run_aur "$repo"
status=$?
if (( status != 0 )); then
    fail "include without a rule should succeed, got $status"
fi
msg="$(refuse_msg check-package)"
if ! grep -F -q "${msg} (it may come from an included file)" "$tmp/run.out"; then
    fail "include without a rule should warn that the target may come from an included file" "$tmp/run.out"
fi

# A check() line that chains commands is checked command by command.
for chain in "make check-package; make lint" "make check-package && make lint"; do
    repo="$(new_repo "chain-${#chain}")"
    commit_makefile "$repo" $'all:\n\t@true\ncheck-package:\n\t@true\nlint:\n\t@true\n'
    git -C "$repo" tag v1.0.0
    write_config "$repo" "$chain"
    run_aur "$repo"
    status=$?
    if (( status != 0 )); then
        fail "chained check '$chain' with both targets at the tag should succeed, got $status" "$tmp/run.err"
    fi
done
repo="$(new_repo chain-missing)"
commit_makefile "$repo" $'all:\n\t@true\ncheck-package:\n\t@true\n'
git -C "$repo" tag v1.0.0
write_config "$repo" "make check-package && make lint"
run_aur "$repo"
status=$?
if (( status == 0 )); then
    fail "a chained check whose second target is missing should fail"
fi
if ! grep -F -q "$(refuse_msg lint)" "$tmp/run.err"; then
    fail "a chained check should name the missing second target" "$tmp/run.err"
fi
