#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stub="$tmp/bin"
mkdir -p "$stub"
cat > "$stub/git" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GIT_ARGV_LOG"
args=("$@")
if [[ "${args[0]}" == "-C" ]]; then
    args=("${args[@]:2}")
fi
case "${args[0]}" in
    commit)
        exit 1
        ;;
    diff)
        exit "$GIT_DIFF_STATUS"
        ;;
    status)
        case "${GIT_STATUS_STATE:-clean}" in
            staged) printf 'M  PKGBUILD\n' ;;
            unstaged) printf ' M PKGBUILD\n' ;;
            untracked)
                if [[ " ${args[*]} " != *" --untracked-files=no "* ]]; then
                    printf '?? notes.txt\n'
                fi
                ;;
            failed) exit 1 ;;
        esac
        exit 0
        ;;
    merge-base)
        exit "${GIT_MERGE_BASE_STATUS:-0}"
        ;;
    rev-list)
        printf '%s\n' "${GIT_REV_LIST_COUNT:-0}"
        exit 0
        ;;
    config)
        # user.name / user.email reads. A set (a third argument) succeeds.
        # Empty GIT_CONFIG_USER_* is a missing key. Unset inherits an identity
        # so cases that do not care about it still reach commit.
        if [[ "${args[1]:-}" == user.name || "${args[1]:-}" == user.email ]]; then
            if (( ${#args[@]} > 2 )); then
                exit 0
            fi
            value=""
            if [[ "${args[1]}" == user.name ]]; then
                value="${GIT_CONFIG_USER_NAME-tester}"
            else
                value="${GIT_CONFIG_USER_EMAIL-tester@example.com}"
            fi
            if [[ -z "$value" ]]; then
                exit 1
            fi
            printf '%s\n' "$value"
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$stub/git"
# deploy ends in aur_web_version, which curls the AUR RPC; keep it offline.
printf '#!/bin/bash\nexit 1\n' > "$stub/curl"
chmod +x "$stub/curl"

unset AURGEN_CONFIG_FILE AURGEN_NOCHECK nocheck build_only AURGEN_MAKEPKG_FLAGS AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_ROLLBACK PKG_URL PKG_EPOCH PKG_REPLACES PKG_OPTIONS
export PATH="$stub:$PATH"
export GIT_ARGV_LOG="$tmp/argv"
export GIT_DIFF_STATUS=1
export AURGEN_ERROR_LOG="$tmp/err.log"
export color_enabled=0
export SILVER=""
export RESET=""
export YELLOW=""
export LIB_INSTALL_DIR="$ROOT/lib"
export AUR_DIR="$tmp/aurdir"
export PKGNAME="demopkg"
export PKGVER="1.0.0"
export PKGBUILD="$tmp/PKGBUILD"
export SRCINFO="$tmp/.SRCINFO"
: > "$GIT_ARGV_LOG"
: > "$AURGEN_ERROR_LOG"
printf 'pkgver=%s\n' "$PKGVER" > "$PKGBUILD"
printf 'pkgbase=%s\n' "$PKGNAME" > "$SRCINFO"
mkdir -p "$AUR_DIR" "$tmp/aur/$PKGNAME/.git"
cat > "$AUR_DIR/aurgen.install.yaml" << EOF
aur_integration:
  aur_repo_dir: $tmp/aur
  auto_push: true
  commit_message: Update to version {version}
  validate_before_push: false
EOF

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/modes/aur-deploy.sh
source "$ROOT/lib/modes/aur-deploy.sh"
# The placeholder PKGBUILD is not a real one; .SRCINFO regeneration is covered in test-deploy-e2e.sh.
generate_srcinfo() { :; }

if mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "failing commit was treated as success"
    exit 1
fi
if grep -F -q "Successfully deployed" "$tmp/out"; then
    echo "failing commit printed a success message"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q "has been pushed" "$tmp/out"; then
    echo "failing commit reported a push"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "failing commit still pushed"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "diff --cached --quiet" "$GIT_ARGV_LOG"; then
    echo "failing commit did not check the index"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

: > "$GIT_ARGV_LOG"
: > "$tmp/out"
export GIT_DIFF_STATUS=0
export GIT_REV_LIST_COUNT=0
if ! mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "empty index was treated as a commit failure"
    cat "$tmp/mode.err"
    exit 1
fi
if grep -F -q "has been pushed" "$tmp/out"; then
    echo "empty index reported a push"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q "Successfully deployed" "$tmp/out"; then
    echo "empty index reported a successful deploy"
    cat "$tmp/out"
    exit 1
fi
if grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "empty index still pushed"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "rev-list --count origin/master..HEAD" "$GIT_ARGV_LOG"; then
    echo "empty index did not count commits ahead of origin/master"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

: > "$GIT_ARGV_LOG"
: > "$tmp/out"
export GIT_REV_LIST_COUNT=1
if ! mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "unpushed commit was not pushed"
    cat "$tmp/mode.err"
    exit 1
fi
if ! grep -F -q "Pushing a previous unpushed commit" "$tmp/out"; then
    echo "unpushed commit was not announced"
    cat "$tmp/out"
    exit 1
fi
if ! grep -F -q "has been pushed" "$tmp/out"; then
    echo "unpushed commit did not report a push"
    cat "$tmp/out"
    exit 1
fi
if ! grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "unpushed commit did not push"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
export GIT_REV_LIST_COUNT=0

printf "pkgver=%s\ninstall='demo.install'\n" "$PKGVER" > "$PKGBUILD"
printf 'post_install() { :; }\n' > "$AUR_DIR/demo.install"
: > "$GIT_ARGV_LOG"
mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err" || true
if ! cmp -s "$AUR_DIR/demo.install" "$tmp/aur/$PKGNAME/demo.install"; then
    echo "install file was not copied"
    exit 1
fi
if ! grep -F -q "add PKGBUILD .SRCINFO demo.install" "$GIT_ARGV_LOG"; then
    echo "git add did not name the install file"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "Copied PKGBUILD, .SRCINFO and demo.install" "$tmp/out"; then
    echo "copy log did not name the install file"
    cat "$tmp/out"
    exit 1
fi

printf "pkgver=%s\ninstall='missing.install'\n" "$PKGVER" > "$PKGBUILD"
: > "$GIT_ARGV_LOG"
: > "$tmp/mode.err"
if mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err"; then
    echo "missing install file was deployed"
    exit 1
fi
if ! grep -F -q "install file not found" "$tmp/mode.err"; then
    echo "missing install file did not report an error"
    cat "$tmp/mode.err"
    exit 1
fi
if grep -F -q "add PKGBUILD .SRCINFO missing.install" "$GIT_ARGV_LOG"; then
    echo "missing install file was staged"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

cat > "$tmp/quoted.yaml" << 'EOF'
aur_integration:
  commit_message: "Update to version {version}"
  git_user_name: "Your Name"
  auto_push: "true"
EOF
cat > "$tmp/plain.yaml" << 'EOF'
aur_integration:
  commit_message: Update to version {version}
  git_user_name: Your Name
  auto_push: true
EOF
parse_aur_integration_config "$tmp/quoted.yaml"
quoted_message="$AUR_COMMIT_MESSAGE"
quoted_name="$AUR_GIT_USER_NAME"
quoted_push="$AUR_AUTO_PUSH"
parse_aur_integration_config "$tmp/plain.yaml"
printf 'aur_integration:\n  auto_push: false' > "$tmp/noeol.yaml"
parse_aur_integration_config "$tmp/noeol.yaml"
if [[ "$AUR_AUTO_PUSH" != "false" ]]; then
    echo "unterminated auto_push: false was ignored: [$AUR_AUTO_PUSH]"
    exit 1
fi
parse_aur_integration_config "$tmp/plain.yaml"
if [[ "$AUR_COMMIT_MESSAGE" != "$quoted_message" ]]; then
    echo "quoted and unquoted commit_message differ: [$quoted_message] [$AUR_COMMIT_MESSAGE]"
    exit 1
fi
if [[ "$AUR_COMMIT_MESSAGE" != "Update to version {version}" ]]; then
    echo "commit_message was not unquoted: [$AUR_COMMIT_MESSAGE]"
    exit 1
fi
if [[ "$AUR_GIT_USER_NAME" != "$quoted_name" ]]; then
    echo "quoted and unquoted git_user_name differ: [$quoted_name] [$AUR_GIT_USER_NAME]"
    exit 1
fi
if [[ "$AUR_GIT_USER_NAME" != "Your Name" ]]; then
    echo "git_user_name was not unquoted: [$AUR_GIT_USER_NAME]"
    exit 1
fi
if [[ "$AUR_AUTO_PUSH" != "$quoted_push" ]]; then
    echo "quoted and unquoted auto_push differ: [$quoted_push] [$AUR_AUTO_PUSH]"
    exit 1
fi
if [[ "$AUR_AUTO_PUSH" != "true" ]]; then
    echo "auto_push was not unquoted: [$AUR_AUTO_PUSH]"
    exit 1
fi

generate_default_config "$tmp/fresh.yaml" >"$tmp/gen.out" 2>"$tmp/gen.err" || exit 1
generate_example_config "$tmp/fresh-example.yaml" >"$tmp/ex.out" 2>"$tmp/ex.err" || exit 1
for generated in "$tmp/fresh.yaml" "$tmp/fresh-example.yaml"; do
    if grep -E -q '^[[:space:]]*git_user_name:' "$generated"; then
        echo "generated config sets git_user_name: $generated"
        exit 1
    fi
    if grep -E -q '^[[:space:]]*git_user_email:' "$generated"; then
        echo "generated config sets git_user_email: $generated"
        exit 1
    fi
    if grep -E -q '^[[:space:]]*ssh_key:' "$generated"; then
        echo "generated config sets ssh_key: $generated"
        exit 1
    fi
    if ! grep -F -q '# ssh_key: ~/.ssh/aur' "$generated"; then
        echo "generated config dropped the commented ssh_key: $generated"
        exit 1
    fi
done

printf 'pkgver=%s\n' "$PKGVER" > "$PKGBUILD"
cat > "$AUR_DIR/aurgen.install.yaml" << EOF
aur_integration:
  aur_repo_dir: $tmp/aur
  auto_push: false
  commit_message: "Update to version {version}"
  validate_before_push: false
EOF
: > "$GIT_ARGV_LOG"
mode_aur_deploy >"$tmp/out" 2>"$tmp/mode.err" || true
if ! grep -F -q "commit -m Update to version 1.0.0" "$GIT_ARGV_LOG"; then
    echo "quoted commit_message was not committed as Update to version 1.0.0"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if grep -F -q 'commit -m "Update' "$GIT_ARGV_LOG"; then
    echo "quoted commit_message kept its quotes"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

clone="$tmp/aur/$PKGNAME"
printf 'pkgver=%s\n' "$PKGVER" > "$clone/PKGBUILD"
chmod 444 "$clone/PKGBUILD"
chmod 555 "$clone"
: > "$tmp/mode.err"
if deploy_to_aur "$PKGNAME" >"$tmp/out" 2>"$tmp/mode.err"; then
    chmod 755 "$clone"
    chmod 644 "$clone/PKGBUILD"
    echo "unwritable PKGBUILD was deployed"
    exit 1
fi
chmod 755 "$clone"
chmod 644 "$clone/PKGBUILD"
if ! grep -F -q "[aur-integration] Failed to copy PKGBUILD to $clone" "$tmp/mode.err"; then
    echo "unwritable PKGBUILD did not report a copy error"
    cat "$tmp/mode.err"
    exit 1
fi

# A downloaded source must have a pinned checksum before it reaches the AUR.
pin="$tmp/pin.SRCINFO"
printf 'pkgbase = demopkg\n\tsource = https://example.com/demo-1.0.tar.gz\n\tb2sums = SKIP\n\npkgname = demopkg\n' > "$pin"
if aur_srcinfo_checksums_pinned "$pin" 2>/dev/null; then
    echo "SKIP checksum on a downloaded tarball was accepted"
    exit 1
fi
printf 'pkgbase = demopkg\n\tsource = demo::git+https://example.com/demo.git#tag=v1?signed\n\tb2sums = SKIP\n\npkgname = demopkg\n' > "$pin"
aur_srcinfo_checksums_pinned "$pin" || { echo "SKIP on a git source was refused"; exit 1; }
printf 'pkgbase = demopkg\n\tsource = https://example.com/demo-1.0.tar.gz\n\tsource = https://example.com/demo-1.0.tar.gz.sig\n\tb2sums = %s\n\tb2sums = SKIP\n\npkgname = demopkg\n' "$(printf 'a%.0s' {1..128})" > "$pin"
# makepkg writes SKIP for signature files itself; gpg verifies them.
aur_srcinfo_checksums_pinned "$pin" || { echo "SKIP on the detached signature was refused"; exit 1; }
printf 'pkgbase = demopkg\n\tsource = demo.tar.gz::https://example.com/download?id=1\n\tb2sums = SKIP\n\npkgname = demopkg\n' > "$pin"
if aur_srcinfo_checksums_pinned "$pin" 2>/dev/null; then
    echo "SKIP checksum on a renamed download was accepted"
    exit 1
fi
printf 'pkgbase = demopkg\n\tsource = https://example.com/demo-1.0.tar.gz\n\tsha256sums = %s\n\npkgname = demopkg\n' "$(printf 'b%.0s' {1..64})" > "$pin"
aur_srcinfo_checksums_pinned "$pin" || { echo "pinned checksum was refused"; exit 1; }

# deploy_to_aur stops before copying when a real deploy would publish a SKIP checksum.
printf 'pkgbase = demopkg\n\tsource = https://example.com/demo-1.0.tar.gz\n\tb2sums = SKIP\n' >| "$SRCINFO"
: >| "$GIT_ARGV_LOG"
if dry_run=0 deploy_to_aur "$PKGNAME" >"$tmp/skip.out" 2>"$tmp/skip.err"; then
    echo "deploy_to_aur published a SKIP checksum"
    exit 1
fi
grep -F -q 'b2sums is SKIP for downloaded source' "$tmp/skip.err" || { echo "SKIP refusal did not explain itself"; cat "$tmp/skip.err"; exit 1; }
if grep -F -q 'add PKGBUILD' "$GIT_ARGV_LOG"; then
    echo "deploy_to_aur staged files despite a SKIP checksum"
    exit 1
fi

assert_no_identity() {
    if grep -F -q 'core.sshCommand' "$GIT_ARGV_LOG"; then
        echo "$1 added core.sshCommand"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
    if grep -F -q -- '-i ' "$GIT_ARGV_LOG"; then
        echo "$1 added -i"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
}

AUR_SSH_KEY="$tmp/no-such-key"
: >| "$GIT_ARGV_LOG"
rm -rf "$tmp/aur/initpkg"
if ! init_aur_repo "initpkg" >|"$tmp/ssh-missing.out" 2>|"$tmp/ssh-missing.err"; then
    echo "init with a missing ssh_key failed"
    cat "$tmp/ssh-missing.err"
    exit 1
fi
assert_no_identity "missing ssh_key on init"
if grep -F -q "ssh_key" "$tmp/ssh-missing.out"; then
    echo "init warned about ssh_key"
    cat "$tmp/ssh-missing.out"
    exit 1
fi
: >| "$GIT_ARGV_LOG"
if ! push_to_aur "$PKGNAME" >|"$tmp/ssh-missing-push.out" 2>|"$tmp/ssh-missing-push.err"; then
    echo "push with a missing ssh_key failed"
    cat "$tmp/ssh-missing-push.err"
    exit 1
fi
assert_no_identity "missing ssh_key on push"
if ! grep -F -q "[aur-integration] ssh_key $tmp/no-such-key does not exist; using the ssh configuration" "$tmp/ssh-missing-push.out"; then
    echo "missing ssh_key did not warn on push"
    cat "$tmp/ssh-missing-push.out"
    exit 1
fi

AUR_SSH_KEY="$tmp/missing key; echo hi"
: >| "$GIT_ARGV_LOG"
if ! push_to_aur "$PKGNAME" >|"$tmp/ssh-missing-space.out" 2>|"$tmp/ssh-missing-space.err"; then
    echo "push with a missing spaced ssh_key failed"
    cat "$tmp/ssh-missing-space.err"
    exit 1
fi
assert_no_identity "missing spaced ssh_key on push"
if ! grep -F -q "[aur-integration] ssh_key $AUR_SSH_KEY does not exist; using the ssh configuration" "$tmp/ssh-missing-space.out"; then
    echo "missing spaced ssh_key did not warn on push"
    cat "$tmp/ssh-missing-space.out"
    exit 1
fi

touch "$tmp/aur_key"
AUR_SSH_KEY="$tmp/aur_key"
expected_ssh="core.sshCommand=ssh -i $(printf %q "$AUR_SSH_KEY")"
: >| "$GIT_ARGV_LOG"
rm -rf "$tmp/aur/initpkg"
if ! init_aur_repo "initpkg" >|"$tmp/ssh-key.out" 2>|"$tmp/ssh-key.err"; then
    echo "init with an existing ssh_key failed"
    cat "$tmp/ssh-key.err"
    exit 1
fi
if grep -F -q -- "$expected_ssh" "$GIT_ARGV_LOG"; then
    echo "init passed an ssh key to clone"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
: >| "$GIT_ARGV_LOG"
if ! push_to_aur "$PKGNAME" >|"$tmp/ssh-key-push.out" 2>|"$tmp/ssh-key-push.err"; then
    echo "push with an existing ssh_key failed"
    cat "$tmp/ssh-key-push.err"
    exit 1
fi
if ! grep -F -q -- "$expected_ssh" "$GIT_ARGV_LOG"; then
    echo "existing ssh_key was not passed to push"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

# aur-push: one commit ahead uses push origin HEAD:master; nothing ahead does not push.
export GIT_REV_LIST_COUNT=1
: >| "$GIT_ARGV_LOG"
if ! mode_aur_push >|"$tmp/push.out" 2>|"$tmp/push.err"; then
    echo "aur-push with a commit ahead failed"
    cat "$tmp/push.err"
    exit 1
fi
if ! grep -F -q "push origin HEAD:master" "$GIT_ARGV_LOG"; then
    echo "aur-push did not push HEAD:master"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

# Reject tracked changes and status failures before validation or push.
export GIT_STATUS_STATE=clean
for push_entry in push_to_aur mode_aur_push; do
    # mode_aur_push reloads the yaml, so validation must be on there too, or the
    # "validated" check below could not fail.
    if [[ "$push_entry" == mode_aur_push ]]; then
        sed -i 's/^  validate_before_push: false$/  validate_before_push: true/' "$AUR_DIR/aurgen.install.yaml"
        grep -q '^  validate_before_push: true$' "$AUR_DIR/aurgen.install.yaml" || { echo "could not turn validation on for aur-push"; exit 1; }
    fi
    for GIT_STATUS_STATE in staged unstaged failed; do
        export AUR_VALIDATE_BEFORE_PUSH=true
        : >| "$GIT_ARGV_LOG"
        if "$push_entry" "$PKGNAME" >|"$tmp/push.out" 2>|"$tmp/push.err"; then
            echo "$push_entry accepted $GIT_STATUS_STATE status"
            exit 1
        fi
        if ! grep -F -q "AUR clone $clone has uncommitted changes, or git status failed there; commit or discard the changes in $clone, then re-run aurgen aur-push" "$tmp/push.err"; then
            echo "$push_entry did not name the clone and recovery for $GIT_STATUS_STATE status"
            cat "$tmp/push.err"
            exit 1
        fi
        if ! grep -F -q -- "-C $clone status --porcelain --untracked-files=no" "$GIT_ARGV_LOG"; then
            echo "$push_entry did not check tracked changes in the clone"
            cat "$GIT_ARGV_LOG"
            exit 1
        fi
        if grep -F -q ' push' "$GIT_ARGV_LOG"; then
            echo "$push_entry pushed with $GIT_STATUS_STATE status"
            cat "$GIT_ARGV_LOG"
            exit 1
        fi
        if grep -F -q 'Validating AUR repository' "$tmp/push.out"; then
            echo "$push_entry validated with $GIT_STATUS_STATE status"
            exit 1
        fi
        if grep -F -q '[FATAL]' "$tmp/push.err"; then
            echo "$push_entry tripped the error trap for $GIT_STATUS_STATE status"
            cat "$tmp/push.err"
            exit 1
        fi
    done

    sed -i 's/^  validate_before_push: true$/  validate_before_push: false/' "$AUR_DIR/aurgen.install.yaml"

    # Once the edit is committed, status is clean; untracked files also allow push.
    for GIT_STATUS_STATE in clean untracked; do
        export AUR_VALIDATE_BEFORE_PUSH=false
        : >| "$GIT_ARGV_LOG"
        if ! "$push_entry" "$PKGNAME" >|"$tmp/push.out" 2>|"$tmp/push.err"; then
            echo "$push_entry refused $GIT_STATUS_STATE status"
            cat "$tmp/push.err"
            exit 1
        fi
        if ! grep -F -q "push origin HEAD:master" "$GIT_ARGV_LOG"; then
            echo "$push_entry did not push with $GIT_STATUS_STATE status"
            cat "$GIT_ARGV_LOG"
            exit 1
        fi
    done
done
unset GIT_STATUS_STATE

# --dry-run never pushes.
: >| "$GIT_ARGV_LOG"
if ! dry_run=1 mode_aur_push >|"$tmp/push.out" 2>|"$tmp/push.err"; then
    echo "aur-push --dry-run failed"
    cat "$tmp/push.err"
    exit 1
fi
if grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "aur-push --dry-run pushed"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
grep -F -q "(dry run) Would push 1 commit(s)" "$tmp/push.out" || { echo "aur-push --dry-run did not say what it would push"; cat "$tmp/push.out"; exit 1; }

export GIT_REV_LIST_COUNT=0
: >| "$GIT_ARGV_LOG"
if ! mode_aur_push >|"$tmp/push.out" 2>|"$tmp/push.err"; then
    echo "aur-push with nothing ahead failed"
    cat "$tmp/push.err"
    exit 1
fi
if grep -F -q " push" "$GIT_ARGV_LOG"; then
    echo "aur-push with nothing ahead still pushed"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "Nothing to push" "$tmp/push.out"; then
    echo "aur-push with nothing ahead did not say so"
    cat "$tmp/push.out"
    exit 1
fi

mv "$tmp/aur/$PKGNAME" "$tmp/aur/$PKGNAME.aside"
if mode_aur_push >|"$tmp/push.out" 2>|"$tmp/push.err"; then
    echo "aur-push with a missing clone succeeded"
    exit 1
fi
if ! grep -F -q "does not exist" "$tmp/push.err"; then
    echo "missing clone did not report an error"
    cat "$tmp/push.err"
    exit 1
fi
mv "$tmp/aur/$PKGNAME.aside" "$tmp/aur/$PKGNAME"

# No usable identity must stop before cp or git add and name the fix.
clone="$tmp/aur/$PKGNAME"
export AUR_REPO_DIR="$tmp/aur"
AUR_COMMIT_MESSAGE="Update to version {version}"
export GIT_DIFF_STATUS=0
export GIT_REV_LIST_COUNT=0
# git also reads an identity from its environment; the refused cases need none.
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL
identity_msg="[aur-integration] No git identity for the AUR clone; set aur_integration.git_user_name/git_user_email or run: git -C $clone config user.name ... && git -C $clone config user.email ..."

seed_clone_markers() {
    printf 'pkgver=source-marker\n' >| "$PKGBUILD"
    printf 'pkgbase=%s\n' "$PKGNAME" >| "$SRCINFO"
    printf 'pkgver=clone-marker\n' >| "$clone/PKGBUILD"
    printf 'srcinfo-clone\n' >| "$clone/.SRCINFO"
}

assert_clone_untouched() {
    local label="$1"
    if grep -F -q "add PKGBUILD" "$GIT_ARGV_LOG"; then
        echo "$label staged files"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
    if grep -F -q "commit -m" "$GIT_ARGV_LOG"; then
        echo "$label committed"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
    if ! grep -F -x -q 'pkgver=clone-marker' "$clone/PKGBUILD"; then
        echo "$label copied PKGBUILD"
        exit 1
    fi
    if ! grep -F -x -q 'srcinfo-clone' "$clone/.SRCINFO"; then
        echo "$label copied .SRCINFO"
        exit 1
    fi
}

assert_identity_refused() {
    local label="$1"
    if ! grep -F -q "$identity_msg" "$tmp/ident.err"; then
        echo "$label did not name the fix"
        cat "$tmp/ident.err"
        exit 1
    fi
    if grep -F -q "[FATAL]" "$tmp/ident.err"; then
        echo "$label tripped the error trap"
        cat "$tmp/ident.err"
        exit 1
    fi
    if ! grep -F -q "merge-base --is-ancestor" "$GIT_ARGV_LOG"; then
        echo "$label stopped before the clone checks"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
    assert_clone_untouched "$label"
}

assert_deploy_copied() {
    local label="$1"
    if grep -F -q "No git identity" "$tmp/ident.err"; then
        echo "$label refused a usable identity"
        cat "$tmp/ident.err"
        exit 1
    fi
    if ! grep -F -q "add PKGBUILD .SRCINFO" "$GIT_ARGV_LOG"; then
        echo "$label did not stage files"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
    if ! grep -F -q "commit -m" "$GIT_ARGV_LOG"; then
        echo "$label did not commit"
        cat "$GIT_ARGV_LOG"
        exit 1
    fi
    if ! cmp -s "$PKGBUILD" "$clone/PKGBUILD"; then
        echo "$label did not copy PKGBUILD"
        exit 1
    fi
    if ! cmp -s "$SRCINFO" "$clone/.SRCINFO"; then
        echo "$label did not copy .SRCINFO"
        exit 1
    fi
}

# Fetch must detect an origin advanced by another clone before copying files.
(
    export PATH="${PATH#"$stub:"}"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    export LC_ALL=C
    AUR_REPO_DIR="$tmp/behind-aur"
    AUR_AUTO_PUSH=false
    AUR_SSH_KEY=""
    AUR_GIT_USER_NAME="tester"
    AUR_GIT_USER_EMAIL="tester@example.com"
    aur_web_version() { :; }
    clone="$AUR_REPO_DIR/$PKGNAME"
    origin="$tmp/behind-origin.git"
    writer="$tmp/behind-writer"
    git init -q --bare --initial-branch=master "$origin" || exit 1
    git clone -q "$origin" "$clone" || exit 1
    seed_clone_markers || exit 1
    printf 'pkgrel=1\n' >> "$clone/PKGBUILD" || exit 1
    git -C "$clone" add PKGBUILD .SRCINFO || exit 1
    git -C "$clone" -c user.name=tester -c user.email=tester@example.com \
        -c commit.gpgsign=false commit -qm baseline || exit 1
    git -C "$clone" push -q -u origin master || exit 1
    head_before=$(git -C "$clone" rev-parse HEAD) || exit 1
    cp "$clone/PKGBUILD" "$tmp/behind.PKGBUILD" || exit 1

    git clone -q "$origin" "$writer" || exit 1
    printf 'pkgver=clone-marker\npkgrel=2\n' >| "$writer/PKGBUILD" || exit 1
    git -C "$writer" add PKGBUILD || exit 1
    git -C "$writer" -c user.name=tester -c user.email=tester@example.com \
        -c commit.gpgsign=false commit -qm 'Bump pkgrel' || exit 1
    git -C "$writer" push -q origin master || exit 1

    if dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/behind-real.out" 2>|"$tmp/behind-real.err"; then
        echo "deploy from a real clone behind origin succeeded"
        exit 1
    fi
    if ! grep -F -q "AUR clone $clone is behind origin" "$tmp/behind-real.err"; then
        echo "real behind clone did not report behind origin"
        cat "$tmp/behind-real.err"
        exit 1
    fi
    if ! cmp -s "$tmp/behind.PKGBUILD" "$clone/PKGBUILD"; then
        echo "real behind clone changed PKGBUILD"
        exit 1
    fi
    if [[ "$(git -C "$clone" rev-parse HEAD)" != "$head_before" ]]; then
        echo "real behind clone created a commit"
        exit 1
    fi
) || exit 1

seed_clone_markers
: >| "$GIT_ARGV_LOG"
if GIT_MERGE_BASE_STATUS=1 dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/behind.out" 2>|"$tmp/behind.err"; then
    echo "deploy from a clone behind origin succeeded"
    exit 1
fi
if ! grep -F -q "AUR clone $clone is behind origin; run git -C $(printf '%q' "$clone") pull --ff-only, then re-run aurgen aur --deploy" "$tmp/behind.err"; then
    echo "behind clone did not name the pull and deploy recovery"
    cat "$tmp/behind.err"
    exit 1
fi
assert_clone_untouched "behind clone"

seed_clone_markers
AUR_GIT_USER_NAME=""
export AUR_GIT_USER_EMAIL=""
export GIT_CONFIG_USER_NAME=""
export GIT_CONFIG_USER_EMAIL=""
: >| "$GIT_ARGV_LOG"
if dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/ident.out" 2>|"$tmp/ident.err"; then
    echo "deploy without a git identity succeeded"
    exit 1
fi
assert_identity_refused "missing git identity"

# A name without an email is still no identity.
seed_clone_markers
AUR_GIT_USER_NAME="Only Name"
AUR_GIT_USER_EMAIL=""
export GIT_CONFIG_USER_NAME="Inherited Name"
export GIT_CONFIG_USER_EMAIL=""
: >| "$GIT_ARGV_LOG"
if dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/ident.out" 2>|"$tmp/ident.err"; then
    echo "deploy with only a git name succeeded"
    exit 1
fi
assert_identity_refused "git name without an email"

# An identity from git's environment is enough when config has none.
seed_clone_markers
AUR_GIT_USER_NAME=""
AUR_GIT_USER_EMAIL=""
export GIT_CONFIG_USER_NAME=""
export GIT_CONFIG_USER_EMAIL=""
: >| "$GIT_ARGV_LOG"
if ! GIT_AUTHOR_NAME="Env Name" GIT_AUTHOR_EMAIL="env@example.com" dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/ident.out" 2>|"$tmp/ident.err"; then
    echo "deploy with an identity from the environment failed"
    cat "$tmp/ident.err"
    exit 1
fi
assert_deploy_copied "environment git identity"

# The configured override is enough when the clone config has no identity.
seed_clone_markers
AUR_GIT_USER_NAME="Override Name"
AUR_GIT_USER_EMAIL="override@example.com"
export GIT_CONFIG_USER_NAME=""
export GIT_CONFIG_USER_EMAIL=""
: >| "$GIT_ARGV_LOG"
if ! dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/ident.out" 2>|"$tmp/ident.err"; then
    echo "deploy with a configured git identity failed"
    cat "$tmp/ident.err"
    exit 1
fi
assert_deploy_copied "configured git identity"
if ! grep -F -q "config user.name Override Name" "$GIT_ARGV_LOG"; then
    echo "configured git identity was not applied"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "config user.email override@example.com" "$GIT_ARGV_LOG"; then
    echo "configured git email was not applied"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

# An inherited clone identity proceeds when no override is set.
seed_clone_markers
AUR_GIT_USER_NAME=""
AUR_GIT_USER_EMAIL=""
export GIT_CONFIG_USER_NAME="Inherited Name"
export GIT_CONFIG_USER_EMAIL="inherited@example.com"
: >| "$GIT_ARGV_LOG"
if ! dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/ident.out" 2>|"$tmp/ident.err"; then
    echo "deploy with an inherited git identity failed"
    cat "$tmp/ident.err"
    exit 1
fi
assert_deploy_copied "inherited git identity"
if ! grep -F -q "config user.name" "$GIT_ARGV_LOG"; then
    echo "inherited git identity was not read"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if ! grep -F -q "config user.email" "$GIT_ARGV_LOG"; then
    echo "inherited git email was not read"
    cat "$GIT_ARGV_LOG"
    exit 1
fi
if grep -F -q "config user.name Inherited Name" "$GIT_ARGV_LOG"; then
    echo "inherited git identity was written into the clone"
    cat "$GIT_ARGV_LOG"
    exit 1
fi

# A staged unrelated edit must survive a refused deploy without any copies.
(
    export PATH="${PATH#"$stub:"}"
    export HOME="$tmp/dirty-home"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    mkdir -p "$HOME"
    AUR_REPO_DIR="$tmp/dirty-aur"
    AUR_AUTO_PUSH=false
    AUR_SSH_KEY=""
    clone="$AUR_REPO_DIR/$PKGNAME"
    git init -q "$clone"
    git -C "$clone" config user.name tester
    git -C "$clone" config user.email tester@example.com
    seed_clone_markers
    printf "install='demo.install'\n" >> "$PKGBUILD"
    printf 'source install\n' >| "$tmp/demo.install"
    printf 'clone install\n' >| "$clone/demo.install"
    printf 'original note\n' >| "$clone/notes.txt"
    git -C "$clone" add PKGBUILD .SRCINFO demo.install notes.txt
    git -C "$clone" -c commit.gpgsign=false commit -qm baseline
    head_before=$(git -C "$clone" rev-parse HEAD)
    printf 'staged unrelated edit\n' >| "$clone/notes.txt"
    git -C "$clone" add notes.txt
    staged_before=$(git -C "$clone" diff --cached -- notes.txt)

    if dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/dirty.out" 2>|"$tmp/dirty.err"; then
        echo "deploy accepted a staged unrelated change"
        exit 1
    fi
    if ! grep -F -q "AUR clone $clone has uncommitted changes, or git status failed there; commit or discard the changes there before deploying" "$tmp/dirty.err"; then
        echo "dirty deploy did not name the clone and recovery"
        cat "$tmp/dirty.err"
        exit 1
    fi
    if [[ "$(git -C "$clone" rev-parse HEAD)" != "$head_before" ]]; then
        echo "dirty deploy created a commit"
        exit 1
    fi
    if [[ "$(git -C "$clone" status --porcelain --untracked-files=no)" != 'M  notes.txt' ]] \
        || [[ "$(git -C "$clone" diff --cached -- notes.txt)" != "$staged_before" ]]; then
        echo "dirty deploy copied files or changed the staged edit"
        exit 1
    fi
) || exit 1

# A failed commit must put the clone back. The copies are staged, and a new
# install file is not in HEAD; the next deploy refuses a dirty clone.
(
    export PATH="${PATH#"$stub:"}"
    export HOME="$tmp/hook-home"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    export LC_ALL=C
    mkdir -p "$HOME"
    AUR_REPO_DIR="$tmp/hook-aur"
    AUR_AUTO_PUSH=false
    AUR_SSH_KEY=""
    AUR_GIT_USER_NAME=""
    AUR_GIT_USER_EMAIL=""
    clone="$AUR_REPO_DIR/$PKGNAME"
    git init -q "$clone"
    git -C "$clone" config user.name tester
    git -C "$clone" config user.email tester@example.com
    git -C "$clone" config commit.gpgsign false
    printf 'pkgver=clone-marker\n' >| "$clone/PKGBUILD"
    printf 'srcinfo-clone\n' >| "$clone/.SRCINFO"
    printf 'kept-baseline\n' >| "$clone/kept.install"
    git -C "$clone" add PKGBUILD .SRCINFO kept.install
    git -C "$clone" -c commit.gpgsign=false commit -qm baseline
    head_before=$(git -C "$clone" rev-parse HEAD)
    printf "pkgver=source-marker\ninstall='demo.install'\n" >| "$PKGBUILD"
    printf 'pkgbase=%s\n' "$PKGNAME" >| "$SRCINFO"
    printf 'source install\n' >| "$tmp/demo.install"
    printf '#!/bin/sh\nexit 1\n' >| "$clone/.git/hooks/pre-commit"
    chmod +x "$clone/.git/hooks/pre-commit"

    if dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/hook.out" 2>|"$tmp/hook.err"; then
        echo "deploy with a failing pre-commit hook succeeded"
        exit 1
    fi
    if ! grep -F -q "Failed to commit changes" "$tmp/hook.err"; then
        echo "failing hook did not report the commit error"
        cat "$tmp/hook.err"
        exit 1
    fi
    if [[ "$(git -C "$clone" rev-parse HEAD)" != "$head_before" ]]; then
        echo "failing hook moved HEAD"
        exit 1
    fi
    if [[ -n "$(git -C "$clone" status --porcelain)" ]]; then
        echo "failing hook left the clone dirty"
        git -C "$clone" status --porcelain
        exit 1
    fi
    if ! grep -F -x -q 'pkgver=clone-marker' "$clone/PKGBUILD"; then
        echo "failing hook did not restore PKGBUILD"
        exit 1
    fi
    if ! grep -F -x -q 'srcinfo-clone' "$clone/.SRCINFO"; then
        echo "failing hook did not restore .SRCINFO"
        exit 1
    fi
    if ! grep -F -x -q 'kept-baseline' "$clone/kept.install"; then
        echo "failing hook did not restore the tracked install file"
        exit 1
    fi
    if [[ -e "$clone/demo.install" ]]; then
        echo "failing hook left an install file HEAD does not track"
        exit 1
    fi

    rm -f -- "$clone/.git/hooks/pre-commit"
    if ! dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/hook2.out" 2>|"$tmp/hook2.err"; then
        echo "deploy after removing the hook failed"
        cat "$tmp/hook2.err"
        exit 1
    fi
    if [[ "$(git -C "$clone" rev-parse HEAD)" == "$head_before" ]]; then
        echo "deploy after removing the hook did not commit"
        exit 1
    fi
    if [[ -n "$(git -C "$clone" status --porcelain)" ]]; then
        echo "deploy after removing the hook left the clone dirty"
        git -C "$clone" status --porcelain
        exit 1
    fi
    if ! grep -F -x -q 'source install' "$clone/demo.install"; then
        echo "deploy after removing the hook did not commit the install file"
        exit 1
    fi
) || exit 1

# A failed first commit must leave an empty clone ready for another deploy.
(
    export PATH="${PATH#"$stub:"}"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    export LC_ALL=C
    AUR_REPO_DIR="$tmp/first-hook-aur"
    AUR_AUTO_PUSH=false
    AUR_SSH_KEY=""
    AUR_GIT_USER_NAME=""
    AUR_GIT_USER_EMAIL=""
    clone="$AUR_REPO_DIR/$PKGNAME"
    git init -q "$clone" || exit 1
    git -C "$clone" config user.name tester || exit 1
    git -C "$clone" config user.email tester@example.com || exit 1
    git -C "$clone" config commit.gpgsign false || exit 1
    printf "pkgver=source-marker\ninstall='demo.install'\n" >| "$PKGBUILD" || exit 1
    printf 'pkgbase=%s\n' "$PKGNAME" >| "$SRCINFO" || exit 1
    printf 'source install\n' >| "$tmp/demo.install" || exit 1
    printf '#!/bin/sh\nexit 1\n' >| "$clone/.git/hooks/pre-commit" || exit 1
    chmod +x "$clone/.git/hooks/pre-commit" || exit 1

    if dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/first-hook.out" 2>|"$tmp/first-hook.err"; then
        echo "first deploy with a failing pre-commit hook succeeded"
        exit 1
    fi
    if ! grep -F -q "Failed to commit changes" "$tmp/first-hook.err"; then
        echo "failing first hook did not report the commit error"
        cat "$tmp/first-hook.err"
        exit 1
    fi
    if git -C "$clone" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        echo "failing first hook created a commit"
        exit 1
    fi
    repo_status=$(git -C "$clone" status --porcelain) || exit 1
    if [[ -n "$repo_status" ]]; then
        echo "failing first hook left staged or untracked files"
        exit 1
    fi
    for copied_file in PKGBUILD .SRCINFO demo.install; do
        if [[ -e "$clone/$copied_file" || -L "$clone/$copied_file" ]]; then
            echo "failing first hook left $copied_file in the clone"
            exit 1
        fi
    done

    rm -f -- "$clone/.git/hooks/pre-commit" || exit 1
    if ! dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/first-hook2.out" 2>|"$tmp/first-hook2.err"; then
        echo "first deploy after removing the hook failed"
        cat "$tmp/first-hook2.err"
        exit 1
    fi
    git -C "$clone" rev-parse --verify --quiet HEAD >/dev/null || exit 1
    repo_status=$(git -C "$clone" status --porcelain) || exit 1
    [[ -z "$repo_status" ]] || { echo "first deploy retry left the clone dirty"; exit 1; }
    for copied_file in PKGBUILD .SRCINFO demo.install; do
        git -C "$clone" ls-files --error-unmatch -- "$copied_file" >/dev/null || exit 1
    done
) || exit 1

# Invalid aur_integration booleans and unknown keys must abort AUR modes before touching git.
(
    # shellcheck source=../lib/modes/aur-init.sh
    source "$ROOT/lib/modes/aur-init.sh"
    # shellcheck source=../lib/modes/aur-status.sh
    source "$ROOT/lib/modes/aur-status.sh"
    printf 'pkgver=1.0.0\n' >| "$PKGBUILD"
    printf 'pkgbase = %s\n\tpkgver = 1.0.0\n\tpkgrel = 1\n' "$PKGNAME" >| "$SRCINFO"
    for bad_spec in \
        "auto_push: no|Invalid configuration value for auto_push" \
        "validate_before_push: 0|Invalid configuration value for validate_before_push" \
        "autopush: false|Unknown aur_integration key 'autopush'" \
        "auto-push: false|Unknown aur_integration key 'auto-push'" \
        "- list_item|Invalid aur_integration entry"; do
        bad_line="${bad_spec%%|*}"
        bad_diag="${bad_spec#*|}"
        cat >| "$AUR_DIR/aurgen.install.yaml" <<EOF
aur_integration:
  aur_repo_dir: $tmp/aur
  $bad_line
EOF
        for fn in mode_aur_deploy mode_aur_push mode_aur_init mode_aur_status; do
            : >| "$GIT_ARGV_LOG"
            if "$fn" >|"$tmp/badcfg.out" 2>|"$tmp/badcfg.err"; then
                echo "$fn succeeded with invalid aur_integration line: $bad_line"
                exit 1
            fi
            if ! grep -Fq "$bad_diag" "$tmp/badcfg.err"; then
                echo "$fn did not report '$bad_diag' for: $bad_line"
                cat "$tmp/badcfg.err"
                exit 1
            fi
            if [[ -s "$GIT_ARGV_LOG" ]]; then
                echo "$fn invoked git despite invalid aur_integration line: $bad_line"
                cat "$GIT_ARGV_LOG"
                exit 1
            fi
        done
    done
) || exit 1

# deploy_to_aur includes .SRCINFO epoch in {version} commit messages when present.
(
    export PATH="${PATH#"$stub:"}"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    export LC_ALL=C
    AUR_REPO_DIR="$tmp/epoch-aur"
    AUR_AUTO_PUSH=false
    AUR_SSH_KEY=""
    AUR_GIT_USER_NAME=""
    AUR_GIT_USER_EMAIL=""
    clone="$AUR_REPO_DIR/$PKGNAME"
    git init -q "$clone" || exit 1
    git -C "$clone" config user.name tester || exit 1
    git -C "$clone" config user.email tester@example.com || exit 1
    git -C "$clone" config commit.gpgsign false || exit 1
    printf 'pkgname=%s\npkgver=1.0.0\npkgrel=1\nepoch=2\n' "$PKGNAME" >| "$PKGBUILD" || exit 1
    printf 'pkgbase = %s\n\tpkgver = 1.0.0\n\tpkgrel = 1\n\tepoch = 2\n' "$PKGNAME" >| "$SRCINFO" || exit 1

    if ! dry_run=0 deploy_to_aur "$PKGNAME" >|"$tmp/epoch-commit.out" 2>|"$tmp/epoch-commit.err"; then
        echo "deploy_to_aur failed with epoch in .SRCINFO"
        cat "$tmp/epoch-commit.err"
        exit 1
    fi
    commit_subject=$(git -C "$clone" log -1 --pretty=%s) || exit 1
    if [[ "$commit_subject" != "Update to version 2:1.0.0-1" ]]; then
        echo "expected commit subject 'Update to version 2:1.0.0-1', got '$commit_subject'"
        exit 1
    fi
) || exit 1

# deploy_to_aur must roll back staged/copied changes cleanly on secondary copy,
# git add, and git commit failures, while keeping pre-existing files on unborn HEAD.
(
    real_git=""
    for d in /usr/local/bin /usr/bin /bin; do
        if [[ -x "$d/git" ]]; then
            real_git="$d/git"
            break
        fi
    done
    [[ -x "$real_git" ]] || { echo "real git binary not found"; exit 1; }
    real_cp="$(command -v cp)"

    rb_dir="$tmp/rollback-staging"
    mkdir -p "$rb_dir/bin" "$rb_dir/aurdir" "$rb_dir/repo"
    rb_clone="$rb_dir/repo/demopkg"
    AUR_REPO_DIR="$rb_dir/repo"
    AUR_DIR="$rb_dir/aurdir"
    AUR_AUTO_PUSH="false"
    AUR_COMMIT_MESSAGE="Update to version {version}"
    AUR_GIT_USER_NAME="Tester"
    AUR_GIT_USER_EMAIL="tester@example.com"
    PKGNAME="demopkg"
    PKGVER="2.0.0"

    "$real_git" init -q "$rb_clone" || exit 1
    "$real_git" -C "$rb_clone" config user.name "Tester" || exit 1
    "$real_git" -C "$rb_clone" config user.email "tester@example.com" || exit 1
    "$real_git" -C "$rb_clone" config commit.gpgsign false || exit 1
    printf 'pkgver=1.0.0\ninstall=old.install\n' > "$rb_clone/PKGBUILD"
    printf 'pkgbase = demopkg\n\tpkgver = 1.0.0\n' > "$rb_clone/.SRCINFO"
    printf 'post_install() { :; }\n' > "$rb_clone/old.install"
    "$real_git" -C "$rb_clone" add PKGBUILD .SRCINFO old.install || exit 1
    "$real_git" -C "$rb_clone" commit -q -m "initial" || exit 1

    PKGBUILD="$rb_dir/PKGBUILD"
    SRCINFO="$rb_dir/.SRCINFO"
    printf 'pkgver=2.0.0\ninstall=new.install\n' > "$PKGBUILD"
    printf 'pkgbase = demopkg\n\tpkgver = 2.0.0\n' > "$SRCINFO"
    printf 'post_install() { echo hi; }\n' > "$rb_dir/new.install"

    clean_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$stub" | paste -sd: -)"

    # Case 1: secondary cp (.SRCINFO) failure after cp PKGBUILD succeeds restores PKGBUILD.
    cat > "$rb_dir/bin/cp" << EOF
#!/bin/bash
if [[ "\$1" == "$SRCINFO" ]]; then
    exit 1
fi
exec "$real_cp" "\$@"
EOF
    chmod +x "$rb_dir/bin/cp"
    if PATH="$rb_dir/bin:$clean_path" dry_run=0 deploy_to_aur demopkg >"$rb_dir/cp.out" 2>"$rb_dir/cp.err"; then
        echo "deploy_to_aur succeeded when cp .SRCINFO failed"
        exit 1
    fi
    rm -f "$rb_dir/bin/cp"
    if ! grep -F -q 'pkgver=1.0.0' "$rb_clone/PKGBUILD" || [[ -n "$("$real_git" -C "$rb_clone" status --porcelain)" ]]; then
        echo "failed secondary cp left clone dirty"
        "$real_git" -C "$rb_clone" status --porcelain
        exit 1
    fi

    # Case 2: git add failure after git rm old.install restores old.install and drops new.install.
    cat > "$rb_dir/bin/git" << EOF
#!/bin/bash
args=("\$@")
if [[ "\${args[0]:-}" == "-C" ]]; then
    args=("\${args[@]:2}")
fi
if [[ "\${args[0]:-}" == "add" ]]; then
    exit 1
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$rb_dir/bin/git"
    if PATH="$rb_dir/bin:$clean_path" dry_run=0 deploy_to_aur demopkg >"$rb_dir/add.out" 2>"$rb_dir/add.err"; then
        echo "deploy_to_aur succeeded when git add failed"
        exit 1
    fi
    if [[ -e "$rb_clone/new.install" ]] || [[ ! -f "$rb_clone/old.install" ]] \
        || ! grep -F -q 'pkgver=1.0.0' "$rb_clone/PKGBUILD" \
        || [[ -n "$("$real_git" -C "$rb_clone" status --porcelain)" ]]; then
        echo "failed git add left clone dirty or leaked new.install / dropped old.install"
        "$real_git" -C "$rb_clone" status --porcelain
        exit 1
    fi

    # Case 3: unborn HEAD preserves pre-existing untracked notes.txt while rolling back copied/staged files.
    unborn_clone="$rb_dir/repo/unbornpkg"
    "$real_git" init -q "$unborn_clone" || exit 1
    "$real_git" -C "$unborn_clone" config user.name "Tester" || exit 1
    "$real_git" -C "$unborn_clone" config user.email "tester@example.com" || exit 1
    "$real_git" -C "$unborn_clone" config commit.gpgsign false || exit 1
    printf 'keep-me\n' > "$unborn_clone/notes.txt"
    cat > "$rb_dir/bin/git" << EOF
#!/bin/bash
args=("\$@")
if [[ "\${args[0]:-}" == "-C" ]]; then
    args=("\${args[@]:2}")
fi
if [[ "\${args[0]:-}" == "commit" ]]; then
    exit 1
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$rb_dir/bin/git"
    printf 'pkgver=2.0.0\n' >| "$PKGBUILD"
    printf 'pkgbase = unbornpkg\n\tpkgver = 2.0.0\n' >| "$SRCINFO"
    if PATH="$rb_dir/bin:$clean_path" dry_run=0 deploy_to_aur unbornpkg >"$rb_dir/unborn.out" 2>"$rb_dir/unborn.err"; then
        echo "deploy_to_aur succeeded when git commit failed on unborn HEAD"
        exit 1
    fi
    if [[ ! -f "$unborn_clone/notes.txt" ]] || ! grep -Fxq 'keep-me' "$unborn_clone/notes.txt"; then
        echo "unborn HEAD rollback deleted or altered pre-existing notes.txt"
        exit 1
    fi
    if [[ -e "$unborn_clone/PKGBUILD" || -e "$unborn_clone/.SRCINFO" ]] \
        || [[ -n "$("$real_git" -C "$unborn_clone" ls-files)" ]]; then
        echo "unborn HEAD rollback left copied or staged files behind"
        ls -la "$unborn_clone"
        "$real_git" -C "$unborn_clone" ls-files
        exit 1
    fi
) || exit 1

# aurgen aur-deploy --rollback safely previews and reverts unpushed commits and dirty files
# back to @{u}, leaves pushed history intact, and refuses history rewrites without @{u}.
(
    real_git=""
    for d in /usr/local/bin /usr/bin /bin; do
        if [[ -x "$d/git" ]]; then
            real_git="$d/git"
            break
        fi
    done
    [[ -x "$real_git" ]] || { echo "real git binary not found"; exit 1; }
    clean_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$stub" | paste -sd: -)"

    rbt_dir="$tmp/cli-rollback"
    rbt_remote="$rbt_dir/upstream.git"
    rbt_seed="$rbt_dir/seed"
    rbt_proj="$rbt_dir/proj"
    rbt_repo_dir="$rbt_dir/aur-repos"
    rbt_clone="$rbt_repo_dir/rbtpkg"
    mkdir -p "$rbt_dir" "$rbt_proj/aur" "$rbt_repo_dir"

    "$real_git" init -q --bare "$rbt_remote" || exit 1
    "$real_git" init -q -b master "$rbt_seed" || exit 1
    "$real_git" -C "$rbt_seed" config user.name "Tester" || exit 1
    "$real_git" -C "$rbt_seed" config user.email "tester@example.com" || exit 1
    "$real_git" -C "$rbt_seed" config commit.gpgsign false || exit 1
    printf 'pkgver=1.0.0\n' > "$rbt_seed/PKGBUILD"
    printf 'pkgbase = rbtpkg\n\tpkgver = 1.0.0\n' > "$rbt_seed/.SRCINFO"
    "$real_git" -C "$rbt_seed" add PKGBUILD .SRCINFO || exit 1
    "$real_git" -C "$rbt_seed" commit -q -m "Upstream v1.0.0" || exit 1
    "$real_git" -C "$rbt_seed" remote add origin "$rbt_remote" || exit 1
    "$real_git" -C "$rbt_seed" push -q -u origin master || exit 1
    pushed_sha="$("$real_git" -C "$rbt_seed" rev-parse HEAD)"

    "$real_git" clone -q "$rbt_remote" "$rbt_clone" || exit 1
    "$real_git" -C "$rbt_clone" config user.name "Tester" || exit 1
    "$real_git" -C "$rbt_clone" config user.email "tester@example.com" || exit 1
    "$real_git" -C "$rbt_clone" config commit.gpgsign false || exit 1

    # Add unpushed local commit + dirty tracked modification + untracked file.
    printf 'pkgver=1.1.0\n' > "$rbt_clone/PKGBUILD"
    printf 'pkgbase = rbtpkg\n\tpkgver = 1.1.0\n' > "$rbt_clone/.SRCINFO"
    "$real_git" -C "$rbt_clone" add PKGBUILD .SRCINFO || exit 1
    "$real_git" -C "$rbt_clone" commit -q -m "Unpushed v1.1.0" || exit 1
    unpushed_sha="$("$real_git" -C "$rbt_clone" rev-parse HEAD)"
    printf 'dirty\n' >> "$rbt_clone/PKGBUILD"
    printf 'untracked\n' > "$rbt_clone/stray.txt"

    "$real_git" -C "$rbt_proj" init -q -b main || exit 1
    "$real_git" -C "$rbt_proj" remote add origin "https://github.com/example/rbtpkg.git" || exit 1
    cat > "$rbt_proj/aur/aurgen.install.yaml" << EOF
aur_integration:
  aur_repo_dir: $rbt_repo_dir
  auto_push: false
EOF

    # 1. --dry-run previews planned rollback without mutating HEAD or clone files.
    if ! (cd "$rbt_proj" && PATH="$clean_path" "$ROOT/bin/aurgen" -n --dry-run aur-deploy --rollback) >"$rbt_dir/dry.out" 2>"$rbt_dir/dry.err"; then
        echo "aurgen --dry-run aur-deploy --rollback failed"
        cat "$rbt_dir/dry.err"
        exit 1
    fi
    grep -Fq "Would reset 1 unpushed commit(s)" "$rbt_dir/dry.out" || { echo "dry-run missing unpushed count"; cat "$rbt_dir/dry.out"; exit 1; }
    grep -Fq "Would discard uncommitted changes and untracked files" "$rbt_dir/dry.out" || { echo "dry-run missing dirty summary"; cat "$rbt_dir/dry.out"; exit 1; }
    [[ "$("$real_git" -C "$rbt_clone" rev-parse HEAD)" == "$unpushed_sha" ]] || { echo "dry-run moved HEAD"; exit 1; }
    [[ -f "$rbt_clone/stray.txt" ]] || { echo "dry-run removed untracked file"; exit 1; }

    # 2. Real --rollback rewinds unpushed commit and cleans dirty/untracked state back to pushed_sha.
    if ! (cd "$rbt_proj" && PATH="$clean_path" "$ROOT/bin/aurgen" -n aur-deploy --rollback) >"$rbt_dir/rb.out" 2>"$rbt_dir/rb.err"; then
        echo "aurgen aur-deploy --rollback failed"
        cat "$rbt_dir/rb.err"
        exit 1
    fi
    [[ "$("$real_git" -C "$rbt_clone" rev-parse HEAD)" == "$pushed_sha" ]] || { echo "rollback did not rewind to pushed upstream commit"; exit 1; }
    [[ -z "$("$real_git" -C "$rbt_clone" status --porcelain)" ]] || { echo "rollback left dirty/untracked files"; exit 1; }
    grep -Fxq 'pkgver=1.0.0' "$rbt_clone/PKGBUILD" || { echo "rollback did not restore pushed PKGBUILD"; exit 1; }

    # 3. Clean rollback is idempotent.
    if ! (cd "$rbt_proj" && PATH="$clean_path" "$ROOT/bin/aurgen" -n aur-deploy --rollback) >"$rbt_dir/clean.out" 2>"$rbt_dir/clean.err"; then
        echo "idempotent clean rollback failed"
        cat "$rbt_dir/clean.err"
        exit 1
    fi
    grep -Fq "nothing to roll back" "$rbt_dir/clean.out" || { echo "clean rollback missing idempotent message"; cat "$rbt_dir/clean.out"; exit 1; }

    # 4. Dirty working tree with ahead_count=0 cleans without altering HEAD.
    printf 'dirty-only\n' >> "$rbt_clone/PKGBUILD"
    printf 'tmp\n' > "$rbt_clone/dirty.txt"
    if ! (cd "$rbt_proj" && PATH="$clean_path" "$ROOT/bin/aurgen" -n aur-deploy --rollback) >"$rbt_dir/dirty.out" 2>"$rbt_dir/dirty.err"; then
        echo "dirty-only rollback failed"
        cat "$rbt_dir/dirty.err"
        exit 1
    fi
    [[ "$("$real_git" -C "$rbt_clone" rev-parse HEAD)" == "$pushed_sha" ]] || { echo "dirty-only rollback changed HEAD"; exit 1; }
    [[ -z "$("$real_git" -C "$rbt_clone" status --porcelain)" ]] || { echo "dirty-only rollback left working tree dirty"; exit 1; }

    # 5. Missing upstream tracking branch (@{u}) refuses history rollback clearly and keeps commits/files untouched.
    "$real_git" -C "$rbt_clone" branch --unset-upstream || exit 1
    printf 'pkgver=1.2.0\n' > "$rbt_clone/PKGBUILD"
    "$real_git" -C "$rbt_clone" add PKGBUILD || exit 1
    "$real_git" -C "$rbt_clone" commit -q -m "Local untracked branch commit" || exit 1
    no_up_sha="$("$real_git" -C "$rbt_clone" rev-parse HEAD)"
    if (cd "$rbt_proj" && PATH="$clean_path" "$ROOT/bin/aurgen" -n aur-deploy --rollback) >"$rbt_dir/noup.out" 2>"$rbt_dir/noup.err"; then
        echo "rollback unexpectedly succeeded without upstream tracking branch"
        exit 1
    fi
    grep -Fq "No valid upstream tracking branch" "$rbt_dir/noup.err" || { echo "missing-upstream refusal message missing"; cat "$rbt_dir/noup.err"; exit 1; }
    [[ "$("$real_git" -C "$rbt_clone" rev-parse HEAD)" == "$no_up_sha" ]] || { echo "rollback altered HEAD without @{u}"; exit 1; }

    # 6. Missing AUR clone exits non-zero clearly.
    rm -rf "$rbt_clone"
    if (cd "$rbt_proj" && PATH="$clean_path" "$ROOT/bin/aurgen" -n aur-deploy --rollback) >"$rbt_dir/missing.out" 2>"$rbt_dir/missing.err"; then
        echo "rollback unexpectedly succeeded for missing clone"
        exit 1
    fi
    grep -Fq "AUR repository does not exist" "$rbt_dir/missing.err" || { echo "missing clone message missing"; cat "$rbt_dir/missing.err"; exit 1; }
) || exit 1
