#!/bin/bash
# Detect build dependencies based on project files
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Source tool mapping functions
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"

# Source exclusion words functions
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/exclude-words.sh"

# Configuration
# Note: Using git ls-files with filter_pkgbuild_sources instead of find for better performance

# Detect dependencies from README.md files
# Usage: detect_readme_deps
# Returns: space-separated list of dependencies found in README
detect_readme_deps() {
    local readme_deps=()
    local readme_file=""
    
    # Get exclusion words array
    local -a exclude_words
    readarray -t exclude_words <<< "$(get_exclude_words)"
    
    # Look for README files (case-insensitive)
    for readme in README.md README.txt README.rst README; do
        if [[ -f "$PROJECT_ROOT/$readme" ]]; then
            readme_file="$PROJECT_ROOT/$readme"
            break
        fi
    done
    
    if [[ -z "$readme_file" ]]; then
        return 0
    fi
    
    debug "[detect_readme_deps] Found README file: $readme_file" >&2
    
    # Extract dependencies from README content
    local content
    content=$(cat "$readme_file" 2>/dev/null || true)
    
    if [[ -z "$content" ]]; then
        return 0
    fi
    
    # Look for specific dependency patterns in the content
    # Focus on installation/requirements sections and package manager commands
    
    # Pacman -S package names. apt, yum, and brew names are not Arch packages.
    local pacman_deps
    pacman_deps=$(echo "$content" | grep -o -E 'pacman\s+-S\s+[a-zA-Z0-9_-]+(\s+[a-zA-Z0-9_-]+)*' | sed -E 's/pacman[[:space:]]+-S[[:space:]]*//' | tr ' ' '\n' | grep -v '^$' || true)
    
    # Sections that explicitly list packages. /regex/i is not a gawk flag.
    # The README awk scans run under LC_ALL=C: a Turkish LC_CTYPE makes tolower("I") a dotless i.
    local section_deps
    section_deps=$(echo "$content" | LC_ALL=C awk '
    BEGIN { in_deps_section = 0; deps = "" }
    tolower($0) ~ /^##?[[:space:]]*(installation|requirements|dependencies|prerequisites|build dependencies|make dependencies)/ { in_deps_section = 1; next }
    /^##?[[:space:]]*[^#]/ { in_deps_section = 0 }
    in_deps_section && /^\s*[-*+]\s*[a-zA-Z0-9_-]+/ { 
        gsub(/^\s*[-*+]\s*/, ""); 
        gsub(/\s*[:;].*$/, ""); 
        if ($0 ~ /^[a-zA-Z0-9_-]+$/) deps = deps " " $0 
    }
    END { print deps }
    ' | tr ' ' '\n' | grep -v '^$' || true)
    
    # 6. Backticked names on a Required: line, and on the single list line after it.
    # Optional names are not makedepends, including when that line follows Required.
    # Only inside a dependency section: an "Optional" doc-table row once pulled
    # the previous row's `lint` in as a makedepend. Every backtick on the line counts.
    local explicit_deps
    # shellcheck disable=SC2016 # literal backticks: Markdown code spans
    explicit_deps=$(echo "$content" | LC_ALL=C awk '
    tolower($0) ~ /^##?[[:space:]]*(installation|requirements|dependencies|prerequisites|build dependencies|make dependencies)/ { in_deps_section = 1; after_marker = 0; next }
    /^##?[[:space:]]*[^#]/ { in_deps_section = 0 }
    in_deps_section && (/Required/ || after_marker) && !/Optional/ { print }
    { after_marker = in_deps_section && /Required/ }
    ' | LC_ALL=C grep -oE '`[a-zA-Z0-9_-]+`' | tr -d '`' | tr '\n' ' ' || true)
    
    # 6.5. Look for AURGen's specific format: "Required: bash (v4+), getopt (GNU, from util-linux), makepkg, updpkgsums, curl, jq"
local aurgen_required_deps
aurgen_required_deps=$(echo "$content" | LC_ALL=C awk '
    BEGIN { in_required = 0; deps = "" }
    # Like step 6, a "Required:" marker counts only inside a dependency section.
    # Names on the marker line count: strip the label and parse the remainder.
    tolower($0) ~ /^##?[[:space:]]*(installation|requirements|dependencies|prerequisites|build dependencies|make dependencies)/ { in_deps_section = 1; in_required = 0; next }
    in_deps_section && /Required:/ { in_required = 1; sub(/^.*Required:[[:space:]]*/, "") }
    /Optional:/ { in_required = 0; next }
    /^##?\s*[^#]/ { in_deps_section = 0; in_required = 0; next }
    in_required && /[a-zA-Z0-9_-]+/ {
        # Extract package names from the line
        gsub(/[[:space:]]*\([^)]*\)/, "");  # Remove parenthetical descriptions
        gsub(/[[:space:]]*,[[:space:]]*/, " ");  # Replace commas with spaces
        gsub(/[[:space:]]+/, " ");  # Normalize spaces
        split($0, arr, " ");
        for (i in arr) {
            if (arr[i] ~ /^[a-zA-Z0-9_-]+$/) {
                deps = deps " " arr[i]
            }
        }
    }
    END { print deps }
    ' | tr ' ' '\n' | grep -v '^$' || true)
    
    # Install-section tool-name mentions are not scanned: they name runtime tools,
    # not makedepends, and awk gsub has no \1 backreference, so that scan only ever
    # kept a tool mentioned at the end of a line.

    # Combine all detected dependencies
    local all_deps
    all_deps=$(printf '%s\n%s\n%s\n%s' "$pacman_deps" "$section_deps" "$aurgen_required_deps" "$explicit_deps" | tr ' ' '\n' | LC_ALL=C tr '[:upper:]' '[:lower:]' | sort -u | grep -v '^$' || true)
    
    # Package names are lowercase, so "- Linux" must meet the lowercase exclusion list.
    # LC_ALL=C above keeps a Turkish locale from lowercasing I to a dotless i.
    # Filter for valid package names and add to dependencies
    while IFS= read -r dep; do
        if [[ -n "$dep" && "$dep" != -* && "$dep" =~ ^[a-zA-Z0-9_-]+$ && ${#dep} -gt 1 ]]; then
            # Check if dependency is in exclusion list
            local should_exclude=false
            for exclude_word in "${exclude_words[@]}"; do
                if [[ "$dep" == "$exclude_word" ]]; then
                    should_exclude=true
                    break
                fi
            done
            
            # Add dependency if not excluded
            if [[ "$should_exclude" == "false" ]]; then
                # Map tool names to their containing packages
                local mapped_dep
                mapped_dep=$(map_tool_to_package "$dep")
                readme_deps+=("$mapped_dep")
            fi
        fi
    done <<< "$all_deps"
    
    # Remove duplicates and return
    if (( ${#readme_deps[@]} > 0 )); then
        printf '%s\n' "${readme_deps[@]}" | sort -u | tr '\n' ' '
        debug "[detect_readme_deps] Found dependencies in README: ${readme_deps[*]}" >&2
    fi
}

# Detect makedepends based on project files
# Usage: detect_makedepends
# Returns: space-separated list of makedepends
detect_makedepends() {
    local makedepends=()
    
    # First, detect dependencies from README.md
    local readme_deps
    readme_deps=$(detect_readme_deps)
    if [[ -n "${readme_deps// }" ]]; then
        # Convert space-separated string to array
        readarray -t readme_deps_array <<< "$(echo "$readme_deps" | tr ' ' '\n')"
        makedepends+=("${readme_deps_array[@]}")
        debug "[detect_makedepends] Added README dependencies: $readme_deps" >&2
    fi
    
    # Check for CMake
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]]; then
        local mapped_cmake
        mapped_cmake=$(map_tool_to_package "cmake")
        makedepends+=("$mapped_cmake")
        local mapped_make
        mapped_make=$(map_tool_to_package "make")
        makedepends+=("$mapped_make")
    fi
    
    # Check for Makefile
    if [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        local mapped_make
        mapped_make=$(map_tool_to_package "make")
        makedepends+=("$mapped_make")
    fi
    
    # Check for Python setup.py
    if [[ -f "$PROJECT_ROOT/setup.py" ]]; then
        local mapped_setuptools
        mapped_setuptools=$(map_tool_to_package "python-setuptools")
        makedepends+=("$mapped_setuptools")
    fi
    
    # Check for package.json (Node.js)
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        local mapped_npm
        mapped_npm=$(map_tool_to_package "npm")
        makedepends+=("$mapped_npm")
    fi
    
    # Check for C++ files using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(cpp|cc|cxx|c\+\+)$' | grep . >/dev/null; then
        local mapped_gcc
        mapped_gcc=$(map_tool_to_package "gcc")
        makedepends+=("$mapped_gcc")
    fi
    
    # Check for C files using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.c$' | grep . >/dev/null; then
        local mapped_gcc
        mapped_gcc=$(map_tool_to_package "gcc")
        makedepends+=("$mapped_gcc")
    fi
    
    # Check for Rust (Cargo.toml)
    if [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        local mapped_rust
        mapped_rust=$(map_tool_to_package "rust")
        makedepends+=("$mapped_rust")
        local mapped_cargo
        mapped_cargo=$(map_tool_to_package "cargo")
        makedepends+=("$mapped_cargo")
    fi
    
    # Check for Go (go.mod)
    if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
        local mapped_go
        mapped_go=$(map_tool_to_package "go")
        makedepends+=("$mapped_go")
    fi
    
    # Check for Java (pom.xml or build.gradle)
    if [[ -f "$PROJECT_ROOT/pom.xml" ]]; then
        local mapped_maven
        mapped_maven=$(map_tool_to_package "maven")
        makedepends+=("$mapped_maven")
        local mapped_jdk
        mapped_jdk=$(map_tool_to_package "jdk-openjdk")
        makedepends+=("$mapped_jdk")
    fi
    
    if [[ -f "$PROJECT_ROOT/build.gradle" ]]; then
        local mapped_gradle
        mapped_gradle=$(map_tool_to_package "gradle")
        makedepends+=("$mapped_gradle")
        local mapped_jdk
        mapped_jdk=$(map_tool_to_package "jdk-openjdk")
        makedepends+=("$mapped_jdk")
    fi
    
    # Check for Meson
    if [[ -f "$PROJECT_ROOT/meson.build" ]]; then
        local mapped_meson
        mapped_meson=$(map_tool_to_package "meson")
        makedepends+=("$mapped_meson")
        local mapped_ninja
        mapped_ninja=$(map_tool_to_package "ninja")
        makedepends+=("$mapped_ninja")
    fi
    
    # Check for Autotools
    if [[ -f "$PROJECT_ROOT/configure.ac" ]] || [[ -f "$PROJECT_ROOT/configure.in" ]]; then
        local mapped_autoconf
        mapped_autoconf=$(map_tool_to_package "autoconf")
        makedepends+=("$mapped_autoconf")
        local mapped_automake
        mapped_automake=$(map_tool_to_package "automake")
        makedepends+=("$mapped_automake")
        local mapped_libtool
        mapped_libtool=$(map_tool_to_package "libtool")
        makedepends+=("$mapped_libtool")
        local mapped_make
        mapped_make=$(map_tool_to_package "make")
        makedepends+=("$mapped_make")
    fi
    
    # Check for qmake
    if [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] && grep -q "find_package(Qt" "$PROJECT_ROOT/CMakeLists.txt"; then
        local mapped_qt
        mapped_qt=$(map_tool_to_package "qt6-base")
        makedepends+=("$mapped_qt")
    elif git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.pro$' | grep . >/dev/null; then
        local mapped_qt
        mapped_qt=$(map_tool_to_package "qt6-base")
        makedepends+=("$mapped_qt")
    fi
    
    # Check for Vala using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.vala$' | grep . >/dev/null; then
        local mapped_vala
        mapped_vala=$(map_tool_to_package "vala")
        makedepends+=("$mapped_vala")
    fi
    
    # Check for TypeScript using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(ts|tsx)$' | grep . >/dev/null; then
        local mapped_typescript
        mapped_typescript=$(map_tool_to_package "typescript")
        makedepends+=("$mapped_typescript")
    fi
    
    # Check for SCSS/SASS using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(scss|sass)$' | grep . >/dev/null; then
        local mapped_sassc
        mapped_sassc=$(map_tool_to_package "sassc")
        makedepends+=("$mapped_sassc")
    fi
    
    # Check for pkg-config (common dependency) using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.pc\.in$' | grep . >/dev/null; then
        local mapped_pkgconf
        mapped_pkgconf=$(map_tool_to_package "pkgconf")
        makedepends+=("$mapped_pkgconf")
    fi
    
    # Check for gettext (internationalization) using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.(po|pot)$' | grep . >/dev/null; then
        local mapped_gettext
        mapped_gettext=$(map_tool_to_package "gettext")
        makedepends+=("$mapped_gettext")
    fi
    
    # Check for asciidoc documentation using filtered file list
    if git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources | grep -E '\.adoc$' | grep . >/dev/null; then
        local mapped_asciidoc
        mapped_asciidoc=$(map_tool_to_package "asciidoc")
        makedepends+=("$mapped_asciidoc")
    fi
    
    # Whole-repo greps for "gh ", "aur" and "git" matched ordinary words ("high" in a
    # LICENSE) and are not build evidence. git comes from signed-tag and git mode.

    # Remove duplicates and return
    printf '%s\n' "${makedepends[@]}" | sort -u | tr '\n' ' '
}

# Package name without a version operator, so systemd>=249 and systemd are one entry.
pkg_dep_base() {
    local dep="$1"
    dep="${dep%%>=*}"
    dep="${dep%%<=*}"
    dep="${dep%%=*}"
    dep="${dep%%>*}"
    dep="${dep%%<*}"
    printf '%s' "$dep"
}

# Interpreter token from a shebang line, or nothing.
_shebang_program() {
    local line="$1"
    local tok
    local -a toks=()
    [[ "$line" == '#!'* ]] || return 0
    line="${line#\#!}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && return 0
    read -ra toks <<< "$line"
    if [[ "${toks[0]}" == "env" || "${toks[0]}" == */env ]]; then
        for tok in "${toks[@]}"; do
            case "$tok" in
                env|*/env|-*) continue ;;
            esac
            printf '%s\n' "$tok"
            return 0
        done
        return 0
    fi
    printf '%s\n' "${toks[0]##*/}"
}

# Shebang interpreters that ship in a known package. sh is bash on Arch; the
# mapping table has no sh arm.
_interpreter_package() {
    case "$1" in
        bash) map_tool_to_package bash ;;
        sh) printf '%s\n' bash ;;
        python|python3) map_tool_to_package python3 ;;
        perl) map_tool_to_package perl ;;
        ruby) map_tool_to_package ruby ;;
        node) map_tool_to_package node ;;
    esac
}

# Package from an explicit tool-mapping.sh arm. The default arm echoes the
# tool unchanged, and a substring match would treat ip as mapped because of zip.
_resolved_package() {
    local tool="$1"
    local map_file pkg
    [[ "$tool" =~ ^[A-Za-z0-9][A-Za-z0-9_+.-]*$ ]] || return 0
    if ! declare -p _TOOL_RESOLVED >/dev/null 2>&1; then
        declare -gA _TOOL_RESOLVED=()
    fi
    if [[ -n "${_TOOL_RESOLVED[$tool]+x}" ]]; then
        pkg="${_TOOL_RESOLVED[$tool]}"
        [[ -n "$pkg" ]] && printf '%s\n' "$pkg"
        return 0
    fi
    map_file="$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"
    pkg=""
    if awk -v tool="$tool" 'BEGIN { found = 0 } $1 == tool ")" { found = 1; exit } END { exit (found ? 0 : 1) }' "$map_file"; then
        pkg="$(map_tool_to_package "$tool")"
    fi
    _TOOL_RESOLVED["$tool"]="$pkg"
    [[ -n "$pkg" ]] && printf '%s\n' "$pkg"
}

_is_python_stdlib() {
    case "$1" in
        __future__|abc|argparse|array|ast|asyncio|atexit|base64|binascii|bisect|builtins|bz2|calendar|cmath|cmd|code|codecs|collections|colorsys|compileall|concurrent|configparser|contextlib|contextvars|copy|copyreg|csv|ctypes|dataclasses|datetime|decimal|difflib|dis|doctest|email|enum|errno|faulthandler|fcntl|filecmp|fileinput|fnmatch|fractions|ftplib|functools|gc|getopt|getpass|gettext|glob|grp|gzip|hashlib|heapq|hmac|html|http|imaplib|importlib|inspect|io|ipaddress|itertools|json|keyword|linecache|locale|logging|lzma|mailbox|marshal|math|mimetypes|mmap|multiprocessing|netrc|numbers|operator|os|pathlib|pdb|pickle|pkgutil|platform|plistlib|poplib|posix|pprint|pwd|py_compile|pydoc|queue|quopri|random|re|readline|reprlib|resource|runpy|sched|secrets|select|selectors|shelve|shlex|shutil|signal|site|smtplib|socket|socketserver|sqlite3|ssl|stat|statistics|string|struct|subprocess|sys|sysconfig|syslog|tarfile|tempfile|termios|textwrap|threading|time|timeit|token|tokenize|trace|traceback|tracemalloc|tty|types|typing|unicodedata|unittest|urllib|uuid|venv|warnings|wave|weakref|webbrowser|wsgiref|xml|xmlrpc|zipfile|zipimport|zlib|zoneinfo)
            return 0
            ;;
    esac
    return 1
}

# Top-level import names, one per line.
_python_modules() {
    local file="$1"
    local line rest part
    local -a parts=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]] ]] && continue
        [[ "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^import[[:space:]]+(.*)$ ]]; then
            rest="${BASH_REMATCH[1]}"
            rest="${rest%%#*}"
            IFS=',' read -ra parts <<< "$rest"
            for part in "${parts[@]}"; do
                part="${part#"${part%%[![:space:]]*}"}"
                part="${part%%[[:space:]]*}"
                part="${part%%.*}"
                [[ "$part" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
                printf '%s\n' "$part"
            done
        elif [[ "$line" =~ ^from[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)([[:space:].]|$) ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

_is_shell_keyword() {
    case "$1" in
        if|then|else|elif|fi|for|while|until|do|done|case|"esac"|in|function|select|time|coproc|!|"{"|"}")
            return 0
            ;;
    esac
    return 1
}

# Text of one source line that is outside quotes. A single quote that stays open
# across lines hides the following lines: an embedded awk program is not a
# command list. Single-quote parity ignores double-quoted text and a
# backslash-escaped quote. $(...) stays visible in or out of double quotes, and
# backticks inside double quotes stay visible: those commands run. Quotes in the
# body use the same rules, and a double-quoted opener resumes at its closer.
_shell_visible_line() {
    local LC_ALL=C
    local -n _sq=$1
    local -n _dq=$2
    local -n _vis=$3
    # Parallel stacks: p is a $(...) opened in double quotes, u an unquoted substitution,
    # b is a backtick one in double quotes, v outside them, s a plain subshell,
    # a is arithmetic opened in double quotes.
    # _sub_case counts open `case` blocks; only a case or esac in command
    # position changes it.
    # _sub_at is 1 when the next word there is a command. _sub_cont is 1 when
    # a trailing backslash joins this line to the next.
    local -n _kind=$4
    local -n _depth=$5
    local -n _sub_case=$6
    local -n _sub_at=$7
    local -n _sub_cont=$8
    local line="$9"
    # Test and arithmetic state have a base frame and one entry per substitution or subshell.
    local -n _test=${10}
    local -n _arith=${11}
    local in_pattern=$(( ${12} > 0 && ${13} ))
    local -n _heredoc_line=${14}
    _heredoc_line="$line"
    # shellcheck disable=SC2034 # namerefs: _shell_apply_case reads and updates them
    local pattern_src pattern_dst pattern_depth pattern_pending pattern_arm
    local i c out="" esc=0
    local len=${#line}
    local opened
    local subshell_open='(^|;|\|\||\||&&|\(|!|\{)[[:space:]]*((if|elif|while|until|then|else|do)[[:space:]]+)?(![[:space:]]+)?$'
    # A newline separates commands inside $(...). A continued line does not.
    if (( ! _sq && ! _dq && ! _sub_cont && ${#_kind[@]} )); then
        if [[ "${_kind[-1]}" == p || "${_kind[-1]}" == u || "${_kind[-1]}" == s ]]; then
            _sub_at[-1]=1
        fi
    fi
    for (( i=0; i<len; i++ )); do
        c="${line:i:1}"
        if (( esc )); then
            esc=0
            if (( ! _sq && ! _dq )); then
                out+="$c"
            fi
            continue
        fi
        if (( _sq )); then
            # Inside single quotes a backslash is literal; only ' ends the string.
            if [[ "$c" == "'" ]]; then
                _sq=0
            fi
            continue
        fi
        # shellcheck disable=SC2016 # literal $(( text
        if [[ "${line:i:3}" == '$((' ]]; then
            if (( _dq )); then
                _kind+=(a)
                _test+=(0)
                _arith+=(0)
                _depth+=(0)
                _sub_case+=(0)
                _sub_at+=(0)
                _dq=0
            fi
            _arith[-1]=$((_arith[-1] + 2))
            out+=' '
            i=$((i + 2))
            continue
        fi
        if (( _dq )); then
            if [[ "$c" == "\\" ]]; then
                esc=1
                continue
            fi
            if [[ "$c" == '"' ]]; then
                _dq=0
                continue
            fi
            opened=""
            if [[ "$c" == '$' && "${line:i+1:1}" == '(' ]]; then
                out+="\$("
                i=$((i + 1))
                opened=p
            elif [[ "$c" == '`' ]]; then
                out+='`'
                opened=b
            fi
            if [[ -n "$opened" ]]; then
                _kind+=("$opened")
                _test+=(0)
                _arith+=(0)
                if [[ "$opened" == p ]]; then
                    _depth+=(1)
                else
                    _depth+=(0)
                fi
                _sub_case+=(0)
                if [[ "$opened" == b ]]; then
                    _sub_at+=(0)
                else
                    _sub_at+=(1)
                fi
                _dq=0
            fi
            continue
        fi
        if (( _arith[-1] > 0 )); then
            # Keep raw delimiter quoting, but hide arithmetic operators from heredoc scanning.
            if [[ "$c" == '<' ]]; then
                _heredoc_line="${_heredoc_line:0:i} ${_heredoc_line:i+1}"
            fi
            case "$c" in
                '(') _arith[-1]=$((_arith[-1] + 1)) ;;
                ')')
                    _arith[-1]=$((_arith[-1] - 1))
                    if (( ! _arith[-1] && ${#_kind[@]} )) && [[ "${_kind[-1]}" == a ]]; then
                        unset -v '_kind[-1]' '_test[-1]' '_arith[-1]' '_depth[-1]' '_sub_case[-1]' '_sub_at[-1]'
                        _dq=1
                    fi
                    ;;
            esac
            # shellcheck disable=SC2016 # literal $( text
            if [[ "$c" != '`' && "${line:i:2}" != '$(' ]]; then
                out+=' '
                continue
            fi
        elif [[ "${line:i:2}" == '((' ]] && (( ! _test[-1] )); then
            _arith[-1]=2
            out+=' '
            i=$((i + 1))
            continue
        fi
        if [[ "${line:i:2}" == '[[' ]]; then
            _test[-1]=1
        elif [[ "${line:i:2}" == ']]' ]] \
            && { (( i == 0 )) || [[ "${line:i-1:1}" == [[:space:]] ]]; }; then
            _test[-1]=0
        fi
        if (( _test[-1] )); then
            case "$c" in
                '|'|'('|')') out+=" "; continue ;;
            esac
        fi
        # shellcheck disable=SC2034 # namerefs: _shell_apply_case reads and updates them
        if [[ "${line:i:2}" == ';;' || "${line:i:2}" == ';&' ]] \
            || { (( in_pattern )) \
                && [[ "${line:i:4}" == 'esac' && "${line:i+4:1}" != [A-Za-z0-9_] ]] \
                && [[ "${line:0:i}" =~ $subshell_open ]]; }; then
            pattern_src="$out"
            # Include the terminator itself: after ;; a pattern follows, after esac an arm body may.
            if [[ "${line:i:4}" == 'esac' ]]; then
                pattern_src+='esac'
            else
                pattern_src+="${line:i:2}"
            fi
            pattern_depth=${12}
            pattern_pending=0
            pattern_arm=${13}
            _shell_apply_case pattern_src pattern_dst pattern_depth pattern_pending pattern_arm
            in_pattern=$(( pattern_depth > 0 && pattern_arm ))
        fi
        # Only command-position parentheses are subshells; array and test data stay literal.
        if [[ "$c" == '(' && "${line:i+1:1}" != '(' ]] \
            && { (( i == 0 )) || [[ "${line:i-1:1}" != '(' ]]; } \
            && (( ! _test[-1] && ! _arith[-1] && ! in_pattern )) && [[ "${line:0:i}" =~ $subshell_open ]]; then
            _kind+=(s)
            _test+=(0)
            _arith+=(0)
            _depth+=(1)
            _sub_case+=(0)
            _sub_at+=(1)
            out+="$c"
            continue
        fi
        [[ "$c" == ')' ]] && in_pattern=0
        if (( ${#_kind[@]} )); then
            if [[ "${_kind[-1]}" == p || "${_kind[-1]}" == u || "${_kind[-1]}" == s ]]; then
                # Command position: right after $(, or after ; && || | ( or a
                # newline, with only spaces between. An argument is not a command.
                # shortcut: case after if/then/else/do/{, an assignment prefix, or a
                # pattern ")" is not counted; upgrade when that command is a real dependency.
                if [[ "$c" == [[:space:]] ]]; then
                    :
                elif [[ "$c" == ';' || "$c" == '|' || "$c" == '(' ]]; then
                    _sub_at[-1]=1
                elif [[ "$c" == '&' && "${line:i+1:1}" == '&' ]]; then
                    _sub_at[-1]=1
                elif (( i > 0 )) && [[ "$c" == '&' && "${line:i-1:1}" == '&' ]]; then
                    _sub_at[-1]=1
                elif [[ "$c" == "\\" ]] && (( i + 1 == len )); then
                    :
                else
                    if (( _sub_at[-1] == 1 )) \
                        && { (( i == 0 )) || [[ "${line:i-1:1}" != [A-Za-z0-9_] ]]; } \
                        && { (( i + 4 == len )) || [[ "${line:i+4:1}" != [A-Za-z0-9_] ]]; }; then
                        if [[ "${line:i:4}" == "case" ]]; then
                            _sub_case[-1]=$((_sub_case[-1] + 1))
                        elif [[ "${line:i:4}" == "esac" ]] && (( _sub_case[-1] > 0 )); then
                            _sub_case[-1]=$((_sub_case[-1] - 1))
                        fi
                    fi
                    _sub_at[-1]=0
                fi
                if [[ "$c" == '(' ]]; then
                    if (( _sub_case[-1] == 0 )); then
                        _depth[-1]=$((_depth[-1] + 1))
                    fi
                    out+="$c"
                    continue
                fi
                if [[ "$c" == ')' ]]; then
                    if (( _sub_case[-1] > 0 )); then
                        out+="$c"
                        continue
                    fi
                    _depth[-1]=$((_depth[-1] - 1))
                    if (( _depth[-1] == 0 )); then
                        # p resumes the double quotes it suspended; u stays outside them.
                        if [[ "${_kind[-1]}" == p ]]; then
                            _dq=1
                        fi
                        unset -v '_kind[-1]'
                        unset -v '_test[-1]'
                        unset -v '_arith[-1]'
                        unset -v '_depth[-1]'
                        unset -v '_sub_case[-1]'
                        unset -v '_sub_at[-1]'
                        # Ends the body's segment: x"$(date)" jq runs jq, not date jq.
                        out+=";"
                    else
                        # Keep inner parentheses visible so multi-line array literals can end.
                        out+="$c"
                    fi
                    continue
                fi
            elif [[ ( "${_kind[-1]}" == b || "${_kind[-1]}" == v ) && "$c" == '`' ]]; then
                [[ "${_kind[-1]}" == b ]] && _dq=1
                unset -v '_kind[-1]'
                unset -v '_test[-1]'
                unset -v '_arith[-1]'
                unset -v '_depth[-1]'
                unset -v '_sub_case[-1]'
                unset -v '_sub_at[-1]'
                out+=";"
                continue
            fi
        fi
        if [[ "$c" == "\\" ]]; then
            esc=1
            out+="$c"
            continue
        fi
        if [[ "$c" == "'" ]]; then
            _sq=1
            continue
        fi
        if [[ "$c" == '"' ]]; then
            _dq=1
            continue
        fi
        # A comment starts only at a word start: $((10#x)) and a#b are not comments.
        if [[ "$c" == '#' ]] && { (( i == 0 )) || [[ "${line:i-1:1}" == [[:space:]\;\&\|\(] ]]; }; then
            break
        fi
        if [[ "$c" == '`' ]]; then
            out+="$c"
            _kind+=(v)
            _test+=(0)
            _arith+=(0)
            _depth+=(0)
            _sub_case+=(0)
            _sub_at+=(0)
            continue
        fi
        # Process substitutions use $( as a segment opener; each opener gets a frame.
        if [[ "${line:i+1:1}" == '(' ]] \
            && { [[ "$c" == '$' ]] \
                || { [[ "$c" == '<' || "$c" == '>' ]] && (( ! _arith[-1] && ! in_pattern )); }; }; then
            out+="\$("
            i=$((i + 1))
            _kind+=(u)
            _test+=(0)
            _arith+=(0)
            _depth+=(1)
            _sub_case+=(0)
            _sub_at+=(1)
            continue
        fi
        out+="$c"
    done
    if (( esc && ! _sq && ! _dq )); then
        _sub_cont=1
    else
        _sub_cont=0
    fi
    _vis="$out"
}

# Drop one leading case pattern from a visible line, or return the line unchanged
# when it is a command. The first ')' ends the pattern. A ')' inside quotes, $(...)
# or $((...)) does not. _shell_visible_line already rewrites the closing ')' of
# $(...) to ';'.
# shortcut: that ';' also ends the substitution, so a ';' inside $(...) does too;
# upgrade if a case pattern contains a semicolon inside $(...).
_shell_without_case_pattern() {
    local s="$1"
    local i=0 j c
    local len=${#s}
    local sub=0 sq=0 dq=0
    while (( i < len )) && [[ "${s:i:1}" == [[:space:]] ]]; do
        i=$((i + 1))
    done
    if (( i >= len )); then
        printf '%s' "$s"
        return 0
    fi
    j=$i
    if [[ "${s:j:1}" == '(' ]]; then
        j=$((j + 1))
    fi
    while (( j < len )); do
        c="${s:j:1}"
        if (( sq )); then
            [[ "$c" == "'" ]] && sq=0
            j=$((j + 1))
            continue
        fi
        if (( dq )); then
            [[ "$c" == '"' ]] && dq=0
            j=$((j + 1))
            continue
        fi
        if (( sub > 0 )); then
            if [[ "$c" == '(' ]]; then
                sub=$((sub + 1))
            elif [[ "$c" == ')' ]]; then
                sub=$((sub - 1))
            elif [[ "$c" == ';' ]]; then
                sub=0
            fi
            j=$((j + 1))
            continue
        fi
        if [[ "$c" == '$' && "${s:j+1:1}" == '(' ]]; then
            sub=$((sub + 1))
            j=$((j + 2))
            continue
        fi
        if [[ "$c" == "'" ]]; then
            sq=1
            j=$((j + 1))
            continue
        fi
        if [[ "$c" == '"' ]]; then
            dq=1
            j=$((j + 1))
            continue
        fi
        # ';;' before ')' is the next arm, not part of a leading pattern.
        if [[ "$c" == ';' && "${s:j+1:1}" == ';' ]]; then
            printf '%s' "$s"
            return 0
        fi
        if [[ "$c" == ')' ]]; then
            printf '%s' "${s:j+1}"
            return 0
        fi
        j=$((j + 1))
    done
    printf '%s' "$s"
}

# Word-bounded case/in/esac on one visible line. Patterns are removed; the
# commands after ')' stay. case_depth counts bodies opened by in, and case_arm
# marks where the next arm pattern may start (after in or ;;, ;&, ;;&).
# Called in the current shell: a command substitution would drop the depth.
_shell_apply_case() {
    local -n _src=$1
    local -n _dst=$2
    local -n _case_depth=$3
    local -n _pending=$4
    local -n _arm=$5
    local out="" rest word next
    rest="$_src"
    while [[ -n "$rest" ]]; do
        if [[ "$rest" == [[:space:]]* ]]; then
            out+="${rest:0:1}"
            rest="${rest:1}"
            continue
        fi
        if (( _case_depth > 0 && _arm )) && [[ "$rest" != 'esac'* || "${rest:4:1}" == [A-Za-z0-9_] ]]; then
            next="$(_shell_without_case_pattern "$rest")"
            if [[ "$next" != "$rest" ]]; then
                _arm=0
                rest="$next"
                continue
            fi
        fi
        if [[ "$rest" == ';;&'* ]]; then
            out+=";;"
            rest="${rest:3}"
            (( _case_depth > 0 )) && _arm=1
            continue
        fi
        if [[ "$rest" == ';;'* || "$rest" == ';&'* ]]; then
            out+=";"
            rest="${rest:2}"
            (( _case_depth > 0 )) && _arm=1
            continue
        fi
        if [[ "$rest" != [A-Za-z0-9_]* ]]; then
            _arm=0
            out+="${rest:0:1}"
            rest="${rest:1}"
            continue
        fi
        word="${rest%%[^A-Za-z0-9_]*}"
        _arm=0
        case "$word" in
            case) _pending=$((_pending + 1)) ;;
            in)
                if (( _pending > 0 )); then
                    _pending=$((_pending - 1))
                    _case_depth=$((_case_depth + 1))
                    _arm=1
                fi
                ;;
            "esac")
                if (( _case_depth > 0 )); then
                    _case_depth=$((_case_depth - 1))
                fi
                ;;
        esac
        out+="$word"
        rest="${rest:${#word}}"
    done
    _dst="$out"
}

# Heredoc delimiters opened on this raw line, outside quotes and comments.
# Quote state is the state at the start of the line. <<< is a here-string.
_shell_queue_heredocs() {
    local LC_ALL=C
    local line="$1"
    local sq="$2"
    local dq="$3"
    local -n _hd=$4
    local -n _tb=$5
    local i=0 c esc=0 tabs q delim
    local len=${#line}
    while (( i < len )); do
        c="${line:i:1}"
        if (( esc )); then
            esc=0
            i=$((i + 1))
            continue
        fi
        if (( sq )); then
            [[ "$c" == "'" ]] && sq=0
            i=$((i + 1))
            continue
        fi
        if (( dq )); then
            if [[ "$c" == "\\" ]]; then
                esc=1
                i=$((i + 1))
                continue
            fi
            if [[ "$c" == '"' ]]; then
                dq=0
            fi
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == "\\" ]]; then
            esc=1
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == "'" ]]; then
            sq=1
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == '"' ]]; then
            dq=1
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == '#' ]]; then
            break
        fi
        if [[ "$c" == '<' && "${line:i+1:1}" == '<' ]]; then
            if [[ "${line:i+2:1}" == '<' ]]; then
                i=$((i + 3))
                continue
            fi
            tabs=0
            q=""
            delim=""
            i=$((i + 2))
            if [[ "${line:i:1}" == '-' ]]; then
                tabs=1
                i=$((i + 1))
            fi
            while (( i < len )) && [[ "${line:i:1}" == [[:space:]] ]]; do
                i=$((i + 1))
            done
            if [[ "${line:i:1}" == "'" || "${line:i:1}" == '"' ]]; then
                q="${line:i:1}"
                i=$((i + 1))
            elif [[ "${line:i:1}" == "\\" ]]; then
                i=$((i + 1))
            fi
            if [[ -n "$q" ]]; then
                while (( i < len )); do
                    c="${line:i:1}"
                    [[ "$c" == "$q" ]] && break
                    delim+="$c"
                    i=$((i + 1))
                done
            else
                while (( i < len )); do
                    c="${line:i:1}"
                    [[ "$c" =~ [A-Za-z0-9_.-] ]] || break
                    delim+="$c"
                    i=$((i + 1))
                done
            fi
            if [[ -n "$q" && "${line:i:1}" == "$q" ]]; then
                i=$((i + 1))
            fi
            if [[ -n "$delim" ]]; then
                _hd+=("$delim")
                _tb+=("$tabs")
            fi
            continue
        fi
        i=$((i + 1))
    done
}

