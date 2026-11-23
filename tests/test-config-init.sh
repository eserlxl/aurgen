#!/bin/bash
# Verify project-tailored aurgen config init starter configuration behavior.
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-config-init.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
export GNUPGHOME="$tmp/gnupg"
export AURGEN_LOG="$tmp/aurgen.log"
export AURGEN_ERROR_LOG="$tmp/aurgen-error.log"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
mkdir -m 700 "$GNUPGHOME"

unset GIT_CONFIG GIT_CONFIG_SYSTEM GIT_CONFIG_PARAMETERS SSH_AUTH_SOCK SSH_AGENT_PID GPG_TTY GPG_AGENT_INFO \
      RELEASE AURGEN_LIB_DIR AURGEN_MODE AURGEN_PUSH_TAG AURGEN_BUMP_PKGREL AURGEN_KEEP_PREV \
      AURGEN_CHROOT_DIR AURGEN_NOCHECK AURGEN_MAKEPKG_FLAGS AURGEN_CONFIG_FILE \
      AURGEN_CONFIG_ACTION AURGEN_JSON AURGEN_STATUS_DIFF AURGEN_TEST_DESC AURGEN_TEST_GH_DESC \
      GH_USER GH_REPO REPO_NAME PKGNAME GPG_KEY_ID DESC MAXDEPTH \
      ALLOW_DIRTY DRY_RUN NO_WAIT ASCII_ARMOR_DEFAULT SOURCE_DATE_EPOCH nocheck build_only \
      OUT_DIR AUR_DIR PROJECT_ROOT PKGBUILD PKGBUILD0 SRCINFO AUR_PREVIEW_SRCINFO \
      PKG_NAME PKG_DESCRIPTION PKG_URL PKG_EPOCH PKG_GPG_KEY PKG_INSTALL PKG_CHECK \
      PKG_SOURCE PKG_DEPENDS PKG_OPTDEPENDS PKG_MAKEDEPENDS PKG_CHECKDEPENDS PKG_CONFLICTS \
      PKG_PROVIDES PKG_REPLACES PKG_OPTIONS PKG_BACKUP PKG_ARCH PKG_LICENSE \
      PKG_INSTALL_VARS PKG_POST_PACKAGE PKG_KEEP COLOR NO_COLOR CI DEBUG_LEVEL

export NO_COLOR=1

stub="$tmp/stub-bin"
trace="$tmp/forbidden.log"
mkdir -p "$stub"
: >| "$trace"
for tool in gh pacman curl makepkg; do
    cat >| "$stub/$tool" <<EOF
#!/bin/bash
printf 'forbidden %s %s\n' "$tool" "\$*" >> "$trace"
exit 99
EOF
    chmod +x "$stub/$tool"
done

run_aurgen() {
    local repo="$1" out="$2" err="$3"
    shift 3
    (
        cd "$repo" || exit 1
        PATH="$stub:$PATH" "$ROOT/bin/aurgen" "$@"
    ) >|"$out" 2>|"$err"
}

fail_with() {
    echo "$1" >&2
    shift
    local f
    for f in "$@"; do
        [[ -e "$f" ]] || continue
        echo "--- $f ---" >&2
        cat "$f" >&2
    done
    exit 1
}

# 1. config help documents init
"$ROOT/bin/aurgen" config help >|"$tmp/help.out" 2>|"$tmp/help.err" || fail_with "config help failed" "$tmp/help.err"
grep -Fq "  init " "$tmp/help.err" || fail_with "config help did not list init" "$tmp/help.err"

# 2. Copy-based repo: writes package.name + only existing copy sections; validates; refuses overwrite
copy_repo="$tmp/copy-repo"
mkdir -p "$copy_repo/bin"
git -C "$copy_repo" init -q -b main
git -C "$copy_repo" config user.name Tester
git -C "$copy_repo" config user.email test@example.com
git -C "$copy_repo" config commit.gpgsign false
git -C "$copy_repo" remote add origin "https://github.com/example/script-init.git"
printf '#!/bin/bash\necho ok\n' >| "$copy_repo/bin/script-init"
chmod +x "$copy_repo/bin/script-init"
printf '2.0.0\n' >| "$copy_repo/VERSION"
printf '# script-init\n\nTailored init demo.\n' >| "$copy_repo/README.md"
printf 'The MIT License (MIT)\n' >| "$copy_repo/LICENSE"
git -C "$copy_repo" add bin/script-init VERSION README.md LICENSE
git -C "$copy_repo" commit -q -m "init"

