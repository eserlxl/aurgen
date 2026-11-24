#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen test and aurgen golden mark their local, aur and git --dry-run children with
# _AURGEN_OFFLINE_DRY_RUN=1, so those children run no gh or curl and the local gate does
# not depend on the network or gh login. The marker is refused on any real packaging run.
# Needs no terminal.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-offline.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf '%s\n' "$1"
    local f
    for f in "${@:2}"; do
        if [[ -f "$f" ]]; then
            printf -- '--- %s ---\n' "$f"
            cat "$f"
        fi
    done
    exit 1
}

unset _AURGEN_OFFLINE_DRY_RUN
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_NON_INTERACTIVE AURGEN_OVERWRITE_ASSETS \
    AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_ROLLBACK AURGEN_CONFIG_ACTION AURGEN_MODE AURGEN_RELEASE_NOTES_FILE \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT ALLOW_DIRTY SOURCE_DATE_EPOCH nocheck build_only dry_run COLOR NO_COLOR CI DEBUG_LEVEL \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO PROJECT_ROOT \
    PKG_NAME PKG_DESCRIPTION PKG_GPG_KEY PKG_INSTALL PKG_CHECK PKG_SOURCE PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS \
    PKG_DEPENDS PKG_OPTDEPENDS PKG_MAKEDEPENDS PKG_CONFLICTS PKG_PROVIDES PKG_BACKUP PKG_ARCH PKG_LICENSE \
    PKG_INSTALL_VARS PKG_POST_PACKAGE PKG_KEEP

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
export AURGEN_LOG="$tmp/aurgen.log"
export AURGEN_ERROR_LOG="$tmp/aurgen-error.log"
export GNUPGHOME="$tmp/gnupg"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
mkdir -m 700 "$GNUPGHOME"

sentinel="$tmp/network-probe.called"
stub="$tmp/bin"
mkdir -p "$stub"
for tool in makepkg updpkgsums gpg jq namcap; do
    printf '#!/bin/bash\nexit 0\n' >| "$stub/$tool"
done

# Every gh or curl call appends "<tool> mode=<AURGEN_MODE> <argv>" to the sentinel.
# fail: gh fails like an unreachable GitHub. talk: gh answers like a logged-in host that
# has a description, a v-prefixed release and the release asset.
install_shims() {
    local gh_kind="$1"
    cat >| "$stub/curl" <<EOF
#!/bin/bash
printf 'curl mode=%s %s\n' "\${AURGEN_MODE:-}" "\$*" >> '$sentinel'
exit 99
EOF
    if [[ "$gh_kind" == talk ]]; then
        cat >| "$stub/gh" <<EOF
#!/bin/bash
printf 'gh mode=%s %s\n' "\${AURGEN_MODE:-}" "\$*" >> '$sentinel'
case "\$*" in
    "repo view"*) printf '%s\n' 'From GitHub.' ;;
    *"--json assets"*) printf '%s\n' "\${PROBE_ASSET_NAME:-}" ;;
esac
exit 0
EOF
    else
        cat >| "$stub/gh" <<EOF
#!/bin/bash
printf 'gh mode=%s %s\n' "\${AURGEN_MODE:-}" "\$*" >> '$sentinel'
exit 99
EOF
    fi
    chmod +x "$stub/gh" "$stub/curl"
}

new_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" remote add origin "https://github.com/example/demo.git"
    printf '1.0.0\n' >| "$repo/VERSION"
    printf '# Demo\n\nA local demo tool.\n' >| "$repo/README.md"
    printf '#!/bin/bash\nprintf "ok\\n"\n' >| "$repo/ok.sh"
    git -C "$repo" add VERSION README.md ok.sh
    git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q -m init
}

# run_aurgen <repo> <name> [env assignments...] -- <aurgen args...>
run_aurgen() {
    local repo="$1" name="$2"
    shift 2
    local -a envs=()
    while [[ "$1" != "--" ]]; do
        envs+=("$1")
        shift
    done
    shift
    (
        cd "$repo" || exit 1
        env PATH="$stub:$PATH" ${envs[@]+"${envs[@]}"} "$ROOT/bin/aurgen" "$@"
    ) >| "$tmp/$name.out" 2>| "$tmp/$name.err" < /dev/null
}

assert_no_probe() {
    [[ ! -e "$sentinel" ]] || fail "$1: gh or curl ran" "$sentinel"
}

