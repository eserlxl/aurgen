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

# Shared PKGBUILD quoting and comment-stripping awk helpers (requires -v sq="'").
_GIT_AWK_PKGBUILD_HELPERS="${_AWK_PKGBUILD_UNQUOTED}"'
    function strip_comment(s,    i, n, c, out, prev) {
        out = ""; prev = ""; n = length(s)
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c == sq) {
                out = out c
                for (i++; i <= n; i++) {
                    c = substr(s, i, 1); out = out c
                    if (c == sq) break
                }
                prev = "_"; continue
            }
            if (c == "\"") {
                out = out c
                for (i++; i <= n; i++) {
                    c = substr(s, i, 1); out = out c
                    if (c == "\\") { i++; if (i <= n) out = out substr(s, i, 1); continue }
                    if (c == "\"") break
                }
                prev = "_"; continue
            }
            if (c == "\\") {
                out = out c; i++
                if (i <= n) out = out substr(s, i, 1)
                prev = "_"; continue
            }
            if (c == "#" && (prev == "" || prev ~ /[[:space:]()]/)) break
            out = out c; prev = c
        }
        return out
    }
    function unquote(s,    n, a, b) {
        n = length(s)
        if (n >= 2) {
            a = substr(s, 1, 1); b = substr(s, n, 1)
            if ((a == sq && b == sq) || (a == "\"" && b == "\"")) return substr(s, 2, n - 2)
        }
        return s
    }
'

# Return 0 when a top-level depends=(...) array in $1 already lists git or git[<>=]...
_git_depends_has_git() {
    local src_pkgbuild="$1"
    LC_ALL=C awk -v sq="'" "${_GIT_AWK_PKGBUILD_HELPERS}"'
        function scan_body(s,    n, k, tok, v) {
            n = split(s, tok, /[[:space:]]+/)
            for (k = 1; k <= n; k++) {
                if (tok[k] == "") continue
                v = unquote(tok[k])
                if (v == "git" || v ~ /^git[<>=]/) found = 1
            }
        }
        /^(build|check|package|prepare|pkgver)\(\)/ { in_fn = 1; next }
        in_fn { if (/^}[[:space:]]*$/) in_fn = 0; next }
        in_dep {
            line = strip_comment($0)
            closed = (unquoted($0) ~ /\)[[:space:]]*$/)
            if (closed) sub(/\)[[:space:]]*$/, "", line)
            scan_body(line)
            if (closed) in_dep = 0
            next
        }
        /^[[:space:]]*depends[[:space:]]*=[[:space:]]*\(/ {
            line = strip_comment($0)
            sub(/^[[:space:]]*depends[[:space:]]*=[[:space:]]*\(/, "", line)
            closed = (unquoted($0) ~ /\)[[:space:]]*$/)
            if (closed) sub(/\)[[:space:]]*$/, "", line)
            else in_dep = 1
            scan_body(line)
            next
        }
        END { exit(found ? 0 : 1) }
    ' "$src_pkgbuild"
}

# Rewrite PKGBUILD.0 into a VCS (-git) PKGBUILD at $2.
# True when PKGBUILD declares a top-level name=(...) array outside function bodies.
_git_has_top_array() {
    local file="$1" target="$2"
    LC_ALL=C awk -v target="$target" '
        /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*\)/ {
            if ($0 !~ /\{.*\}[[:space:]]*$/) {
                in_fn = 1
            }
            next
        }
        in_fn {
            if ($0 ~ /^[[:space:]]*}[[:space:]]*$/) {
                in_fn = 0
            }
            next
        }
        $0 ~ ("^[[:space:]]*" target "[[:space:]]*=[[:space:]]*\\(") {
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$file"
}