_shell_visible_lines() {
    local file="$1"
    # namerefs: _shell_visible_line updates quote and substitution state here.
    # shellcheck disable=SC2034
    local line in_sq=0 in_dq=0 visible heredoc_line
    # shellcheck disable=SC2034
    local -a sub_kind=() sub_depth=() sub_case=() sub_at=() in_test=(0) in_arith=(0)
    # shellcheck disable=SC2034
    local sub_cont=0
    local -a hd_delim=() hd_tabs=()
    # shellcheck disable=SC2034 # namerefs: _shell_apply_case updates them
    local case_depth=0 case_pending=0 case_arm=0
    local sq0 dq0 cmp filtered in_array=0
    local array_open='[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=\([^)]*$'
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( ${#hd_delim[@]} )); then
            cmp="$line"
            if [[ "${hd_tabs[0]}" == 1 ]]; then
                cmp="${cmp#"${cmp%%[!$'\t']*}"}"
            fi
            if [[ "$cmp" == "${hd_delim[0]}" ]]; then
                if (( ${#hd_delim[@]} > 1 )); then
                    hd_delim=("${hd_delim[@]:1}")
                    hd_tabs=("${hd_tabs[@]:1}")
                else
                    hd_delim=()
                    hd_tabs=()
                fi
            fi
            # shortcut: an unquoted delimiter hides the body whole, so $(...) in it is not a command; upgrade when here-document expansions must be scanned.
            continue
        fi
        sq0=$in_sq
        dq0=$in_dq
        _shell_visible_line in_sq in_dq visible sub_kind sub_depth sub_case sub_at sub_cont "$line" in_test in_arith "$case_depth" "$case_arm" heredoc_line
        _shell_apply_case visible filtered case_depth case_pending case_arm
        _shell_queue_heredocs "$heredoc_line" "$sq0" "$dq0" hd_delim hd_tabs
        # Elements of a multi-line array literal are data: `linux gnu unix` is not a command.
        # shortcut: a $(...) element of such an array is hidden too; upgrade if one must be scanned.
        if (( in_array )); then
            [[ "$filtered" == *')'* ]] && in_array=0
            printf '\n'
            continue
        fi
        if [[ "$filtered" =~ $array_open ]]; then
            in_array=1
            filtered="${filtered%"${BASH_REMATCH[0]}"}"
        fi
        printf '%s\n' "$filtered"
    done < "$file"
}

_shell_segments_of() {
    local line="$1"
    line="${line//$'\t'/ }"
    line="${line//||/$'\n'}"
    line="${line//&&/$'\n'}"
    line="${line//;/$'\n'}"
    line="${line//|/$'\n'}"
    line="${line//\`/$'\n'}"
    line="${line//\$\(/$'\n'}"
    printf '%s\n' "$line"
}

# Assignments, keywords, exec and its options, and one leading "(" removed, so the first word is the command.
_shell_command_text() {
    local segment="$1"
    local word
    segment="${segment#"${segment%%[![:space:]]*}"}"
    [[ -z "$segment" ]] && return 0
    while true; do
        if [[ "$segment" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.+)$ ]]; then
            segment="${BASH_REMATCH[1]}"
            segment="${segment#"${segment%%[![:space:]]*}"}"
            [[ -z "$segment" ]] && return 0
            continue
        fi
        # One "(" opens a subshell (cd dir && tar xf a.tar). "((" stays arithmetic.
        if [[ "$segment" == '('* && "$segment" != '(('* ]]; then
            segment="${segment:1}"
            segment="${segment#"${segment%%[![:space:]]*}"}"
            [[ -z "$segment" ]] && return 0
            continue
        fi
        word="${segment%%[[:space:]]*}"
        # The word after for/select is a loop variable (for file in ...), never a command.
        case "$word" in
            for|select) return 0 ;;
        esac
        # exec replaces the shell. Skip it and -a NAME, -c, -l, and -- so the next
        # word is the command. A redirection-only exec runs nothing new.
        if [[ "$word" == exec ]]; then
            segment="${segment#"$word"}"
            segment="${segment#"${segment%%[![:space:]]*}"}"
            while [[ -n "$segment" ]]; do
                word="${segment%%[[:space:]]*}"
                case "$word" in
                    -c|-l|-cl|-lc)
                        segment="${segment#"$word"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        ;;
                    -a)
                        segment="${segment#"$word"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        [[ -z "$segment" ]] && return 0
                        segment="${segment#"${segment%%[[:space:]]*}"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        ;;
                    --)
                        segment="${segment#"$word"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        break
                        ;;
                    *)
                        break
                        ;;
                esac
            done
            [[ -z "$segment" ]] && return 0
            word="${segment%%[[:space:]]*}"
            case "$word" in
                *">"*|*"<"*) return 0 ;;
            esac
            break
        fi
        _is_shell_keyword "$word" || break
        segment="${segment#"$word"}"
        segment="${segment#"${segment%%[![:space:]]*}"}"
        [[ -z "$segment" ]] && return 0
    done
    printf '%s\n' "$segment"
}

