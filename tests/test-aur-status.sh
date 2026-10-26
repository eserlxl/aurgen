#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-aur-status.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
# Scratch-repo commits must never sign with the user's key (commit.gpgsign in ~/.gitconfig).
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

export color_enabled=0
export DEBUG_LEVEL=0

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

log() { :; }

# get_aur_status ends in aur_web_version, which curls the AUR RPC; never reach it.
stub="$tmp/bin"
mkdir -p "$stub"
PATH="$stub:$PATH"

install_curl_stub() {
    printf '%s\n' '#!/bin/bash' "$1" >| "$stub/curl"
    chmod +x "$stub/curl"
}
install_curl_stub 'exit 1'
# aur-status runs gen_pkgbuild0, which asks gh for the repo description: keep it off GitHub.
export GH_ARGV_LOG="$tmp/gh.argv"
: >| "$GH_ARGV_LOG"
cat >| "$stub/gh" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_ARGV_LOG"
exit 1
EOF
chmod +x "$stub/gh"

export AUR_REPO_DIR="$tmp/aur"
repo="$AUR_REPO_DIR/demopkg"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
printf 'hello\n' > "$repo/PKGBUILD"
git -C "$repo" add PKGBUILD
git -C "$repo" commit -q -m init
printf 'changed\n' > "$repo/PKGBUILD"

if ! get_aur_status demopkg >|"$tmp/status.out"; then
    echo "modified repository status returned non-zero"
    exit 1
fi
if ! grep -F -x -q '   M PKGBUILD' "$tmp/status.out"; then
    echo "modified file line is not indented by two spaces"
    cat "$tmp/status.out"
    exit 1
fi

if get_aur_status missingpkg >|"$tmp/missing.out"; then
    echo "missing repository returned 0"
    exit 1
fi
if ! grep -F -q 'Status: Repository does not exist' "$tmp/missing.out"; then
    echo "missing repository status text changed"
    cat "$tmp/missing.out"
    exit 1
fi
if grep -q '^Version:' "$tmp/status.out"; then
    echo "version line printed without .SRCINFO"
    cat "$tmp/status.out"
    exit 1
fi

write_srcinfo() {
    local path="$1"
    local pkgver="$2"
    local pkgrel="$3"
    printf 'pkgbase = demopkg\n\tpkgver = %s\n\tpkgrel = %s\n' "$pkgver" "$pkgrel" >|"$path"
}

export SRCINFO="$tmp/generated.SRCINFO"
write_srcinfo "$SRCINFO" "1.2.3" "1"
write_srcinfo "$repo/.SRCINFO" "1.2.3" "1"

if ! get_aur_status demopkg >|"$tmp/same.out"; then
    echo "matching versions returned non-zero"
    exit 1
fi
if ! grep -F -q 'Version: AUR 1.2.3-1, generated 1.2.3-1 (up to date)' "$tmp/same.out"; then
    echo "matching versions did not report up to date"
    cat "$tmp/same.out"
    exit 1
fi

export PKGBUILD="$tmp/generated/PKGBUILD" AUR_DIR="$tmp/aur-source"
mkdir -p "$(dirname "$PKGBUILD")" "$AUR_DIR"
printf "pkgname=demopkg\ninstall='demopkg.install'\n" >|"$PKGBUILD"
printf '\tinstall = demopkg.install\n' >> "$SRCINFO"
cp "$SRCINFO" "$repo/.SRCINFO"
printf 'post_install() { :; }\n' >|"$tmp/generated/demopkg.install"
cp "$tmp/generated/demopkg.install" "$repo/demopkg.install"

for scriptlet_case in unchanged changed missing-clone missing-source fallback; do
    scriptlet_rc=0
    scriptlet_want=3
    scriptlet_verdict='deploy pending; install scriptlet differs or is missing'
    case "$scriptlet_case" in
        unchanged)
            scriptlet_want=0
            scriptlet_verdict='up to date'
            ;;
        changed) printf 'post_install() { echo changed; }\n' >|"$tmp/generated/demopkg.install" ;;
        missing-clone) rm "$repo/demopkg.install" ;;
        missing-source)
            cp "$tmp/generated/demopkg.install" "$repo/demopkg.install"
            rm "$tmp/generated/demopkg.install"
            ;;
        fallback)
            cp "$repo/demopkg.install" "$AUR_DIR/demopkg.install"
            scriptlet_want=0
            scriptlet_verdict='up to date'
            ;;
    esac
    get_aur_status demopkg >|"$tmp/scriptlet-$scriptlet_case.out" || scriptlet_rc=$?
    if [[ "$scriptlet_rc" -ne "$scriptlet_want" ]] \
        || ! grep -F -q "Version: AUR 1.2.3-1, generated 1.2.3-1 ($scriptlet_verdict)" "$tmp/scriptlet-$scriptlet_case.out"; then
        echo "$scriptlet_case scriptlet: exit $scriptlet_rc, expected $scriptlet_want and $scriptlet_verdict"
        cat "$tmp/scriptlet-$scriptlet_case.out"
        exit 1
    fi
