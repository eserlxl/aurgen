#!/bin/bash
# Verify read-only aurgen config detect project inspection behavior.
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aurgen-config-detect.XXXXXX")"
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

# 1. config help documents detect
"$ROOT/bin/aurgen" config help >|"$tmp/help.out" 2>|"$tmp/help.err" || fail_with "config help failed" "$tmp/help.err"
grep -Fq "detect" "$tmp/help.err" || fail_with "config help did not list detect" "$tmp/help.err"

# 2. Empty 0-commit repo: non-mutating (aur/ absent), clean fallback detection
empty_repo="$tmp/empty-repo"
mkdir -p "$empty_repo"
git -C "$empty_repo" init -q -b main
git -C "$empty_repo" remote add origin "https://github.com/example/empty-demo.git"

run_aurgen "$empty_repo" "$tmp/empty.out" "$tmp/empty.err" config detect || \
    fail_with "config detect failed on empty 0-commit repo" "$tmp/empty.out" "$tmp/empty.err"
[[ ! -e "$empty_repo/aur" ]] || fail_with "config detect created aur/ on empty repo"
grep -Fxq "  pkgname: empty-demo" "$tmp/empty.out" || fail_with "missing pkgname on empty repo" "$tmp/empty.out"
grep -Fxq "  version: 1.0.0 (source: fallback)" "$tmp/empty.out" || fail_with "missing fallback version" "$tmp/empty.out"
grep -Fxq "  aur_pkgbuild: absent" "$tmp/empty.out" || fail_with "unexpected aur_pkgbuild on empty repo" "$tmp/empty.out"
grep -Fq "aurgen config init" "$tmp/empty.out" || fail_with "missing config init recommendation" "$tmp/empty.out"
# -n is --no-color; the dry-run hint must name -d, or users run a real build and install.
grep -Fq "'aurgen -d local' to dry-run" "$tmp/empty.out" || fail_with "dry-run hint does not name -d" "$tmp/empty.out"
! grep -Fq "aurgen -n local" "$tmp/empty.out" || fail_with "dry-run hint names -n (--no-color)" "$tmp/empty.out"
[[ ! -s "$trace" ]] || fail_with "config detect invoked network/Arch tool on empty repo" "$trace"

# 3. Copy-based shell repo: detects version, description, license, copy_dirs, depends, optdepends, filters base-devel
script_repo="$tmp/script-repo"
mkdir -p "$script_repo/bin" "$script_repo/lib"
git -C "$script_repo" init -q -b main
git -C "$script_repo" config user.name Tester
git -C "$script_repo" config user.email test@example.com
git -C "$script_repo" config commit.gpgsign false
git -C "$script_repo" remote add origin "https://github.com/example/script-demo.git"

cat >| "$script_repo/bin/script-demo" <<'EOF'
#!/bin/bash
set -euo pipefail
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$0"
fi
jq -n '{}'
EOF
chmod +x "$script_repo/bin/script-demo"
printf 'printf "helper\\n"\n' >| "$script_repo/lib/util.sh"
printf '1.2.3\n' >| "$script_repo/VERSION"
cat >| "$script_repo/LICENSE" <<'EOF'
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The MIT License (MIT)
EOF
cat >| "$script_repo/README.md" <<'EOF'
# script-demo

Fast offline script demo tool.

## Build Dependencies

Required: `make`, `cmake`
EOF
git -C "$script_repo" add bin/script-demo lib/util.sh VERSION LICENSE README.md
git -C "$script_repo" commit -q -m "init"

run_aurgen "$script_repo" "$tmp/script.out" "$tmp/script.err" -n config detect || \
    fail_with "config detect failed on script repo" "$tmp/script.out" "$tmp/script.err"
