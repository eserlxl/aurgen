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
    rev-list)
        printf '%s\n' "${GIT_REV_LIST_COUNT:-0}"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$stub/git"

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
  backup_existing: false
  validate_before_push: false
EOF

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/config.sh
source "$ROOT/lib/config.sh"
# shellcheck source=../lib/modes/aur-deploy.sh
source "$ROOT/lib/modes/aur-deploy.sh"

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
  backup_existing: false
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
if aur_srcinfo_checksums_pinned "$pin" 2>/dev/null; then
    echo "SKIP checksum on the downloaded signature was accepted"
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
if ! init_aur_repo "$PKGNAME" >|"$tmp/ssh-missing.out" 2>|"$tmp/ssh-missing.err"; then
    echo "init with a missing ssh_key failed"
    cat "$tmp/ssh-missing.err"
    exit 1
fi
assert_no_identity "missing ssh_key on init"
if ! grep -F -q "[aur-integration] ssh_key $tmp/no-such-key does not exist; using the ssh configuration" "$tmp/ssh-missing.out"; then
    echo "missing ssh_key did not warn"
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

touch "$tmp/aur_key"
AUR_SSH_KEY="$tmp/aur_key"
expected_ssh="core.sshCommand=ssh -i $(printf %q "$AUR_SSH_KEY")"
: >| "$GIT_ARGV_LOG"
if ! init_aur_repo "$PKGNAME" >|"$tmp/ssh-key.out" 2>|"$tmp/ssh-key.err"; then
    echo "init with an existing ssh_key failed"
    cat "$tmp/ssh-key.err"
    exit 1
fi
if ! grep -F -q -- "$expected_ssh" "$GIT_ARGV_LOG"; then
    echo "existing ssh_key was not passed to init"
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
