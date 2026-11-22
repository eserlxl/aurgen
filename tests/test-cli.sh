#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Unknown options are parse errors, not a missing GNU getopt.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-cli.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf '%s\n' "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        cat "$2"
    fi
    exit 1
}

# Check runner isolation before this fixture replaces any destinations.
if [[ -n "${AURGEN_TEST_STATE_ROOT:-}" ]]; then
    [[ "$HOME" == "$AURGEN_TEST_STATE_ROOT/home" && "${XDG_CONFIG_HOME:-}" == "$AURGEN_TEST_STATE_ROOT/config" ]] || fail "runner did not isolate HOME and XDG_CONFIG_HOME"
    [[ "${TMPDIR:-}" == "$AURGEN_TEST_STATE_ROOT/tmp" && "$tmp" == "$AURGEN_TEST_STATE_ROOT/tmp/"* ]] || fail "runner did not isolate TMPDIR"
    global_config="$(env GIT_CONFIG_COUNT=0 git config --global --list)" || fail "runner global Git config is unreadable"
    [[ -z "$global_config" ]] || fail "runner inherited global Git config after fixture overrides"
    [[ -z "${RELEASE+x}" ]] || fail "runner kept the caller's RELEASE=$RELEASE"
    [[ -z "${REPO_NAME+x}" && -z "${DRY_RUN+x}" && -z "${NO_WAIT+x}" && -z "${ALLOW_DIRTY+x}" && -z "${AUR_PREVIEW_SRCINFO+x}" && -z "${AURGEN_CONFIG_FILE+x}" && -z "${AURGEN_MAKEPKG_FLAGS+x}" && -z "${AURGEN_NOCHECK+x}" && -z "${AURGEN_NON_INTERACTIVE+x}" && -z "${AURGEN_OVERWRITE_ASSETS+x}" && -z "${nocheck+x}" && -z "${build_only+x}" && -z "${AURGEN_JSON+x}" && -z "${AURGEN_STATUS_DIFF+x}" && -z "${AURGEN_ROLLBACK+x}" && -z "${AURGEN_CONFIG_ACTION+x}" && -z "${PKG_URL+x}" && -z "${PKG_EPOCH+x}" && -z "${PKG_REPLACES+x}" && -z "${PKG_OPTIONS+x}" ]] || fail "runner kept caller CLI/env overrides"
fi

export AURGEN_LOG="$tmp/aurgen.log"
export AURGEN_ERROR_LOG="$tmp/aurgen-error.log"
# bin/aurgen creates its state dir and aur mode reads the AUR clone dir; keep both in tmp.
export XDG_STATE_HOME="$tmp/state"
export XDG_DATA_HOME="$tmp/data"
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export GNUPGHOME="$tmp/gnupg"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
mkdir -m 700 "$GNUPGHOME"
unset GIT_CONFIG GIT_CONFIG_PARAMETERS RELEASE AURGEN_LIB_DIR AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV AURGEN_PUSH_TAG \
    AURGEN_CHROOT_DIR AURGEN_CONFIG_FILE AURGEN_MAKEPKG_FLAGS AURGEN_NOCHECK AURGEN_NON_INTERACTIVE AURGEN_OVERWRITE_ASSETS AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_ROLLBACK AURGEN_CONFIG_ACTION \
    GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
    DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT ALLOW_DIRTY SOURCE_DATE_EPOCH nocheck build_only COLOR NO_COLOR CI DEBUG_LEVEL \
    AUR_DIR OUT_DIR PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
    PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS

expect_parse_error() {
    local name="$1"
    shift
    if "$ROOT/bin/aurgen" "$@" >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail "$name: expected a non-zero exit" "$tmp/$name.err"
    fi
    if ! grep -F -q 'Failed to parse options' "$tmp/$name.err"; then
        fail "$name: missing parse error" "$tmp/$name.err"
    fi
    if grep -F -q 'GNU getopt required' "$tmp/$name.err"; then
        fail "$name: reported a missing getopt" "$tmp/$name.err"
    fi
    if ! grep -F -q 'Usage: aurgen' "$tmp/$name.out"; then
        fail "$name: missing usage" "$tmp/$name.out"
    fi
}

expect_parse_error bogus --bogus
expect_parse_error maxdepth --maxdepth

for mode in local aur git; do
    if (cd "$tmp" && "$ROOT/bin/aurgen" --build-only --deploy "$mode") >|"$tmp/build-deploy.out" 2>|"$tmp/build-deploy.err"; then
        fail "--build-only --deploy $mode should fail" "$tmp/build-deploy.out"
    fi
    grep -F -q -- '--build-only cannot be combined with --deploy' "$tmp/build-deploy.err" || fail "build-only deploy refusal did not explain the error" "$tmp/build-deploy.err"
done
if (cd "$tmp" && "$ROOT/bin/aurgen" --build-only lint) >|"$tmp/build-only.out" 2>|"$tmp/build-only.err"; then
    fail "--build-only lint should fail" "$tmp/build-only.out"
fi
grep -F -q -- '--build-only is only valid with local, aur or git' "$tmp/build-only.err" || fail "build-only mode refusal did not explain the error" "$tmp/build-only.err"
[[ ! -e "$tmp/aur" ]] || fail "invalid build-only options should fail before initialization"

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "t@example.com"
git -C "$repo" config user.name "t"
git -C "$repo" config commit.gpgsign false
printf '#!/bin/bash\nprintf ok\n' > "$repo/ok.sh"
chmod +x "$repo/ok.sh"
git -C "$repo" add ok.sh
git -C "$repo" commit -q -m init
git -C "$repo" remote add origin "https://github.com/example/demo.git"

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/makepkg"
printf '#!/bin/bash\nexit 0\n' > "$stub/updpkgsums"
printf '#!/bin/bash\nexit 22\n' > "$stub/curl"
# Logged in; no release exists yet; creating and uploading succeed.
cat > "$stub/gh" <<'EOF'
#!/bin/bash
case "${1:-} ${2:-}" in
    "auth status"|"release create"|"release upload") exit 0 ;;
esac
exit 1
EOF
chmod +x "$stub/makepkg" "$stub/updpkgsums" "$stub/curl" "$stub/gh"

run_in_repo() {
    local name="$1"
    shift
    if ! (cd "$repo" && "$@") >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail "$name failed" "$tmp/$name.err"
    fi
}

mkdir -p "$repo/aur"
printf 'package:\n  name: demo\n' >| "$repo/aur/aurgen.install.yaml"
run_in_repo release-debug env PATH="$stub:$PATH" RELEASE=1 DEBUG_LEVEL=1 AURGEN_LIB_DIR="$ROOT/lib" "$ROOT/bin/aurgen" lint
grep -F -q '[DEBUG] [config] Loading configuration from' "$tmp/release-debug.out" || fail "release ignored DEBUG_LEVEL=1" "$tmp/release-debug.out"
run_in_repo release-quiet env -u DEBUG_LEVEL PATH="$stub:$PATH" RELEASE=1 AURGEN_LIB_DIR="$ROOT/lib" "$ROOT/bin/aurgen" lint
if grep -F -q '[DEBUG]' "$tmp/release-quiet.out" "$tmp/release-quiet.err"; then
    fail "release enabled debug logging by default" "$tmp/release-quiet.out"
fi
rm "$repo/aur/aurgen.install.yaml"

run_in_repo lint-env env PATH="$stub:$PATH" MAXDEPTH=2 "$ROOT/bin/aurgen" lint
if ! grep -E -q 'depth 2([^0-9]|$)' "$tmp/lint-env.out"; then
    fail "MAXDEPTH=2 lint did not log depth 2" "$tmp/lint-env.out"
fi

run_in_repo lint-flag env PATH="$stub:$PATH" MAXDEPTH=9 "$ROOT/bin/aurgen" --maxdepth 2 lint
if ! grep -E -q 'depth 2([^0-9]|$)' "$tmp/lint-flag.out"; then
    fail "--maxdepth did not override MAXDEPTH" "$tmp/lint-flag.out"
fi
if grep -E -q 'depth 9([^0-9]|$)' "$tmp/lint-flag.out"; then
    fail "--maxdepth kept the MAXDEPTH value" "$tmp/lint-flag.out"
fi

