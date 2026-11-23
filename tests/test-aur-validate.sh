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
cat > "$stub/makepkg" << 'EOF'
#!/bin/bash
printf '%s\n' 'pkgbase = demopkg' 'pkgver = 1.0.0'
EOF
chmod +x "$stub/makepkg"

export PATH="$stub:$PATH"
export color_enabled=0
export AURGEN_ERROR_LOG="$tmp/err.log"
: > "$AURGEN_ERROR_LOG"

# shellcheck source=../lib/helpers.sh
source "$ROOT/lib/helpers.sh"
# shellcheck source=../lib/aur-integration.sh
source "$ROOT/lib/aur-integration.sh"

log() { :; }

export AUR_REPO_DIR="$tmp/aur"
repo="$AUR_REPO_DIR/demopkg"
mkdir -p "$repo"
printf 'pkgname=demopkg\n' > "$repo/PKGBUILD"
printf '%s\n' 'pkgbase = demopkg' 'pkgver = 1.0.0' > "$repo/.SRCINFO"

if ! validate_aur_repo demopkg; then
    echo "matching .SRCINFO was rejected"
    exit 1
fi

# namcap's errors stop the push; its warnings do not. A function is the stub, so the
# host's namcap never decides these cases.
namcap() { printf 'PKGBUILD (demopkg) E: Missing makedepends\n'; return 1; }
if validate_aur_repo demopkg >|"$tmp/out" 2>|"$tmp/err"; then
    echo "a namcap error was accepted"
    exit 1
fi
grep -F -q "namcap reported errors" "$tmp/err" || { echo "a namcap error was not reported"; cat "$tmp/err"; exit 1; }
namcap() { printf 'PKGBUILD (demopkg) W: Reference to x86_64 should be changed\n'; }
if ! validate_aur_repo demopkg >|"$tmp/out" 2>|"$tmp/err"; then
    echo "a namcap warning stopped validation"
    cat "$tmp/err"
    exit 1
fi
unset -f namcap

printf 'pkgname=(\n' >| "$repo/PKGBUILD"
if validate_aur_repo demopkg >|"$tmp/out" 2>|"$tmp/err"; then
    echo "malformed PKGBUILD was accepted"
    exit 1
fi
if ! grep -F -q "[aur-integration] PKGBUILD syntax validation failed" "$tmp/err"; then
    echo "malformed PKGBUILD did not report syntax validation failure"
    cat "$tmp/err"
    exit 1
fi
printf 'pkgname=demopkg\n' >| "$repo/PKGBUILD"

printf '%s\n' 'pkgbase = demopkg' 'pkgver = 9.9.9' > "$repo/.SRCINFO"
if validate_aur_repo demopkg >"$tmp/out" 2>"$tmp/err"; then
    echo "stale .SRCINFO was accepted"
    exit 1
fi
if ! grep -F -q "[aur-integration] .SRCINFO is out of date; run (cd $(printf '%q' "$repo") && makepkg --printsrcinfo >| .SRCINFO)" "$tmp/err"; then
    echo "stale .SRCINFO did not report it was out of date"
    cat "$tmp/err"
    exit 1
fi

# aur_srcinfo_checksums_pinned must reject SKIP on both generic and architecture-specific
# HTTP/HTTPS/FTP downloads while allowing pinned hashes, detached signatures, and git+ VCS URLs.
cat >| "$tmp/arch-skip.srcinfo" <<'EOF'
pkgbase = demopkg
	pkgver = 1.0.0
	source_x86_64 = https://example.com/demopkg-1.0.0-x86_64.tar.gz
	source_x86_64 = https://example.com/demopkg-1.0.0-x86_64.tar.gz.sig
	b2sums_x86_64 = SKIP
	b2sums_x86_64 = SKIP

pkgname = demopkg
EOF
if aur_srcinfo_checksums_pinned "$tmp/arch-skip.srcinfo" 2>"$tmp/arch-skip.err"; then
    echo "unpinned source_x86_64 download with b2sums_x86_64 = SKIP was accepted"
    exit 1
fi
if ! grep -F -q "b2sums_x86_64 is SKIP for downloaded source https://example.com/demopkg-1.0.0-x86_64.tar.gz" "$tmp/arch-skip.err"; then
    echo "b2sums_x86_64 error message did not name the offending key and source"
    cat "$tmp/arch-skip.err"
    exit 1
fi

cat >| "$tmp/arch-pinned.srcinfo" <<'EOF'
pkgbase = demopkg
	pkgver = 1.0.0
	source = git+https://github.com/example/demopkg.git
	b2sums = SKIP
	source_x86_64 = https://example.com/demopkg-1.0.0-x86_64.tar.gz
	source_x86_64 = demopkg-1.0.0-x86_64.tar.gz.asc::https://example.com/demopkg-1.0.0-x86_64.tar.gz.asc
	b2sums_x86_64 = 0123456789abcdef0123456789abcdef
	b2sums_x86_64 = SKIP
	source_aarch64 = https://example.com/demopkg-1.0.0-aarch64.tar.gz
	sha256sums_aarch64 = fedcba9876543210fedcba9876543210

pkgname = demopkg
EOF
if ! aur_srcinfo_checksums_pinned "$tmp/arch-pinned.srcinfo" 2>"$tmp/arch-pinned.err"; then
    echo "valid pinned multi-arch + VCS + signature .SRCINFO was rejected"
    cat "$tmp/arch-pinned.err"
    exit 1
fi

