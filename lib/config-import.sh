#!/bin/bash
# Import a hand-written PKGBUILD into aurgen.install.yaml
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# True when the config already has an uncommented package: section.
_import_has_package_section() {
    local config_file="$1"
    [[ -f "$config_file" ]] || return 1
    grep -q -E '^package:[[:space:]]*$' "$config_file"
}

# Source the PKGBUILD the way makepkg does: a clean environment, so aurgen's
# variables cannot leak into pkgname/source/package().
_import_source_pkgbuild() {
    local pkgbuild="$1"
    local script
    script=$(cat <<'EOF'
set -euo pipefail
# shellcheck disable=SC1090
source "$1"
b64() { printf '%s' "$1" | base64 -w0; }
emit_s() { printf 's %s %s\n' "$1" "$(b64 "$2")"; }
emit_array() {
    local name="$1" decl item
    decl="$(declare -p "$name" 2>/dev/null)" || return 0
    if [[ "$decl" != "declare -a"* ]]; then
        emit_s "$name" "${!name}"
        return 0
    fi
    local -n ref="$name"
    for item in "${ref[@]}"; do
        printf 'a %s %s\n' "$name" "$(b64 "$item")"
    done
}
[[ -n "${pkgname:-}" ]] && emit_s pkgname "$pkgname"
[[ -n "${pkgdesc:-}" ]] && emit_s pkgdesc "$pkgdesc"
[[ -n "${install:-}" ]] && emit_s install "$install"
emit_array arch
emit_array license
emit_array depends
emit_array optdepends
emit_array makedepends
emit_array checkdepends
emit_array conflicts
emit_array provides
emit_array backup
emit_array source
if declare -F package >/dev/null 2>&1; then
    emit_s package_fn "$(declare -f package)"
fi
if declare -F check >/dev/null 2>&1; then
    emit_s check_fn "$(declare -f check)"
fi
EOF
)
    # makepkg defines CARCH. A top-level $CARCH must be set under set -u.
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" CARCH="$(uname -m)" bash --noprofile --norc -c "$script" _ "$pkgbuild"
}

# Non-comment body lines of a sourced function. declare -f appends ";" to every
# command but the last in a list, and the function's own "}" is the last "}" line.
_import_fn_lines() {
    local fn_text="$1"
    local line started=0 trimmed i last=-1
    local -a body=()
    while IFS= read -r line; do
        if [[ "$started" -eq 0 ]]; then
            [[ "$line" == *'{'* ]] && started=1
            continue
        fi
        trimmed="$(_yaml_trim "$line")"
        [[ "$trimmed" == *';' && ( "$trimmed" != *';;' || "$trimmed" == *'\;;' ) ]] && trimmed="${trimmed%;}"
        trimmed="$(_yaml_trim "$trimmed")"
        [[ -z "$trimmed" || "$trimmed" == '#'* ]] && continue
        body+=("$trimmed")
    done <<< "$fn_text"
    for i in "${!body[@]}"; do
        [[ "${body[$i]}" == '}' ]] && last="$i"
    done
    for i in "${!body[@]}"; do
        [[ "$i" == "$last" ]] && continue
        printf '%s\n' "${body[$i]}"
    done
}