done
unset PKGBUILD AUR_DIR
write_srcinfo "$SRCINFO" "1.2.3" "1"
write_srcinfo "$repo/.SRCINFO" "1.2.3" "1"

printf '\tdepends = bash\n' >> "$SRCINFO"
metadata_rc=0
get_aur_status demopkg >|"$tmp/metadata.out" || metadata_rc=$?
if [[ "$metadata_rc" -ne 3 ]]; then
    echo "differing metadata returned $metadata_rc, expected 3"
    cat "$tmp/metadata.out"
    exit 1
fi
if ! grep -F -q 'Version: AUR 1.2.3-1, generated 1.2.3-1 (deploy pending; only metadata differs)' "$tmp/metadata.out"; then
    echo "differing metadata did not report deploy pending"
    cat "$tmp/metadata.out"
    exit 1
fi

write_srcinfo "$SRCINFO" "1.2.4" "1"
diff_rc=0
get_aur_status demopkg >|"$tmp/diff.out" || diff_rc=$?
if [[ "$diff_rc" -ne 3 ]]; then
    echo "differing versions returned $diff_rc, expected 3"
    cat "$tmp/diff.out"
    exit 1
fi
if ! grep -F -q 'Version: AUR 1.2.3-1, generated 1.2.4-1 (deploy pending)' "$tmp/diff.out"; then
    echo "differing versions did not report deploy pending"
    cat "$tmp/diff.out"
    exit 1
fi

# Later checks call get_aur_status again and expect a match.
write_srcinfo "$SRCINFO" "1.2.3" "1"


assert_web_line() {
    local name="$1"
    local line="$2"
    if ! get_aur_status demopkg >|"$tmp/$name.out"; then
        echo "$name returned non-zero"
        exit 1
    fi
    if ! grep -F -q "$line" "$tmp/$name.out"; then
        echo "$name did not print: $line"
        cat "$tmp/$name.out"
        exit 1
    fi
}

install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\"}]}'"
assert_web_line web-version 'AUR web: 1.2.3-1'

if get_aur_status missingpkg >|"$tmp/missing-web.out"; then
    echo "missing repository with web version returned 0"
    exit 1
fi
if ! grep -F -q 'AUR web: 1.2.3-1' "$tmp/missing-web.out"; then
    echo "missing repository did not print AUR web version"
    cat "$tmp/missing-web.out"
    exit 1
fi

install_curl_stub "printf '%s\n' '{\"resultcount\":0,\"results\":[]}'"
assert_web_line web-empty 'AUR web: not published'

install_curl_stub 'exit 1'
assert_web_line web-fail 'AUR web: unavailable'

# aurgen aur-status: the process exit is 0 for a match or a missing clone, and 3
# when a deploy or an unpushed commit is pending. A tag keeps git describe from
# tripping the error trap during PKGBUILD.0 generation.
proj="$tmp/proj"
cli_clones="$tmp/cli-clones"
mkdir -p "$proj/aur" "$cli_clones" "$tmp/cli-state" "$tmp/cli-data"
git -C "$proj" init -q -b main
git -C "$proj" config user.email "t@example.com"
git -C "$proj" config user.name "t"
git -C "$proj" config commit.gpgsign false
printf 'readme\n' > "$proj/README"
git -C "$proj" add README
git -C "$proj" commit -q -m init
git -C "$proj" tag v1.2.3
git -C "$proj" remote add origin "https://github.com/example/demopkg.git"
printf '%s\n' 'aur_integration:' "  aur_repo_dir: $cli_clones" 'package:' '  name: demopkg' >|"$proj/aur/aurgen.install.yaml"

cli_clone="$cli_clones/demopkg"
mkdir -p "$cli_clone"
git -C "$cli_clone" init -q -b main
git -C "$cli_clone" config user.email "t@example.com"
git -C "$cli_clone" config user.name "t"
git -C "$cli_clone" config commit.gpgsign false
printf 'pkg\n' > "$cli_clone/PKGBUILD"
write_srcinfo "$proj/aur/.SRCINFO" "1.2.3" "1"
write_srcinfo "$cli_clone/.SRCINFO" "1.2.3" "1"
git -C "$cli_clone" add PKGBUILD .SRCINFO
git -C "$cli_clone" commit -q -m init