[[ ! -e "$script_repo/aur" ]] || fail_with "config detect created aur/ on script repo"
grep -Fxq "  version: 1.2.3 (source: version-file)" "$tmp/script.out" || fail_with "wrong version" "$tmp/script.out"
grep -Fxq "  description: Fast offline script demo tool. (source: README.md)" "$tmp/script.out" || fail_with "wrong description" "$tmp/script.out"
grep -Fxq "  license: MIT (file: LICENSE)" "$tmp/script.out" || fail_with "wrong license" "$tmp/script.out"
grep -Fxq "  build_system: none" "$tmp/script.out" || fail_with "wrong build_system" "$tmp/script.out"
grep -Fxq "  install_mode: copy-rules" "$tmp/script.out" || fail_with "wrong install_mode" "$tmp/script.out"
grep -Fxq "  arch: any (script/data)" "$tmp/script.out" || fail_with "wrong arch" "$tmp/script.out"
grep -Eq '^  depends: .*bash.*jq|^  depends: .*jq.*bash' "$tmp/script.out" || fail_with "missing bash/jq runtime depends" "$tmp/script.out"
grep -Fq "optdepends_suggestions: shellcheck (shellcheck)" "$tmp/script.out" || fail_with "missing shellcheck optdepends suggestion" "$tmp/script.out"
grep -Fxq "  makedepends: cmake" "$tmp/script.out" || fail_with "base-devel make should be filtered leaving cmake" "$tmp/script.out"
grep -Fq "bin -> usr/bin (755), lib -> usr/lib/\$pkgname (644)" "$tmp/script.out" || fail_with "missing matching copy_dirs" "$tmp/script.out"
[[ ! -s "$trace" ]] || fail_with "config detect invoked network/Arch tool on script repo" "$trace"

# 4. Compiled build-system repo (Rust)
rust_repo="$tmp/rust-repo"
mkdir -p "$rust_repo/src"
git -C "$rust_repo" init -q -b main
git -C "$rust_repo" config user.name Tester
git -C "$rust_repo" config user.email test@example.com
git -C "$rust_repo" config commit.gpgsign false
git -C "$rust_repo" remote add origin "https://github.com/example/rust-demo.git"
cat >| "$rust_repo/Cargo.toml" <<'EOF'
[package]
name = "rust-demo"
version = "0.4.0"
description = "Small Rust CLI helper"
EOF
printf 'fn main() {}\n' >| "$rust_repo/src/main.rs"
git -C "$rust_repo" add Cargo.toml src/main.rs
git -C "$rust_repo" commit -q -m "rust init"

run_aurgen "$rust_repo" "$tmp/rust.out" "$tmp/rust.err" config detect || \
    fail_with "config detect failed on rust repo" "$tmp/rust.out" "$tmp/rust.err"
grep -Fxq "  build_system: rust" "$tmp/rust.out" || fail_with "expected rust build_system" "$tmp/rust.out"
grep -Fxq "  install_mode: build-system" "$tmp/rust.out" || fail_with "expected build-system install_mode" "$tmp/rust.out"
grep -Fxq "  arch: x86_64 aarch64 (compiled)" "$tmp/rust.out" || fail_with "expected x86_64 aarch64 arch" "$tmp/rust.out"
grep -Fxq "  description: Small Rust CLI helper (source: Cargo.toml)" "$tmp/rust.out" || fail_with "expected Cargo.toml description" "$tmp/rust.out"
grep -Fxq "  check: cargo test --release" "$tmp/rust.out" || fail_with "expected cargo test check command" "$tmp/rust.out"
grep -Fxq "  makedepends: rust" "$tmp/rust.out" || fail_with "expected rust makedepends" "$tmp/rust.out"
grep -Fxq "  copy_dirs: none" "$tmp/rust.out" || fail_with "expected copy_dirs: none" "$tmp/rust.out"

# 5. Unimported aur/PKGBUILD notice + non-modification
mkdir -p "$script_repo/aur"
cat >| "$script_repo/aur/PKGBUILD" <<'EOF'
pkgname=custom-script-demo
pkgver=1.2.3
pkgrel=1
EOF
pkg_before="$(cksum "$script_repo/aur/PKGBUILD")"
run_aurgen "$script_repo" "$tmp/import-hint.out" "$tmp/import-hint.err" config detect || \
    fail_with "config detect failed with aur/PKGBUILD" "$tmp/import-hint.out" "$tmp/import-hint.err"
pkg_after="$(cksum "$script_repo/aur/PKGBUILD")"
[[ "$pkg_before" == "$pkg_after" ]] || fail_with "config detect modified aur/PKGBUILD"
[[ ! -e "$script_repo/aur/aurgen.install.yaml" ]] || fail_with "config detect created aurgen.install.yaml"
grep -Fxq "  aur_pkgbuild: present (unimported)" "$tmp/import-hint.out" || fail_with "missing unimported PKGBUILD status" "$tmp/import-hint.out"
grep -Fq "aurgen config import" "$tmp/import-hint.out" || fail_with "missing config import guidance" "$tmp/import-hint.out"