# A cd target is the source root only when it is $srcdir or $srcdir/<one
# component>, quoted or written as ${srcdir}. A deeper target is a subdirectory
# of that root. Prints "root", "sub <relative cd target>", or "other".
# shellcheck disable=SC2016 # literal $srcdir as written in the PKGBUILD
_import_cd_place() {
    local LC_ALL=C
    local line="$1" target="" quote="" inner="" prefix="" tail="" rel=""
    [[ "$line" == cd[[:space:]]* ]] || { printf 'other\n'; return 0; }
    target="$(_yaml_trim "${line#cd}")"
    if [[ "$target" =~ ^(.*)[[:space:]]+\|\|[[:space:]]+(return|exit)([[:space:]]+[0-9]+)?[[:space:]]*$ ]]; then
        target="$(_yaml_trim "${BASH_REMATCH[1]}")"
    fi
    if [[ "$target" == --[[:space:]]* ]]; then
        target="$(_yaml_trim "${target#--}")"
    fi
    if [[ "$target" =~ ^\"[^\"]*\"$ ]]; then
        quote='"'
        inner="${target:1:$((${#target} - 2))}"
    elif [[ "$target" =~ ^[^[:space:]\"\'\&\|\;]+$ ]]; then
        inner="$target"
    else
        printf 'other\n'
        return 0
    fi
    while [[ "$inner" == */ ]]; do
        inner="${inner%/}"
    done
    if [[ "$inner" == '$srcdir' || "$inner" == '$srcdir/'* ]]; then
        prefix='$srcdir'
    elif [[ "$inner" == '${srcdir}' || "$inner" == '${srcdir}/'* ]]; then
        prefix='${srcdir}'
    else
        printf 'other\n'
        return 0
    fi
    if [[ "$inner" == "$prefix" ]]; then
        printf 'root\n'
        return 0
    fi
    tail="${inner#"$prefix"/}"
    if [[ "/$tail/" == */./* || "/$tail/" == */../* ]]; then
        printf 'other\n'
        return 0
    fi
    if [[ -n "$tail" && "$tail" != */* ]]; then
        printf 'root\n'
        return 0
    fi
    rel="${tail#*/}"
    if [[ -z "${tail%%/*}" || -z "$rel" ]]; then
        printf 'other\n'
        return 0
    fi
    if [[ -n "$quote" ]]; then
        printf 'sub %s%s%s\n' "$quote" "$rel" "$quote"
    else
        printf 'sub %s\n' "$rel"
    fi
}

# install_vars are VAR=VALUE words after DESTDIR and PREFIX. One matching pair
# of quotes around a value is removed before the check. Any word that is still
# not a safe value stops the import. A cd into the source root is ignored. A cd
# anywhere else stops the import. Any other command before
# make install, and a later heredoc, also stop the import. Later lines are
# post_package. Prints "V <var>" and "P <line>".
_import_package_tail() {
    local line seen=0 has_make_install=0 tok name value q place
    local -a toks=() lines=()
    mapfile -t lines < <(_import_fn_lines "$1")
    if (( ${#lines[@]} == 0 )); then
        return 0
    fi
    for line in "${lines[@]}"; do
        if [[ "$line" == 'make install' || "$line" == 'make install '* ]]; then
            has_make_install=1
            break
        fi
    done
    if [[ "$has_make_install" -eq 0 ]]; then
        printf '[config] Cannot import %s: package() has no make install line\n' "$2" >&2
        return 1
    fi
    for line in "${lines[@]}"; do
        if [[ "$seen" -eq 0 ]]; then
            if [[ "$line" == 'make install' || "$line" == 'make install '* ]]; then
                seen=1
                read -ra toks <<< "$line"
                if (( ${#toks[@]} > 2 )); then
                    for tok in "${toks[@]:2}"; do
                        case "$tok" in
                            DESTDIR=*|PREFIX=*) ;;
                            *)
                                # declare -f keeps the quotes that were in the PKGBUILD.
                                if [[ "$tok" == *=* ]]; then
                                    name="${tok%%=*}"
                                    value="${tok#*=}"
                                    if [[ ${#value} -ge 2 ]]; then
                                        q="${value:0:1}"
                                        if [[ ( "$q" == '"' || "$q" == "'" ) && "$q" == "${value: -1}" ]]; then
                                            value="${value:1:$((${#value} - 2))}"
                                            tok="${name}=${value}"
                                        fi
                                    fi
                                fi
                                if [[ "$tok" =~ ^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._/+-]+$ ]]; then
                                    printf 'V %s\n' "$tok"
                                else
                                    printf '[config] Cannot import %s: unsafe install word %s\n' "$2" "$tok" >&2
                                    return 1
                                fi
                                ;;
                        esac
                    done
                fi
                continue
            fi
            if [[ "$line" == cd || "$line" == cd[[:space:]]* ]]; then
                place="$(_import_cd_place "$line")"
                [[ "$place" == root ]] && continue
                printf '[config] Cannot import %s: package() changes directory with %s\n' "$2" "$line" >&2
                return 1
            fi
            printf '[config] Cannot import %s: package() runs %s before make install\n' "$2" "$line" >&2
            return 1
        fi
        if [[ "${line//<<</}" == *'<<'* ]]; then
            printf '[config] Cannot import %s: package() uses a heredoc\n' "$2" >&2
            return 1
        fi
        printf 'P %s\n' "$line"
    done
}

# Commands in check(). A cd into the source root is dropped. A deeper cd is
# kept as cd <rest>, relative to that root.
_import_check_command() {
    local LC_ALL=C
    local line cmd="" extra place chained_place
    local -a cmds=()
    while IFS= read -r line; do
        if [[ "$line" == cd[[:space:]]* ]]; then
            place="$(_import_cd_place "$line")"
            if [[ "$place" == other && "$line" == *'&&'* ]]; then
                chained_place="$(_import_cd_place "${line%%&&*}")"
                case "$chained_place" in
                    root) line="$(_yaml_trim "${line#*&&}")" ;;
                    sub[[:space:]]*) line="cd ${chained_place#sub } && $(_yaml_trim "${line#*&&}")" ;;
                esac
            fi
            case "$place" in
                root) continue ;;
                sub[[:space:]]*) line="cd ${place#sub }" ;;
            esac
        fi
        cmds+=("$line")
    done < <(_import_fn_lines "$1")
    (( ${#cmds[@]} )) || return 0
    cmd="${cmds[0]}"
    if (( ${#cmds[@]} > 1 )); then
        local last="${cmds[0]}" case_depth=0
        local case_word="([^[:space:]\"']|\"[^\"]*\"|'[^']*')+"
        for extra in "${cmds[@]:1}"; do
            if [[ "$last" =~ ^case[[:space:]].*[[:space:]]in$ ]]; then
                case_depth=$((case_depth + 1))
            elif [[ "$last" == 'esac' ]]; then
                case_depth=$((case_depth - 1))
            fi
            # A keyword or operator that opens the next command takes no separator,
            # nor do case headers/terminators or the inside of subshell parentheses.
            if [[ "$cmd" =~ (^|[[:space:];])(then|do|else|\{|&&|\|\|)$ || "$last" =~ ^case[[:space:]].*[[:space:]]in$ || ( "$case_depth" -gt 0 && "$last" =~ ^$case_word(\ \|\ $case_word)*\)$ ) || "$last" == *';;' || "$last" == *';&' || "$last" == '(' || "$extra" == ')' ]]; then
                cmd+=" ${extra}"
            else
                cmd+="; ${extra}"
            fi
            last="$extra"
        done
    fi
    printf '%s\n' "$cmd"
}

# archive/refs/tags → archive, git+...?signed → signed-tag, else release.
_import_source_kind() {
    local item kind=release
    for item in "$@"; do
        if [[ "$item" == *'archive/refs/tags'* ]]; then
            kind=archive
            break
        fi
    done
    if [[ "$kind" == release ]]; then
        for item in "$@"; do
            if [[ "$item" == *git+* && "$item" == *'?signed'* ]]; then
                kind=signed-tag
                break
            fi
        done
    fi
    printf '%s\n' "$kind"
}

# Generation writes arch=('any') unless the project compiles.
_import_project_compiles() {
    local root="${PROJECT_ROOT:-}"
    [[ -n "$root" ]] || return 1
    _import_load_detector
    project_compiles "$root"
}

# The check generation fills in when check is empty; any other suite (make
# test, a package target) stays explicit.
_import_default_check() {
    [[ -n "${PROJECT_ROOT:-}" ]] || return 0
    _import_load_detector
    default_check_command "$(detect_buildsys "$PROJECT_ROOT")" "$PROJECT_ROOT"
}

_import_load_detector() {
    if declare -F detect_runtime_deps >/dev/null 2>&1 && declare -F filter_pkgbuild_sources >/dev/null 2>&1; then
        return 0
    fi
    # shellcheck source=lib/gen-pkgbuild0.sh
    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/gen-pkgbuild0.sh"
}

# One pair of single quotes. An apostrophe is written as '' so a later " #"
# stays inside the scalar instead of becoming a comment.
_import_yaml_quote() {
    local value="$1"
    value="${value//\'/\'\'}"
    printf "'%s'" "$value"
}

_import_yaml_scalar() {
    local key="$1"
    local value="$2"
    [[ -n "$value" ]] || return 0
    printf '  %s: %s\n' "$key" "$(_import_yaml_quote "$value")"
}

_import_yaml_list() {
    local key="$1"
    shift
    local item
    (( $# == 0 )) && return 0
    printf '  %s:\n' "$key"
    for item in "$@"; do
        printf '    - %s\n' "$(_import_yaml_quote "$item")"
    done
}

# Usage: config_import <pkgbuild> <aurgen.install.yaml>
config_import() {
    local pkgbuild="$1"
    local config_file="$2"
    local output line kind rest key payload
    local pkg_name="" pkg_desc="" pkg_install=""
    local package_fn="" check_fn="" check_cmd="" default_check=""
    local source_kind="" runtime_deps="" dep="" doc="" block="" status=0
    local -a arch=() license=() depends=() optdepends=() makedepends=() checkdepends=()
    local -a conflicts=() provides=() backup=() sources=()
    local -a install_vars=() post_package=() kept=() detected_deps=()
    local -a saved_depends=() saved_vars=()
    local -A detected_set=()

    if [[ ! -f "$pkgbuild" ]]; then
        echo -e "${RED}[config] PKGBUILD not found: $pkgbuild${RESET}" >&2
        return 1
    fi
    if _import_has_package_section "$config_file"; then
        echo -e "${RED}[config] package: section already exists in $config_file${RESET}" >&2
        echo -e "${YELLOW}[config] Refusing to overwrite it.${RESET}" >&2
        return 1
    fi

    output="$(_import_source_pkgbuild "$pkgbuild")" || {
        echo -e "${RED}[config] Failed to read $pkgbuild${RESET}" >&2
        return 1
    }
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        kind="${line%% *}"
        rest="${line#* }"
        key="${rest%% *}"
        payload="$(printf '%s' "${rest#* }" | base64 -d)" || return 1
        case "$kind" in
            s)
                case "$key" in
                    pkgname) pkg_name="$payload" ;;
                    pkgdesc) pkg_desc="$payload" ;;
                    install) pkg_install="$payload" ;;
                    package_fn) package_fn="$payload" ;;
                    check_fn) check_fn="$payload" ;;
                esac
                ;;
            a)
                case "$key" in
                    arch) arch+=("$payload") ;;
                    license) license+=("$payload") ;;
                    depends) depends+=("$payload") ;;
                    optdepends) optdepends+=("$payload") ;;
                    makedepends) makedepends+=("$payload") ;;
                    checkdepends) checkdepends+=("$payload") ;;
                    conflicts) conflicts+=("$payload") ;;
                    provides) provides+=("$payload") ;;
                    backup) backup+=("$payload") ;;
                    source) sources+=("$payload") ;;
                esac
                ;;
        esac
    done <<< "$output"

    if [[ -z "$pkg_name" ]]; then
        echo -e "${RED}[config] PKGBUILD has no pkgname: $pkgbuild${RESET}" >&2
        return 1
    fi

    if (( ${#sources[@]} )); then
        source_kind="$(_import_source_kind "${sources[@]}")"
    else
        source_kind=release
    fi

    if [[ -n "$package_fn" ]]; then
        output="$(_import_package_tail "$package_fn" "$pkgbuild")" || return 1
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            case "$line" in
                V\ *) install_vars+=("${line#V }") ;;
                P\ *) post_package+=("${line#P }") ;;
            esac
        done <<< "$output"
    fi

    if [[ -n "$check_fn" ]]; then
        check_cmd="$(_import_check_command "$check_fn")"
    fi
    default_check="$(_import_default_check)"
    if [[ -n "$default_check" && "$check_cmd" == "$default_check" ]]; then
        check_cmd=""
    elif [[ -n "$default_check" && -z "$check_fn" ]]; then
        # A hand PKGBUILD without check() must not gain the build system default.
        check_cmd="false"
    fi

    # arch=('any') is what generation writes when package.arch is empty and
    # nothing is compiled. A compiled tree's default is x86_64 and aarch64.
    if _import_project_compiles; then
        if (( ${#arch[@]} == 2 )) && [[ "${arch[0]}" == x86_64 && "${arch[1]}" == aarch64 ]]; then
            arch=()
        fi
    elif (( ${#arch[@]} == 1 )) && [[ "${arch[0]}" == any ]]; then
        arch=()
    fi

    # Depends that detection would add are not package metadata. A version pin
    # (bash>=4.4) does not match the detected name, so it stays.
    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        _import_load_detector
        if (( ${#PKG_DEPENDS[@]} )); then
            saved_depends=("${PKG_DEPENDS[@]}")
        fi
        if (( ${#PKG_INSTALL_VARS[@]} )); then
            saved_vars=("${PKG_INSTALL_VARS[@]}")
        fi
        PKG_DEPENDS=()
        if (( ${#install_vars[@]} )); then
            PKG_INSTALL_VARS=("${install_vars[@]}")
        else
            PKG_INSTALL_VARS=()
        fi
        runtime_deps="$(detect_runtime_deps)" || status=$?
        PKG_DEPENDS=()
        PKG_INSTALL_VARS=()
        if (( ${#saved_depends[@]} )); then
            PKG_DEPENDS=("${saved_depends[@]}")
        fi
        if (( ${#saved_vars[@]} )); then
            PKG_INSTALL_VARS=("${saved_vars[@]}")
        fi
        if [[ "$status" -ne 0 ]]; then
            echo -e "${RED}[config] Failed to detect runtime dependencies${RESET}" >&2
            return 1
        fi
        if [[ -n "${runtime_deps//[[:space:]]}" ]]; then
            read -ra detected_deps <<< "$runtime_deps"
        fi
        for dep in "${detected_deps[@]}"; do
            [[ -n "$dep" ]] && detected_set["$dep"]=1
        done
        kept=()
        for dep in "${depends[@]}"; do
            [[ -n "${detected_set[$dep]:-}" ]] && continue
            kept+=("$dep")
        done
        depends=()
        if (( ${#kept[@]} )); then
            depends=("${kept[@]}")
        fi
    fi

    # A signed tag always makedepends on git; recording it would duplicate that.
    if [[ "$source_kind" == signed-tag ]] && (( ${#makedepends[@]} )); then
        kept=()
        for dep in "${makedepends[@]}"; do
            [[ "$dep" == git ]] && continue
            kept+=("$dep")
        done
        makedepends=()
        if (( ${#kept[@]} )); then
            makedepends=("${kept[@]}")
        fi
    fi

    doc="package:"$'\n'
    block="$(_import_yaml_scalar name "$pkg_name")"
    [[ -n "$block" ]] && doc+="$block"$'\n'
    block="$(_import_yaml_scalar description "$pkg_desc")"
    [[ -n "$block" ]] && doc+="$block"$'\n'
    if (( ${#license[@]} )); then
        block="$(_import_yaml_list license "${license[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    block="$(_import_yaml_scalar source "$source_kind")"
    [[ -n "$block" ]] && doc+="$block"$'\n'
    if (( ${#depends[@]} )); then
        block="$(_import_yaml_list depends "${depends[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#optdepends[@]} )); then
        block="$(_import_yaml_list optdepends "${optdepends[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#makedepends[@]} )); then
        block="$(_import_yaml_list makedepends "${makedepends[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#checkdepends[@]} )); then
        block="$(_import_yaml_list checkdepends "${checkdepends[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#conflicts[@]} )); then
        block="$(_import_yaml_list conflicts "${conflicts[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#provides[@]} )); then
        block="$(_import_yaml_list provides "${provides[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#backup[@]} )); then
        block="$(_import_yaml_list backup "${backup[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    block="$(_import_yaml_scalar install "$pkg_install")"
    [[ -n "$block" ]] && doc+="$block"$'\n'
    if (( ${#install_vars[@]} )); then
        block="$(_import_yaml_list install_vars "${install_vars[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    block="$(_import_yaml_scalar check "$check_cmd")"
    [[ -n "$block" ]] && doc+="$block"$'\n'
    if (( ${#post_package[@]} )); then
        block="$(_import_yaml_list post_package "${post_package[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi
    if (( ${#arch[@]} )); then
        block="$(_import_yaml_list arch "${arch[@]}")"
        [[ -n "$block" ]] && doc+="$block"$'\n'
    fi

    if [[ ! -f "$config_file" ]]; then
        generate_default_config "$config_file" || return 1
    fi
    if _import_has_package_section "$config_file"; then
        echo -e "${RED}[config] package: section already exists in $config_file${RESET}" >&2
        echo -e "${YELLOW}[config] Refusing to overwrite it.${RESET}" >&2
        return 1
    fi
    if ! printf '\n%s' "$doc" >> "$config_file"; then
        echo -e "${RED}[config] Cannot write $config_file${RESET}" >&2
        return 1
    fi
    echo -e "${GREEN}[config] Imported package metadata from $pkgbuild${RESET}" >&2
}
