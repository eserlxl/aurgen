#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-aur-status.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" GNUPGHOME="$tmp/gnupg"
export AURGEN_ERROR_LOG="$tmp/err.log"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
mkdir -m 700 "$GNUPGHOME"
: > "$AURGEN_ERROR_LOG"
# Scratch-repo commits must never sign with the user's key (commit.gpgsign in ~/.gitconfig).
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_MODE AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CONFIG_FILE AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_CONFIG_ACTION \
    DRY_RUN OUT_DIR AUR_DIR PROJECT_ROOT PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    AURGEN_TEST_DESC AURGEN_TEST_GH_DESC \
    PKG_NAME PKG_DESCRIPTION PKG_GPG_KEY PKG_INSTALL PKG_CHECK PKG_SOURCE \
    PKG_DEPENDS PKG_OPTDEPENDS PKG_MAKEDEPENDS PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

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
cp "$PKGBUILD" "$repo/PKGBUILD"
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
assert_ahead_paths 0 || exit 1
printf 'ahead\n' >> "$cli_clone/PKGBUILD"
git -C "$cli_clone" add PKGBUILD
git -C "$cli_clone" commit -q -m ahead
git -C "$cli_clone" commit -q --allow-empty -m ahead-again
assert_aur_status cli-ahead 3 'Remote Status: ## main...origin/main [ahead 2]'
assert_ahead_paths 2 || exit 1

git -C "$cli_clone" branch --unset-upstream
if [[ "$(aur_ahead_count "$cli_clone")" != 3 ]]; then
    echo "ahead count did not fall back to origin/master"
    exit 1
fi

printf 'pkgbase = noclone\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >|"$proj/aur/.SRCINFO"
assert_aur_status cli-missing 0 'Status: Repository does not exist'

# --diff shows unified diff against local AUR clone for differing PKGBUILD/.SRCINFO
diff_proj="$tmp/diff-proj"
diff_clones="$tmp/diff-clones"
diff_clone="$diff_clones/diffpkg"
mkdir -p "$diff_proj/aur" "$diff_clone"
git -C "$diff_proj" init -q -b main
git -C "$diff_proj" config user.email "t@example.com"
git -C "$diff_proj" config user.name "t"
git -C "$diff_proj" config commit.gpgsign false
printf 'readme\n' > "$diff_proj/README"
git -C "$diff_proj" add README
git -C "$diff_proj" commit -q -m init
git -C "$diff_proj" tag v1.0.0
git -C "$diff_proj" remote add origin https://github.com/example/diff-proj.git
cat >| "$diff_proj/aur/aurgen.install.yaml" <<EOF
package:
  name: diffpkg
aur_integration:
  aur_repo_dir: $diff_clones
  auto_push: false
EOF
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\n' >| "$diff_proj/aur/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >| "$diff_proj/aur/.SRCINFO"
git -C "$diff_clone" init -q -b main
git -C "$diff_clone" config user.email "t@example.com"
git -C "$diff_clone" config user.name "t"
git -C "$diff_clone" config commit.gpgsign false
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\n' >| "$diff_clone/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >| "$diff_clone/.SRCINFO"
git -C "$diff_clone" add PKGBUILD .SRCINFO
git -C "$diff_clone" commit -q -m init
diff_upstream="$tmp/diff-upstream.git"
git init -q --bare -b main "$diff_upstream"
git -C "$diff_clone" remote add origin "$diff_upstream"
git -C "$diff_clone" push -q -u origin main

diff_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --diff aur-status) >|"$tmp/diff-clean.out" 2>|"$tmp/diff-clean.err" || diff_rc=$?
(( diff_rc == 0 )) || { echo "--diff up-to-date exited $diff_rc"; cat "$tmp/diff-clean.out" "$tmp/diff-clean.err"; exit 1; }
grep -Fq 'Diff (PKGBUILD): identical' "$tmp/diff-clean.out" || { echo "--diff missing identical PKGBUILD line"; cat "$tmp/diff-clean.out"; exit 1; }
grep -Fq 'Diff (.SRCINFO): identical' "$tmp/diff-clean.out" || { echo "--diff missing identical .SRCINFO line"; cat "$tmp/diff-clean.out"; exit 1; }