# Git lint includes new scripts, skips ignored/generated paths and respects depth.
(
    repo="$tmp/lint-repo"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" remote add origin https://github.com/example/lint-repo.git
    printf 'node_modules/\nbuild/\n' >| "$repo/.gitignore"
    mkdir -p "$repo/node_modules" "$repo/build" "$repo/aur" "$repo/Backups" \
        "$repo/nested/aur" "$repo/nested/Backups" "$repo/nested/deep"
    printf '#!/bin/bash\nprintf ok\n' >| "$repo/ok.sh"
    printf '#!/bin/bash\nif\n' >| "$repo/deleted.sh"
    git -C "$repo" add .gitignore ok.sh deleted.sh
    rm "$repo/deleted.sh"
    for path in node_modules/broken.sh build/broken.sh aur/broken.sh Backups/broken.sh \
        nested/aur/broken.sh nested/Backups/broken.sh nested/deep/broken.sh; do
        printf '#!/bin/bash\nif\n' >| "$repo/$path"
    done
    printf '#!/bin/bash\nprintf ok\n' >| "$repo/nested/ok.sh"
    run_in_repo lint-git env PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 2 lint
    grep -F -q 'nested/ok.sh' "$tmp/lint-git.out" || fail "lint skipped a file at maxdepth" "$tmp/lint-git.out"

    printf '#!/bin/bash\nif\n' >| "$repo/new.sh"
    if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 2 lint) >|"$tmp/lint-new.out" 2>|"$tmp/lint-new.err"; then
        fail "lint accepted a broken untracked script" "$tmp/lint-new.out"
    fi
    grep -F -q 'new.sh' "$tmp/lint-new.out" || fail "lint did not report the new script" "$tmp/lint-new.out"
    rm "$repo/new.sh"

    printf '#!/bin/bash\nif\n' >| "$repo/new-command"
    if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 2 lint) >|"$tmp/lint-shebang.out" 2>|"$tmp/lint-shebang.err"; then
        fail "lint accepted a broken extensionless Bash script" "$tmp/lint-shebang.out"
    fi
    grep -F -q 'new-command' "$tmp/lint-shebang.out" || fail "lint did not report the Bash shebang script" "$tmp/lint-shebang.out"
    rm "$repo/new-command"

    if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 3 lint) >|"$tmp/lint-depth.out" 2>|"$tmp/lint-depth.err"; then
        fail "lint skipped a broken script at maxdepth 3" "$tmp/lint-depth.out"
    fi
    grep -F -q 'nested/deep/broken.sh' "$tmp/lint-depth.out" || fail "lint did not report the deeper script" "$tmp/lint-depth.out"
    rm "$repo/nested/deep/broken.sh"
    run_in_repo lint-generated env PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 3 lint
) || exit 1

run_in_repo local-env env PATH="$stub:$PATH" DRY_RUN=1 "$ROOT/bin/aurgen" local
if ! grep -F -q 'Dry run: skipping install' "$tmp/local-env.out"; then
    fail "DRY_RUN=1 local did not skip install" "$tmp/local-env.out"
fi

run_in_repo local-flag env PATH="$stub:$PATH" DRY_RUN=0 "$ROOT/bin/aurgen" -d local
if ! grep -F -q 'Dry run: skipping install' "$tmp/local-flag.out"; then
    fail "-d did not override DRY_RUN=0" "$tmp/local-flag.out"
fi

run_in_repo aur-env env PATH="$stub:$PATH" DRY_RUN=0 NO_WAIT=1 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$ROOT/bin/aurgen" aur
if ! grep -F -q 'Asset(s) uploaded.' "$tmp/aur-env.out"; then
    fail "aur-env did not upload missing release assets" "$tmp/aur-env.out"
fi
if ! grep -F -q 'Skipping post-upload wait' "$tmp/aur-env.err"; then
    fail "NO_WAIT=1 aur did not skip the upload wait" "$tmp/aur-env.err"
fi
if grep -F -q 'Waiting for GitHub to propagate' "$tmp/aur-env.err"; then
    fail "NO_WAIT=1 aur still waited" "$tmp/aur-env.err"
fi

run_in_repo aur-flag env PATH="$stub:$PATH" DRY_RUN=0 NO_WAIT=0 GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$ROOT/bin/aurgen" --no-wait aur
if ! grep -F -q 'Skipping post-upload wait' "$tmp/aur-flag.err"; then
    fail "--no-wait did not override NO_WAIT=0" "$tmp/aur-flag.err"
fi

# Build the final recipe with isolated tools; no network, signing, or installation.
(
    stub="$tmp/build-bin"
    mkdir -p "$stub" "$tmp/chroot/root"
    export BUILD_TRACE="$tmp/build.trace" BUILT="$tmp/built.pkg.tar.zst"
    export RECIPE_BUILT="$tmp/recipe-built" REAL_GIT
    REAL_GIT="$(command -v git)"
    export PATH="$stub:$PATH" DRY_RUN=0
    unset AURGEN_CHROOT_DIR
    cat >| "$stub/git" <<'EOF'
#!/bin/bash
args=("$@")
[[ "${1:-}" != -C ]] || shift 2
case "${1:-}" in
    ls-remote) exit 0 ;;
    verify-tag)
        printf '[GNUPG:] VALIDSIG 0123456789ABCDEF0123456789ABCDEF01234567\n'
        exit 0 ;;
    push|clone|fetch|archive)
        printf 'forbidden git %s\n' "$*" >> "$BUILD_TRACE"
        exit 99 ;;
esac
exec "$REAL_GIT" "${args[@]}"
EOF
    cat >| "$stub/makepkg" <<'EOF'
#!/bin/bash
printf 'makepkg %s|%s\n' "$PWD" "$*" >> "$BUILD_TRACE"
case "${1:-}" in
    --printsrcinfo) printf 'pkgbase = demo\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' ;;
    -sf)
        cp PKGBUILD "$RECIPE_BUILT" || exit 1
        (( ${BUILD_STATUS:-0} == 0 )) || exit "$BUILD_STATUS"
        printf 'pkg\n' >| "$BUILT" ;;
    --packagelist) printf '%s\n' "$BUILT" ;;
    *) exit 99 ;;
esac
EOF
    cat >| "$stub/makechrootpkg" <<'EOF'
#!/bin/bash
printf 'makechrootpkg %s|%s\n' "$PWD" "$*" >> "$BUILD_TRACE"
cp PKGBUILD "$RECIPE_BUILT" || exit 1
(( ${BUILD_STATUS:-0} == 0 )) || exit "$BUILD_STATUS"
printf 'pkg\n' >| "$BUILT"
EOF
    cat >| "$stub/namcap" <<'EOF'
#!/bin/bash
printf 'namcap %s\n' "$*" >> "$BUILD_TRACE"
if [[ "${NAMCAP_ERROR:-0}" == 1 ]]; then
    printf '%s E: stub package error\n' "$1"
    exit 1
fi
EOF
    cat >| "$stub/updpkgsums" <<'EOF'
#!/bin/bash
[[ -f PKGBUILD ]] || exit 1
sed -i "s/^b2sums=.*/b2sums=('deadbeef')/" PKGBUILD
EOF
    for tool in curl gh gpg ssh scp pacman; do
        cat >| "$stub/$tool" <<'EOF'
#!/bin/bash
if [[ "${0##*/}" == gh && "${1:-} ${2:-}" == 'repo view' ]]; then
    printf 'Test package\n'
    exit 0