# A real (non-dry-run) golden parent regenerates aur/PKGBUILD.0 and may ask gh for the
# description. Every other call would come from a child.
assert_only_golden_parent_probed() {
    local line
    if [[ -e "$sentinel" ]]; then
        # shellcheck disable=SC2094 # fail only prints the file before exiting.
        while IFS= read -r line; do
            [[ "$line" == "gh mode=golden repo view "* ]] || fail "$1: a golden child ran gh or curl" "$sentinel"
        done < "$sentinel"
    fi
}

assert_test_json_ok() {
    python3 - "$1" <<'PY' || fail "$2: --json test output is not all ok" "$1"
import json, sys
raw = open(sys.argv[1]).read()
assert len(raw.splitlines()) == 1, raw
data = json.loads(raw)
assert data == {
    "ok": True,
    "errors": 0,
    "modes": [
        {"mode": "local", "ok": True},
        {"mode": "aur", "ok": True},
        {"mode": "git", "ok": True},
    ],
}, data
PY
}

assert_matches_goldens() {
    local mode
    for mode in local aur git; do
        grep -Fq "$mode PKGBUILD matches golden file." "$tmp/$1.out" "$tmp/$1.err" \
            || fail "$1: the $mode PKGBUILD was not compared equal to its golden" "$tmp/$1.err"
    done
}

# (a) gh and curl fail on use: test, then golden, then test again run no probe.
install_shims fail
repo_a="$tmp/repo-a"
new_repo "$repo_a"
rm -f "$sentinel"
run_aurgen "$repo_a" a-test-first -- --json test || fail "(a) --json test failed with fail-on-use gh and curl" "$tmp/a-test-first.err"
assert_no_probe "(a) --json test"
assert_test_json_ok "$tmp/a-test-first.out" "(a) --json test"
# No aur/PKGBUILD.0 yet, so the children generated their own from the README.
grep -Fxq "pkgdesc='A local demo tool.'" "$repo_a/aur/dry-run/PKGBUILD" \
    || fail "(a) the offline child did not take pkgdesc from the README" "$repo_a/aur/dry-run/PKGBUILD"

run_aurgen "$repo_a" a-golden-first -- golden || fail "(a) golden failed with fail-on-use gh and curl" "$tmp/a-golden-first.err"
assert_only_golden_parent_probed "(a) first golden"
rm -f "$sentinel"
for mode in local aur git; do
    [[ -f "$repo_a/aur/golden/PKGBUILD.$mode.golden" ]] || fail "(a) golden did not write the $mode golden" "$tmp/a-golden-first.err"
done
run_aurgen "$repo_a" a-golden -- golden || fail "(a) a second golden failed" "$tmp/a-golden.err"
assert_no_probe "(a) golden"
run_aurgen "$repo_a" a-test -- --json test || fail "(a) --json test after golden failed" "$tmp/a-test.err" "$tmp/a-test.out"
assert_no_probe "(a) --json test after golden"
assert_test_json_ok "$tmp/a-test.out" "(a) --json test after golden"
assert_matches_goldens a-test

# (b) gh answers with a description, a v-prefixed release and the asset; no PKG_DESCRIPTION.
# golden and test must still agree for all three modes and neither child may ask gh.
install_shims talk
export PROBE_ASSET_NAME="demo-1.0.0.tar.gz"
repo_b="$tmp/repo-b"
new_repo "$repo_b"
rm -f "$sentinel"
run_aurgen "$repo_b" b-golden -- golden || fail "(b) golden failed with a talking gh" "$tmp/b-golden.err"
assert_only_golden_parent_probed "(b) golden"
rm -f "$sentinel"
# gh would have answered v1.0.0; the offline aur child keeps the local tag name.
grep -Fq "/releases/download/1.0.0/demo-1.0.0.tar.gz" "$repo_b/aur/golden/PKGBUILD.aur.golden" \
    || fail "(b) the aur golden did not use the local release tag" "$repo_b/aur/golden/PKGBUILD.aur.golden"
if grep -Fq "/releases/download/v1.0.0/" "$repo_b/aur/golden/PKGBUILD.aur.golden"; then
    fail "(b) the aur golden took its release tag from gh" "$repo_b/aur/golden/PKGBUILD.aur.golden"
fi
run_aurgen "$repo_b" b-test -- --json test || fail "(b) --json test after golden failed with a talking gh" "$tmp/b-test.err" "$tmp/b-test.out"
assert_no_probe "(b) --json test"
assert_test_json_ok "$tmp/b-test.out" "(b) --json test"
assert_matches_goldens b-test
unset PROBE_ASSET_NAME

