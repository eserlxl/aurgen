#!/bin/bash
# AURGen config mode
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Configuration management mode for AURGen

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# shellcheck source=lib/config.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/config.sh"
# shellcheck source=lib/config-import.sh
# shellcheck disable=SC1091
. "$LIB_INSTALL_DIR/config-import.sh"

# One parsed scalar. Empty means the key was absent, so generation will not use it.
_config_print_scalar() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
        printf '%s: %s\n' "$key" "$value"
    fi
}

# One parsed list, in the order the YAML reader stored it.
_config_print_list() {
    local key="$1"
    shift
    local item
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    printf '%s:\n' "$key"
    for item in "$@"; do
        printf '  - %s\n' "$item"
    done
}

# Package fields as parse_yaml_config stored them, then copy rules as generation emits them.
# shellcheck disable=SC2154 # PKG_* are set by parse_yaml_config
_config_show_effective() {
    local -a copy_rules=()
    local copy_rules_output
    load_aurgen_config || return 1
    copy_rules_output=$(get_copy_directories) || return 1
    if [[ -n "$copy_rules_output" ]]; then
        mapfile -t copy_rules <<< "$copy_rules_output"
    fi
    _config_print_scalar name "$PKG_NAME"
    _config_print_scalar description "$PKG_DESCRIPTION"
    _config_print_scalar url "$PKG_URL"
    _config_print_scalar epoch "$PKG_EPOCH"
    _config_print_scalar install "$PKG_INSTALL"
    _config_print_scalar check "$PKG_CHECK"
    _config_print_scalar source "$PKG_SOURCE"
    _config_print_scalar gpg_key "$PKG_GPG_KEY"
    _config_print_list arch "${PKG_ARCH[@]}"
    _config_print_list depends "${PKG_DEPENDS[@]}"
    _config_print_list optdepends "${PKG_OPTDEPENDS[@]}"
    _config_print_list makedepends "${PKG_MAKEDEPENDS[@]}"
    _config_print_list checkdepends "${PKG_CHECKDEPENDS[@]}"
    _config_print_list conflicts "${PKG_CONFLICTS[@]}"
    _config_print_list provides "${PKG_PROVIDES[@]}"
    _config_print_list replaces "${PKG_REPLACES[@]}"
    _config_print_list options "${PKG_OPTIONS[@]}"
    _config_print_list backup "${PKG_BACKUP[@]}"
    _config_print_list install_vars "${PKG_INSTALL_VARS[@]}"
    _config_print_list keep "${PKG_KEEP[@]}"
    _config_print_list license "${PKG_LICENSE[@]}"
    _config_print_list post_package "${PKG_POST_PACKAGE[@]}"
    if (( ${#PKG_POST_INSTALL[@]} + ${#PKG_POST_UPGRADE[@]} + ${#PKG_PRE_REMOVE[@]} )); then
        printf 'install_messages:\n'
        _config_print_list post_install "${PKG_POST_INSTALL[@]}" | sed 's/^/  /'
        _config_print_list post_upgrade "${PKG_POST_UPGRADE[@]}" | sed 's/^/  /'
        _config_print_list pre_remove "${PKG_PRE_REMOVE[@]}" | sed 's/^/  /'
    fi
    _config_print_list copy "${copy_rules[@]}"
    # Where aur-init clones and whether aur-deploy pushes, after defaults.
    # shellcheck disable=SC1091
    . "$LIB_INSTALL_DIR/aur-integration.sh"
    load_aur_integration_config || return 1
    printf 'aur_integration:\n'
    {
        _config_print_scalar aur_repo_dir "$AUR_REPO_DIR"
        _config_print_scalar auto_push "$AUR_AUTO_PUSH"
        _config_print_scalar validate_before_push "$AUR_VALIDATE_BEFORE_PUSH"
        _config_print_scalar commit_message "$AUR_COMMIT_MESSAGE"
        _config_print_scalar ssh_key "$AUR_SSH_KEY"
        _config_print_scalar git_user_name "$AUR_GIT_USER_NAME"
        _config_print_scalar git_user_email "$AUR_GIT_USER_EMAIL"
    } | sed 's/^/  /'
}

# Resolve configured EDITOR (supporting command flags) or fallback to nano/vim/vi.
_config_resolve_editor() {
    local -n _config_resolve_out="$1"
    _config_resolve_out=()
    if [[ -n "${EDITOR:-}" ]]; then
        if command -v "$EDITOR" >/dev/null 2>&1; then
            _config_resolve_out=("$EDITOR")
            return 0
        fi
        local -a _split_cmd=()
        IFS=$' \t' read -r -a _split_cmd <<< "$EDITOR" || true
        if (( ${#_split_cmd[@]} > 0 )) && command -v "${_split_cmd[0]}" >/dev/null 2>&1; then
            _config_resolve_out=("${_split_cmd[@]}")
            return 0
        fi
    fi

    local candidate
    for candidate in nano vim vi; do
        if command -v "$candidate" >/dev/null 2>&1; then
            _config_resolve_out=("$candidate")
            return 0
        fi
    done

    echo -e "${RED}[config] Error: No suitable editor found. Please set EDITOR environment variable or install nano/vim.${RESET}" >&2
    return 1
}

# Run configured EDITOR (supporting command flags) or fall back to nano/vim/vi.
_config_open_editor() {
    local config_file="$1"
    local -a _resolved_editor=()
    _config_resolve_editor _resolved_editor || return 1
    "${_resolved_editor[@]}" "$config_file"
}

_config_validate_file() {
    local cfg="$1"
    if [[ ! -f "$cfg" || ! -r "$cfg" ]]; then
        err "[config] Configuration file is missing or unreadable: $cfg"
        return 1
    fi
    (
        local lib_dir="${LIB_INSTALL_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}"
        # shellcheck disable=SC1091
        . "$lib_dir/aur-integration.sh"
        # shellcheck disable=SC2329 # Invoked indirectly by load_aur_integration_config
        aurgen_config_file() { printf '%s\n' "$cfg"; }
        load_aurgen_config "$cfg" >/dev/null \
            && get_copy_directories >/dev/null \
            && load_aur_integration_config >/dev/null
    )
}

_config_edit_file() {
    local config_file="$1"
    local -a _edit_cmd=()
    _config_resolve_editor _edit_cmd || return 1

    local was_new=0 backup_file="" editor_rc=0

    if [[ -f "$config_file" ]]; then
        backup_file=$(mktemp "${TMPDIR:-/tmp}/aurgen-config-edit.XXXXXX") || return 1
        if ! cp -p -- "$config_file" "$backup_file"; then
            rm -f -- "$backup_file"
            return 1
        fi
        echo -e "${CYAN}[config] Opening configuration file: $config_file${RESET}" >&2
    else
        was_new=1
        echo -e "${YELLOW}[config] No configuration file found. Generating default configuration...${RESET}" >&2
        if ! generate_default_config "$config_file"; then
            return 1
        fi
        echo -e "${CYAN}[config] Opening newly generated configuration file...${RESET}" >&2
    fi

    "${_edit_cmd[@]}" "$config_file" || editor_rc=$?
    if (( editor_rc != 0 )); then
        if (( was_new )); then
            rm -f -- "$config_file"
            err "[config] Editor exited with status $editor_rc; restored configuration state"
        elif [[ -n "$backup_file" && -f "$backup_file" ]]; then
            if cp -f -- "$backup_file" "$config_file" 2>/dev/null; then
                rm -f -- "$backup_file"
                err "[config] Editor exited with status $editor_rc; restored configuration state"
            else
                err "[config] Editor exited with status $editor_rc; failed to restore $config_file (backup kept at $backup_file)"
            fi
        else
            err "[config] Editor exited with status $editor_rc; restored configuration state"
        fi
        return 1
    fi

    if (( ! was_new )) && [[ -n "$backup_file" ]] && cmp -s "$backup_file" "$config_file"; then
        rm -f -- "$backup_file"
        return 0
    fi

    if _config_validate_file "$config_file"; then
        [[ -n "$backup_file" ]] && rm -f -- "$backup_file"
        return 0
    fi

    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/aurgen"
    local stamp base_name recovery_src="" recovery_path=""
    stamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf '%s' "${BASHPID:-$$}")
    base_name="${config_file##*/}"
    if (( was_new )); then
        recovery_src="$config_file"
    else
        recovery_src="$backup_file"
    fi
    if [[ -n "$recovery_src" && -f "$recovery_src" ]] && mkdir -p "$state_dir" 2>/dev/null; then
        recovery_path="$state_dir/${base_name}.recovery.${stamp}.${BASHPID:-$$}"
        if cp -p -- "$recovery_src" "$recovery_path" 2>/dev/null; then
            warn "[config] Saved configuration recovery backup to: $recovery_path" >&2
        else
            recovery_path=""
        fi
    fi

    local keep_backup=0
    if (( ! was_new )) && [[ -n "$backup_file" && -f "$backup_file" ]]; then
        local restore_choice=""
        prompt "Edited configuration is invalid. Restore pre-edit backup? [y/N]: " restore_choice n
        case "$restore_choice" in
            [yY]|[yY][eE][sS])
                if cp -f -- "$backup_file" "$config_file" 2>/dev/null; then
                    warn "[config] Restored pre-edit configuration to $config_file" >&2
                else
                    keep_backup=1
                    err "[config] Failed to restore pre-edit configuration to $config_file (backup kept at $backup_file)"
                fi
                ;;
            *)
                err "[config] Edited configuration failed validation; kept edited file at $config_file"
                ;;
        esac
    else
        err "[config] Edited configuration failed validation at $config_file"
    fi

    if (( ! keep_backup )) && [[ -n "$backup_file" ]]; then
        rm -f -- "$backup_file"
    fi
    return 1
}

_config_source_gen_helpers() {
    if ! declare -F detect_project_version >/dev/null 2>&1; then
        local lib_dir="${LIB_INSTALL_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}"
        # shellcheck source=../gen-pkgbuild0.sh
        # shellcheck disable=SC1091
        . "$lib_dir/gen-pkgbuild0.sh"
    fi
}

# Collect repo-detected metadata, dependencies, build layout, and config status.
# Optional arg: 1 to allow an unset/not-yet-created AURGEN_CONFIG_FILE (for config init).
# Sets _CFG_DETECT_* variables for _config_print_detect and mode_config init.
_config_collect_detected() {
    local allow_missing_cfg="${1:-0}"
    _CFG_DETECT_PKGNAME=""
    _CFG_DETECT_CONFIG_FILE=""
    _CFG_DETECT_CONFIG_EXISTS=0
    _CFG_DETECT_AUR_PKGBUILD="absent"
    _CFG_DETECT_VERSION=""
    _CFG_DETECT_VERSION_SOURCE=""
    _CFG_DETECT_DESCRIPTION=""
    _CFG_DETECT_DESCRIPTION_SOURCE=""
    _CFG_DETECT_CONFIGURED_DESCRIPTION=""
    _CFG_DETECT_LICENSE=""
    _CFG_DETECT_LICENSE_FOUND=0
    _CFG_DETECT_LICENSE_FILE=""
    _CFG_DETECT_CONFIGURED_LICENSE=""
    _CFG_DETECT_BUILD_SYSTEM="none"
    _CFG_DETECT_INSTALL_MODE="copy-rules"
    _CFG_DETECT_DETECTED_ARCH="any"
    _CFG_DETECT_ARCH=""
    _CFG_DETECT_ARCH_SOURCE=""
    _CFG_DETECT_CHECK=""
    _CFG_DETECT_CONFIGURED_CHECK=""
    _CFG_DETECT_DEPENDS=""
    _CFG_DETECT_DEPENDS_SOURCE="none"
    _CFG_DETECT_OPTDEPENDS_SUGGESTIONS=""
    _CFG_DETECT_SYSTEMD_UNITS=""
    _CFG_DETECT_MAKEDEPENDS=""
    _CFG_DETECT_CONFIGURED_MAKEDEPENDS=""
    _CFG_DETECT_COPY_DIRS=""
    _CFG_DETECT_COPY_RULES_DISPLAY=""
    _CFG_DETECT_NEXT=""

    local project_root="${PROJECT_ROOT:-}"
    if [[ -z "$project_root" ]]; then
        project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    [[ -n "${PROJECT_ROOT:-}" ]] || PROJECT_ROOT="$project_root"
    [[ -n "${AUR_DIR:-}" ]] || AUR_DIR="$project_root/aur"

    if (( ! allow_missing_cfg )) && [[ -n "${AURGEN_CONFIG_FILE:-}" && ! -f "$AURGEN_CONFIG_FILE" ]]; then
        err "[config] Configuration file not found: $AURGEN_CONFIG_FILE"
        return 1
    fi

    local config_file
    config_file="$(aurgen_config_file)"
    load_aurgen_config || return 1

    local config_exists=0
    [[ -f "$config_file" ]] && config_exists=1

    local aur_pkgbuild_state="absent"
    if [[ -f "$AUR_DIR/PKGBUILD" ]]; then
        if ! _import_has_package_section "$config_file"; then
            aur_pkgbuild_state="present (unimported)"
        else
            aur_pkgbuild_state="present (configured)"
        fi
    fi

    _config_source_gen_helpers

    local pkgname="${PKG_NAME:-${PKGNAME:-}}"
    if [[ -z "$pkgname" ]]; then
        local raw_name="${REPO_NAME:-$(basename "$project_root")}"
        pkgname="$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9@._+-]+/-/g; s/^[.-]+//; s/-+$//')"
        [[ -n "$pkgname" ]] || pkgname="package"
    fi

    local ver_info ver_src pkgver
    ver_info="$(detect_project_version "$project_root")"
    IFS=$'\t' read -r ver_src pkgver <<< "$ver_info"

    local -a desc_lines=()
    mapfile -t desc_lines < <(detect_project_description "$project_root" "$pkgname" 0)
    local desc_src="${desc_lines[0]:-fallback}"
    local pkgdesc="${desc_lines[1]:-$pkgname}"

    local lic_info lic_found lic_spdx lic_file
    lic_info="$(detect_project_license "$project_root")"
    IFS=$'\t' read -r lic_found lic_spdx lic_file <<< "$lic_info"

    local buildsys has_make_install=0 install_mode="copy-rules"
    buildsys="$(detect_buildsys "$project_root" || true)"
    if [[ "$buildsys" == "make" && -f "$project_root/Makefile" ]] && grep -E -q '^install:' "$project_root/Makefile"; then
        has_make_install=1
    fi
    if [[ -n "$buildsys" && ( "$buildsys" != "make" || "$has_make_install" -eq 1 ) ]]; then
        install_mode="build-system"
    fi

    local det_arch="any" arch_str arch_src
    if project_compiles "$project_root"; then
        det_arch="x86_64"
    fi
    if (( ${#PKG_ARCH[@]} )); then
        arch_str="${PKG_ARCH[*]}"
        arch_src="configured"
    else
        arch_str="$det_arch"
        if [[ "$det_arch" == "x86_64" ]]; then
            arch_src="compiled"
        else
            arch_src="script/data"
        fi
    fi

    local check_cmd=""
    check_cmd="$(default_check_command "$buildsys" "$project_root" || true)"

    local rt_err_file rt_out="" rt_line rt_depends="" rt_src="none" line_idx=0
    local -a unit_list=() opt_list=()
    rt_err_file="$(mktemp "${TMPDIR:-/tmp}/aurgen-detect.XXXXXX")"
    if ! rt_out="$(detect_runtime_deps --units 2>|"$rt_err_file")"; then
        rm -f "$rt_err_file"
        return 1
    fi
    while IFS= read -r rt_line; do
        rt_line="${rt_line#"${rt_line%%[![:space:]]*}"}"
        rt_line="${rt_line%"${rt_line##*[![:space:]]}"}"
        if (( line_idx == 0 )); then
            rt_depends="$rt_line"
        elif [[ -n "$rt_line" ]]; then
            unit_list+=("$rt_line")
        fi
        line_idx=$((line_idx + 1))
    done <<< "$rt_out"

    if [[ -s "$rt_err_file" ]]; then
        local src_match opt_line opt_pkg opt_cmd
        src_match="$(sed -n 's/.*\[detect_runtime_deps\] source: //p' "$rt_err_file" | head -n 1 || true)"
        [[ -n "$src_match" ]] && rt_src="$src_match"
        while IFS= read -r opt_line; do
            [[ -n "$opt_line" ]] || continue
            if [[ "$opt_line" == *" "* ]]; then
                opt_pkg="${opt_line%% *}"
                opt_cmd="${opt_line#* }"
                opt_list+=("$opt_pkg ($opt_cmd)")
            else
                opt_list+=("$opt_line")
            fi
        done < <(sed -n 's/.*\[detect_runtime_deps\] optdepends suggestion: //p' "$rt_err_file" | sort -u || true)
    fi
    rm -f "$rt_err_file"

    local -A excluded_md_bases=() md_seen=()
    local dep base cfg
    for dep in $rt_depends "${PKG_DEPENDS[@]}"; do
        [[ -n "$dep" ]] || continue
        base="$(pkg_dep_base "$dep")"
        [[ -n "$base" ]] && excluded_md_bases["$base"]=1
    done
    for cfg in "${PKG_OPTDEPENDS[@]}"; do
        [[ -n "$cfg" ]] || continue
        base="$(pkg_dep_base "${cfg%%:*}")"
        [[ -n "$base" ]] && excluded_md_bases["$base"]=1
    done

    local raw_makedepends
    local -a filtered_md=()
    raw_makedepends="$(detect_makedepends || true)"
    for dep in $raw_makedepends; do
        [[ -n "$dep" ]] || continue
        base="$(pkg_dep_base "$dep")"
        if is_base_devel_package "$base"; then
            continue
        fi
        if [[ -n "${excluded_md_bases[$base]:-}" || -n "${md_seen[$base]:-}" ]]; then
            continue
        fi
        md_seen["$base"]=1
        filtered_md+=("$dep")
    done

    local -a copy_rules=() copy_dir_names=() copy_dir_displays=()
    local copy_rules_output rule src dest perms
    copy_rules_output="$(get_copy_directories)" || return 1
    if [[ -n "$copy_rules_output" ]]; then
        mapfile -t copy_rules <<< "$copy_rules_output"
        for rule in "${copy_rules[@]}"; do
            [[ -n "$rule" ]] || continue
            IFS=':' read -r src dest perms _ <<< "$rule"
            if [[ -n "$src" && -d "$project_root/$src" ]]; then
                copy_dir_names+=("$src")
                copy_dir_displays+=("$src -> $dest ($perms)")
            fi
        done
    fi

    local next_hint
    if [[ "$aur_pkgbuild_state" == "present (unimported)" ]]; then
        next_hint="Run 'aurgen config import' (or 'aurgen config init') to import aur/PKGBUILD."
    elif (( config_exists == 0 )); then
        next_hint="Run 'aurgen config init' to write a starter config, or 'aurgen -n local' to dry-run with defaults."
    else
        next_hint="Run 'aurgen doctor' to verify environment readiness, or 'aurgen -n local' to dry-run packaging."
    fi

    local copy_dirs_csv="" copy_display="" opt_display="" i
    for i in "${!copy_dir_names[@]}"; do
        (( i > 0 )) && copy_dirs_csv+=","
        copy_dirs_csv+="${copy_dir_names[$i]}"
    done
    for i in "${!copy_dir_displays[@]}"; do
        (( i > 0 )) && copy_display+=", "
        copy_display+="${copy_dir_displays[$i]}"
    done
    for i in "${!opt_list[@]}"; do
        (( i > 0 )) && opt_display+=", "
        opt_display+="${opt_list[$i]}"
    done

    _CFG_DETECT_PKGNAME="$pkgname"
    _CFG_DETECT_CONFIG_FILE="$config_file"
    _CFG_DETECT_CONFIG_EXISTS="$config_exists"
    _CFG_DETECT_AUR_PKGBUILD="$aur_pkgbuild_state"
    _CFG_DETECT_VERSION="$pkgver"
    _CFG_DETECT_VERSION_SOURCE="$ver_src"
    _CFG_DETECT_DESCRIPTION="$pkgdesc"
    _CFG_DETECT_DESCRIPTION_SOURCE="$desc_src"
    _CFG_DETECT_CONFIGURED_DESCRIPTION="${PKG_DESCRIPTION:-}"
    _CFG_DETECT_LICENSE="$lic_spdx"
    _CFG_DETECT_LICENSE_FOUND="$lic_found"
    _CFG_DETECT_LICENSE_FILE="$lic_file"
    _CFG_DETECT_CONFIGURED_LICENSE="${PKG_LICENSE[*]:-}"
    _CFG_DETECT_BUILD_SYSTEM="${buildsys:-none}"
    _CFG_DETECT_INSTALL_MODE="$install_mode"
    _CFG_DETECT_DETECTED_ARCH="$det_arch"
    _CFG_DETECT_ARCH="$arch_str"
    _CFG_DETECT_ARCH_SOURCE="$arch_src"
    _CFG_DETECT_CHECK="$check_cmd"
    _CFG_DETECT_CONFIGURED_CHECK="${PKG_CHECK:-}"
    _CFG_DETECT_DEPENDS="$rt_depends"
    _CFG_DETECT_DEPENDS_SOURCE="$rt_src"
    _CFG_DETECT_OPTDEPENDS_SUGGESTIONS="$opt_display"
    _CFG_DETECT_SYSTEMD_UNITS="${unit_list[*]:-}"
    _CFG_DETECT_MAKEDEPENDS="${filtered_md[*]:-}"
    _CFG_DETECT_CONFIGURED_MAKEDEPENDS="${PKG_MAKEDEPENDS[*]:-}"
    _CFG_DETECT_COPY_DIRS="$copy_dirs_csv"
    _CFG_DETECT_COPY_RULES_DISPLAY="$copy_display"
    _CFG_DETECT_NEXT="$next_hint"
}

_config_print_detect() {
    _config_collect_detected || return 1

    local cfg_state="absent"
    (( _CFG_DETECT_CONFIG_EXISTS == 1 )) && cfg_state="present"

    local desc_line="$_CFG_DETECT_DESCRIPTION (source: $_CFG_DETECT_DESCRIPTION_SOURCE)"
    if [[ -n "$_CFG_DETECT_CONFIGURED_DESCRIPTION" ]]; then
        desc_line+="; configured: $_CFG_DETECT_CONFIGURED_DESCRIPTION"
    fi

    local lic_line
    if [[ "$_CFG_DETECT_LICENSE_FOUND" == 1 ]]; then
        lic_line="$_CFG_DETECT_LICENSE (file: $_CFG_DETECT_LICENSE_FILE)"
    else
        lic_line="$_CFG_DETECT_LICENSE (default fallback)"
    fi
    if [[ -n "$_CFG_DETECT_CONFIGURED_LICENSE" ]]; then
        lic_line+="; configured: $_CFG_DETECT_CONFIGURED_LICENSE"
    fi

    local check_line="${_CFG_DETECT_CHECK:-none}"
    if [[ -n "$_CFG_DETECT_CONFIGURED_CHECK" ]]; then
        check_line+="; configured: $_CFG_DETECT_CONFIGURED_CHECK"
    fi

    local md_line="${_CFG_DETECT_MAKEDEPENDS:-none}"
    if [[ -n "$_CFG_DETECT_CONFIGURED_MAKEDEPENDS" ]]; then
        md_line+="; configured: $_CFG_DETECT_CONFIGURED_MAKEDEPENDS"
    fi

    printf 'Detected project settings:\n'
    printf '  pkgname: %s\n' "$_CFG_DETECT_PKGNAME"
    printf '  config: %s (%s)\n' "$cfg_state" "$_CFG_DETECT_CONFIG_FILE"
    printf '  aur_pkgbuild: %s\n' "$_CFG_DETECT_AUR_PKGBUILD"
    printf '  version: %s (source: %s)\n' "$_CFG_DETECT_VERSION" "$_CFG_DETECT_VERSION_SOURCE"
    printf '  description: %s\n' "$desc_line"
    printf '  license: %s\n' "$lic_line"
    printf '  build_system: %s\n' "$_CFG_DETECT_BUILD_SYSTEM"
    printf '  install_mode: %s\n' "$_CFG_DETECT_INSTALL_MODE"
    printf '  arch: %s (%s)\n' "$_CFG_DETECT_ARCH" "$_CFG_DETECT_ARCH_SOURCE"
    printf '  check: %s\n' "$check_line"
    printf '  depends: %s (scan: %s)\n' "${_CFG_DETECT_DEPENDS:-none}" "$_CFG_DETECT_DEPENDS_SOURCE"
    printf '  optdepends_suggestions: %s\n' "${_CFG_DETECT_OPTDEPENDS_SUGGESTIONS:-none}"
    printf '  makedepends: %s\n' "$md_line"
    printf '  systemd_units: %s\n' "${_CFG_DETECT_SYSTEMD_UNITS:-none}"
    printf '  copy_dirs: %s\n' "${_CFG_DETECT_COPY_RULES_DISPLAY:-none}"
    printf '  next: %s\n' "$_CFG_DETECT_NEXT"
}

# Config mode implementation
mode_config() {
    local action="${1:-}"
    local config_file
    config_file="$(aurgen_config_file)"
    # Drop the action word so it is not treated as the output path.
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$action" in
        generate|gen|g)
            if generate_default_config "$config_file"; then
                echo -e "${GREEN}[config] Configuration file generated successfully.${RESET}" >&2
            else
                return 1
            fi
            ;;
        edit|e)
            _config_edit_file "$config_file" || return 1
            ;;
        show|s|list|l)
            if [[ -n "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" ]]; then
                err "[config] Configuration file not found: $config_file"
                return 1
            elif [[ "${1:-}" == "effective" ]]; then
                _config_show_effective
            elif [[ -f "$config_file" && ! -r "$config_file" ]]; then
                err "[config] Configuration file is not readable: $config_file"
                return 1
            elif [[ -f "$config_file" ]]; then
                echo -e "${CYAN}[config] Configuration file: $config_file${RESET}" >&2
                echo "---"
                cat "$config_file"
            else
                echo -e "${YELLOW}[config] No configuration file found. Using default configuration:${RESET}" >&2
                echo "---"
                echo "bin: usr/bin (executable)"
                echo "lib: usr/lib/\$pkgname (read-only)"
                echo "etc: etc/\$pkgname (read-only)"
                echo "share: usr/share/\$pkgname (read-only)"
                echo "include: usr/include/\$pkgname (read-only)"
                echo "local: usr/local/\$pkgname (read-only)"
                echo "var: var/\$pkgname (read-only)"
                echo "opt: opt/\$pkgname (read-only)"
            fi
            ;;
        validate|v)
            if [[ -n "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" ]]; then
                err "[config] Configuration file not found: $config_file"
                return 1
            fi
            # Load and validate configuration
            local copy_rules_output source_dir dest_dir permissions
            # shellcheck disable=SC1091
            . "$LIB_INSTALL_DIR/aur-integration.sh"
            if load_aurgen_config "$config_file" && copy_rules_output=$(get_copy_directories) &&
                load_aur_integration_config; then
                echo -e "${GREEN}[config] Configuration is valid.${RESET}" >&2
                echo -e "${CYAN}[config] Active copy rules:${RESET}" >&2
                while IFS=':' read -r source_dir dest_dir permissions _; do
                    [[ -n "$source_dir" ]] || continue
                    printf '  %s: %s (%s)\n' "$source_dir" "$dest_dir" "$permissions"
                done <<< "$copy_rules_output"
            else
                echo -e "${RED}[config] Configuration validation failed.${RESET}" >&2
                return 1
            fi
            ;;
        reset|r)
            if [[ -f "$config_file" ]]; then
                local config_status
                if ! config_status=$(git -C "$PROJECT_ROOT" status --porcelain -- "$config_file" 2>/dev/null) ||
                    [[ -n "$config_status" ]] ||
                    ! git -C "$PROJECT_ROOT" ls-files --error-unmatch -- "$config_file" >/dev/null 2>&1; then
                    echo -e "${RED}[config] Error: Cannot reset $config_file unless it is tracked and clean in a git work tree. Commit the file or delete it by hand.${RESET}" >&2
                    return 1
                fi
                rm -f "$config_file" || return 1
                generate_default_config "$config_file" || return 1
                echo -e "${GREEN}[config] Configuration file reset to defaults.${RESET}" >&2
                printf '%b[config] Restore the previous version with: git checkout -- %q%b\n' "$CYAN" "$config_file" "$RESET" >&2
            else
                echo -e "${YELLOW}[config] No configuration file found. Generating default configuration...${RESET}" >&2
                generate_default_config "$config_file" || return 1
                echo -e "${GREEN}[config] Configuration file generated.${RESET}" >&2
            fi
            ;;
        import|i)
            if ! config_import "${1:-$AUR_DIR/PKGBUILD}" "$config_file"; then
                return 1
            fi
            ;;
        detect)
            if (( $# > 0 )); then
                err "[config] Unknown argument for 'detect': $1"
                return 1
            fi
            _config_print_detect || return 1
            ;;
        init)
            if (( $# > 0 )); then
                err "[config] Unknown argument for 'init': $1"
                return 1
            fi
            if [[ -f "$config_file" ]]; then
                warn "[config] Configuration file already exists: $config_file"
                return 1
            fi
            local project_root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
            local aur_dir="${AUR_DIR:-$project_root/aur}"
            local abs_cfg abs_default_cfg
            abs_cfg="$(realpath -m -- "$config_file")"
            abs_default_cfg="$(realpath -m -- "$aur_dir/aurgen.install.yaml")"
            if [[ -f "$aur_dir/PKGBUILD" && "$abs_cfg" == "$abs_default_cfg" ]]; then
                log "[config] Found existing $aur_dir/PKGBUILD; importing into $config_file"
                if ! config_import "$aur_dir/PKGBUILD" "$config_file"; then
                    return 1
                fi
                return 0
            fi
            _config_collect_detected 1 || return 1
            generate_init_config "$config_file" \
                --pkgname "$_CFG_DETECT_PKGNAME" \
                --version "$_CFG_DETECT_VERSION" \
                --description "$_CFG_DETECT_DESCRIPTION" \
                --license "$_CFG_DETECT_LICENSE" \
                --build-system "$_CFG_DETECT_BUILD_SYSTEM" \
                --install-mode "$_CFG_DETECT_INSTALL_MODE" \
                --arch "$_CFG_DETECT_DETECTED_ARCH" \
                --check "$_CFG_DETECT_CHECK" \
                --depends "$_CFG_DETECT_DEPENDS" \
                --makedepends "$_CFG_DETECT_MAKEDEPENDS" \
                --copy-dirs "$_CFG_DETECT_COPY_DIRS" || return 1
            load_aurgen_config || return 1
            validate_config || return 1
            echo -e "${GREEN}[config] Tailored configuration initialized at $config_file.${RESET}" >&2
            ;;
        help|h|--help|-h)
            echo -e "${CYAN}AURGen Install Configuration Management${RESET}" >&2
            echo "" >&2
            echo "Usage: aurgen config <action>" >&2
            echo "" >&2
            echo "Actions:" >&2
            echo "  init                Initialize a project-tailored configuration (or import aur/PKGBUILD)" >&2
            echo "  generate, gen, g    Generate default configuration file" >&2
            echo "  edit, e             Edit configuration file with default editor" >&2
            echo "  show, s, list, l    Show current configuration" >&2
            echo "  show effective      Print parsed package metadata and copy rules" >&2
            echo "  detect              Print project metadata, dependencies, and install rules detected" >&2
            echo "  validate, v         Validate configuration syntax" >&2
            echo "  reset, r            Reset configuration to defaults (requires a clean tracked file)" >&2
            echo "  import, i [path]    Import package metadata from a PKGBUILD (default: aur/PKGBUILD)" >&2
            echo "  help, h             Show this help message" >&2
            echo "" >&2
            echo "Configuration file format (YAML):" >&2
            echo "  section_name:" >&2
            echo "    source: source_directory" >&2
            echo "    destination: destination_path" >&2
            echo "    permissions: executable|read-only" >&2
            echo "    exclude: [item1, item2]" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  executables:" >&2
            echo "    source: bin" >&2
            echo "    destination: usr/bin" >&2
            echo "    permissions: executable" >&2
            echo "    exclude: []" >&2
            echo "" >&2
            echo "  # headers:  # Commented out - won't copy include/" >&2
            echo "  #   source: include" >&2
            echo "  #   destination: usr/include/\$pkgname" >&2
            echo "  #   permissions: read-only" >&2
            echo "" >&2
            echo "Configuration file locations:" >&2
            echo "  $config_file" >&2
            echo "  $AUR_DIR/aurgen.install.yaml.example" >&2
            echo "" >&2
            echo "Note: Configuration files are project-specific and located in the aur/ directory." >&2
            echo "      They are automatically generated when PKGBUILD.0 is created for the first time." >&2
            echo "" >&2
            ;;
        "")
            echo -e "${YELLOW}[config] No action specified. Use 'aurgen config help' for usage information.${RESET}" >&2
            return 1
            ;;
        *)
            echo -e "${RED}[config] Unknown action: $action${RESET}" >&2
            echo -e "${YELLOW}[config] Use 'aurgen config help' for usage information.${RESET}" >&2
            return 1
            ;;
    esac
}