_shell_walk_segments() {
    local file="$1"
    local line segment
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]}" ]] && continue
        while IFS= read -r segment || [[ -n "$segment" ]]; do
            [[ -z "$segment" ]] && continue
            printf '%s\n' "$segment"
        done < <(_shell_segments_of "$line")
    done < <(_shell_visible_lines "$file")
}

# Command names in command position, one per line.
_shell_commands() {
    local file="$1"
    local segment text word
    while IFS= read -r segment || [[ -n "$segment" ]]; do
        text="$(_shell_command_text "$segment")"
        [[ -z "$text" ]] && continue
        word="${text%%[[:space:]]*}"
        case "$word" in
            ''|-*) continue ;;
            *[!A-Za-z0-9._+-]*) continue ;;
        esac
        printf '%s\n' "$word"
    done < <(_shell_walk_segments "$file")
}

# Arguments of presence checks. Those tools are optional, not hard depends.
_shell_guarded_commands() {
    local file="$1"
    local segment text word
    while IFS= read -r segment || [[ -n "$segment" ]]; do
        text="$(_shell_command_text "$segment")"
        [[ -z "$text" ]] && continue
        word="${text%%[[:space:]]*}"
        case "$word" in
            command)
                text="${text#"$word"}"
                text="${text#"${text%%[![:space:]]*}"}"
                [[ "$text" == -v || "$text" == -v[[:space:]]* ]] || continue
                text="${text#-v}"
                text="${text#"${text%%[![:space:]]*}"}"
                word="${text%%[[:space:]]*}"
                [[ "$word" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || continue
                printf '%s\n' "$word"
                ;;
            type)
                text="${text#"$word"}"
                text="${text#"${text%%[![:space:]]*}"}"
                # -p is the usual spelling; -P and -a are the same presence check.
                case "$text" in
                    -p|-p[[:space:]]*|-P|-P[[:space:]]*|-a|-a[[:space:]]*)
                        text="${text:2}"
                        ;;
                    *) continue ;;
                esac
                text="${text#"${text%%[![:space:]]*}"}"
                while [[ -n "$text" ]]; do
                    word="${text%%[[:space:]]*}"
                    case "$word" in
                        -*|*[!A-Za-z0-9._+-]*) break ;;
                    esac
                    printf '%s\n' "$word"
                    text="${text#"$word"}"
                    text="${text#"${text%%[![:space:]]*}"}"
                done
                ;;
            hash|which)
                text="${text#"$word"}"
                text="${text#"${text%%[![:space:]]*}"}"
                while [[ -n "$text" ]]; do
                    word="${text%%[[:space:]]*}"
                    case "$word" in
                        -*|*[!A-Za-z0-9._+-]*) break ;;
                    esac
                    printf '%s\n' "$word"
                    text="${text#"$word"}"
                    text="${text#"${text%%[![:space:]]*}"}"
                done
                ;;
        esac
    done < <(_shell_walk_segments "$file")
}

