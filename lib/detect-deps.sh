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

# Source shell command scanner functions
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/shell-scan.sh"

# Configuration
# Note: Using git ls-files with filter_pkgbuild_sources instead of find for better performance

# Detect dependencies from README.md files
# Usage: detect_readme_deps
# Returns: space-separated list of dependencies found in README
detect_readme_deps() {
    local -x LC_ALL=C
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
    local -x LC_ALL=C
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
    local -x LC_ALL=C
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
    local LC_ALL=C
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
    local work="$1"
    local dest="$work/src"
    local rel raw_list="$work/raw.nul" list_file="$work/tracked.nul"
    mkdir "$dest" || return 1
    if command -v git >/dev/null 2>&1 \
            && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
            && git -c core.quotePath=false -C "$PROJECT_ROOT" ls-files -z > "$raw_list" 2>/dev/null; then
        : >| "$list_file"
        while IFS= read -r -d '' rel; do
            [[ -n "$rel" ]] || continue
            if [[ -e "$PROJECT_ROOT/$rel" || -L "$PROJECT_ROOT/$rel" ]]; then
                printf '%s\0' "$rel" >> "$list_file"
            fi
        done < "$raw_list"
        rm -f -- "$raw_list"
        if [[ ! -s "$list_file" ]]; then
            rm -f -- "$list_file"
            return 0
        fi
        if tar -C "$PROJECT_ROOT" --null --verbatim-files-from -T "$list_file" -cf - 2>/dev/null \
                | tar -C "$dest" -xf - 2>/dev/null; then
            rm -f -- "$list_file"
            return 0
        fi
        rm -f -- "$list_file"
        return 1
    fi
    rm -f -- "$raw_list"
    if tar -C "$PROJECT_ROOT" --exclude=.git --exclude=aur -cf - . 2>/dev/null \
            | tar -C "$dest" -xf - 2>/dev/null; then
        return 0
    fi
    return 1
}

_runtime_bwrap_usable() {
    bwrap --unshare-all --new-session --die-with-parent \
        --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run \
        true >/dev/null 2>&1
}

_runtime_try_install() {
    local -x LC_ALL=C
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
    if ! _runtime_bwrap_usable; then
        warn "[detect_runtime_deps] bwrap sandbox unavailable; skipping make install scan" >&2
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
    local -x LC_ALL=C
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