# 6. -c missing.yaml fails; -c custom.yaml reflects configured overrides; extra arg fails
if run_aurgen "$script_repo" "$tmp/miss.out" "$tmp/miss.err" -c custom/missing.yaml config detect; then
    fail_with "config detect succeeded on missing -c file" "$tmp/miss.out" "$tmp/miss.err"
fi
grep -Fq "Configuration file not found" "$tmp/miss.err" || fail_with "missing config error mismatch" "$tmp/miss.err"

mkdir -p "$script_repo/custom"
cat >| "$script_repo/custom/override.yaml" <<'EOF'
package:
  name: custom-demo
  description: Override description
  arch: [x86_64]
EOF
run_aurgen "$script_repo" "$tmp/custom.out" "$tmp/custom.err" -c custom/override.yaml config detect || \
    fail_with "config detect failed with custom -c file" "$tmp/custom.out" "$tmp/custom.err"
grep -Fxq "  pkgname: custom-demo" "$tmp/custom.out" || fail_with "-c override pkgname missing" "$tmp/custom.out"
grep -Fxq "  arch: x86_64 (configured)" "$tmp/custom.out" || fail_with "-c override arch missing" "$tmp/custom.out"
grep -Fq "; configured: Override description" "$tmp/custom.out" || fail_with "-c override description missing" "$tmp/custom.out"

if run_aurgen "$script_repo" "$tmp/extra.out" "$tmp/extra.err" config detect unexpected; then
    fail_with "config detect accepted unexpected positional argument" "$tmp/extra.out" "$tmp/extra.err"
fi

# 7. --json config detect emits valid structured JSON without mutating repo and keeps RELEASE=0 banners on stderr
(
    cd "$empty_repo" || exit 1
    RELEASE=0 PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json config detect
) >|"$tmp/json-empty.out" 2>|"$tmp/json-empty.err" || fail_with "--json config detect failed on empty repo" "$tmp/json-empty.out" "$tmp/json-empty.err"
[[ ! -e "$empty_repo/aur" ]] || fail_with "--json config detect created aur/ on empty repo"
grep -Fq 'DEVELOPMENT mode' "$tmp/json-empty.err" || fail_with "--json config detect leaked/omitted dev info on stderr" "$tmp/json-empty.err"
python3 - "$tmp/json-empty.out" <<'PY' || fail_with "--json config detect empty output invalid" "$tmp/json-empty.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["pkgname"] == "empty-demo", d
assert d["config"]["exists"] is False, d
assert d["version"] == {"value": "1.0.0", "source": "fallback"}, d
assert d["aur_pkgbuild"] == "absent", d
assert d["copy_rules"] == [], d
PY

(
    cd "$script_repo" || exit 1
    RELEASE=0 PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json config detect
) >|"$tmp/json-script.out" 2>|"$tmp/json-script.err" || fail_with "--json config detect failed on script repo" "$tmp/json-script.out" "$tmp/json-script.err"
python3 - "$tmp/json-script.out" <<'PY' || fail_with "--json config detect script output invalid" "$tmp/json-script.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["pkgname"] == "script-demo", d
assert d["config"]["exists"] is False, d
assert d["aur_pkgbuild"] == "present (unimported)", d
assert d["description"]["configured"] is None, d
assert d["license"]["value"] == "MIT", d
assert d["license"]["found"] is True, d
assert d["build_system"] == "none", d
assert d["install_mode"] == "copy-rules", d
assert d["arch"] == {"value": "any", "source": "script/data"}, d
assert "bash" in d["depends"]["packages"] and "jq" in d["depends"]["packages"], d
assert any("shellcheck" in s for s in d["optdepends_suggestions"]), d
assert d["makedepends"]["packages"] == ["cmake"], d
srcs = {r["source"]: r for r in d["copy_rules"]}
assert srcs["bin"]["permissions"] == "755" and srcs["bin"]["destination"] == "usr/bin", srcs
assert srcs["lib"]["permissions"] == "644", srcs
PY

# A !name in package.makedepends drops that detected dependency from detect too, and
# a !name that matches nothing detected is reported.
mkdir -p "$script_repo/custom"
printf 'package:\n  makedepends: ["!cmake", "!nosuch"]\n' >| "$script_repo/custom/md-drop.yaml"
run_aurgen "$script_repo" "$tmp/md-drop.out" "$tmp/md-drop.err" -n -c custom/md-drop.yaml config detect || \
    fail_with "config detect failed with makedepends drops" "$tmp/md-drop.out" "$tmp/md-drop.err"