# make install runs in a copy so the project tree is never the DESTDIR.
_runtime_install_cleanup() {
    local status=$?
    if [[ "${_RUNTIME_WORKTREE:-0}" == 1 && -n "${_RUNTIME_COPY:-}" ]]; then
        git -C "$PROJECT_ROOT" worktree remove --force "$_RUNTIME_COPY/src" >/dev/null 2>&1 || true
    fi
    if [[ -n "${_RUNTIME_COPY:-}" ]]; then
        rm -rf "$_RUNTIME_COPY"
    fi
    if [[ -n "${_RUNTIME_DEST:-}" ]]; then
        rm -rf "$_RUNTIME_DEST"
    fi
    _RUNTIME_COPY=""
    _RUNTIME_DEST=""
    _RUNTIME_WORKTREE=0
    exit "$status"
}

# The copy goes to <private mktemp dir>/src. That dir is never deleted and re-created,
# so no other user can slip a symlink into the path between the two steps.
_runtime_project_copy() {
    local dest="$1/src"
    if git -C "$PROJECT_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
        mkdir "$dest" || return 1
        if git -C "$PROJECT_ROOT" archive --format=tar HEAD 2>/dev/null | tar -x -C "$dest" 2>/dev/null; then
            return 0
        fi
        rm -rf "$dest"
    fi
    if git -C "$PROJECT_ROOT" worktree add --detach "$dest" HEAD >/dev/null 2>&1; then
        _RUNTIME_WORKTREE=1
        return 0
    fi
    return 1
}