run_aurgen "$copy_repo" "$tmp/copy-init.out" "$tmp/copy-init.err" -n config init || \
    fail_with "config init failed on copy repo" "$tmp/copy-init.out" "$tmp/copy-init.err"
cfg="$copy_repo/aur/aurgen.install.yaml"
[[ -f "$cfg" ]] || fail_with "config init did not create aur/aurgen.install.yaml"
grep -Fq '#   auto_push: true' "$cfg" || fail_with "config init hint does not show the auto_push default (true)" "$cfg"
grep -Fxq "  name: script-init" "$cfg" || fail_with "missing package.name in generated config" "$cfg"
grep -Fxq "executables:" "$cfg" || fail_with "missing active executables copy rule for existing bin/" "$cfg"
if grep -Eq '^(libraries|config|shared_data|headers|local_data|variable_data|optional_data):' "$cfg"; then
    fail_with "config init enabled non-existent copy directories" "$cfg"
fi

run_aurgen "$copy_repo" "$tmp/copy-val.out" "$tmp/copy-val.err" config validate || \
    fail_with "config validate rejected config init output" "$tmp/copy-val.out" "$tmp/copy-val.err"
run_aurgen "$copy_repo" "$tmp/copy-eff.out" "$tmp/copy-eff.err" config show effective || \
    fail_with "config show effective failed on config init output" "$tmp/copy-eff.out" "$tmp/copy-eff.err"
grep -Fxq "name: script-init" "$tmp/copy-eff.out" || fail_with "show effective missing package.name" "$tmp/copy-eff.out"

before_sum="$(cksum "$cfg")"
if run_aurgen "$copy_repo" "$tmp/copy-dup.out" "$tmp/copy-dup.err" config init; then
    fail_with "config init overwrote existing config" "$tmp/copy-dup.out" "$tmp/copy-dup.err"
fi
after_sum="$(cksum "$cfg")"
[[ "$before_sum" == "$after_sum" ]] || fail_with "existing config modified when config init failed"
[[ ! -s "$trace" ]] || fail_with "config init invoked network/Arch tool" "$trace"

# 3. Build-system repo (Rust) + custom -c path: comments optional copy sections, leaves default path absent
rust_repo="$tmp/rust-repo"
mkdir -p "$rust_repo/src"
git -C "$rust_repo" init -q -b main
git -C "$rust_repo" config user.name Tester
git -C "$rust_repo" config user.email test@example.com
git -C "$rust_repo" config commit.gpgsign false
git -C "$rust_repo" remote add origin "https://github.com/example/rust-init.git"
cat >| "$rust_repo/Cargo.toml" <<'EOF'
[package]
name = "rust-init"
version = "0.1.0"
description = "Rust init sample"
EOF
printf 'fn main() {}\n' >| "$rust_repo/src/main.rs"
git -C "$rust_repo" add Cargo.toml src/main.rs
git -C "$rust_repo" commit -q -m "rust init"

run_aurgen "$rust_repo" "$tmp/rust-init.out" "$tmp/rust-init.err" -c custom/init.yaml config init || \
    fail_with "config init with -c failed on rust repo" "$tmp/rust-init.out" "$tmp/rust-init.err"
custom_cfg="$rust_repo/custom/init.yaml"
[[ -f "$custom_cfg" ]] || fail_with "custom -c init file not created"
[[ ! -e "$rust_repo/aur/aurgen.install.yaml" ]] || fail_with "custom -c init unexpectedly wrote default config"
grep -Fxq "  name: rust-init" "$custom_cfg" || fail_with "custom init missing package.name" "$custom_cfg"
grep -Fq "Build system 'rust' handles installation" "$custom_cfg" || fail_with "custom init missing build system comment" "$custom_cfg"
if grep -Eq '^executables:' "$custom_cfg"; then
    fail_with "build-system init left copy sections uncommented" "$custom_cfg"
fi
run_aurgen "$rust_repo" "$tmp/rust-val.out" "$tmp/rust-val.err" -c custom/init.yaml config validate || \
    fail_with "config validate failed on custom init file" "$tmp/rust-val.out" "$tmp/rust-val.err"

# 4. Existing aur/PKGBUILD is imported cleanly by default config init without modifying aur/PKGBUILD
import_repo="$tmp/import-repo"
mkdir -p "$import_repo"
cp -a "$ROOT/tests/fixtures/cleaner/." "$import_repo/"
rm -f "$import_repo/aur/aurgen.install.yaml"
cp "$import_repo/hand/PKGBUILD" "$import_repo/aur/PKGBUILD"
git -C "$import_repo" init -q -b main
git -C "$import_repo" config user.name Tester
git -C "$import_repo" config user.email test@example.com
git -C "$import_repo" config commit.gpgsign false
git -C "$import_repo" remote add origin "https://github.com/example/linux-cleaner.git"
git -C "$import_repo" add -A
git -C "$import_repo" commit -q -m "with hand pkgbuild"