if grep -Eq '^  makedepends: ([^;]* )?cmake( |;|$)' "$tmp/md-drop.out"; then
    fail_with "config detect still lists a dropped makedepend" "$tmp/md-drop.out"
fi
grep -Fq "package.makedepends !nosuch matches no detected build dependency" "$tmp/md-drop.out" || \
    fail_with "config detect did not report an unmatched !name" "$tmp/md-drop.out" "$tmp/md-drop.err"
if grep -Fq "!cmake matches no" "$tmp/md-drop.out"; then
    fail_with "config detect reported a !name that matched" "$tmp/md-drop.out"
fi
(
    cd "$script_repo" || exit 1
    RELEASE=0 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -c custom/md-drop.yaml --json config detect
) >|"$tmp/md-drop-json.out" 2>|"$tmp/md-drop-json.err" || fail_with "--json config detect failed with makedepends drops" "$tmp/md-drop-json.out" "$tmp/md-drop-json.err"
python3 - "$tmp/md-drop-json.out" <<'PY' || fail_with "--json config detect kept a dropped makedepend" "$tmp/md-drop-json.out"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["makedepends"]["packages"] == [], d
PY
rm -f "$script_repo/custom/md-drop.yaml"

(
    cd "$script_repo" || exit 1
    RELEASE=0 PATH="$stub:$PATH" "$ROOT/bin/aurgen" -c custom/override.yaml --json config detect
) >|"$tmp/json-override.out" 2>|"$tmp/json-override.err" || fail_with "--json config detect failed with -c override" "$tmp/json-override.out" "$tmp/json-override.err"
python3 - "$tmp/json-override.out" <<'PY' || fail_with "--json config detect override output invalid" "$tmp/json-override.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["pkgname"] == "custom-demo", d
assert d["config"]["exists"] is True, d
assert d["aur_pkgbuild"] == "present (configured)", d
assert d["description"]["configured"] == "Override description", d
assert d["arch"] == {"value": "x86_64", "source": "configured"}, d
assert d["copy_rules"] == [], d
PY

if run_aurgen "$script_repo" "$tmp/json-extra.out" "$tmp/json-extra.err" --json config detect unexpected; then
    fail_with "--json config detect accepted unexpected positional argument" "$tmp/json-extra.out" "$tmp/json-extra.err"
fi

# 8. Compiled C project: assert both arches in text and --json output
c_repo="$tmp/c-repo"
mkdir -p "$c_repo"
git -C "$c_repo" init -q -b main
git -C "$c_repo" config user.name Tester
git -C "$c_repo" config user.email test@example.com
git -C "$c_repo" config commit.gpgsign false
git -C "$c_repo" remote add origin "https://github.com/example/c-demo.git"
cat >| "$c_repo/Makefile" <<'EOF'
all:
	cc -o c-demo main.c
EOF
cat >| "$c_repo/main.c" <<'EOF'
int main(void) { return 0; }
EOF
git -C "$c_repo" add Makefile main.c
git -C "$c_repo" commit -q -m "c init"

run_aurgen "$c_repo" "$tmp/c.out" "$tmp/c.err" config detect || \
    fail_with "config detect failed on C repo" "$tmp/c.out" "$tmp/c.err"
grep -Fxq "  arch: x86_64 aarch64 (compiled)" "$tmp/c.out" || fail_with "expected x86_64 aarch64 arch in C text output" "$tmp/c.out"
[[ ! -s "$trace" ]] || fail_with "config detect invoked network/Arch tool on C repo" "$trace"

(
    cd "$c_repo" || exit 1
    RELEASE=0 PATH="$stub:$PATH" "$ROOT/bin/aurgen" --json config detect
) >|"$tmp/json-c.out" 2>|"$tmp/json-c.err" || fail_with "--json config detect failed on C repo" "$tmp/json-c.out" "$tmp/json-c.err"
python3 - "$tmp/json-c.out" <<'PY' || fail_with "--json config detect C output invalid" "$tmp/json-c.out"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
assert d["arch"] == {"value": "x86_64 aarch64", "source": "compiled"}, d
PY

echo "PASS test-config-detect.sh"