fi
printf 'forbidden %s %s\n' "${0##*/}" "$*" >> "$BUILD_TRACE"
exit 99
EOF
    done
    chmod +x "$stub/"*

    # AUR lookup stays local, and the signed-tag fixture needs no real key.
    mkdir -p "$XDG_DATA_HOME/aurgen/aur/demo"
    printf 'pkgbase = demo\n\tpkgver = 0.9\n\tpkgrel = 1\n' >| "$XDG_DATA_HOME/aurgen/aur/demo/.SRCINFO"
    commit="$(git -C "$repo" rev-parse HEAD)"
    tagsha="$(printf 'object %s\ntype commit\ntag v1.0.0\ntagger Test <t@example.com> 1700000000 +0000\n\nv1.0.0\n\n-----BEGIN PGP SIGNATURE-----\n\nZmFrZQ==\n-----END PGP SIGNATURE-----\n' "$commit" | git -C "$repo" hash-object -t tag -w --stdin)"
    git -C "$repo" update-ref refs/tags/v1.0.0 "$tagsha"
    printf '1.0.0\n' >| "$repo/VERSION"

    for kind in local archive signed-tag git; do
        mode=aur
        [[ "$kind" != git && "$kind" != local ]] || mode="$kind"
        source_kind="$kind"
        [[ "$kind" != git && "$kind" != local ]] || source_kind=release
        printf 'package:\n  name: demo\n  source: %s\n' "$source_kind" >| "$repo/aur/aurgen.install.yaml"
        for builder in host chroot; do
            unset AURGEN_CHROOT_DIR
            [[ "$builder" != chroot ]] || export AURGEN_CHROOT_DIR="$tmp/chroot"
            : >| "$BUILD_TRACE"
            run_in_repo "build-$kind-$builder" "$ROOT/bin/aurgen" --build-only "$mode"
            cmp -s "$RECIPE_BUILT" "$repo/aur/PKGBUILD" || fail "$kind $builder did not build the final recipe"
            case "$kind" in
                archive) source_pattern='/archive/refs/tags/' ;;
                signed-tag) source_pattern='?signed' ;;
                git) source_pattern='.git#branch=' ;;
                local) source_pattern='source=("demo-1.0.0.tar.gz")' ;;
            esac
            grep -F -q "$source_pattern" "$RECIPE_BUILT" || fail "$kind built the wrong source" "$RECIPE_BUILT"
            grep -Fx -q "namcap $BUILT" "$BUILD_TRACE" || fail "$kind $builder skipped package namcap" "$BUILD_TRACE"
            if [[ "$builder" == host ]]; then
                grep -Fx -q "makepkg $repo/aur|-sf" "$BUILD_TRACE" || fail "$kind did not build in OUT_DIR" "$BUILD_TRACE"
            else
                grep -Fx -q "makechrootpkg $repo/aur|-c -r $tmp/chroot" "$BUILD_TRACE" || fail "$kind ignored the chroot" "$BUILD_TRACE"
                ! grep -F -q '|-sf' "$BUILD_TRACE" || fail "$kind chroot built on the host" "$BUILD_TRACE"
            fi
            ! grep -E -q 'forbidden|\|(-i|-sif)( |$)' "$BUILD_TRACE" || fail "$kind installed or published" "$BUILD_TRACE"

            if (cd "$repo" && BUILD_STATUS=17 "$ROOT/bin/aurgen" --build-only "$mode") >|"$tmp/build-fail.out" 2>|"$tmp/build-fail.err"; then
                fail "$kind $builder hid the build failure"
            fi
            if (cd "$repo" && NAMCAP_ERROR=1 "$ROOT/bin/aurgen" --build-only "$mode") >|"$tmp/namcap-fail.out" 2>|"$tmp/namcap-fail.err"; then
                fail "$kind $builder hid the package namcap failure"
            fi
        done
        unset AURGEN_CHROOT_DIR
        : >| "$BUILD_TRACE"
        run_in_repo "build-$kind-dry" "$ROOT/bin/aurgen" --build-only --dry-run "$mode"
        ! grep -E -q 'makechrootpkg|\|-sf|namcap |forbidden' "$BUILD_TRACE" || fail "$kind dry run built or published" "$BUILD_TRACE"
    done
    for kind in release default; do
        printf 'package:\n  name: demo\n' >| "$repo/aur/aurgen.install.yaml"
        [[ "$kind" != release ]] || printf '  source: release\n' >> "$repo/aur/aurgen.install.yaml"
        # Cover both an existing template and rejection during template generation.
        rm -f "$repo/aur/.PKGBUILD.0.stamp"
        [[ "$kind" != default ]] || rm -f "$repo/aur/PKGBUILD.0"
        : >| "$BUILD_TRACE"
        if (cd "$repo" && "$ROOT/bin/aurgen" --build-only aur) >|"$tmp/release-build.out" 2>|"$tmp/release-build.err"; then
            fail "$kind release source accepted --build-only"
        fi
        grep -F -q -- '--build-only is not supported with package.source=release' "$tmp/release-build.err" || fail "release refusal did not explain the error" "$tmp/release-build.err"
        ! grep -E -q 'forbidden|\|-sf|makechrootpkg' "$BUILD_TRACE" || fail "release refusal happened after side effects" "$BUILD_TRACE"
        [[ ! -e "$repo/aur/demo-1.0.0.tar.gz" && ! -e "$repo/aur/demo-1.0.0.tar.gz.sig" ]] || fail "release refusal created assets"
    done
    # --nocheck and AURGEN_MAKEPKG_FLAGS through bin/aurgen in host and chroot build-only runs
    printf 'package:\n  name: demo\n  source: release\n' >| "$repo/aur/aurgen.install.yaml"
    unset AURGEN_CHROOT_DIR
    : >| "$BUILD_TRACE"
    run_in_repo "build-nocheck-host" env AURGEN_MAKEPKG_FLAGS="--cleanbuild --noconfirm" "$ROOT/bin/aurgen" --build-only --nocheck git
    grep -Fx -q "makepkg $repo/aur|-sf --nocheck --cleanbuild --noconfirm" "$BUILD_TRACE" || fail "CLI --nocheck + AURGEN_MAKEPKG_FLAGS host mismatch" "$BUILD_TRACE"

    export AURGEN_CHROOT_DIR="$tmp/chroot"
    : >| "$BUILD_TRACE"
    run_in_repo "build-nocheck-chroot" env AURGEN_MAKEPKG_FLAGS="--holdver" "$ROOT/bin/aurgen" --build-only --nocheck local
    grep -Fx -q "makechrootpkg $repo/aur|-c -r $tmp/chroot -- --nocheck --holdver" "$BUILD_TRACE" || fail "CLI --nocheck + AURGEN_MAKEPKG_FLAGS chroot mismatch" "$BUILD_TRACE"
    unset AURGEN_CHROOT_DIR

    # --build-only must refuse install flags from AURGEN_MAKEPKG_FLAGS before makepkg runs.
    for install_flag in --install -si; do
        : >| "$BUILD_TRACE"
        if (cd "$repo" && AURGEN_MAKEPKG_FLAGS="$install_flag" "$ROOT/bin/aurgen" --build-only local) >|"$tmp/build-install-flag.out" 2>|"$tmp/build-install-flag.err"; then
            fail "--build-only local accepted AURGEN_MAKEPKG_FLAGS=$install_flag" "$tmp/build-install-flag.out"
        fi
        grep -F -q -- "$install_flag" "$tmp/build-install-flag.err" || fail "--build-only did not name refused flag $install_flag" "$tmp/build-install-flag.err"
        if grep -F -q -- "$install_flag" "$BUILD_TRACE"; then
            fail "--build-only called makepkg with $install_flag" "$BUILD_TRACE"
        fi
    done
    : >| "$BUILD_TRACE"
    run_in_repo "build-only-plain-nocheck" env AURGEN_MAKEPKG_FLAGS="--nocheck" "$ROOT/bin/aurgen" --build-only local
    grep -Fx -q "makepkg $repo/aur|-sf --nocheck" "$BUILD_TRACE" || fail "AURGEN_MAKEPKG_FLAGS=--nocheck did not build under --build-only" "$BUILD_TRACE"
) || exit 1

if "$ROOT/bin/aurgen" --maxdepth abc lint >"$tmp/maxdepth.out" 2>"$tmp/maxdepth.err"; then
    fail "--maxdepth abc should fail" "$tmp/maxdepth.out"
fi
if ! grep -F -q 'Invalid --maxdepth: abc (expected a positive integer)' "$tmp/maxdepth.err"; then
    fail "--maxdepth abc did not explain the error" "$tmp/maxdepth.err"
fi
run_in_repo maxdepth-ok env PATH="$stub:$PATH" "$ROOT/bin/aurgen" --maxdepth 3 lint

# clean has no dry run, so --dry-run clean is refused and deletes nothing.
mkdir -p "$repo/aur"
printf 'pkgname=demo\n' > "$repo/aur/PKGBUILD"
if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --dry-run clean) >"$tmp/dry-clean.out" 2>"$tmp/dry-clean.err"; then
    fail "--dry-run clean should fail" "$tmp/dry-clean.out"
fi
[[ -f "$repo/aur/PKGBUILD" ]] || fail "--dry-run clean deleted aur/PKGBUILD" "$tmp/dry-clean.err"

# golden cleans and regenerates outputs, so it has no dry run either.
if (cd "$repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" --dry-run golden) >|"$tmp/dry-golden.out" 2>|"$tmp/dry-golden.err"; then
    fail "--dry-run golden should fail" "$tmp/dry-golden.out"
fi
[[ -f "$repo/aur/PKGBUILD" ]] || fail "--dry-run golden deleted aur/PKGBUILD" "$tmp/dry-golden.err"
[[ "$(cat "$repo/aur/PKGBUILD")" == 'pkgname=demo' ]] || fail "--dry-run golden changed aur/PKGBUILD" "$tmp/dry-golden.err"
grep -F -q '[golden] golden has no dry run: it cleans and regenerates aur/ outputs' "$tmp/dry-golden.err" || fail "--dry-run golden did not explain the error" "$tmp/dry-golden.err"