# (c) A real local, aur or git run refuses the marker before it writes or probes anything.
install_shims fail
repo_c="$tmp/repo-c"
new_repo "$repo_c"
rm -f "$sentinel"
for mode in local aur git; do
    if run_aurgen "$repo_c" "c-$mode" _AURGEN_OFFLINE_DRY_RUN=1 -- "$mode"; then
        fail "(c) _AURGEN_OFFLINE_DRY_RUN=1 aurgen $mode without --dry-run succeeded" "$tmp/c-$mode.err"
    else
        status=$?
    fi
    [[ "$status" -eq 1 ]] || fail "(c) aurgen $mode with the marker exited $status, not 1" "$tmp/c-$mode.err"
    grep -Fq "_AURGEN_OFFLINE_DRY_RUN" "$tmp/c-$mode.err" || fail "(c) the $mode refusal does not name _AURGEN_OFFLINE_DRY_RUN" "$tmp/c-$mode.err"
    [[ ! -e "$repo_c/aur/PKGBUILD" ]] || fail "(c) aurgen $mode with the marker wrote aur/PKGBUILD"
    [[ ! -e "$repo_c/aur" ]] || fail "(c) aurgen $mode with the marker created aur/ before refusing"
    assert_no_probe "(c) aurgen $mode with the marker"
done

# (d) Only 0 and 1 are accepted.
if run_aurgen "$repo_c" d-yes _AURGEN_OFFLINE_DRY_RUN=yes -- --dry-run local; then
    fail "(d) _AURGEN_OFFLINE_DRY_RUN=yes was accepted" "$tmp/d-yes.err"
else
    status=$?
fi
[[ "$status" -eq 1 ]] || fail "(d) _AURGEN_OFFLINE_DRY_RUN=yes exited $status, not 1" "$tmp/d-yes.err"
grep -Fq "Invalid _AURGEN_OFFLINE_DRY_RUN: yes" "$tmp/d-yes.err" || fail "(d) missing Invalid _AURGEN_OFFLINE_DRY_RUN error" "$tmp/d-yes.err"
[[ ! -e "$repo_c/aur" ]] || fail "(d) _AURGEN_OFFLINE_DRY_RUN=yes created aur/ before refusing"
run_aurgen "$repo_c" d-zero _AURGEN_OFFLINE_DRY_RUN=0 -- --usage || fail "(d) _AURGEN_OFFLINE_DRY_RUN=0 was refused" "$tmp/d-zero.err"

# (e) With the marker, a dry-run aur child skips the asset probe, says so, and reports release "none".
# DRY_RUN=1 is a dry run too.
if ! run_aurgen "$repo_c" e-aur _AURGEN_OFFLINE_DRY_RUN=1 DRY_RUN=1 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN -- --json aur; then
    fail "(e) an offline DRY_RUN=1 aur run failed" "$tmp/e-aur.err"
fi
assert_no_probe "(e) offline dry-run aur"
grep -Fq "[aur] (dry run, offline) asset probe skipped" "$tmp/e-aur.err" "$tmp/e-aur.out" \
    || fail "(e) the offline asset-probe skip was not reported" "$tmp/e-aur.err"
if grep -Fq -e "Asset is missing" -e "GitHub could not be reached" "$tmp/e-aur.err" "$tmp/e-aur.out"; then
    fail "(e) the skipped probe was reported as a missing asset or an unreachable GitHub" "$tmp/e-aur.err"
fi
python3 - "$tmp/e-aur.out" <<'PY' || fail "(e) aur --json did not report release none" "$tmp/e-aur.out"
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["release"] == "none", data
assert data["release_tag"] == "1.0.0", data
assert data["dry_run"] is True, data
PY
# The shims are live: the same dry run without the marker probes GitHub.
run_aurgen "$repo_c" e-online GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN -- --dry-run aur || true
[[ -s "$sentinel" ]] || fail "(e) a dry run without the marker ran no gh or curl, so the shims prove nothing" "$tmp/e-online.err"
rm -f "$sentinel"