_runtime_try_install() {
    local makefile="$PROJECT_ROOT/Makefile"
    local install_var path
    local -a make_args=()
    [[ -f "$makefile" ]] || return 1
    grep -E -q '^install:' "$makefile" || return 1
    # The project's Makefile runs at generation time, outside makepkg and fakeroot. Run it
    # only in a bubblewrap sandbox: read-only root, writable copy and DESTDIR, no network.
    if ! command -v bwrap >/dev/null 2>&1; then
        warn "[detect_runtime_deps] bwrap not found; skipping make install scan (install bubblewrap to enable it)" >&2
        return 1
    fi
    _RUNTIME_COPY="$(mktemp -d -t aurgen-rtdep-copy.XXXXXX)"
    _RUNTIME_DEST="$(mktemp -d -t aurgen-rtdep-dest.XXXXXX)"
    _RUNTIME_WORKTREE=0
    _runtime_project_copy "$_RUNTIME_COPY" || return 1
    make_args=(install "DESTDIR=$_RUNTIME_DEST" PREFIX=/usr)
    if declare -p PKG_INSTALL_VARS >/dev/null 2>&1; then
        for install_var in "${PKG_INSTALL_VARS[@]}"; do
            [[ -z "$install_var" ]] && continue
            if [[ ! "$install_var" =~ ^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._/+-]+$ ]]; then
                warn "[detect_runtime_deps] skipping unsafe install variable" >&2
                continue
            fi
            make_args+=("$install_var")
        done
    fi
    # stdout would be captured as the depends list.
    # unshare-all: no network, and a PID namespace so nothing make starts outlives it.
    # new-session blocks terminal input injection. /run is masked because a read-only
    # bind still lets a process connect to D-Bus sockets there and run code outside.
    if ! bwrap --unshare-all --new-session --die-with-parent \
            --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run \
            --bind "$_RUNTIME_COPY" "$_RUNTIME_COPY" --bind "$_RUNTIME_DEST" "$_RUNTIME_DEST" \
            make -C "$_RUNTIME_COPY/src" "${make_args[@]}" >/dev/null; then
        warn "[detect_runtime_deps] make install failed" >&2
        return 1
    fi
    while IFS= read -r path; do
        [[ -n "$path" ]] && _RUNTIME_FILES+=("$path")
    done < <(find "$_RUNTIME_DEST" -type f -print)
    return 0
}