# A non-GitHub remote is refused before cleanup removes existing artifacts, even
# when github.com appears elsewhere in the URL.
other="$tmp/other"
mkdir -p "$other/aur"
git -C "$other" init -q -b main
git -C "$other" remote add origin "https://gitlab.com/example/demo.git"
for url in "https://gitlab.com/example/demo.git" "https://evilgithub.com/example/demo.git" \
    "https://gitlab.com/github.com/demo.git" "git@notgithub.com:example/demo.git"; do
    git -C "$other" remote set-url origin "$url"
    printf 'pkgname=demo\n' > "$other/aur/PKGBUILD"
    if (cd "$other" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/gitlab.out" 2>"$tmp/gitlab.err"; then
        fail "remote $url should be refused" "$tmp/gitlab.out"
    fi
    if ! grep -F -q 'only supports GitHub projects' "$tmp/gitlab.err"; then
        fail "refusal of $url did not name the GitHub requirement" "$tmp/gitlab.err"
    fi
    if [[ ! -f "$other/aur/PKGBUILD" ]]; then
        fail "refused run for $url deleted aur/PKGBUILD" "$tmp/gitlab.err"
    fi
done

# aurgen's own package (aurgen and aurgen-git alike) installs its lib and VERSION
# where the installed bin/aurgen looks for them.
grep -F -q 'LIB_INSTALL_DIR="/usr/lib/aurgen"' "$ROOT/bin/aurgen" || fail "bin/aurgen no longer searches /usr/lib/aurgen"
(
    export AUR_DIR="$ROOT/aur" AURGEN_ERROR_LOG="$tmp/own-config.err" DEBUG_LEVEL=0 color_enabled=0
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    # shellcheck source=../lib/config.sh
    source "$ROOT/lib/config.sh"
    load_aurgen_config >/dev/null 2>&1 || exit 1
    [[ "$COPY_RULES_LIB" == usr/lib/aurgen:* ]] || { echo "lib rule: $COPY_RULES_LIB"; exit 1; }
    [[ "${PKG_POST_PACKAGE[*]}" == *'/usr/lib/aurgen/VERSION'* ]] || { echo "post_package: ${PKG_POST_PACKAGE[*]}"; exit 1; }
) >"$tmp/own-config.out" 2>&1 || fail "aurgen's own config installs its lib outside /usr/lib/aurgen" "$tmp/own-config.out"

# www.github.com is GitHub too: it gets past the refusal.
rm -rf "$other/aur"
mkdir -p "$other/bin"
git -C "$other" config user.email "t@example.com"
git -C "$other" config user.name "t"
git -C "$other" config commit.gpgsign false
printf '#!/bin/sh\necho hi\n' > "$other/bin/imagetool"
chmod +x "$other/bin/imagetool"
git -C "$other" add bin/imagetool
git -C "$other" commit -q -m init
git -C "$other" remote set-url origin "https://www.github.com/example/imagetool.git"
if ! (cd "$other" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --dry-run local) >"$tmp/www.out" 2>"$tmp/www.err"; then
    fail "a www.github.com remote failed" "$tmp/www.err"
fi
if grep -F -q 'only supports GitHub projects' "$tmp/www.err"; then
    fail "a www.github.com remote was refused" "$tmp/www.err"
fi
grep -F -q 'pkgname=imagetool' "$other/aur/dry-run/PKGBUILD" || fail "www.github.com did not write pkgname=imagetool" "$other/aur/dry-run/PKGBUILD"

# A Turkish locale must not drop i from the [a-z] ranges that validate names.
if locale -a 2>/dev/null | grep -qix 'tr_TR\.utf-\?8'; then
    trrepo="$tmp/linux-cleaner"
    mkdir -p "$trrepo/bin"
    git -C "$trrepo" init -q -b main
    git -C "$trrepo" config user.email "t@example.com"
    git -C "$trrepo" config user.name "t"
    git -C "$trrepo" config commit.gpgsign false
    git -C "$trrepo" remote add origin "https://github.com/example/linux-cleaner.git"
    printf '#!/bin/sh\necho hi\n' > "$trrepo/bin/linux-cleaner"
    chmod +x "$trrepo/bin/linux-cleaner"
    git -C "$trrepo" add bin/linux-cleaner
    git -C "$trrepo" commit -q -m init
    if ! (cd "$trrepo" && env LC_ALL=tr_TR.UTF-8 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --dry-run local) >"$tmp/tr.out" 2>"$tmp/tr.err"; then
        fail "a Turkish LC_ALL failed on linux-cleaner" "$tmp/tr.err"
    fi
    if grep -F -q 'Invalid package name' "$tmp/tr.out" "$tmp/tr.err"; then
        fail "a Turkish LC_ALL rejected the name linux-cleaner" "$tmp/tr.err"
    fi
    grep -F -q 'pkgname=linux-cleaner' "$trrepo/aur/dry-run/PKGBUILD" || fail "linux-cleaner did not become the package name linux-cleaner" "$trrepo/aur/dry-run/PKGBUILD"
    # The default package name is the repo name in ASCII lowercase, never a dotless i.
    caprepo="$tmp/ImageTool"
    mkdir -p "$caprepo/bin"
    git -C "$caprepo" init -q -b main
    git -C "$caprepo" config user.email "t@example.com"
    git -C "$caprepo" config user.name "t"
    git -C "$caprepo" config commit.gpgsign false
    git -C "$caprepo" remote add origin "https://github.com/example/ImageTool.git"
    printf '#!/bin/sh\necho hi\n' > "$caprepo/bin/imagetool"
    chmod +x "$caprepo/bin/imagetool"
    git -C "$caprepo" add bin/imagetool
    git -C "$caprepo" commit -q -m init
    if ! (cd "$caprepo" && env LC_ALL=tr_TR.UTF-8 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --dry-run local) >"$tmp/trcap.out" 2>"$tmp/trcap.err"; then
        fail "a Turkish LC_ALL failed on ImageTool" "$tmp/trcap.err"
    fi
    if grep -F -q 'Invalid package name' "$tmp/trcap.out" "$tmp/trcap.err"; then
        fail "a Turkish LC_ALL folded ImageTool into an invalid package name" "$tmp/trcap.err"
    fi
    grep -F -q 'pkgname=imagetool' "$caprepo/aur/dry-run/PKGBUILD" || fail "ImageTool did not become the package name imagetool" "$caprepo/aur/dry-run/PKGBUILD"
fi

# Installed layout: bin/ and lib/ live apart and VERSION sits in the lib dir.
inst="$tmp/inst"
mkdir -p "$inst/usr/bin" "$inst/usr/lib/aurgen"
cp "$ROOT/bin/aurgen" "$inst/usr/bin/aurgen"
cp -r "$ROOT/lib/." "$inst/usr/lib/aurgen/"
printf '9.9.9\n' > "$inst/usr/lib/aurgen/VERSION"
if ! RELEASE=0 AURGEN_LIB_DIR="$inst/usr/lib/aurgen" "$inst/usr/bin/aurgen" --version >"$tmp/inst.out" 2>&1; then
    fail "installed aurgen --version failed" "$tmp/inst.out"
fi
if ! grep -F -q 'aurgen version 9.9.9' "$tmp/inst.out"; then
    fail "installed aurgen did not read VERSION from its lib dir" "$tmp/inst.out"
fi

# A copied aurgen runs in release mode on the lib AURGEN_LIB_DIR names, with no
# fallback to development mode. CI=1 (aurgen test sets it for its child runs) must
# not switch it to development mode either.
for env_case in "RELEASE=1" "CI=1"; do
    if ! (unset RELEASE; env "$env_case" AURGEN_LIB_DIR="$inst/usr/lib/aurgen" "$inst/usr/bin/aurgen" --version) >"$tmp/rel.out" 2>&1; then
        fail "installed aurgen --version failed under $env_case" "$tmp/rel.out"
    fi
    grep -F -q 'aurgen version 9.9.9' "$tmp/rel.out" || fail "$env_case: AURGEN_LIB_DIR was not used" "$tmp/rel.out"
    if grep -E -q 'DEVELOPMENT mode|Falling back' "$tmp/rel.out"; then
        fail "$env_case: installed aurgen left release mode" "$tmp/rel.out"
    fi
done


# A relative lib path must survive aur mode changing from a subdirectory to the project root.
cat >> "$inst/usr/lib/aurgen/aur-integration.sh" <<'EOF'
printf 'relative-lib: %s|%s\n' "$PWD" "$LIB_INSTALL_DIR"
EOF
mkdir -p "$repo/subdir"
ln -s "$inst/usr/lib/aurgen" "$repo/subdir/lib"
for release in 0 1; do
    for cdpath in '' .; do
        if ! (cd "$repo/subdir" && env CDPATH="$cdpath" PATH="$stub:$PATH" RELEASE="$release" AURGEN_LIB_DIR="lib" GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$inst/usr/bin/aurgen" --dry-run aur) >| "$tmp/relative-lib.out" 2>&1; then
            fail "RELEASE=$release CDPATH=$cdpath: relative AURGEN_LIB_DIR failed" "$tmp/relative-lib.out"
        fi
        grep -F -x -q "relative-lib: $repo|$repo/subdir/lib" "$tmp/relative-lib.out" || fail "RELEASE=$release CDPATH=$cdpath: lib was not absolute and loaded after cd" "$tmp/relative-lib.out"
    done
done


# A color choice made before lib/colors.sh is sourced again (-n, CI) must survive it.
# The check needs a terminal: init_colors already turns color off without one.
color_probe() {
    script -qec "bash -c '$1 AURGEN_ERROR_LOG=/dev/null; source \"$ROOT/lib/colors.sh\"; init_colors; printf \"[%s]\" \"\$YELLOW\"'" /dev/null | tr -d '\r'
}
[[ "$(color_probe '')" == "["$'\e'* ]] || fail "colors.sh should color a terminal by default (pty probe broken?)"
[[ "$(color_probe 'color_enabled=0;')" == "[]" ]] || fail "re-sourcing colors.sh turned color back on after color_enabled=0"

# COLOR=0 or 1 forces color after --no-color and CI. Count escapes in a real run on a terminal.
# script -e passes aurgen's exit status through, so a crash cannot pass as zero escapes.
color_run() {
    local rc=0
    (cd "$repo" && script -qec "env $1 '$ROOT/bin/aurgen' $2 --maxdepth 1 lint" /dev/null) >| "$tmp/color.out" || rc=$?
    # stderr: callers read stdout as the count.
    (( rc == 0 )) || fail "aurgen lint failed on a terminal ($1 $2, exit $rc)" "$tmp/color.out" >&2
    grep -c $'\e\[' "$tmp/color.out" || true
}
color_count="$(color_run X=1 '')" || exit 1
[[ "$color_count" -gt 0 ]] || fail "aurgen lint printed no color on a terminal (pty probe broken?)"
color_count="$(color_run COLOR=0 '')" || exit 1
[[ "$color_count" -eq 0 ]] || fail "COLOR=0 still printed color"
color_count="$(color_run COLOR=1 -n)" || exit 1
[[ "$color_count" -gt 0 ]] || fail "COLOR=1 did not override --no-color"

# aur and git only write packaging files; the AUR push is aur-deploy (or --deploy).
"$ROOT/bin/aurgen" --help >"$tmp/help.out" 2>&1 || fail "--help failed" "$tmp/help.out"
if grep -E -q '^  (aur|git) .*upload to AUR' "$tmp/help.out"; then
    fail "--help says aur or git uploads to the AUR" "$tmp/help.out"
fi
if grep -E -q 'Lint PKGBUILD|on this script' "$tmp/help.out"; then
    fail "--help says lint checks the PKGBUILD or only this script" "$tmp/help.out"
fi
if grep -F -q '(local only)' "$tmp/help.out" || ! grep -E -q '^  --build-only .*local, aur, git' "$tmp/help.out"; then
    fail "--help does not advertise --build-only for local, aur, git" "$tmp/help.out"
fi

# Untagged repos and controlled mode/build failures must not trigger ERR-trap [FATAL] diagnostics.
fatal_repo="$tmp/fatal-check"
mkdir -p "$fatal_repo"
git -C "$fatal_repo" init -q -b main
git -C "$fatal_repo" config user.email "t@example.com"
git -C "$fatal_repo" config user.name "t"
git -C "$fatal_repo" config commit.gpgsign false
printf '#!/bin/bash\nprintf ok\n' > "$fatal_repo/app"
chmod +x "$fatal_repo/app"
git -C "$fatal_repo" add app
git -C "$fatal_repo" commit -q -m init
git -C "$fatal_repo" remote add origin "https://github.com/example/fatal-check.git"

: >| "$AURGEN_ERROR_LOG"
if ! (cd "$fatal_repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n -d git) >"$tmp/untagged-git.out" 2>"$tmp/untagged-git.err"; then
    fail "dry-run git on untagged repo failed" "$tmp/untagged-git.err"
fi
if grep -F -q '[FATAL]' "$tmp/untagged-git.err" "$AURGEN_ERROR_LOG"; then
    fail "untagged dry-run git emitted [FATAL]" "$tmp/untagged-git.err"
fi

for err_case in "config-no-arg:config" "deploy-no-pkgbuild:aur-deploy"; do
    label="${err_case%%:*}"
    mode_arg="${err_case#*:}"
    : >| "$AURGEN_ERROR_LOG"
    rm -f "$fatal_repo/aur/PKGBUILD" "$fatal_repo/aur/.SRCINFO"
    if (cd "$fatal_repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n "$mode_arg") >"$tmp/$label.out" 2>"$tmp/$label.err"; then
        fail "$label: expected non-zero exit" "$tmp/$label.out"
    fi
    if grep -F -q '[FATAL]' "$tmp/$label.err" "$AURGEN_ERROR_LOG"; then
        fail "$label: controlled failure emitted [FATAL]" "$tmp/$label.err"
    fi
done

fail_stub="$tmp/fail-makepkg"
mkdir -p "$fail_stub"
cat > "$fail_stub/makepkg" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--printsrcinfo" ]]; then
    printf 'pkgbase = fatal-check-git\n\tpkgname = fatal-check-git\n'
    exit 0
fi
exit 2
EOF
chmod +x "$fail_stub/makepkg"
: >| "$AURGEN_ERROR_LOG"
rc=0
(cd "$fatal_repo" && PATH="$fail_stub:$stub:$PATH" "$ROOT/bin/aurgen" -n --build-only git) >"$tmp/build-fail.out" 2>"$tmp/build-fail.err" || rc=$?
[[ "$rc" -eq 2 ]] || fail "--build-only git did not preserve makepkg exit status 2 (got $rc)" "$tmp/build-fail.err"
if grep -F -q '[FATAL]' "$tmp/build-fail.err" "$AURGEN_ERROR_LOG"; then
    fail "--build-only makepkg failure emitted [FATAL]" "$tmp/build-fail.err"
fi

# Direct unit tests for lib/valid-modes.sh (guard, VALID_MODES, is_valid_mode, and usage).
if bash "$ROOT/lib/valid-modes.sh" >"$tmp/vm-direct.out" 2>"$tmp/vm-direct.err"; then
    fail "lib/valid-modes.sh should refuse direct execution"
fi
grep -Fq 'must be sourced, not executed' "$tmp/vm-direct.err" || fail "lib/valid-modes.sh guard message missing" "$tmp/vm-direct.err"

if ! (
    # shellcheck source=../lib/valid-modes.sh
    source "$ROOT/lib/valid-modes.sh"
    expected_modes=(local aur git aur-init aur-deploy aur-push aur-status doctor clean test lint golden config)
    [[ "${#VALID_MODES[@]}" -eq "${#expected_modes[@]}" ]] || exit 1
    for m in "${expected_modes[@]}"; do
        is_valid_mode "$m" || exit 2
    done
    for bad in "" "unknown" "local " " local" "AUR" "--help"; do
        if is_valid_mode "$bad"; then
            exit 3
        fi
    done
    usage_out="$(usage)"
    [[ "$usage_out" == *"Usage: aurgen <mode> [options]"* ]] || exit 4
    [[ "$usage_out" == *"aur-push"* && "$usage_out" == *"--build-only"* && "$usage_out" == *"--rollback"* ]] || exit 5
); then
    fail "lib/valid-modes.sh unit assertions failed"
fi

# Preflight refusals (missing/non-GitHub origin, --dry-run clean/golden, missing required tools)
# must fail fast before aurgen_init creates aur/ or mutates a tracked .gitattributes.
preflight="$tmp/preflight-clean"
mkdir -p "$preflight"
git -C "$preflight" init -q -b main
git -C "$preflight" config user.email "t@example.com"
git -C "$preflight" config user.name "t"
git -C "$preflight" config commit.gpgsign false
printf '*.txt text\n' > "$preflight/.gitattributes"
printf '# preflight\n' > "$preflight/README.md"
git -C "$preflight" add .gitattributes README.md
git -C "$preflight" commit -q -m init

: >| "$AURGEN_ERROR_LOG"
if (cd "$preflight" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/pf-noorigin.out" 2>"$tmp/pf-noorigin.err"; then
    fail "missing origin should be refused" "$tmp/pf-noorigin.out"
fi
grep -F -q 'No remote origin URL found' "$tmp/pf-noorigin.err" || fail "missing origin error not explained" "$tmp/pf-noorigin.err"
[[ ! -e "$preflight/aur" ]] || fail "missing origin refusal created aur/"
[[ -z "$(git -C "$preflight" status --porcelain)" ]] || fail "missing origin refusal dirtied worktree"

git -C "$preflight" remote add origin "https://gitlab.com/example/preflight.git"
if (cd "$preflight" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n local) >"$tmp/pf-gitlab.out" 2>"$tmp/pf-gitlab.err"; then
    fail "non-GitHub origin should be refused" "$tmp/pf-gitlab.out"
fi
grep -F -q 'only supports GitHub projects' "$tmp/pf-gitlab.err" || fail "non-GitHub refusal missing message" "$tmp/pf-gitlab.err"
[[ ! -e "$preflight/aur" ]] || fail "non-GitHub refusal created aur/"
[[ -z "$(git -C "$preflight" status --porcelain)" ]] || fail "non-GitHub refusal modified .gitattributes"

git -C "$preflight" remote set-url origin "https://github.com/example/preflight.git"
for dry_mode in clean golden; do
    if (cd "$preflight" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --dry-run "$dry_mode") >"$tmp/pf-dry-$dry_mode.out" 2>"$tmp/pf-dry-$dry_mode.err"; then
        fail "--dry-run $dry_mode should be refused" "$tmp/pf-dry-$dry_mode.out"
    fi
    [[ ! -e "$preflight/aur" ]] || fail "--dry-run $dry_mode created aur/ before refusal"
    [[ -z "$(git -C "$preflight" status --porcelain)" ]] || fail "--dry-run $dry_mode modified .gitattributes"
done

min_bin="$tmp/min-bin"
mkdir -p "$min_bin"
for tool in bash git getopt awk tr dirname basename realpath mkdir chmod rm cat curl; do
    ln -s "$(command -v "$tool")" "$min_bin/$tool"
done
if (cd "$preflight" && PATH="$min_bin" "$ROOT/bin/aurgen" -n local) >"$tmp/pf-notool.out" 2>"$tmp/pf-notool.err"; then
    fail "missing makepkg/updpkgsums should be refused" "$tmp/pf-notool.out"
fi
grep -F -q "Missing required tool(s) for 'local' mode" "$tmp/pf-notool.out" "$tmp/pf-notool.err" || fail "missing-tool error not printed" "$tmp/pf-notool.err"
grep -F -q "sudo pacman -S pacman-contrib" "$tmp/pf-notool.out" "$tmp/pf-notool.err" || fail "missing-tool hint for updpkgsums not printed" "$tmp/pf-notool.out"
[[ ! -e "$preflight/aur" ]] || fail "missing-tool refusal created aur/"
[[ -z "$(git -C "$preflight" status --porcelain)" ]] || fail "missing-tool refusal modified .gitattributes"
if grep -F -q '[FATAL]' "$tmp/pf-noorigin.err" "$tmp/pf-gitlab.err" "$tmp/pf-dry-clean.err" "$tmp/pf-dry-golden.err" "$tmp/pf-notool.err" "$AURGEN_ERROR_LOG"; then
    fail "preflight refusal emitted [FATAL]" "$AURGEN_ERROR_LOG"
fi

# Invalid COLOR must fail fast with a clear diagnostic and never trigger [FATAL].
for bad_color in yes 2 foo-bar " "; do
    if env COLOR="$bad_color" "$ROOT/bin/aurgen" --version >|"$tmp/bad-color.out" 2>|"$tmp/bad-color.err"; then
        fail "COLOR=$bad_color should fail" "$tmp/bad-color.out"
    fi
    grep -F -q "Invalid COLOR: $bad_color (expected 0 or 1)" "$tmp/bad-color.err" || fail "bad COLOR=$bad_color missing message" "$tmp/bad-color.err"
    if grep -F -q '[FATAL]' "$tmp/bad-color.err"; then
        fail "bad COLOR=$bad_color emitted [FATAL]" "$tmp/bad-color.err"
    fi
done

# Non-TTY and CI=1 fallbacks from missing release lib dir must skip the 5s sleep.
fallback_repo="$tmp/fallback-repo"
mkdir -p "$fallback_repo/bin"
sed "s|/usr/lib/aurgen|$tmp/missing-usr-lib|g" "$ROOT/bin/aurgen" > "$fallback_repo/bin/aurgen"
chmod +x "$fallback_repo/bin/aurgen"
ln -s "$ROOT/lib" "$fallback_repo/lib"
ln -s "$ROOT/VERSION" "$fallback_repo/VERSION"

SECONDS=0
if ! (env -u CI RELEASE=1 "$fallback_repo/bin/aurgen" --version < /dev/null >|"$tmp/fallback.out" 2>|"$tmp/fallback.err"); then
    fail "non-TTY fallback failed" "$tmp/fallback.err"
fi
(( SECONDS < 3 )) || fail "non-TTY fallback waited ${SECONDS}s instead of skipping sleep" "$tmp/fallback.err"
grep -F -q 'Falling back to development mode (RELEASE=0)...' "$tmp/fallback.err" || fail "fallback notice missing" "$tmp/fallback.err"

SECONDS=0
if ! script -qec "env CI=1 RELEASE=1 '$fallback_repo/bin/aurgen' --version" /dev/null >|"$tmp/fallback-ci.out" 2>&1; then
    fail "CI=1 TTY fallback failed" "$tmp/fallback-ci.out"
fi
(( SECONDS < 3 )) || fail "CI=1 fallback waited ${SECONDS}s instead of skipping sleep" "$tmp/fallback-ci.out"
grep -F -q 'Falling back to development mode (RELEASE=0)...' "$tmp/fallback-ci.out" || fail "CI=1 fallback notice missing" "$tmp/fallback-ci.out"

# Early CLI errors before option parsing must honor CI=1 and COLOR=0/1 on a terminal.
no_getopt_bin="$tmp/no-getopt-bin"
bad_getopt_bin="$tmp/bad-getopt-bin"
mkdir -p "$no_getopt_bin" "$bad_getopt_bin"
for tool in bash dirname realpath mkdir chmod tr tput; do
    tool_path="$(command -v "$tool")" || fail "required test helper tool missing: $tool"
    ln -s "$tool_path" "$no_getopt_bin/$tool"
    ln -s "$tool_path" "$bad_getopt_bin/$tool"
done
printf '#!/bin/bash\nexit 0\n' > "$bad_getopt_bin/getopt"
chmod +x "$bad_getopt_bin/getopt"

check_early_color() {
    local label="$1" bin_dir="$2" env_spec="$3" expect_color="$4" expect_msg="$5"
    local rc=0 escapes=0
    script -qec "env -u CI -u COLOR -u NO_COLOR $env_spec PATH='$bin_dir' '$ROOT/bin/aurgen' --version" /dev/null >| "$tmp/early-color.out" || rc=$?
    (( rc != 0 )) || fail "$label unexpectedly succeeded" "$tmp/early-color.out"
    grep -F -q "$expect_msg" "$tmp/early-color.out" || fail "$label missing expected message '$expect_msg'" "$tmp/early-color.out"
    escapes="$(grep -c $'\e\[' "$tmp/early-color.out" || true)"
    if [[ "$expect_color" == "0" && "$escapes" -gt 0 ]]; then
        fail "$label emitted ANSI color escapes" "$tmp/early-color.out"
    fi
    if [[ "$expect_color" == "1" && "$escapes" -eq 0 ]]; then
        fail "$label did not emit ANSI color escapes" "$tmp/early-color.out"
    fi
}

check_early_color "missing getopt CI=1" "$no_getopt_bin" "CI=1" 0 "Missing required tool:"
check_early_color "missing getopt COLOR=0" "$no_getopt_bin" "COLOR=0" 0 "Missing required tool:"
check_early_color "missing getopt CI=1 COLOR=1" "$no_getopt_bin" "CI=1 COLOR=1" 1 "Missing required tool:"
check_early_color "non-GNU getopt CI=1" "$bad_getopt_bin" "CI=1" 0 "GNU getopt required (util-linux)"
check_early_color "non-GNU getopt COLOR=0" "$bad_getopt_bin" "COLOR=0" 0 "GNU getopt required (util-linux)"
check_early_color "non-GNU getopt CI=1 COLOR=1" "$bad_getopt_bin" "CI=1 COLOR=1" 1 "GNU getopt required (util-linux)"

# --config and AURGEN_CONFIG_FILE option handling
usage_out="$("$ROOT/bin/aurgen" --usage 2>&1)" || fail "--usage failed"
echo "$usage_out" | grep -F -q -- "-c, --config FILE" || fail "--usage missing -c, --config FILE" "$usage_out"
help_out="$("$ROOT/bin/aurgen" --help 2>&1)" || fail "--help failed"
echo "$help_out" | grep -F -q -- "-c, --config FILE" || fail "--help missing -c, --config FILE" "$help_out"

cfg_repo="$tmp/cfg-repo"
mkdir -p "$cfg_repo/bin" "$cfg_repo/custom"
printf '#!/bin/bash\necho hi\n' > "$cfg_repo/bin/demo"
chmod +x "$cfg_repo/bin/demo"
(
    cd "$cfg_repo" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name Tester
    git remote add origin https://github.com/example/cfg-repo.git
    git add bin/demo
    git commit -q -m "init"
    git tag -a v1.0.0 -m "v1.0.0"
)

if (cd "$cfg_repo" && "$ROOT/bin/aurgen" -n -c "" local) >|"$tmp/cfg-empty.out" 2>|"$tmp/cfg-empty.err"; then
    fail "empty --config unexpectedly succeeded" "$tmp/cfg-empty.err"
fi
grep -F -q -- "--config requires a non-empty file path" "$tmp/cfg-empty.err" || fail "empty --config error mismatch" "$tmp/cfg-empty.err"
[[ ! -e "$cfg_repo/aur" ]] || fail "empty --config preflight created aur/"

if (cd "$cfg_repo" && "$ROOT/bin/aurgen" -n -c "$cfg_repo" local) >|"$tmp/cfg-dir.out" 2>|"$tmp/cfg-dir.err"; then
    fail "directory --config unexpectedly succeeded" "$tmp/cfg-dir.err"
fi
grep -F -q "is a directory" "$tmp/cfg-dir.err" || fail "directory --config error mismatch" "$tmp/cfg-dir.err"
[[ ! -e "$cfg_repo/aur" ]] || fail "directory --config preflight created aur/"

if (cd "$cfg_repo" && "$ROOT/bin/aurgen" -n -c "$cfg_repo/missing.yaml" local) >|"$tmp/cfg-missing.out" 2>|"$tmp/cfg-missing.err"; then
    fail "missing --config unexpectedly succeeded" "$tmp/cfg-missing.err"
fi
grep -F -q "Configuration file not found" "$tmp/cfg-missing.err" || fail "missing --config error mismatch" "$tmp/cfg-missing.err"
[[ ! -e "$cfg_repo/aur" ]] || fail "missing --config preflight created aur/"

if (cd "$cfg_repo" && AURGEN_CONFIG_FILE="$cfg_repo" "$ROOT/bin/aurgen" -n local) >|"$tmp/cfg-envdir.out" 2>|"$tmp/cfg-envdir.err"; then
    fail "directory AURGEN_CONFIG_FILE unexpectedly succeeded" "$tmp/cfg-envdir.err"
fi
grep -F -q "is a directory" "$tmp/cfg-envdir.err" || fail "directory AURGEN_CONFIG_FILE error mismatch" "$tmp/cfg-envdir.err"
[[ ! -e "$cfg_repo/aur" ]] || fail "directory AURGEN_CONFIG_FILE preflight created aur/"

mkdir -p "$cfg_repo/aur"
cat > "$cfg_repo/aur/PKGBUILD" <<'EOF'
pkgname=decoy-from-pkgbuild
pkgver=1.0.0
pkgrel=1
EOF
cat > "$cfg_repo/custom/alt.yaml" <<'EOF'
package:
  name: custom-cli-pkg
  description: Custom CLI config package

bin:
  source: bin
  destination: usr/bin
  permissions: executable
EOF
if ! (cd "$cfg_repo" && AURGEN_CONFIG_FILE="$cfg_repo/missing-env.yaml" "$ROOT/bin/aurgen" -n -c custom/alt.yaml --dry-run local) >|"$tmp/cfg-dry.out" 2>|"$tmp/cfg-dry.err"; then
    fail "relative --config dry-run local failed" "$tmp/cfg-dry.err"
fi
grep -F -q "pkgname=custom-cli-pkg" "$cfg_repo/aur/dry-run/PKGBUILD" || fail "--config custom package.name not applied to dry-run PKGBUILD" "$cfg_repo/aur/dry-run/PKGBUILD"
[[ ! -e "$cfg_repo/aur/aurgen.install.yaml" ]] || fail "--config run auto-imported or created default aur/aurgen.install.yaml"

# --diff and --json preflight checks
echo "$usage_out" | grep -F -q -- "--diff" || fail "--usage missing --diff" "$usage_out"
echo "$usage_out" | grep -F -q -- "--json" || fail "--usage missing --json" "$usage_out"
echo "$usage_out" | grep -F -q -- "--non-interactive" || fail "--usage missing --non-interactive" "$usage_out"
echo "$help_out" | grep -F -q -- "--diff" || fail "--help missing --diff" "$help_out"
echo "$help_out" | grep -F -q -- "--json" || fail "--help missing --json" "$help_out"
echo "$help_out" | grep -F -q -- "--non-interactive" || fail "--help missing --non-interactive" "$help_out"

if "$ROOT/bin/aurgen" --diff local >|"$tmp/diff-badmode.out" 2>|"$tmp/diff-badmode.err"; then
    fail "--diff unexpectedly accepted with local"
fi
grep -F -q -- "--diff is only valid with aur-status" "$tmp/diff-badmode.err" || fail "--diff mode mismatch error absent" "$tmp/diff-badmode.err"

if "$ROOT/bin/aurgen" --json clean >|"$tmp/json-badmode.out" 2>|"$tmp/json-badmode.err"; then
    fail "--json unexpectedly accepted with clean"
fi
grep -F -q -- "--json is only valid with aur-status, doctor, config detect, or lint" "$tmp/json-badmode.err" || fail "--json mode mismatch error absent" "$tmp/json-badmode.err"
if "$ROOT/bin/aurgen" --json config edit >|"$tmp/json-badcfg.out" 2>|"$tmp/json-badcfg.err"; then
    fail "--json unexpectedly accepted with config edit"
fi
grep -F -q -- "--json is only valid with aur-status, doctor, config detect, or lint" "$tmp/json-badcfg.err" || fail "--json config action mismatch error absent" "$tmp/json-badcfg.err"

lint_json_repo="$tmp/lint-json-repo"
mkdir -p "$lint_json_repo"
printf '#!/bin/bash\nprintf "ok\\n"\n' >| "$lint_json_repo/ok.sh"
if ! (
    cd "$lint_json_repo" || exit 1
    git init -q
    git remote add origin "https://github.com/example/demo.git"
    git add ok.sh
    "$ROOT/bin/aurgen" --json lint
) >|"$tmp/lint-json.out" 2>|"$tmp/lint-json.err"; then
    fail "--json lint failed on valid repo" "$tmp/lint-json.err"
fi
python3 - "$tmp/lint-json.out" <<'PY' || fail "--json lint output invalid" "$tmp/lint-json.out"
import json, sys
data = json.loads(open(sys.argv[1]).read())
assert data["ok"] is True
assert data["summary"]["passed"] == 1 and data["summary"]["failed"] == 0
assert [f["path"] for f in data["files"]] == ["ok.sh"]
assert data["files"][0]["bashn_report"] is None
assert data["files"][0]["shellcheck_report"] is None
PY

(
    # shellcheck source=../lib/helpers.sh
    source "$ROOT/lib/helpers.sh"
    [[ "$(_aurgen_json_escape $'a\nb"c\\d\te')" == 'a\nb\"c\\d\te' ]] || exit 1
    [[ "$(_aurgen_json_nullable_string "")" == "null" ]] || exit 1
    [[ "$(_aurgen_json_nullable_string)" == "null" ]] || exit 1
    [[ "$(_aurgen_json_nullable_string "ok")" == '"ok"' ]] || exit 1
) || fail "_aurgen_json_escape or _aurgen_json_nullable_string failed in helpers.sh"

# DRY_RUN and NO_WAIT must be 0 or 1: DRY_RUN=true used to run for real.
for bad in DRY_RUN=true NO_WAIT=yes; do
    if env "$bad" "$ROOT/bin/aurgen" --usage >|"$tmp/badbool.out" 2>|"$tmp/badbool.err"; then
        fail "$bad was unexpectedly accepted"
    fi
    grep -F -q -- "Invalid ${bad%%=*}: ${bad#*=}" "$tmp/badbool.err" || fail "missing Invalid ${bad%%=*} error" "$tmp/badbool.err"
done
DRY_RUN=1 "$ROOT/bin/aurgen" --usage >/dev/null 2>&1 || fail "DRY_RUN=1 was refused"

# --non-interactive and AURGEN_NON_INTERACTIVE preflight checks
if AURGEN_NON_INTERACTIVE=maybe "$ROOT/bin/aurgen" --usage >|"$tmp/nonint-bad.out" 2>|"$tmp/nonint-bad.err"; then
    fail "invalid AURGEN_NON_INTERACTIVE=maybe was unexpectedly accepted"
fi
grep -F -q -- "Invalid AURGEN_NON_INTERACTIVE: maybe" "$tmp/nonint-bad.err" || fail "missing Invalid AURGEN_NON_INTERACTIVE error" "$tmp/nonint-bad.err"

nonint_repo="$tmp/nonint-repo"
mkdir -p "$nonint_repo"
git -C "$nonint_repo" init -q
git -C "$nonint_repo" remote add origin "https://github.com/example/demo.git"
if (
    cd "$nonint_repo" || exit 1
    export AURGEN_NON_INTERACTIVE=0 EDITOR=true
    "$ROOT/bin/aurgen" --non-interactive config edit
) >|"$tmp/nonint-edit1.out" 2>|"$tmp/nonint-edit1.err"; then
    fail "--non-interactive config edit unexpectedly succeeded"
fi
grep -F -q -- "non-interactive" "$tmp/nonint-edit1.err" || fail "--non-interactive config edit lacked non-interactive error" "$tmp/nonint-edit1.err"
[[ ! -e "$nonint_repo/aur/aurgen.install.yaml" ]] || fail "--non-interactive config edit created aur/aurgen.install.yaml before failing"

mkdir -p "$nonint_repo/aur"
printf 'package:\n  name: demo\n  source: release\n' >| "$nonint_repo/aur/aurgen.install.yaml"
before_nonint_cfg="$(cat "$nonint_repo/aur/aurgen.install.yaml")"
if (
    cd "$nonint_repo" || exit 1
    export AURGEN_NON_INTERACTIVE=1 EDITOR=true
    "$ROOT/bin/aurgen" config edit
) >|"$tmp/nonint-edit2.out" 2>|"$tmp/nonint-edit2.err"; then
    fail "AURGEN_NON_INTERACTIVE=1 config edit unexpectedly succeeded"
fi
[[ "$(cat "$nonint_repo/aur/aurgen.install.yaml")" == "$before_nonint_cfg" ]] || fail "AURGEN_NON_INTERACTIVE=1 config edit modified existing config"

if "$ROOT/bin/aurgen" --diff --json aur-status >|"$tmp/diff-json.out" 2>|"$tmp/diff-json.err"; then
    fail "--diff --json unexpectedly accepted together"
fi
grep -F -q -- "--diff cannot be combined with --json" "$tmp/diff-json.err" || fail "--diff --json conflict error absent" "$tmp/diff-json.err"

# --nocheck and AURGEN_MAKEPKG_FLAGS preflight checks
echo "$usage_out" | grep -F -q -- "--nocheck" || fail "--usage missing --nocheck" "$usage_out"
echo "$help_out" | grep -F -q -- "--nocheck" || fail "--help missing --nocheck" "$help_out"

for bad_nocheck_mode in lint aur git aur-status; do
    nocheck_repo="$tmp/nocheck-$bad_nocheck_mode"
    mkdir -p "$nocheck_repo"
    git -C "$nocheck_repo" init -q -b main
    git -C "$nocheck_repo" remote add origin "https://github.com/example/nocheck-demo.git"
    if (cd "$nocheck_repo" && "$ROOT/bin/aurgen" --nocheck "$bad_nocheck_mode") >|"$tmp/nc-$bad_nocheck_mode.out" 2>|"$tmp/nc-$bad_nocheck_mode.err"; then
        fail "--nocheck unexpectedly accepted with $bad_nocheck_mode"
    fi
    grep -F -q -- "--nocheck is only valid with local, or aur/git with --build-only" "$tmp/nc-$bad_nocheck_mode.err" || fail "--nocheck mode refusal missing for $bad_nocheck_mode" "$tmp/nc-$bad_nocheck_mode.err"
    [[ ! -e "$nocheck_repo/aur" ]] || fail "--nocheck preflight refusal created aur/ for $bad_nocheck_mode"
done

nc_ok_repo="$tmp/nocheck-ok"
mkdir -p "$nc_ok_repo/bin"
printf '#!/bin/sh\necho ok\n' > "$nc_ok_repo/bin/nc-demo"
git -C "$nc_ok_repo" init -q -b main
git -C "$nc_ok_repo" config user.email "t@example.com"
git -C "$nc_ok_repo" config user.name "t"
git -C "$nc_ok_repo" config commit.gpgsign false
git -C "$nc_ok_repo" add bin/nc-demo
git -C "$nc_ok_repo" commit -q -m init
git -C "$nc_ok_repo" remote add origin "https://github.com/example/nocheck-ok.git"
if ! (cd "$nc_ok_repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --nocheck --dry-run local) >|"$tmp/nc-local.out" 2>|"$tmp/nc-local.err"; then
    fail "--nocheck --dry-run local failed" "$tmp/nc-local.err"
fi
if ! (cd "$nc_ok_repo" && PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --build-only --nocheck --dry-run git) >|"$tmp/nc-git.out" 2>|"$tmp/nc-git.err"; then
    fail "--build-only --nocheck --dry-run git failed" "$tmp/nc-git.err"
fi

nc_badflag_repo="$tmp/nocheck-badflag"
mkdir -p "$nc_badflag_repo"
git -C "$nc_badflag_repo" init -q -b main
git -C "$nc_badflag_repo" remote add origin "https://github.com/example/nocheck-badflag.git"
if (cd "$nc_badflag_repo" && AURGEN_MAKEPKG_FLAGS="--foo=bar" "$ROOT/bin/aurgen" -n --dry-run local) >|"$tmp/nc-badflag.out" 2>|"$tmp/nc-badflag.err"; then
    fail "malformed AURGEN_MAKEPKG_FLAGS unexpectedly passed CLI preflight"
fi
grep -F -q "Invalid AURGEN_MAKEPKG_FLAGS" "$tmp/nc-badflag.err" || fail "CLI preflight malformed AURGEN_MAKEPKG_FLAGS message missing" "$tmp/nc-badflag.err"
[[ ! -e "$nc_badflag_repo/aur" ]] || fail "malformed AURGEN_MAKEPKG_FLAGS preflight created aur/"

# Inherited AURGEN_NOCHECK=1 without --nocheck must neither trip non-build lint nor inject --nocheck into makepkg.
nc_env_bin="$tmp/nc-env-bin"
mkdir -p "$nc_env_bin"
cat > "$nc_env_bin/makepkg" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--packagelist"* ]]; then
    pkg="$PWD/nocheck-ok-1.0.0-1-any.pkg.tar.zst"
    : > "$pkg"
    printf '%s\n' "$pkg"
    exit 0
fi
printf '%s\n' "$*" >> "$NC_ENV_LOG"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$nc_env_bin/namcap"
chmod +x "$nc_env_bin/makepkg" "$nc_env_bin/namcap"
: > "$tmp/nc-env-makepkg.log"
if ! (cd "$nc_ok_repo" && env AURGEN_NOCHECK=1 "$ROOT/bin/aurgen" lint) >|"$tmp/nc-env-lint.out" 2>|"$tmp/nc-env-lint.err"; then
    fail "inherited AURGEN_NOCHECK=1 unexpectedly broke lint" "$tmp/nc-env-lint.err"
fi
if ! (cd "$nc_ok_repo" && env AURGEN_NOCHECK=1 NC_ENV_LOG="$tmp/nc-env-makepkg.log" PATH="$nc_env_bin:$stub:$PATH" "$ROOT/bin/aurgen" -n --build-only local) >|"$tmp/nc-env-local.out" 2>|"$tmp/nc-env-local.err"; then
    fail "AURGEN_NOCHECK=1 local --build-only failed" "$tmp/nc-env-local.err"
fi
[[ -s "$tmp/nc-env-makepkg.log" ]] || fail "AURGEN_NOCHECK=1 local --build-only did not invoke makepkg" "$tmp/nc-env-local.err"
if grep -Fq -- '--nocheck' "$tmp/nc-env-makepkg.log"; then
    fail "inherited AURGEN_NOCHECK=1 leaked --nocheck without CLI --nocheck" "$tmp/nc-env-makepkg.log"
fi

# --rollback is only valid with aur-deploy, fails before aurgen_init creates aur/, and env leakage is ignored.
for bad_rollback_mode in local aur git aur-init aur-push aur-status clean lint config; do
    rb_bad_repo="$tmp/rollback-$bad_rollback_mode"
    mkdir -p "$rb_bad_repo"
    git -C "$rb_bad_repo" init -q -b main
    git -C "$rb_bad_repo" remote add origin "https://github.com/example/rb-demo.git"
    if (cd "$rb_bad_repo" && "$ROOT/bin/aurgen" --rollback "$bad_rollback_mode") >|"$tmp/rb-$bad_rollback_mode.out" 2>|"$tmp/rb-$bad_rollback_mode.err"; then
        fail "--rollback unexpectedly accepted with $bad_rollback_mode"
    fi
    grep -Fq -- "--rollback is only valid with aur-deploy" "$tmp/rb-$bad_rollback_mode.err" \
        || fail "--rollback refusal missing for $bad_rollback_mode" "$tmp/rb-$bad_rollback_mode.err"
    [[ ! -e "$rb_bad_repo/aur" ]] || fail "--rollback preflight refusal created aur/ for $bad_rollback_mode"
done

if ! (cd "$nc_ok_repo" && env AURGEN_ROLLBACK=1 "$ROOT/bin/aurgen" lint) >|"$tmp/rb-env-lint.out" 2>|"$tmp/rb-env-lint.err"; then
    fail "inherited AURGEN_ROLLBACK=1 unexpectedly broke lint" "$tmp/rb-env-lint.err"
fi
rb_env_repo="$tmp/rollback-env-deploy"
mkdir -p "$rb_env_repo/aur"
git -C "$rb_env_repo" init -q -b main
git -C "$rb_env_repo" remote add origin "https://github.com/example/rb-env.git"
if (cd "$rb_env_repo" && env AURGEN_ROLLBACK=1 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n aur-deploy) >|"$tmp/rb-env-deploy.out" 2>|"$tmp/rb-env-deploy.err"; then
    fail "aur-deploy without PKGBUILD unexpectedly succeeded with inherited AURGEN_ROLLBACK=1"
fi
grep -Fq "PKGBUILD not found" "$tmp/rb-env-deploy.err" \
    || fail "inherited AURGEN_ROLLBACK=1 triggered rollback path instead of normal deploy check" "$tmp/rb-env-deploy.err"

# --overwrite-assets and AURGEN_OVERWRITE_ASSETS preflight checks
echo "$usage_out" | grep -F -q -- "--overwrite-assets" || fail "--usage missing --overwrite-assets" "$usage_out"
echo "$help_out" | grep -F -q -- "--overwrite-assets" || fail "--help missing --overwrite-assets" "$help_out"

for bad_ow_val in yes 2 foo " "; do
    if env AURGEN_OVERWRITE_ASSETS="$bad_ow_val" "$ROOT/bin/aurgen" --usage >|"$tmp/ow-bad.out" 2>|"$tmp/ow-bad.err"; then
        fail "invalid AURGEN_OVERWRITE_ASSETS='$bad_ow_val' was unexpectedly accepted"
    fi
    grep -F -q -- "Invalid AURGEN_OVERWRITE_ASSETS: $bad_ow_val (expected 0 or 1)" "$tmp/ow-bad.err" \
        || fail "missing Invalid AURGEN_OVERWRITE_ASSETS error for '$bad_ow_val'" "$tmp/ow-bad.err"
done

for bad_ow_mode in local git aur-init aur-deploy aur-push aur-status doctor clean test lint golden config; do
    ow_bad_repo="$tmp/ow-$bad_ow_mode"
    mkdir -p "$ow_bad_repo"
    git -C "$ow_bad_repo" init -q -b main
    git -C "$ow_bad_repo" remote add origin "https://github.com/example/ow-demo.git"
    if (cd "$ow_bad_repo" && "$ROOT/bin/aurgen" --overwrite-assets "$bad_ow_mode") >|"$tmp/ow-$bad_ow_mode.out" 2>|"$tmp/ow-$bad_ow_mode.err"; then
        fail "--overwrite-assets unexpectedly accepted with $bad_ow_mode"
    fi
    grep -Fq -- "--overwrite-assets is only valid with aur" "$tmp/ow-$bad_ow_mode.err" \
        || fail "--overwrite-assets refusal missing for $bad_ow_mode" "$tmp/ow-$bad_ow_mode.err"
    [[ ! -e "$ow_bad_repo/aur" ]] || fail "--overwrite-assets preflight refusal created aur/ for $bad_ow_mode"
done

if ! (cd "$nc_ok_repo" && env AURGEN_OVERWRITE_ASSETS=1 "$ROOT/bin/aurgen" lint) >|"$tmp/ow-env-lint.out" 2>|"$tmp/ow-env-lint.err"; then
    fail "inherited AURGEN_OVERWRITE_ASSETS=1 unexpectedly broke lint" "$tmp/ow-env-lint.err"
fi
if ! (cd "$nc_ok_repo" && env AURGEN_OVERWRITE_ASSETS=1 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -n --dry-run local) >|"$tmp/ow-env-local.out" 2>|"$tmp/ow-env-local.err"; then
    fail "inherited AURGEN_OVERWRITE_ASSETS=1 unexpectedly broke local" "$tmp/ow-env-local.err"
fi
if ! (cd "$nc_ok_repo" && env AURGEN_OVERWRITE_ASSETS=0 PATH="$stub:$PATH" GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN "$ROOT/bin/aurgen" -n --overwrite-assets --dry-run aur) >|"$tmp/ow-cli-aur.out" 2>|"$tmp/ow-cli-aur.err"; then
    fail "--overwrite-assets --dry-run aur failed" "$tmp/ow-cli-aur.err"
fi
