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
