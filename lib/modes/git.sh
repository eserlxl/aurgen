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
    local has_provides=0 has_conflicts=0 sq="'"
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
    if grep -q '^provides=' "$PKGBUILD0"; then
        has_provides=1
    fi
    if grep -q '^conflicts=' "$PKGBUILD0"; then
        has_conflicts=1
    fi
    # makepkg clones a git source into $srcdir/<repo>, not the archive tree.
    awk -v gh_user="$GH_USER" -v pkgname_short="$pkgname_short" -v repo_name="$repo_name" -v branch="$default_branch" -v has_provides="$has_provides" -v has_conflicts="$has_conflicts" -v sq="$sq" '
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
        # shortcut: one-line arrays only, upgrade when provides/conflicts span lines
        function has_pkg(line, name,    body, n, i, tok) {
            body = line
            sub(/^[^=]*=\(/, "", body)
            sub(/\)[[:space:]]*$/, "", body)
            n = split(body, tok, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                if (unquote(tok[i]) == name) {
                    return 1
                }
            }
            return 0
        }
        function append_pkg(line, name) {
            if (has_pkg(line, name)) {
                return line
            }
            sub(/\)[[:space:]]*$/, " " sq name sq ")", line)
            return line
        }
        BEGIN { sums = "b2sums=(\"SKIP\")" }
        /^pkgname=/ {
            print "pkgname=" pkgname_short "-git"
            if (has_provides == 0) {
                print "provides=(" pkgname_short ")"
            }
            if (has_conflicts == 0) {
                print "conflicts=(" pkgname_short ")"
            }
            next
        }
        # A one-line source=(...) already closed the array; skipping until ")" drops every function.
        /^source=\(/ {
            print "source=(\"git+https://github.com/" gh_user "/" repo_name ".git#branch=" branch "\")";
            print sums;
            in_source=1;
            if ($0 ~ /\)[[:space:]]*$/) {
                in_source = 0
            }
            next
        }
        # Skip all lines until we see the closing parenthesis of the array
        in_source && /^[[:space:]]*\)/ { in_source=0; next }
        # While in skip mode, skip lines
        in_source { next }
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
        # Remove b2sums and sha256sums lines
        /^b2sums=/ || /^sha256sums=/ { next }
        /^provides=/ { emit(append_pkg($0, pkgname_short)); next }
        /^conflicts=/ { emit(append_pkg($0, pkgname_short)); next }
        # A VCS package has no detached signature, so drop validpgpkeys instead of appending another array.
        /^[[:space:]]*validpgpkeys[[:space:]]*=/ {
            in_pgp = 1
            if ($0 ~ /\)[[:space:]]*$/) {
                in_pgp = 0
            }
            next
        }
        in_pgp && /\)/ { in_pgp = 0; next }
        in_pgp { next }
        # Otherwise, print lines as-is, with variable substitution
        { emit($0) }
        END { if (in_func) flush_func() }
    ' "$PKGBUILD0" >| "$out/PKGBUILD.git"
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
    # Own array token only; a substring such as libgit2 is not the git package.
    if ! grep -qE '^makedepends=.*[[:space:]'"'"'"(]git([[:space:]'"'"'")]|$)' "$PKGBUILD_TEMPLATE"; then
        # Check if makedepends already exists
        if grep -q '^makedepends=' "$PKGBUILD_TEMPLATE"; then
            # Append git to existing makedepends
            sed -i 's/^makedepends=(\([^)]*\))/makedepends=(\1 git)/' "$PKGBUILD_TEMPLATE"
            log "[git] Added git to existing makedepends in PKGBUILD.git."
        else
            # Insert new makedepends line after pkgname
            awk 'BEGIN{done=0} \
                /^pkgname=/ && !done {print; print "makedepends=(git)"; done=1; next} \
                {print}' "$PKGBUILD_TEMPLATE" >| "$PKGBUILD_TEMPLATE.tmp" && mv "$PKGBUILD_TEMPLATE.tmp" "$PKGBUILD_TEMPLATE"
            log "[git] Injected makedepends=(git) into PKGBUILD.git."
        fi
    fi
    cp -f "$PKGBUILD_TEMPLATE" "$PKGBUILD"
    log "[git] PKGBUILD.git generated and copied to PKGBUILD."
    generate_srcinfo || exit 1
    install_pkg "git"
}