pkg_before="$(cksum "$import_repo/aur/PKGBUILD")"
run_aurgen "$import_repo" "$tmp/imp-init.out" "$tmp/imp-init.err" config init || \
    fail_with "config init failed when importing aur/PKGBUILD" "$tmp/imp-init.out" "$tmp/imp-init.err"
pkg_after="$(cksum "$import_repo/aur/PKGBUILD")"
[[ "$pkg_before" == "$pkg_after" ]] || fail_with "config init altered existing aur/PKGBUILD"
[[ -f "$import_repo/aur/aurgen.install.yaml" ]] || fail_with "config init did not create imported config"
grep -Eq "^  name: '?linux-cleaner'?\$" "$import_repo/aur/aurgen.install.yaml" || \
    fail_with "imported config missing pkgname from aur/PKGBUILD" "$import_repo/aur/aurgen.install.yaml"
run_aurgen "$import_repo" "$tmp/imp-val.out" "$tmp/imp-val.err" config validate || \
    fail_with "config validate failed after config init import" "$tmp/imp-val.out" "$tmp/imp-val.err"

# 4b. Relative -c aur/aurgen.install.yaml config init still imports aur/PKGBUILD
rel_import_repo="$tmp/rel-import-repo"
mkdir -p "$rel_import_repo"
cp -a "$ROOT/tests/fixtures/cleaner/." "$rel_import_repo/"
rm -f "$rel_import_repo/aur/aurgen.install.yaml"
cp "$rel_import_repo/hand/PKGBUILD" "$rel_import_repo/aur/PKGBUILD"
git -C "$rel_import_repo" init -q -b main
git -C "$rel_import_repo" config user.name Tester
git -C "$rel_import_repo" config user.email test@example.com
git -C "$rel_import_repo" config commit.gpgsign false
git -C "$rel_import_repo" remote add origin "https://github.com/example/linux-cleaner.git"
git -C "$rel_import_repo" add -A
git -C "$rel_import_repo" commit -q -m "with hand pkgbuild"

run_aurgen "$rel_import_repo" "$tmp/rel-imp.out" "$tmp/rel-imp.err" -c aur/aurgen.install.yaml config init || \
    fail_with "config init with relative default -c failed to import aur/PKGBUILD" "$tmp/rel-imp.out" "$tmp/rel-imp.err"
grep -Eq "^  name: '?linux-cleaner'?\$" "$rel_import_repo/aur/aurgen.install.yaml" || \
    fail_with "relative -c config init did not import package.name from aur/PKGBUILD" "$rel_import_repo/aur/aurgen.install.yaml"

# 5. Extra positional arg and read-only parent directory fail cleanly
if run_aurgen "$rust_repo" "$tmp/extra.out" "$tmp/extra.err" config init unexpected; then
    fail_with "config init accepted unexpected argument" "$tmp/extra.out" "$tmp/extra.err"
fi

ro_dir="$tmp/ro-parent"
mkdir -p "$ro_dir/aur"
git -C "$ro_dir" init -q -b main
git -C "$ro_dir" remote add origin "https://github.com/example/ro-init.git"
chmod 0555 "$ro_dir/aur"
if run_aurgen "$ro_dir" "$tmp/ro.out" "$tmp/ro.err" config init; then
    chmod 0755 "$ro_dir/aur"
    fail_with "config init succeeded in read-only aur/" "$tmp/ro.out" "$tmp/ro.err"
fi
chmod 0755 "$ro_dir/aur"
# It must fail on the write into aur/, not for an unrelated reason.
if ! grep -Fq "Cannot write $ro_dir/aur/.gitignore" "$tmp/ro.err"; then
    fail_with "config init in a read-only aur/ failed for another reason" "$tmp/ro.out" "$tmp/ro.err"
fi
if grep -Fq "[FATAL]" "$tmp/ro.err"; then
    fail_with "config init in a read-only aur/ died through the ERR trap" "$tmp/ro.err"
fi

# No section may call a network or Arch tool; the check after section 2 covers only 1-2.
[[ ! -s "$trace" ]] || fail_with "config init invoked network/Arch tool" "$trace"

echo "PASS test-config-init.sh"
