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
# aur-status is read-only: it no longer generates PKGBUILD.0, so it never asks gh for metadata.
if grep -F -q 'repo view' "$GH_ARGV_LOG"; then
    echo "aur-status ran PKGBUILD.0 generation (gh repo view)"
    cat "$GH_ARGV_LOG"
    exit 1
fi

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
assert d["aur_out_of_date"] is None and d["aur_orphaned"] is None
PY

# A flagged, orphaned AUR package reports both facts as --json fields; the text line keeps its notes.
install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\",\"OutOfDate\":1700000000,\"Maintainer\":null}]}'"
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/json-flag.out" 2>|"$tmp/json-flag.err" || true
python3 - "$tmp/json-flag.out" <<'PY' || { echo "--json out-of-date/orphaned fields wrong"; cat "$tmp/json-flag.out" "$tmp/json-flag.err"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["aur_out_of_date"] == "2023-11-14", d["aur_out_of_date"]
assert d["aur_orphaned"] is True, d["aur_orphaned"]
assert d["aur_web"] == "1.2.3-1 (flagged out of date since 2023-11-14) (orphaned)", d["aur_web"]
PY
install_curl_stub "printf '%s\n' '{\"resultcount\":1,\"results\":[{\"Version\":\"1.2.3-1\",\"OutOfDate\":null,\"Maintainer\":\"someone\"}]}'"
(cd "$diff_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/json-kept.out" 2>|"$tmp/json-kept.err" || true
python3 - "$tmp/json-kept.out" <<'PY' || { echo "--json maintained package fields wrong"; cat "$tmp/json-kept.out" "$tmp/json-kept.err"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["aur_out_of_date"] is None and d["aur_orphaned"] is False, d
PY
install_curl_stub 'exit 1'

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
grep -Fq "Behind: 2 commit(s) behind upstream and 1 unpushed: the clone has diverged; run aurgen aur-deploy --rollback, then git -C $(printf '%q' "$diff_clone") pull --ff-only" "$tmp/div-prose.out" || { echo "diverged prose missing the rollback hint"; cat "$tmp/div-prose.out"; exit 1; }

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

# A read-only mode must not source an untrusted aur/PKGBUILD or write packaging files.
for ro_mode in aur-status doctor; do
    ro_repo="$tmp/ro-$ro_mode"
    mkdir -p "$ro_repo/aur"
    printf '#!/bin/sh\necho hi\n' > "$ro_repo/tool"
    printf 'pkgname=demo\npkgver=1.0.0\npkgrel=1\n$(touch %s)\npackage() { :; }\n' "$tmp/ro-$ro_mode.marker" > "$ro_repo/aur/PKGBUILD"
    git -C "$ro_repo" init -q -b main
    git -C "$ro_repo" add -A
    git -C "$ro_repo" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m init
    git -C "$ro_repo" remote add origin "https://github.com/example/demo.git"
    (cd "$ro_repo" && env DEBUG_LEVEL=0 PATH="$stub:$PATH" XDG_STATE_HOME="$tmp/ro-state" XDG_DATA_HOME="$tmp/ro-data" \
        "$ROOT/bin/aurgen" -n "$ro_mode") >"$tmp/ro-$ro_mode.out" 2>&1 || true
    if [[ -e "$tmp/ro-$ro_mode.marker" ]]; then
        echo "$ro_mode sourced the untrusted aur/PKGBUILD"
        exit 1
    fi
    if [[ -e "$ro_repo/aur/aurgen.install.yaml" || -e "$ro_repo/aur/PKGBUILD.0" ]]; then
        echo "$ro_mode wrote packaging files"
        ls "$ro_repo/aur"
        exit 1
    fi
done

# Read-only modes on a repository without aur/ leave none behind.
for ro_mode in aur-status doctor; do
    noaur_repo="$tmp/noaur-$ro_mode"
    mkdir -p "$noaur_repo"
    printf '#!/bin/sh\necho hi\n' > "$noaur_repo/tool"
    git -C "$noaur_repo" init -q -b main
    git -C "$noaur_repo" add -A
    git -C "$noaur_repo" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m init
    git -C "$noaur_repo" remote add origin "https://github.com/example/demo.git"
    (cd "$noaur_repo" && env DEBUG_LEVEL=0 PATH="$stub:$PATH" XDG_STATE_HOME="$tmp/ro-state" XDG_DATA_HOME="$tmp/ro-data" \
        "$ROOT/bin/aurgen" -n "$ro_mode") >"$tmp/noaur-$ro_mode.out" 2>&1 || true
    if [[ -e "$noaur_repo/aur" ]]; then
        echo "$ro_mode created aur/"
        ls -a "$noaur_repo/aur"
        exit 1
    fi
done

# GitHub release and asset publication status in aur-status (prose and --json)
gh_proj="$tmp/gh-proj"
gh_clones="$tmp/gh-clones"
gh_clone="$gh_clones/ghpkg"
mkdir -p "$gh_proj/aur" "$gh_clone"
git -C "$gh_proj" init -q -b main
git -C "$gh_proj" config user.email "t@example.com"
git -C "$gh_proj" config user.name "t"
git -C "$gh_proj" config commit.gpgsign false
printf 'readme\n' > "$gh_proj/README"
git -C "$gh_proj" add README
git -C "$gh_proj" commit -q -m init
git -C "$gh_proj" tag v2.0.0
git -C "$gh_proj" remote add origin https://github.com/example/ghpkg.git
cat >| "$gh_proj/aur/aurgen.install.yaml" <<EOF
package:
  name: ghpkg
aur_integration:
  aur_repo_dir: $gh_clones
  auto_push: false
EOF
printf 'pkgname=ghpkg\npkgver=2.0.0\npkgrel=1\n' >| "$gh_proj/aur/PKGBUILD"
printf 'pkgbase = ghpkg\n\tpkgver = 2.0.0\n\tpkgrel = 1\n' >| "$gh_proj/aur/.SRCINFO"
git -C "$gh_clone" init -q -b main
git -C "$gh_clone" config user.email "t@example.com"
git -C "$gh_clone" config user.name "t"
git -C "$gh_clone" config commit.gpgsign false
cp "$gh_proj/aur/PKGBUILD" "$gh_clone/PKGBUILD"
cp "$gh_proj/aur/.SRCINFO" "$gh_clone/.SRCINFO"
git -C "$gh_clone" add PKGBUILD .SRCINFO
git -C "$gh_clone" commit -q -m init
gh_upstream="$tmp/gh-upstream.git"
git init -q --bare -b main "$gh_upstream"
git -C "$gh_clone" remote add origin "$gh_upstream"
git -C "$gh_clone" push -q -u origin main

install_gh_stub() {
    printf '%s\n' '#!/bin/bash' "$1" >| "$stub/gh"
    chmod +x "$stub/gh"
}

# 1. Offline / failing gh and curl gives unknown without failing aur-status
install_gh_stub 'exit 1'
install_curl_stub 'exit 1'
gh_rc=0
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-unknown.out" 2>|"$tmp/gh-unknown.err" || gh_rc=$?
(( gh_rc == 0 )) || { echo "gh-unknown exited $gh_rc"; cat "$tmp/gh-unknown.out" "$tmp/gh-unknown.err"; exit 1; }
grep -Fq 'GitHub release: v2.0.0 (tarball: unknown, signature: unknown)' "$tmp/gh-unknown.out" || { echo "gh-unknown prose mismatch"; cat "$tmp/gh-unknown.out"; exit 1; }
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/gh-unknown.json" 2>/dev/null
python3 - "$tmp/gh-unknown.json" <<'PY' || { echo "gh-unknown json invalid"; cat "$tmp/gh-unknown.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["github_release"] == {"tag": "v2.0.0", "tarball": "unknown", "signature": "unknown"}, d["github_release"]
PY

# 2. gh release view lists both tarball and .sig
install_gh_stub 'printf "%s\n" "ghpkg-2.0.0.tar.gz" "ghpkg-2.0.0.tar.gz.sig"'
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-present.out" 2>/dev/null
grep -Fq 'GitHub release: v2.0.0 (tarball: present, signature: present)' "$tmp/gh-present.out" || { echo "gh-present prose mismatch"; cat "$tmp/gh-present.out"; exit 1; }
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/gh-present.json" 2>/dev/null
python3 - "$tmp/gh-present.json" <<'PY' || { echo "gh-present json invalid"; cat "$tmp/gh-present.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["github_release"] == {"tag": "v2.0.0", "tarball": "present", "signature": "present"}, d["github_release"]
PY

# 3. gh release view lists tarball and .asc (missing for .sig default, present with -a)
install_gh_stub 'printf "%s\n" "ghpkg-2.0.0.tar.gz" "ghpkg-2.0.0.tar.gz.asc"'
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-nosig.out" 2>/dev/null
grep -Fq 'GitHub release: v2.0.0 (tarball: present, signature: missing)' "$tmp/gh-nosig.out" || { echo "gh-nosig prose mismatch"; cat "$tmp/gh-nosig.out"; exit 1; }
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -a --json aur-status) >|"$tmp/gh-asc.json" 2>/dev/null
python3 - "$tmp/gh-asc.json" <<'PY' || { echo "gh-asc json invalid"; cat "$tmp/gh-asc.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["github_release"] == {"tag": "v2.0.0", "tarball": "present", "signature": "present"}, d["github_release"]
PY

# 4. Bare tag ($pkgver) and curl -I 404 (exit 22) fallback -> missing
git -C "$gh_proj" tag -d v2.0.0 >/dev/null
git -C "$gh_proj" tag 2.0.0
install_gh_stub 'exit 1'
install_curl_stub 'for arg in "$@"; do [[ "$arg" == "-I" ]] && exit 22; done; exit 1'
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-missing.out" 2>/dev/null
grep -Fq 'GitHub release: 2.0.0 (tarball: missing, signature: missing)' "$tmp/gh-missing.out" || { echo "gh-missing prose mismatch"; cat "$tmp/gh-missing.out"; exit 1; }
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/gh-missing.json" 2>/dev/null
python3 - "$tmp/gh-missing.json" <<'PY' || { echo "gh-missing json invalid"; cat "$tmp/gh-missing.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["github_release"] == {"tag": "2.0.0", "tarball": "missing", "signature": "missing"}, d["github_release"]
PY

# 5. package.source archive omits GitHub release: line and sets github_release to null
cat >| "$gh_proj/aur/aurgen.install.yaml" <<EOF
package:
  name: ghpkg
  source: archive
aur_integration:
  aur_repo_dir: $gh_clones
  auto_push: false
EOF
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-archive.out" 2>/dev/null
if grep -Fq 'GitHub release:' "$tmp/gh-archive.out"; then
    echo "gh-archive unexpectedly printed GitHub release:"
    cat "$tmp/gh-archive.out"
    exit 1
fi
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/gh-archive.json" 2>/dev/null
python3 - "$tmp/gh-archive.json" <<'PY' || { echo "gh-archive json invalid"; cat "$tmp/gh-archive.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["github_release"] is None, d["github_release"]
PY

# 6. A -git package never has release assets: no probe, no line, github_release null.
cat >| "$gh_proj/aur/aurgen.install.yaml" <<EOF
package:
  name: ghpkg
aur_integration:
  aur_repo_dir: $gh_clones
  auto_push: false
EOF
cp "$gh_proj/aur/.SRCINFO" "$tmp/gh-release.srcinfo"
printf 'pkgbase = ghpkg-git\n\tpkgver = 2.0.0.r3.gabc1234\n\tpkgrel = 1\n\tsource = git+https://github.com/example/ghpkg.git\n' >| "$gh_proj/aur/.SRCINFO"
install_gh_stub "printf '%s\n' \"\$*\" >> \"$tmp/gh-git.log\"; exit 1"
: >| "$tmp/gh-git.log"
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-git.out" 2>/dev/null || true
if grep -Fq 'GitHub release:' "$tmp/gh-git.out" || grep -Fq 'release view' "$tmp/gh-git.log"; then
    echo "gh-git probed or printed a GitHub release for a -git package"
    cat "$tmp/gh-git.out" "$tmp/gh-git.log"
    exit 1
fi
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/gh-git.json" 2>/dev/null || true
python3 - "$tmp/gh-git.json" <<'PY' || { echo "gh-git json invalid"; cat "$tmp/gh-git.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["github_release"] is None, d["github_release"]
PY
cp "$tmp/gh-release.srcinfo" "$gh_proj/aur/.SRCINFO"

# 6b. The probe uses the tag the .SRCINFO source URL names (aur mode publishes 2.0.0
# when no v2.0.0 tag exists), not a guessed v2.0.0.
printf 'pkgbase = ghpkg\n\tpkgver = 2.0.0\n\tpkgrel = 1\n\tsource = ghpkg-2.0.0.tar.gz::https://github.com/example/ghpkg/releases/download/rel-2.0.0/ghpkg-2.0.0.tar.gz\n' >| "$gh_proj/aur/.SRCINFO"
install_gh_stub "printf '%s\n' \"\$*\" >> \"$tmp/gh-srctag.log\"; exit 1"
: >| "$tmp/gh-srctag.log"
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-srctag.out" 2>/dev/null || true
grep -Fq 'GitHub release: rel-2.0.0 (' "$tmp/gh-srctag.out" || { echo "gh-srctag: the probe did not use the source URL tag"; cat "$tmp/gh-srctag.out"; exit 1; }
cp "$tmp/gh-release.srcinfo" "$gh_proj/aur/.SRCINFO"

# 7. A gh that hangs is cut off, and the HEAD probe gets a time limit too.
install_gh_stub 'sleep 30; printf "%s\n" "ghpkg-2.0.0.tar.gz"'
install_curl_stub "printf '%s\n' \"\$*\" >> \"$tmp/curl-args.log\"; exit 22"
: >| "$tmp/curl-args.log"
start_s=$SECONDS
(cd "$gh_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/gh-hang.out" 2>/dev/null || true
(( SECONDS - start_s < 60 )) || { echo "gh-hang: aur-status took $((SECONDS - start_s))s"; exit 1; }
grep -Eq 'GitHub release: v?2\.0\.0 \(tarball: missing, signature: missing\)' "$tmp/gh-hang.out" || { echo "gh-hang: a timed-out gh did not fall back to the HEAD probe"; cat "$tmp/gh-hang.out"; exit 1; }
grep -q -- '--max-time' "$tmp/curl-args.log" || { echo "gh-hang: the HEAD probe has no --max-time"; cat "$tmp/curl-args.log"; exit 1; }
install_curl_stub 'exit 1'
install_gh_stub 'exit 1'

# Newer project version tag not packaged yet: Release line, release_pending JSON field, and exit 3
rel_proj="$tmp/rel-proj"
rel_clones="$tmp/rel-clones"
rel_clone="$rel_clones/relpkg"
mkdir -p "$rel_proj/aur" "$rel_clone"
git -C "$rel_proj" init -q -b main
git -C "$rel_proj" config user.email "t@example.com"
git -C "$rel_proj" config user.name "t"
git -C "$rel_proj" config commit.gpgsign false
printf 'readme\n' > "$rel_proj/README"
git -C "$rel_proj" add README
git -C "$rel_proj" commit -q -m init
git -C "$rel_proj" tag v1.0.0
git -C "$rel_proj" remote add origin https://github.com/example/relpkg.git
cat >| "$rel_proj/aur/aurgen.install.yaml" <<EOF
package:
  name: relpkg
aur_integration:
  aur_repo_dir: $rel_clones
  auto_push: false
EOF
printf 'pkgname=relpkg\npkgver=1.0.0\npkgrel=1\n' >| "$rel_proj/aur/PKGBUILD"
printf 'pkgbase = relpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' >| "$rel_proj/aur/.SRCINFO"
git -C "$rel_clone" init -q -b main
git -C "$rel_clone" config user.email "t@example.com"
git -C "$rel_clone" config user.name "t"
git -C "$rel_clone" config commit.gpgsign false
cp "$rel_proj/aur/PKGBUILD" "$rel_clone/PKGBUILD"
cp "$rel_proj/aur/.SRCINFO" "$rel_clone/.SRCINFO"
git -C "$rel_clone" add PKGBUILD .SRCINFO
git -C "$rel_clone" commit -q -m init
rel_upstream="$tmp/rel-upstream.git"
git init -q --bare -b main "$rel_upstream"
git -C "$rel_clone" remote add origin "$rel_upstream"
git -C "$rel_clone" push -q -u origin main

# Tag at packaged version (v1.0.0): no Release line, release_pending is null, exit 0
rel_rc=0
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/rel-match.out" 2>|"$tmp/rel-match.err" || rel_rc=$?
(( rel_rc == 0 )) || { echo "rel-match exited $rel_rc instead of 0"; cat "$tmp/rel-match.out" "$tmp/rel-match.err"; exit 1; }
if grep -Fq 'Release:' "$tmp/rel-match.out"; then
    echo "rel-match unexpectedly printed Release: line"
    cat "$tmp/rel-match.out"
    exit 1
fi
rel_json_rc=0
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/rel-match.json" 2>|"$tmp/rel-match-json.err" || rel_json_rc=$?
(( rel_json_rc == 0 )) || { echo "rel-match --json exited $rel_json_rc instead of 0"; cat "$tmp/rel-match.json" "$tmp/rel-match-json.err"; exit 1; }
python3 - "$tmp/rel-match.json" <<'PY' || { echo "rel-match --json invalid"; cat "$tmp/rel-match.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["release_pending"] is None, d["release_pending"]
assert d["pending"] is False, d["pending"]
assert d["verdict"] == "up to date", d["verdict"]
PY

# Newer tag v1.1.0 while generated and AUR .SRCINFO both say 1.0.0: prints Release line after Version, release_pending is "1.1.0", exit 3
git -C "$rel_proj" tag -a v1.1.0 -m v1.1.0
rel_rc=0
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/rel-pend.out" 2>|"$tmp/rel-pend.err" || rel_rc=$?
(( rel_rc == 3 )) || { echo "rel-pend exited $rel_rc instead of 3"; cat "$tmp/rel-pend.out" "$tmp/rel-pend.err"; exit 1; }
grep -Fq 'Release: 1.1.0 is not packaged yet; run aurgen aur' "$tmp/rel-pend.out" || { echo "rel-pend missing Release line"; cat "$tmp/rel-pend.out"; exit 1; }
awk '
    /^Version:/ { v = NR }
    /^Release: 1\.1\.0 is not packaged yet; run aurgen aur$/ { r = NR }
    END { exit !(v > 0 && r == v + 1) }
' "$tmp/rel-pend.out" || { echo "rel-pend Release line is not immediately after Version line"; cat "$tmp/rel-pend.out"; exit 1; }
rel_json_rc=0
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/rel-pend.json" 2>|"$tmp/rel-pend-json.err" || rel_json_rc=$?
(( rel_json_rc == 3 )) || { echo "rel-pend --json exited $rel_json_rc instead of 3"; cat "$tmp/rel-pend.json" "$tmp/rel-pend-json.err"; exit 1; }
python3 - "$tmp/rel-pend.json" <<'PY' || { echo "rel-pend --json invalid"; cat "$tmp/rel-pend.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["release_pending"] == "1.1.0", d["release_pending"]
assert d["pending"] is True, d["pending"]
assert d["verdict"] == "up to date", d["verdict"]
PY

# A -git package never reports Release: or release_pending
rel_git_clone="$rel_clones/relpkg-git"
cp -a "$rel_clone" "$rel_git_clone"
printf 'pkgbase = relpkg-git\n\tpkgver = 1.0.0.r0.gabc1234\n\tpkgrel = 1\n\tsource = git+https://github.com/example/relpkg.git\n' >| "$rel_proj/aur/.SRCINFO"
cp "$rel_proj/aur/.SRCINFO" "$rel_git_clone/.SRCINFO"
git -C "$rel_git_clone" add .SRCINFO
git -C "$rel_git_clone" commit -q -m 'git pkg'
git -C "$rel_git_clone" push -q origin main
rel_git_rc=0
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/rel-git.out" 2>|"$tmp/rel-git.err" || rel_git_rc=$?
(( rel_git_rc == 0 )) || { echo "rel-git exited $rel_git_rc instead of 0"; cat "$tmp/rel-git.out" "$tmp/rel-git.err"; exit 1; }
if grep -Fq 'Release:' "$tmp/rel-git.out"; then
    echo "rel-git unexpectedly printed Release: line for -git package"
    cat "$tmp/rel-git.out"
    exit 1
fi
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json aur-status) >|"$tmp/rel-git.json" 2>|"$tmp/rel-git-json.err" || true
python3 - "$tmp/rel-git.json" <<'PY' || { echo "rel-git --json invalid"; cat "$tmp/rel-git.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert d["release_pending"] is None, d["release_pending"]
assert d["pending"] is False, d["pending"]
PY

# A signed-tag release package (git+ source with #tag=) still reports an unpackaged tag.
# The -git case above pushed its clone to the same upstream; catch up first.
git -C "$rel_clone" pull -q --ff-only origin main
printf 'pkgbase = relpkg\n\tpkgver = 1.0.0\n\tpkgrel = 1\n\tsource = relpkg::git+https://github.com/example/relpkg.git#tag=v1.0.0?signed\n' >| "$rel_proj/aur/.SRCINFO"
cp "$rel_proj/aur/.SRCINFO" "$rel_clone/.SRCINFO"
git -C "$rel_clone" add .SRCINFO
git -C "$rel_clone" commit -q -m 'signed-tag source'
git -C "$rel_clone" push -q origin main
rel_st_rc=0
(cd "$rel_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/rel-st.out" 2>|"$tmp/rel-st.err" || rel_st_rc=$?
(( rel_st_rc == 3 )) || { echo "rel-signed-tag exited $rel_st_rc instead of 3"; cat "$tmp/rel-st.out" "$tmp/rel-st.err"; exit 1; }
grep -Fq 'Release: 1.1.0 is not packaged yet; run aurgen aur' "$tmp/rel-st.out" || { echo "rel-signed-tag missing Release line"; cat "$tmp/rel-st.out"; exit 1; }

# A tagless project takes pkgver from VERSION: a bumped VERSION is reported, an equal one is not.
ver_proj="$tmp/ver-proj"
cp -a "$rel_proj" "$ver_proj"
git -C "$ver_proj" tag -d v1.0.0 v1.1.0 >/dev/null
printf '1.0.0\n' >| "$ver_proj/VERSION"
ver_rc=0
(cd "$ver_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/ver-eq.out" 2>|"$tmp/ver-eq.err" || ver_rc=$?
(( ver_rc == 0 )) || { echo "ver-eq exited $ver_rc instead of 0"; cat "$tmp/ver-eq.out" "$tmp/ver-eq.err"; exit 1; }
if grep -Fq 'Release:' "$tmp/ver-eq.out"; then echo "ver-eq printed a Release line"; cat "$tmp/ver-eq.out"; exit 1; fi
printf '1.1.0\n' >| "$ver_proj/VERSION"
ver_rc=0
(cd "$ver_proj" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" aur-status) >|"$tmp/ver-new.out" 2>|"$tmp/ver-new.err" || ver_rc=$?
(( ver_rc == 3 )) || { echo "ver-new exited $ver_rc instead of 3"; cat "$tmp/ver-new.out" "$tmp/ver-new.err"; exit 1; }
grep -Fq 'Release: 1.1.0 is not packaged yet; run aurgen aur' "$tmp/ver-new.out" || { echo "ver-new missing Release line"; cat "$tmp/ver-new.out"; exit 1; }