# (f) The probe sites honor the marker only on a dry run, even if bin/aurgen's check were bypassed.
install_shims talk
repo_f="$tmp/repo-f"
new_repo "$repo_f"
mkdir -p "$repo_f/aur"
rm -f "$sentinel"
(
    export PATH="$stub:$PATH"
    export LIB_INSTALL_DIR="$ROOT/lib" PROJECT_ROOT="$repo_f" AUR_DIR="$repo_f/aur" PKGNAME=demo
    export AURGEN_MODE=test GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN color_enabled=0 DEBUG_LEVEL=0
    export _AURGEN_OFFLINE_DRY_RUN=1 dry_run=0
    # shellcheck source=../lib/gen-pkgbuild0.sh
    source "$ROOT/lib/gen-pkgbuild0.sh"
    load_aurgen_config
    gen_pkgbuild0
) >| "$tmp/f-gen.out" 2>| "$tmp/f-gen.err" < /dev/null || fail "(f) gen_pkgbuild0 failed" "$tmp/f-gen.err"
grep -Fxq "pkgdesc='From GitHub.'" "$repo_f/aur/PKGBUILD.0" \
    || fail "(f) a non-dry-run gen_pkgbuild0 with the marker skipped gh repo view" "$repo_f/aur/PKGBUILD.0"
grep -Fq "gh mode=test repo view" "$sentinel" || fail "(f) gen_pkgbuild0 did not ask gh for the description" "$sentinel"
rm -f "$sentinel"

# shellcheck disable=SC2034 # The sourced aur.sh functions read these globals.
aur_probe_site() (
    export PATH="$stub:$PATH"
    export AURGEN_LOG="$tmp/f-site.log" AURGEN_ERROR_LOG="$tmp/f-site-err.log" color_enabled=0 DEBUG_LEVEL=0
    export _AURGEN_OFFLINE_DRY_RUN=1 PROBE_ASSET_NAME="demo-1.0.0.tar.gz"
    dry_run="$1"
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/modes/aur.sh
    source "$ROOT/lib/modes/aur.sh"
    # Everything after the probe is another test's subject.
    aur_upload_assets() { :; }
    aur_verify_published_assets() { :; }
    update_source_array_in_pkgbuild() { :; }
    write_validpgpkeys() { :; }
    update_checksums() { :; }
    PKGVER=1.0.0 PROJECT_ROOT="$repo_f" GH_USER=example repo_name=demo
    PKGBUILD="$tmp/f-PKGBUILD" TARBALL="demo-1.0.0.tar.gz" SIGNATURE_EXT=".sig" out="$tmp"
    printf "pkgname=demo\nb2sums=('SKIP' 'SKIP')\n" >| "$PKGBUILD"
    RELEASE_TAG="" asset_exists=0 assets_uploaded=0 release_state="none"
    _aur_resolve_release_tag
    printf 'tag=%s\n' "$RELEASE_TAG"
    TARBALL_URL="https://github.com/example/demo/releases/download/1.0.0/demo-1.0.0.tar.gz"
    RELEASE_TAG=1.0.0
    _aur_publish_release_assets
    printf 'release_state=%s\n' "$release_state"
)

aur_probe_site 0 >| "$tmp/f-aur-real.out" 2>| "$tmp/f-aur-real.err" < /dev/null || fail "(f) the aur probe sites failed on a real run" "$tmp/f-aur-real.err"
grep -Fxq "tag=v1.0.0" "$tmp/f-aur-real.out" || fail "(f) a real run with the marker skipped gh release view" "$tmp/f-aur-real.out"
grep -Fxq "release_state=existing" "$tmp/f-aur-real.out" || fail "(f) a real run with the marker skipped the asset probe" "$tmp/f-aur-real.out"
grep -Fq "gh mode= release view v1.0.0 --repo example/demo" "$sentinel" || fail "(f) gh release view did not run on a real run" "$sentinel"
grep -Fq -- "--json assets" "$sentinel" || fail "(f) the asset probe did not run on a real run" "$sentinel"
rm -f "$sentinel"

aur_probe_site 1 >| "$tmp/f-aur-dry.out" 2>| "$tmp/f-aur-dry.err" < /dev/null || fail "(f) the aur probe sites failed on a dry run" "$tmp/f-aur-dry.err"
assert_no_probe "(f) offline dry-run aur probe sites"
grep -Fxq "tag=1.0.0" "$tmp/f-aur-dry.out" || fail "(f) the offline dry run did not keep the local tag" "$tmp/f-aur-dry.out"
grep -Fxq "release_state=none" "$tmp/f-aur-dry.out" || fail "(f) the offline dry run changed release_state" "$tmp/f-aur-dry.out"
grep -Fq "[aur] (dry run, offline) asset probe skipped" "$tmp/f-aur-dry.out" "$tmp/f-aur-dry.err" \
    || fail "(f) the offline dry run did not report the skipped probe" "$tmp/f-aur-dry.out"

echo "offline probe tests passed"