cat >| "$tmp/aarch64-skip.srcinfo" <<'EOF'
pkgbase = demopkg
	pkgver = 1.0.0
	source_x86_64 = https://example.com/demopkg-1.0.0-x86_64.tar.gz
	sha256sums_x86_64 = 0123456789abcdef
	source_aarch64 = ftp://example.com/demopkg-1.0.0-aarch64.tar.gz
	sha256sums_aarch64 = SKIP

pkgname = demopkg
EOF
if aur_srcinfo_checksums_pinned "$tmp/aarch64-skip.srcinfo" 2>"$tmp/aarch64.err"; then
    echo "unpinned ftp source_aarch64 with sha256sums_aarch64 = SKIP was accepted"
    exit 1
fi
if ! grep -F -q "sha256sums_aarch64 is SKIP for downloaded source ftp://example.com/demopkg-1.0.0-aarch64.tar.gz" "$tmp/aarch64.err"; then
    echo "sha256sums_aarch64 refusal did not name the key and source"
    cat "$tmp/aarch64.err"
    exit 1
fi

# Turkish LC_ALL must still match source_i686 and b2sums_i686 = SKIP in .SRCINFO.
if locale -a 2>/dev/null | LC_ALL=C grep -qix 'tr_TR\.utf-\?8'; then
    cat > "$tmp/i686-skip.srcinfo" <<'EOF'
pkgbase = demopkg
	pkgver = 1.0.0
	pkgrel = 1
	source_i686 = https://example.com/demopkg-1.0.0-i686.tar.gz
	b2sums_i686 = SKIP

pkgname = demopkg
EOF
    if LC_ALL=tr_TR.UTF-8 aur_srcinfo_checksums_pinned "$tmp/i686-skip.srcinfo" 2>"$tmp/i686.err"; then
        echo "Turkish LC_ALL accepted unpinned source_i686 with b2sums_i686 = SKIP"
        exit 1
    fi
    if ! LC_ALL=C grep -F -q "b2sums_i686 is SKIP for downloaded source https://example.com/demopkg-1.0.0-i686.tar.gz" "$tmp/i686.err"; then
        echo "b2sums_i686 refusal did not name the key and source under Turkish LC_ALL"
        cat "$tmp/i686.err"
        exit 1
    fi
fi

# validate_aur_repo must also reject missing pkgbase/pkgname, unpinned download SKIP sums,
# and missing or syntactically invalid install= scripts while keeping git-less dirs valid.
(
    val_stub="$tmp/val-stub"
    mkdir -p "$val_stub"
    PATH="$val_stub:$PATH"
    vrepo="$tmp/aur/valpkg"
    mkdir -p "$vrepo"

    cat > "$val_stub/makepkg" << 'EOF'
#!/bin/bash
cat "$MOCK_SRCINFO"
EOF
    chmod +x "$val_stub/makepkg"

    printf 'pkgname=valpkg\n' > "$vrepo/PKGBUILD"
    printf 'pkgver = 1.0.0\n' > "$vrepo/.SRCINFO"
    export MOCK_SRCINFO="$vrepo/.SRCINFO"
    if validate_aur_repo valpkg >"$tmp/val.out" 2>"$tmp/val.err"; then
        echo "validate_aur_repo accepted .SRCINFO missing pkgbase and pkgname"
        exit 1
    fi
    if ! grep -F -q "[aur-integration] .SRCINFO is missing pkgbase/pkgname" "$tmp/val.err"; then
        echo "validate_aur_repo did not report missing pkgbase/pkgname"
        cat "$tmp/val.err"
        exit 1
    fi

    cat > "$vrepo/.SRCINFO" << 'EOF'
pkgbase = valpkg
	pkgver = 1.0.0
	source = https://example.com/valpkg-1.0.0.tar.gz
	b2sums = SKIP

pkgname = valpkg
EOF
    if validate_aur_repo valpkg >"$tmp/val.out" 2>"$tmp/val.err"; then
        echo "validate_aur_repo accepted unpinned SKIP checksum"
        exit 1
    fi
    if ! grep -F -q "b2sums is SKIP for downloaded source https://example.com/valpkg-1.0.0.tar.gz" "$tmp/val.err"; then
        echo "validate_aur_repo did not report unpinned SKIP checksum"
        cat "$tmp/val.err"
        exit 1
    fi

    cat > "$vrepo/.SRCINFO" << 'EOF'
pkgbase = valpkg
	pkgver = 1.0.0

pkgname = valpkg
EOF
    printf 'pkgname=valpkg\ninstall=valpkg.install\n' > "$vrepo/PKGBUILD"
    if validate_aur_repo valpkg >"$tmp/val.out" 2>"$tmp/val.err"; then
        echo "validate_aur_repo accepted missing install= script"
        exit 1
    fi
    if ! grep -F -q "[aur-integration] install= file not found in AUR repository: valpkg.install" "$tmp/val.err"; then
        echo "validate_aur_repo did not report missing install= script"
        cat "$tmp/val.err"
        exit 1
    fi

    printf 'post_install() {\n' > "$vrepo/valpkg.install"
    if validate_aur_repo valpkg >"$tmp/val.out" 2>"$tmp/val.err"; then
        echo "validate_aur_repo accepted broken install= script syntax"
        exit 1
    fi
    if ! grep -F -q "[aur-integration] install= script syntax validation failed: valpkg.install" "$tmp/val.err"; then
        echo "validate_aur_repo did not report invalid install= script syntax"
        cat "$tmp/val.err"
        exit 1
    fi

    printf 'post_install() {\n    :\n}\n' > "$vrepo/valpkg.install"
    if ! validate_aur_repo valpkg >"$tmp/val.out" 2>"$tmp/val.err"; then
        echo "validate_aur_repo rejected valid package with install= script"
        cat "$tmp/val.err"
        exit 1
    fi
) || exit 1