assert_aur_status() {
    local name="$1"
    local want="$2"
    local needle="$3"
    local rc=0
    (
        cd "$proj" || exit 1
        env DEBUG_LEVEL=0 \
            PATH="$stub:$PATH" \
            XDG_STATE_HOME="$tmp/cli-state" \
            XDG_DATA_HOME="$tmp/cli-data" \
            "$ROOT/bin/aurgen" aur-status
    ) >|"$tmp/$name.out" 2>|"$tmp/$name.err" || rc=$?
    if [[ "$rc" -ne "$want" ]]; then
        echo "$name: exit $rc, expected $want"
        cat "$tmp/$name.out"
        cat "$tmp/$name.err"
        exit 1
    fi
    if grep -F -q '[FATAL]' "$tmp/$name.out" "$tmp/$name.err"; then
        echo "$name printed [FATAL]"
        cat "$tmp/$name.out"
        cat "$tmp/$name.err"
        exit 1
    fi
    if ! grep -F -q "$needle" "$tmp/$name.out"; then
        echo "$name did not print: $needle"
        cat "$tmp/$name.out"
        cat "$tmp/$name.err"
        exit 1
    fi
    if ! grep -F -q '=== AUR Integration Configuration ===' "$tmp/$name.out"; then
        echo "$name did not print the configuration block"
        cat "$tmp/$name.out"
        exit 1
    fi
}

assert_aur_status cli-match 0 'Version: AUR 1.2.3-1, generated 1.2.3-1 (up to date)'
grep -F -q 'repo view' "$GH_ARGV_LOG" || { echo "aur-status did not reach the gh stub"; cat "$GH_ARGV_LOG"; exit 1; }

write_srcinfo "$proj/aur/.SRCINFO" "1.2.3" "2"
assert_aur_status cli-pkgrel 3 'Version: AUR 1.2.3-1, generated 1.2.3-2 (deploy pending)'

write_srcinfo "$proj/aur/.SRCINFO" "1.2.3" "1"
cli_upstream="$tmp/cli-upstream.git"
git init -q --bare -b main "$cli_upstream"
git -C "$cli_clone" remote add origin "$cli_upstream"
# A first deploy to an empty AUR repo: a local commit, no origin/master yet.
assert_aur_status cli-unpushed 3 'Version: AUR 1.2.3-1, generated 1.2.3-1 (up to date)'
if aur_ahead_count "$cli_clone" >|"$tmp/ahead.out"; then
    echo "ahead count succeeded without an upstream ref"
    exit 1
fi
git -C "$cli_clone" push -q -u origin main
git -C "$cli_clone" push -q origin HEAD:master
git -C "$cli_clone" commit -q --allow-empty -m published
git -C "$cli_clone" push -q origin main

assert_ahead_paths() (
    local count="$1"
    if [[ "$(aur_ahead_count "$cli_clone")" != "$count" ]]; then
        echo "ahead count did not use origin/main"
        exit 1
    fi
    export AURGEN_ERROR_LOG="$tmp/ahead-err.log"
    # shellcheck source=../lib/colors.sh
    source "$ROOT/lib/colors.sh"
    color_enabled=0 init_colors
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    # shellcheck source=../lib/modes/aur-deploy.sh
    source "$ROOT/lib/modes/aur-deploy.sh"
    export LIB_INSTALL_DIR="$ROOT/lib" AUR_DIR="$proj/aur"
    export SRCINFO="$tmp/deploy/.SRCINFO" PKGBUILD="$tmp/deploy/PKGBUILD"
    mkdir -p "$tmp/deploy"
    cp "$cli_clone/PKGBUILD" "$PKGBUILD"
    cp "$cli_clone/.SRCINFO" "$SRCINFO"
    log() { printf '%s\n' "$*"; }

    dry_run=1 mode_aur_push >|"$tmp/push-count.out"
    if (( count == 0 )); then
        grep -F -q 'Nothing to push' "$tmp/push-count.out" || exit 1
    else
        grep -F -q "Would push $count commit(s)" "$tmp/push-count.out" || exit 1
    fi

    push_to_aur() { echo 'push requested'; }
    dry_run=0 deploy_to_aur demopkg >|"$tmp/deploy-count.out"
    if (( count == 0 )); then
        if grep -F -q 'push requested' "$tmp/deploy-count.out"; then
            echo "deploy retried a push despite being up to date with origin/main"
            exit 1
        fi
    else
        grep -F -q 'push requested' "$tmp/deploy-count.out" || exit 1
    fi
)

assert_aur_status cli-tracking-main 0 'Remote Status: ## main...origin/main'
assert_ahead_paths 0
printf 'ahead\n' >> "$cli_clone/PKGBUILD"
git -C "$cli_clone" add PKGBUILD
git -C "$cli_clone" commit -q -m ahead
git -C "$cli_clone" commit -q --allow-empty -m ahead-again
assert_aur_status cli-ahead 3 'Remote Status: ## main...origin/main [ahead 2]'
assert_ahead_paths 2

git -C "$cli_clone" branch --unset-upstream
if [[ "$(aur_ahead_count "$cli_clone")" != 3 ]]; then
    echo "ahead count did not fall back to origin/master"
    exit 1
fi

printf 'pkgbase = noclone\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >|"$proj/aur/.SRCINFO"
assert_aur_status cli-missing 0 'Status: Repository does not exist'