# Copy-rule sources are what package() installs when there is no install target.
_runtime_fill_copy_rules() {
    local rule src excludes exclude abs path
    local found=0
    local -a rules=() exclude_array=() find_cmd=()
    declare -F get_copy_directories >/dev/null 2>&1 || return 1
    mapfile -t rules < <(get_copy_directories)
    (( ${#rules[@]} )) || return 1
    for rule in "${rules[@]}"; do
        [[ -z "$rule" ]] && continue
        IFS=':' read -r src _ _ excludes <<< "$rule"
        [[ -n "$src" && -d "$PROJECT_ROOT/$src" ]] || continue
        found=1
        abs="$PROJECT_ROOT/$src"
        find_cmd=(find "$abs" -type f)
        if [[ -n "${excludes:-}" ]]; then
            IFS=',' read -ra exclude_array <<< "$excludes"
            for exclude in "${exclude_array[@]}"; do
                exclude="${exclude#"${exclude%%[![:space:]]*}"}"
                exclude="${exclude%"${exclude##*[![:space:]]}"}"
                [[ -z "$exclude" ]] && continue
                find_cmd+=(-not -path "$abs/$exclude/*")
            done
        fi
        find_cmd+=(-print)
        while IFS= read -r path; do
            [[ -n "$path" ]] && _RUNTIME_FILES+=("$path")
        done < <("${find_cmd[@]}")
    done
    (( found ))
}

_runtime_fill_tracked() {
    local file
    declare -F filter_pkgbuild_sources >/dev/null 2>&1 || return 1
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        case "$file" in
            tests/*|test/*|doc/*|docs/*) continue ;;
        esac
        [[ -f "$PROJECT_ROOT/$file" && -r "$PROJECT_ROOT/$file" ]] || continue
        _RUNTIME_FILES+=("$PROJECT_ROOT/$file")
    done < <(git -C "$PROJECT_ROOT" ls-files | filter_pkgbuild_sources)
}

_runtime_collect_files() {
    _RUNTIME_FILES=()
    if _runtime_try_install; then
        warn "[detect_runtime_deps] source: installed files" >&2
        return 0
    fi
    _RUNTIME_FILES=()
    if _runtime_fill_copy_rules; then
        warn "[detect_runtime_deps] source: copy rules" >&2
        return 0
    fi
    _RUNTIME_FILES=()
    warn "[detect_runtime_deps] source: tracked files" >&2
    _runtime_fill_tracked
}

_runtime_systemd_units() {
    local path unit scope kind
    local -a timers=() services=()
    [[ -n "${_RUNTIME_DEST:-}" ]] || return 0
    for path in "${_RUNTIME_FILES[@]}"; do
        unit="${path#"$_RUNTIME_DEST/"}"
        case "$unit" in
            usr/lib/systemd/system/*) scope=system; unit="${unit#usr/lib/systemd/system/}" ;;
            usr/lib/systemd/user/*) scope=user; unit="${unit#usr/lib/systemd/user/}" ;;
            *) continue ;;
        esac
        [[ "$unit" != */* ]] || continue
        kind="${unit##*.}"
        case "$kind" in
            timer) timers+=("$scope:$unit") ;;
            service) services+=("$scope:$unit") ;;
        esac
    done
    if (( ${#timers[@]} )); then
        printf '%s\n' "${timers[@]}" | sort -u
    elif (( ${#services[@]} )); then
        printf '%s\n' "${services[@]}" | sort -u
    fi
}

_runtime_script_kind() {
    local path="$1"
    local first="" prog="" kind=""
    IFS= read -r first < "$path" || true
    prog="$(_shebang_program "$first")"
    case "$prog" in
        bash|sh) kind=shell ;;
        python|python3) kind=python ;;
    esac
    case "$path" in
        *.sh|*.bash)
            [[ -z "$kind" ]] && kind=shell
            ;;
        *.py)
            kind=python
            ;;
    esac
    printf '%s\n' "$kind"
}

# depends for shipped scripts: shebang interpreter, mapped shell commands, and
# python-<module> only when that name is in the mapping table. An install
# target is scanned from the files it installs; otherwise copy-rule sources;
# otherwise tracked files except tests/, test/, doc/ and docs/. Commands named
# by command -v, type -p, type -P, type -a, hash or which in the same script
# are optdepends suggestions. Configured PKG_DEPENDS win on the same base
# name, and a detected package named in PKG_OPTDEPENDS is left out.
# Space-separated, empty when there is nothing to emit.
_detect_runtime_deps_impl() {
    local -a detected=()
    local -a merged=()
    local -A seen=()
    local -A merged_base=()
    local -A guarded=()
    local -A file_guarded=()
    local path first prog kind pkg cmd mod base cfg

    trap _runtime_install_cleanup EXIT
    _RUNTIME_COPY=""
    _RUNTIME_DEST=""
    _RUNTIME_WORKTREE=0
    _runtime_collect_files

    for path in "${_RUNTIME_FILES[@]}"; do
        [[ -f "$path" && -r "$path" ]] || continue
        [[ "$(_runtime_script_kind "$path")" == shell ]] || continue
        while IFS= read -r cmd; do
            [[ -n "$cmd" ]] && guarded["$cmd"]=1
        done < <(_shell_guarded_commands "$path")
    done
    # A package the config lists in optdepends stays optional: it is neither
    # suggested again nor added to depends below.
    local -A optional=()
    if declare -p PKG_OPTDEPENDS >/dev/null 2>&1; then
        for cfg in "${PKG_OPTDEPENDS[@]}"; do
            [[ -n "$cfg" ]] && optional["$(pkg_dep_base "${cfg%%:*}")"]=1
        done
    fi
    for cmd in "${!guarded[@]}"; do
        pkg="$(_resolved_package "$cmd")"
        [[ -z "$pkg" || -n "${optional[$(pkg_dep_base "$pkg")]:-}" ]] && continue
        warn "[detect_runtime_deps] optdepends suggestion: $pkg $cmd" >&2
    done

    for path in "${_RUNTIME_FILES[@]}"; do
        [[ -f "$path" && -r "$path" ]] || continue
        first=""
        IFS= read -r first < "$path" || true
        prog="$(_shebang_program "$first")"
        kind="$(_runtime_script_kind "$path")"
        if [[ -n "$prog" ]]; then
            pkg="$(_interpreter_package "$prog")"
            if [[ -n "$pkg" && -z "${seen[$pkg]:-}" ]]; then
                seen["$pkg"]=1
                detected+=("$pkg")
            fi
        fi
        if [[ "$kind" == shell ]]; then
            # A guard covers this file only. The union above is the suggestion list.
            file_guarded=()
            while IFS= read -r cmd; do
                [[ -n "$cmd" ]] && file_guarded["$cmd"]=1
            done < <(_shell_guarded_commands "$path")
            while IFS= read -r cmd; do
                [[ -z "$cmd" ]] && continue
                if [[ -n "${file_guarded[$cmd]:-}" ]]; then
                    continue
                fi
                pkg="$(_resolved_package "$cmd")"
                [[ -z "$pkg" || -n "${seen[$pkg]:-}" ]] && continue
                seen["$pkg"]=1
                detected+=("$pkg")
            done < <(_shell_commands "$path")
        elif [[ "$kind" == python ]]; then
            while IFS= read -r mod; do
                [[ -z "$mod" ]] && continue
                _is_python_stdlib "$mod" && continue
                pkg="$(_resolved_package "python-$mod")"
                [[ -z "$pkg" || -n "${seen[$pkg]:-}" ]] && continue
                seen["$pkg"]=1
                detected+=("$pkg")
            done < <(_python_modules "$path")
        fi
    done

    if declare -p PKG_DEPENDS >/dev/null 2>&1; then
        for cfg in "${PKG_DEPENDS[@]}"; do
            [[ -z "$cfg" ]] && continue
            base="$(pkg_dep_base "$cfg")"
            [[ -z "$base" || -n "${merged_base[$base]:-}" ]] && continue
            merged_base["$base"]=1
            merged+=("$cfg")
        done
    fi
    if (( ${#detected[@]} )); then
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            base="$(pkg_dep_base "$pkg")"
            [[ -n "${merged_base[$base]:-}" || -n "${optional[$base]:-}" ]] && continue
            merged_base["$base"]=1
            merged+=("$pkg")
        done < <(printf '%s\n' "${detected[@]}" | sort -u)
    fi
    if (( ${#merged[@]} )); then
        printf '%s\n' "${merged[@]}" | tr '\n' ' '
    fi
    if [[ "${1:-}" == --units ]]; then
        printf '\n'
        _runtime_systemd_units
    fi
}

detect_runtime_deps() {
    local result status=0
    # The install tree lives in this subshell so its EXIT trap cannot replace the caller's.
    result="$(_detect_runtime_deps_impl "$@")" || status=$?
    printf '%s' "$result"
    return "$status"
}
