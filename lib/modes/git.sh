#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen git mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

mode_git() {
    log "[git] Prepare PKGBUILD for VCS (git) package. No tarball is created."
    # origin/HEAD is the clone default; a local checkout may be on another branch.
    local default_branch pkgname_short pkgver_inserted line repo_name
    local has_provides=0 has_conflicts=0 has_makedepends=0 sq="'"
    local out="${OUT_DIR:-$AUR_DIR}"
    pkgname_short="${PKGNAME%-git}"
    # Clone directory follows the remote repo, which may differ from pkgname.
    repo_name="${REPO_NAME:-$pkgname_short}"
    if default_branch=$(git -C "$PROJECT_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
        default_branch="${default_branch#refs/remotes/origin/}"
    else
        default_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)
    fi
    # These land inside source=("...") in a file makepkg sources; git allows $() in ref names.
    if [[ ! "$default_branch" =~ ^[A-Za-z0-9._/+-]+$ || ! "$GH_USER" =~ ^[A-Za-z0-9._-]+$ || ! "$pkgname_short" =~ ^[a-z0-9@._+-]+$ || ! "$repo_name" =~ ^[A-Za-z0-9@._+-]+$ ]]; then
        err "[git] Refusing unsafe source URL parts: user '$GH_USER', repo '$repo_name', branch '$default_branch'"
        exit 1
    fi
    # A later array in PKGBUILD0 overrides one printed at pkgname, so merge into it.
    if grep -qE '^[[:space:]]*provides=' "$PKGBUILD0"; then
        has_provides=1
    fi
    if grep -qE '^[[:space:]]*conflicts=' "$PKGBUILD0"; then
        has_conflicts=1
    fi
    if grep -qE '^[[:space:]]*makedepends=' "$PKGBUILD0"; then
        has_makedepends=1
    fi
    # makepkg clones a git source into $srcdir/<repo>, not the archive tree.
    awk -v gh_user="$GH_USER" -v pkgname_short="$pkgname_short" -v repo_name="$repo_name" -v branch="$default_branch" -v has_provides="$has_provides" -v has_conflicts="$has_conflicts" -v has_makedepends="$has_makedepends" -v sq="$sq" '
        function emit(line) {
            gsub(/\${pkgname}-\${pkgver}|\$pkgname-\$pkgver/, pkgname_short, line)
            print line
        }
        # Archive and release PKGBUILDs cd elsewhere, or not at all. The clone is $srcdir/<repo>.
        function flush_func(    i, has_cd, insert_at, line) {
            has_cd = 0
            for (i = 1; i <= nbuf; i++) {
                if (buf[i] ~ /^[[:space:]]*cd "\$srcdir\//) {
                    has_cd = 1
                }
            }
            insert_at = 0
            if (!has_cd) {
                for (i = 1; i <= nbuf; i++) {
                    if (buf[i] ~ /\{/) {
                        insert_at = i
                        break
                    }
                }
            }
            for (i = 1; i <= nbuf; i++) {
                line = buf[i]
                if (has_cd && line ~ /^[[:space:]]*cd "\$srcdir\//) {
                    sub(/cd "\$srcdir\/[^"]*"/, "cd \"$srcdir/" repo_name "\"", line)
                }
                emit(line)
                if (i == insert_at) {
                    emit("    cd \"$srcdir/" repo_name "\"")
                }
            }
            nbuf = 0
            in_func = 0
            delete buf
        }
        function unquote(s,    n, a, b) {
            n = length(s)
            if (n < 2) {
                return s
            }
            a = substr(s, 1, 1)
            b = substr(s, n, 1)
            if ((a == sq && b == sq) || (a == "\"" && b == "\"")) {
                return substr(s, 2, n - 2)
            }
            return s
        }
        function arr_has_pkg(name,    i, body, n, k, tok) {
            for (i = 1; i <= nabuf; i++) {
                body = abuf[i]
                if (i == 1) {
                    sub(/^[[:space:]]*[^=]+=\(/, "", body)
                }
                sub(/[[:space:]]*#.*$/, "", body)
                if (i == nabuf) {
                    sub(/\)[[:space:]]*$/, "", body)
                }
                n = split(body, tok, /[[:space:]]+/)
                for (k = 1; k <= n; k++) {
                    if (tok[k] != "" && unquote(tok[k]) == name) {
                        return 1
                    }
                }
            }
            return 0
        }
        function flush_arr(    i, indent) {
            if (!arr_has_pkg(arr_target)) {
                if (nabuf == 1) {
                    if (abuf[1] ~ /=\([[:space:]]*\)[[:space:]]*(#.*)?$/) {
                        sub(/=\([[:space:]]*\)/, "=(" arr_fmt ")", abuf[1])
                    } else {
                        sub(/\)[[:space:]]*(#.*)?$/, " " arr_fmt ")", abuf[1])
                    }
                } else if (abuf[nabuf] ~ /^[[:space:]]*\)[[:space:]]*(#.*)?$/) {
                    indent = "  "
                    if (nabuf >= 2 && match(abuf[nabuf - 1], /^[[:space:]]+/)) {
                        indent = substr(abuf[nabuf - 1], RSTART, RLENGTH)
                    }
                    abuf[nabuf + 1] = abuf[nabuf]
                    abuf[nabuf] = indent arr_fmt
                    nabuf++
                } else {
                    sub(/\)[[:space:]]*(#.*)?$/, " " arr_fmt ")", abuf[nabuf])
                }
            }
            for (i = 1; i <= nabuf; i++) {
                emit(abuf[i])
            }
            nabuf = 0
            in_arr = 0
            delete abuf
        }
        function start_arr(target, fmt) {
            in_arr = 1
            arr_target = target
            arr_fmt = fmt
            nabuf = 0
            delete abuf
            abuf[++nabuf] = $0
            if ($0 ~ /\)[[:space:]]*(#.*)?$/) {
                flush_arr()
            }
        }
        BEGIN { sums = "b2sums=(\"SKIP\")" }
        # Skip all lines of a multi-line source=(...) array until its closing ")"
        in_source && /^[[:space:]]*\)/ { in_source=0; next }
        in_source && /\)[[:space:]]*(#.*)?$/ { in_source=0; next }
        in_source { next }
        # Skip continuation lines of multi-line *sums=(...) arrays
        in_sums && /\)[[:space:]]*(#.*)?$/ { in_sums=0; next }
        in_sums { next }
        # Buffer continuation lines of provides/conflicts/makedepends arrays
        in_arr {
            abuf[++nabuf] = $0
            if ($0 ~ /\)[[:space:]]*(#.*)?$/) {
                flush_arr()
            }
            next
        }
        /^pkgname=/ {
            print "pkgname=" pkgname_short "-git"
            if (has_provides == 0) {
                print "provides=(" pkgname_short ")"
            }
            if (has_conflicts == 0) {
                print "conflicts=(" pkgname_short ")"
            }
            if (has_makedepends == 0) {
                print "makedepends=(git)"
            }
            next
        }
        # A one-line source=(...) already closed the array; skipping until ")" drops every function.
        /^source=\(/ {
            print "source=(\"git+https://github.com/" gh_user "/" repo_name ".git#branch=" branch "\")";
            print sums;
            in_source=1;
            if ($0 ~ /\)[[:space:]]*(#.*)?$/) {
                in_source = 0
            }
            next
        }
        /^(build|check|package)\(\)/ {
            if (in_func) {
                flush_func()
            }
            in_func = 1
            nbuf = 0
            delete buf
            buf[++nbuf] = $0
            if ($0 ~ /^}[[:space:]]*$/) {
                flush_func()
            }
            next
        }
        in_func {
            buf[++nbuf] = $0
            if ($0 ~ /^}[[:space:]]*$/) {
                flush_func()
            }
            next
        }
        # Remove single- and multi-line checksum arrays
        /^[[:space:]]*[a-zA-Z0-9_]*sums(_[a-zA-Z0-9_]+)?=/ {
            if ($0 ~ /=\(/ && $0 !~ /\)[[:space:]]*(#.*)?$/) {
                in_sums = 1
            }
            next
        }
        /^[[:space:]]*provides=\(/ { start_arr(pkgname_short, sq pkgname_short sq); next }
        /^[[:space:]]*conflicts=\(/ { start_arr(pkgname_short, sq pkgname_short sq); next }
        /^[[:space:]]*makedepends=\(/ { start_arr("git", "git"); next }
        # Otherwise, print lines as-is, with variable substitution
        { emit($0) }
        END {
            if (in_arr) flush_arr()
            if (in_func) flush_func()
        }
    ' "$PKGBUILD0" >| "$out/PKGBUILD.git"
    write_validpgpkeys "$out/PKGBUILD.git" ""
    # Insert pkgver() as before if missing. No aurgen variables: makepkg does not set them.
    if ! grep -q '^pkgver()' "$out/PKGBUILD.git"; then
        pkgver_inserted=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "$line"
            if [[ "$pkgver_inserted" -eq 0 && "$line" == source=* ]]; then
                printf '\n'
                printf 'pkgver() {\n'
                # shellcheck disable=SC2016 # $srcdir is for makepkg, not this shell
                printf '    cd "$srcdir/%s"\n' "$repo_name"
                cat <<'EOF'
    if ver=$(git describe --long --tags 2>/dev/null); then
        printf '%s\n' "$ver" | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
    else
        printf 'r%s.%s\n' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
    fi
}
EOF
                pkgver_inserted=1
            fi
        done < "$out/PKGBUILD.git" >| "$out/PKGBUILD.git.tmp"
        mv "$out/PKGBUILD.git.tmp" "$out/PKGBUILD.git"
    fi
    PKGBUILD_TEMPLATE="$out/PKGBUILD.git"
    cp -f "$PKGBUILD_TEMPLATE" "$PKGBUILD"
    log "[git] PKGBUILD.git generated and copied to PKGBUILD."
    generate_srcinfo || exit 1
    install_pkg "git" || return $?
}