# --json on up-to-date repo emits pure JSON on stdout (no [INFO] leaks even under RELEASE=0)
json_rc=0
(cd "$diff_proj" && RELEASE=0 PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/json-clean.out" 2>|"$tmp/json-clean.err" || json_rc=$?
(( json_rc == 0 )) || { echo "--json up-to-date exited $json_rc"; cat "$tmp/json-clean.out" "$tmp/json-clean.err"; exit 1; }
python3 - "$tmp/json-clean.out" <<'PY' || { echo "--json clean output invalid"; cat "$tmp/json-clean.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["package"] == "diffpkg"
assert d["repo_exists"] is True
assert d["git_clean"] is True
assert d["ahead_count"] == 0
assert d["behind_count"] == 0
assert d["pending"] is False
assert d["verdict"] == "up to date"
assert d["aur_integration"]["auto_push"] is False
PY

# Change generated PKGBUILD and .SRCINFO, verify --diff shows diff -u and --json returns exit 3 pending
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=2\n' >| "$diff_proj/aur/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 2\n' >| "$diff_proj/aur/.SRCINFO"
diff_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --diff aur-status) >|"$tmp/diff-pend.out" 2>|"$tmp/diff-pend.err" || diff_rc=$?
(( diff_rc == 3 )) || { echo "--diff pending exited $diff_rc instead of 3"; cat "$tmp/diff-pend.out" "$tmp/diff-pend.err"; exit 1; }
grep -Fq -- '+pkgrel=2' "$tmp/diff-pend.out" || { echo "--diff did not print unified PKGBUILD diff"; cat "$tmp/diff-pend.out"; exit 1; }
grep -Fq -- '+	pkgrel = 2' "$tmp/diff-pend.out" || { echo "--diff did not print unified .SRCINFO diff"; cat "$tmp/diff-pend.out"; exit 1; }

json_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/json-pend.out" 2>|"$tmp/json-pend.err" || json_rc=$?
(( json_rc == 3 )) || { echo "--json pending exited $json_rc instead of 3"; cat "$tmp/json-pend.out" "$tmp/json-pend.err"; exit 1; }
python3 - "$tmp/json-pend.out" <<'PY' || { echo "--json pending output invalid"; cat "$tmp/json-pend.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["package"] == "diffpkg"
assert d["aur_version"] == "1.0.0-1"
assert d["generated_version"] == "1.0.0-2"
assert d["verdict"] == "deploy pending"
assert d["pending"] is True
PY

# Epoch differences at the same pkgver-pkgrel must appear in version strings and verdict (prose + --json)
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\nepoch=1\n' >| "$diff_clone/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n\tepoch = 1\n' >| "$diff_clone/.SRCINFO"
git -C "$diff_clone" add PKGBUILD .SRCINFO
git -C "$diff_clone" commit -q -m 'epoch 1'
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\nepoch=2\n' >| "$diff_proj/aur/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n\tepoch = 2\n' >| "$diff_proj/aur/.SRCINFO"
ep_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/epoch-prose.out" 2>|"$tmp/epoch-prose.err" || ep_rc=$?
(( ep_rc == 3 )) || { echo "epoch bump prose exited $ep_rc instead of 3"; cat "$tmp/epoch-prose.out" "$tmp/epoch-prose.err"; exit 1; }
grep -Fq 'Version: AUR 1:1.0.0-1, generated 2:1.0.0-1 (deploy pending)' "$tmp/epoch-prose.out" || { echo "epoch bump prose version mismatch"; cat "$tmp/epoch-prose.out"; exit 1; }
ep_json_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/epoch-json.out" 2>|"$tmp/epoch-json.err" || ep_json_rc=$?
(( ep_json_rc == 3 )) || { echo "epoch bump --json exited $ep_json_rc instead of 3"; cat "$tmp/epoch-json.out" "$tmp/epoch-json.err"; exit 1; }
python3 - "$tmp/epoch-json.out" <<'PY' || { echo "epoch bump --json invalid"; cat "$tmp/epoch-json.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["aur_version"] == "1:1.0.0-1"
assert d["generated_version"] == "2:1.0.0-1"
assert d["verdict"] == "deploy pending"
assert d["pending"] is True
PY

# Behind-upstream clone surfaces Behind: line (prose) and behind_count (--json) without changing 0/3 exit codes
git -C "$diff_clone" push -q origin main
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\nepoch=1\n' >| "$diff_proj/aur/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n\tepoch = 1\n' >| "$diff_proj/aur/.SRCINFO"
peer_clone="$tmp/diff-peer"
git clone -q "$diff_upstream" "$peer_clone"
git -C "$peer_clone" config user.email "p@example.com"
git -C "$peer_clone" config user.name "p"
git -C "$peer_clone" config commit.gpgsign false
git -C "$peer_clone" commit -q --allow-empty -m 'peer 1'
git -C "$peer_clone" commit -q --allow-empty -m 'peer 2'
git -C "$peer_clone" push -q origin main
git -C "$diff_clone" fetch -q origin

if [[ "$(aur_behind_count "$diff_clone")" != 2 ]]; then
    echo "aur_behind_count did not report 2 behind tracking upstream"
    exit 1
fi
bh_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/behind-prose.out" 2>|"$tmp/behind-prose.err" || bh_rc=$?
(( bh_rc == 0 )) || { echo "behind-only prose exited $bh_rc instead of 0"; cat "$tmp/behind-prose.out" "$tmp/behind-prose.err"; exit 1; }
grep -Fq 'Remote Status: ## main...origin/main [behind 2]' "$tmp/behind-prose.out" || { echo "behind prose missing remote behind status"; cat "$tmp/behind-prose.out"; exit 1; }
grep -Fq "Behind: 2 commit(s) behind upstream; run git -C $(printf '%q' "$diff_clone") pull --ff-only" "$tmp/behind-prose.out" || { echo "behind prose missing Behind hint"; cat "$tmp/behind-prose.out"; exit 1; }

bh_json_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/behind-json.out" 2>|"$tmp/behind-json.err" || bh_json_rc=$?
(( bh_json_rc == 0 )) || { echo "behind-only --json exited $bh_json_rc instead of 0"; cat "$tmp/behind-json.out" "$tmp/behind-json.err"; exit 1; }
python3 - "$tmp/behind-json.out" <<'PY' || { echo "behind-only --json invalid"; cat "$tmp/behind-json.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ahead_count"] == 0
assert d["behind_count"] == 2
assert d["pending"] is False
assert d["verdict"] == "up to date"
PY

# Diverged clone (1 ahead, 2 behind): both counts reported and exit remains 3
git -C "$diff_clone" commit -q --allow-empty -m 'local ahead'
div_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/div-prose.out" 2>|"$tmp/div-prose.err" || div_rc=$?
(( div_rc == 3 )) || { echo "diverged prose exited $div_rc instead of 3"; cat "$tmp/div-prose.out" "$tmp/div-prose.err"; exit 1; }
grep -Fq "Behind: 2 commit(s) behind upstream; run git -C $(printf '%q' "$diff_clone") pull --ff-only" "$tmp/div-prose.out" || { echo "diverged prose missing Behind hint"; cat "$tmp/div-prose.out"; exit 1; }

div_json_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/div-json.out" 2>|"$tmp/div-json.err" || div_json_rc=$?
(( div_json_rc == 3 )) || { echo "diverged --json exited $div_json_rc instead of 3"; cat "$tmp/div-json.out" "$tmp/div-json.err"; exit 1; }
python3 - "$tmp/div-json.out" <<'PY' || { echo "diverged --json invalid"; cat "$tmp/div-json.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ahead_count"] == 1
assert d["behind_count"] == 2
assert d["pending"] is True
PY

# Unset upstream falls back to origin/master and errors when no upstream ref exists
git -C "$diff_clone" branch --unset-upstream
git -C "$diff_clone" update-ref refs/remotes/origin/master refs/remotes/origin/main
if [[ "$(aur_behind_count "$diff_clone")" != 2 ]]; then
    echo "aur_behind_count did not fall back to origin/master"
    exit 1
fi
git -C "$diff_clone" update-ref -d refs/remotes/origin/master
if aur_behind_count "$diff_clone" >|"$tmp/behind-noref.out"; then
    echo "aur_behind_count succeeded without an upstream ref"
    exit 1
fi

# Change generated PKGBUILD only (body difference), verify --json returns pending: true and status 3
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\n\npackage() { echo NEW; }\n' >| "$diff_proj/aur/PKGBUILD"
printf 'pkgname=diffpkg\npkgver=1.0.0\npkgrel=1\n\npackage() { echo OLD; }\n' >| "$diff_clone/PKGBUILD"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >| "$diff_proj/aur/.SRCINFO"
printf 'pkgbase = diffpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >| "$diff_clone/.SRCINFO"
pkg_diff_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/pkg-diff-prose.out" 2>|"$tmp/pkg-diff-prose.err" || pkg_diff_rc=$?
(( pkg_diff_rc == 3 )) || { echo "PKGBUILD-only diff prose exited $pkg_diff_rc instead of 3"; cat "$tmp/pkg-diff-prose.out"; exit 1; }
grep -Fq '(deploy pending; PKGBUILD differs)' "$tmp/pkg-diff-prose.out" || { echo "PKGBUILD-only diff prose missing verdict"; cat "$tmp/pkg-diff-prose.out"; exit 1; }

pkg_diff_json_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/pkg-diff-json.out" 2>|"$tmp/pkg-diff-json.err" || pkg_diff_json_rc=$?
(( pkg_diff_json_rc == 3 )) || { echo "PKGBUILD-only diff --json exited $pkg_diff_json_rc instead of 3"; cat "$tmp/pkg-diff-json.out"; exit 1; }
python3 - "$tmp/pkg-diff-json.out" <<'PY' || { echo "PKGBUILD-only diff --json invalid"; cat "$tmp/pkg-diff-json.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["verdict"] == "deploy pending; PKGBUILD differs"
assert d["pending"] is True
PY

# Missing clone under --json exits 0 with repo_exists: false
rm -rf "$diff_clone"
json_rc=0
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/json-miss.out" 2>|"$tmp/json-miss.err" || json_rc=$?
(( json_rc == 0 )) || { echo "--json missing clone exited $json_rc instead of 0"; cat "$tmp/json-miss.out" "$tmp/json-miss.err"; exit 1; }
python3 - "$tmp/json-miss.out" <<'PY' || { echo "--json missing output invalid"; cat "$tmp/json-miss.out"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["package"] == "diffpkg"
assert d["repo_exists"] is False
assert d["behind_count"] is None
assert d["pending"] is False
PY