# makepkg clones a git source into $srcdir/<repo>, not the archive tree.
_git_write_pkgbuild() {
    local src_pkgbuild="$1" dest="$2" pkgname_short="$3" repo_name="$4" default_branch="$5"
    local has_provides="$6" has_conflicts="$7" has_makedepends="$8" depends_has_git="$9"
    LC_ALL=C awk -v gh_user="$GH_USER" -v pkgname_short="$pkgname_short" -v repo_name="$repo_name" \
        -v branch="$default_branch" -v has_provides="$has_provides" -v has_conflicts="$has_conflicts" \
        -v has_makedepends="$has_makedepends" -v depends_has_git="$depends_has_git" -v sq="'" \
        "${_GIT_AWK_PKGBUILD_HELPERS}"'
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
                    sub(/cd "\$srcdir\/[^"\/]*/, "cd \"$srcdir/" repo_name, line)
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
        function arr_has_pkg(name,    i, body, n, k, tok, val) {
            for (i = 1; i <= nabuf; i++) {
                body = strip_comment(abuf[i])
                if (i == 1) {
                    sub(/^[[:space:]]*[^=]+=[[:space:]]*\(/, "", body)
                }
                if (i == nabuf) {
                    sub(/\)[[:space:]]*$/, "", body)
                }
                n = split(body, tok, /[[:space:]]+/)
                for (k = 1; k <= n; k++) {
                    if (tok[k] == "") continue
                    val = unquote(tok[k])
                    if (val == name || (name == "git" && val ~ /^git[<>=]/)) {
                        return 1
                    }
                }
            }
            return 0
        }
        function flush_arr(    i, indent, base) {
            if (!arr_has_pkg(arr_target)) {
                if (nabuf == 1) {
                    base = strip_comment(abuf[1])
                    if (unquoted(abuf[1]) ~ /=[[:space:]]*\([[:space:]]*\)[[:space:]]*$/) {
                        sub(/\([[:space:]]*\)[[:space:]]*$/, "(" arr_fmt ")", base)
                    } else {
                        sub(/\)[[:space:]]*$/, " " arr_fmt ")", base)
                    }
                    abuf[1] = base
                } else if (unquoted(abuf[nabuf]) ~ /^[[:space:]]*\)[[:space:]]*$/) {
                    indent = "  "
                    if (nabuf >= 2 && match(abuf[nabuf - 1], /^[[:space:]]+/)) {
                        indent = substr(abuf[nabuf - 1], RSTART, RLENGTH)
                    }
                    abuf[nabuf + 1] = abuf[nabuf]
                    abuf[nabuf] = indent arr_fmt
                    nabuf++
                } else {
                    base = strip_comment(abuf[nabuf])
                    sub(/\)[[:space:]]*$/, " " arr_fmt ")", base)
                    abuf[nabuf] = base
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
            if (unquoted($0) ~ /\)[[:space:]]*$/) {
                flush_arr()
            }
        }
        BEGIN { sums = "b2sums=(\"SKIP\")" }
        # Skip all lines of a multi-line source=(...) array until its closing ")"
        in_source && unquoted($0) ~ /\)[[:space:]]*$/ { in_source=0; next }
        in_source { next }
        # Skip continuation lines of multi-line *sums=(...) arrays
        in_sums && unquoted($0) ~ /\)[[:space:]]*$/ { in_sums=0; next }
        in_sums { next }
        # Buffer continuation lines of provides/conflicts/makedepends arrays
        in_arr {
            abuf[++nabuf] = $0
            if (unquoted($0) ~ /\)[[:space:]]*$/) {
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
            if (has_makedepends == 0 && depends_has_git == 0) {
                print "makedepends=(git)"
            }
            next
        }
        # A one-line source=(...) already closed the array; skipping until ")" drops every function.
        /^source=\(/ {
            branch_spec = (branch != "" && branch != "HEAD") ? "#branch=" branch : ""
            print "source=(\"git+https://github.com/" gh_user "/" repo_name ".git" branch_spec "\")";
            print sums;
            in_source=1;
            if (unquoted($0) ~ /\)[[:space:]]*$/) {
                in_source = 0
            }
            next
        }
        /^(prepare|build|check|package)\(\)/ {
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
        /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*\)/ {
            if ($0 !~ /\{.*\}[[:space:]]*$/) {
                in_other_fn = 1
            }
            emit($0)
            next
        }
        in_other_fn {
            emit($0)
            if ($0 ~ /^[[:space:]]*}[[:space:]]*$/) {
                in_other_fn = 0
            }
            next
        }
        # Remove single- and multi-line checksum arrays
        /^[[:space:]]*[a-zA-Z0-9_]*sums(_[a-zA-Z0-9_]+)?=/ {
            u = unquoted($0)
            if (u ~ /=[[:space:]]*\(/ && u !~ /\)[[:space:]]*$/) {
                in_sums = 1
            }
            next
        }
        /^[[:space:]]*provides[[:space:]]*=[[:space:]]*\(/ { start_arr(pkgname_short, sq pkgname_short sq); next }
        /^[[:space:]]*conflicts[[:space:]]*=[[:space:]]*\(/ { start_arr(pkgname_short, sq pkgname_short sq); next }
        /^[[:space:]]*makedepends[[:space:]]*=[[:space:]]*\(/ {
            if (depends_has_git == 0) {
                start_arr("git", "git")
                next
            }
        }
        # Otherwise, print lines as-is, with variable substitution
        { emit($0) }
        END {
            if (in_arr) flush_arr()
            if (in_func) flush_func()
        }
    ' "$src_pkgbuild" >| "$dest"
}

# Insert pkgver() after source= when absent. No aurgen variables: makepkg does not set them.
_git_insert_pkgver() {
    local pkgbuild_git="$1" repo_name="$2"
    local pkgver_inserted=0 line
    grep -q '^pkgver()' "$pkgbuild_git" && return 0
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
    done < "$pkgbuild_git" >| "$pkgbuild_git.tmp"
    mv "$pkgbuild_git.tmp" "$pkgbuild_git"
}

_git_safe_url_parts() {
    local LC_ALL=C
    [[ "$1" =~ ^[A-Za-z0-9._/+-]*$ && "$2" =~ ^[A-Za-z0-9._-]+$ && "$3" =~ ^[a-z0-9@._+-]+$ && "$4" =~ ^[A-Za-z0-9@._+-]+$ ]]
}

mode_git() {
    log "[git] Prepare PKGBUILD for VCS (git) package. No tarball is created."
    # origin/HEAD is the clone default; a local checkout may be on another branch.
    local default_branch pkgname_short repo_name
    local has_provides=0 has_conflicts=0 has_makedepends=0 depends_has_git=0
    local out="${OUT_DIR:-$AUR_DIR}"
    pkgname_short="${PKGNAME%-git}"
    # Clone directory follows the remote repo, which may differ from pkgname.
    repo_name="${REPO_NAME:-$pkgname_short}"
    if default_branch=$(git -C "$PROJECT_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
        default_branch="${default_branch#refs/remotes/origin/}"
    else
        default_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)
        if [[ "$default_branch" == "HEAD" ]]; then
            warn "[git] Detached checkout (HEAD); leaving #branch= out of source to use remote default branch."
            default_branch=""
        fi
    fi
    # These land inside source=("...") in a file makepkg sources; git allows $() in ref names.
    if ! _git_safe_url_parts "$default_branch" "$GH_USER" "$pkgname_short" "$repo_name"; then
        err "[git] Refusing unsafe source URL parts: user '$GH_USER', repo '$repo_name', branch '$default_branch'"
        exit 1
    fi
    # A later array in PKGBUILD0 overrides one printed at pkgname, so merge into it.
    if _git_has_top_array "$PKGBUILD0" provides; then
        has_provides=1
    fi
    if _git_has_top_array "$PKGBUILD0" conflicts; then
        has_conflicts=1
    fi
    if _git_has_top_array "$PKGBUILD0" makedepends; then
        has_makedepends=1
    fi
    if _git_depends_has_git "$PKGBUILD0"; then
        depends_has_git=1
    fi
    local lock_fd=""
    [[ -d "$out" ]] || mkdir -p "$out" || exit 1
    exec {lock_fd}>>"$out/.aurgen.lock"
    if ! flock -n "$lock_fd"; then
        exec {lock_fd}>&-
        err "[git] Another process is already updating PKGBUILD. Aborting."
        exit 1
    fi
    _git_write_pkgbuild "$PKGBUILD0" "$out/PKGBUILD.git" "$pkgname_short" "$repo_name" \
        "$default_branch" "$has_provides" "$has_conflicts" "$has_makedepends" "$depends_has_git" || { exec {lock_fd}>&-; exit 1; }
    write_validpgpkeys "$out/PKGBUILD.git" "" || { exec {lock_fd}>&-; exit 1; }
    _git_insert_pkgver "$out/PKGBUILD.git" "$repo_name" || { exec {lock_fd}>&-; exit 1; }
    PKGBUILD_TEMPLATE="$out/PKGBUILD.git"
    cp -f "$PKGBUILD_TEMPLATE" "$PKGBUILD" || { exec {lock_fd}>&-; exit 1; }
    log "[git] PKGBUILD.git generated and copied to PKGBUILD."
    generate_srcinfo || { exec {lock_fd}>&-; exit 1; }
    # shellcheck disable=SC2034 # Read by bin/aurgen failure recovery handler
    _AURGEN_ARTIFACTS_COMMITTED=1
    exec {lock_fd}>&-
    install_pkg "git" || exit $?
}
