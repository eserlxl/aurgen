#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen doctor mode-specific read-only preflight diagnostics

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

_doctor_pkg_hint() {
    local tool="$1"
    if declare -p PKG_HINT >/dev/null 2>&1 && [[ -v "PKG_HINT[$tool]" ]]; then
        printf '%s\n' "${PKG_HINT[$tool]}"
        return 0
    fi
    case "$tool" in
        getopt) printf 'util-linux\n' ;;
        updpkgsums) printf 'pacman-contrib\n' ;;
        makepkg) printf 'base-devel\n' ;;
        gpg) printf 'gnupg\n' ;;
        gh) printf 'github-cli\n' ;;
        bwrap) printf 'bubblewrap\n' ;;
        *) printf '%s\n' "$tool" ;;
    esac
}

_doctor_source_helpers() {
    if ! declare -F load_aurgen_config >/dev/null 2>&1; then
        # shellcheck source=../config.sh
        # shellcheck disable=SC1091
        . "$LIB_INSTALL_DIR/config.sh"
    fi
    if ! declare -F load_aur_integration_config >/dev/null 2>&1; then
        # shellcheck source=../aur-integration.sh
        # shellcheck disable=SC1091
        . "$LIB_INSTALL_DIR/aur-integration.sh"
    fi
    if ! declare -F detect_project_version >/dev/null 2>&1; then
        # shellcheck source=../gen-pkgbuild0.sh
        # shellcheck disable=SC1091
        . "$LIB_INSTALL_DIR/gen-pkgbuild0.sh"
    fi
    set +e +u
    set +o pipefail
}

mode_doctor() {
    local -x LC_ALL=C
    local _had_e=0 _had_u=0 _had_pipefail=0
    [[ $- == *e* ]] && _had_e=1
    [[ $- == *u* ]] && _had_u=1
    shopt -qo pipefail && _had_pipefail=1
    set +e +u
    set +o pipefail

    local pass_count=0 warn_count=0 fail_count=0

    _doctor_emit() {
        local level="$1" label="$2" detail="$3" color="" tag=""
        case "$level" in
            PASS) pass_count=$((pass_count + 1)); tag="[PASS]"; color="${GREEN:-}" ;;
            WARN) warn_count=$((warn_count + 1)); tag="[WARN]"; color="${YELLOW:-}" ;;
            FAIL) fail_count=$((fail_count + 1)); tag="[FAIL]"; color="${RED:-}" ;;
            INFO) tag="[INFO]"; color="${CYAN:-}" ;;
        esac
        if (( ${color_enabled:-0} )); then
            printf '  %b%-6s%b %-20s %s\n' "$color" "$tag" "${RESET:-}" "$label:" "$detail"
        else
            printf '  %-6s %-20s %s\n' "$tag" "$label:" "$detail"
        fi
    }

    _doctor_hint() {
        printf '         -> %s\n' "$1"
    }

    printf '=== Environment & Tools ===\n'
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
        _doctor_emit PASS "Bash" "${BASH_VERSION}"
    else
        _doctor_emit FAIL "Bash" "${BASH_VERSION} (Bash >= 4.4 required)"
    fi

    if command -v getopt >/dev/null 2>&1; then
        local getopt_probe=0
        getopt -T >/dev/null 2>&1 || getopt_probe=$?
        if (( getopt_probe == 4 )); then
            _doctor_emit PASS "GNU getopt" "util-linux getopt available"
        else
            _doctor_emit FAIL "GNU getopt" "non-GNU getopt detected"
            _doctor_hint "Install GNU getopt: sudo pacman -S util-linux"
        fi
    else
        _doctor_emit FAIL "GNU getopt" "missing"
        _doctor_hint "Install: sudo pacman -S util-linux"
    fi

    local tool pkg
    for tool in git makepkg updpkgsums curl jq; do
        if command -v "$tool" >/dev/null 2>&1; then
            _doctor_emit PASS "$tool" "found"
        else
            pkg="$(_doctor_pkg_hint "$tool")"
            _doctor_emit FAIL "$tool" "missing (required for packaging/AUR workflows)"
            _doctor_hint "Install: sudo pacman -S $pkg"
        fi
    done

    local have_gpg=0
    if command -v gpg >/dev/null 2>&1; then
        have_gpg=1
        _doctor_emit PASS "gpg" "found"
    else
        _doctor_emit WARN "gpg" "not installed (required for 'aur' mode release signing)"
        _doctor_hint "Install: sudo pacman -S $(_doctor_pkg_hint gpg)"
    fi

    local opt_desc=""
    for tool in gh shellcheck namcap bwrap; do
        case "$tool" in
            gh) opt_desc="optional (release uploads & GitHub description lookup)" ;;
            shellcheck) opt_desc="optional (static analysis in 'aurgen lint')" ;;
            namcap) opt_desc="optional (PKGBUILD/package lint in 'aurgen test'/'local')" ;;
            bwrap) opt_desc="optional (sandboxed 'make install' dependency scan)" ;;
        esac
        if command -v "$tool" >/dev/null 2>&1; then
            _doctor_emit PASS "$tool" "found"
        else
            _doctor_emit INFO "$tool" "not installed — $opt_desc (sudo pacman -S $(_doctor_pkg_hint "$tool"))"
        fi
    done

    printf '\n=== Git & Remote ===\n'
    local git_root="" repo_url="" repo_name="" git_name="" git_email=""
    if command -v git >/dev/null 2>&1; then
        git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    fi

    if [[ -z "$git_root" ]]; then
        _doctor_emit FAIL "Git repository" "not inside a git repository"
        _doctor_hint "Run: git init && git remote add origin https://github.com/<user>/<repo>.git"
    else
        _doctor_emit PASS "Git repository" "$git_root"
        PROJECT_ROOT="$git_root"
        AUR_DIR="$PROJECT_ROOT/aur"

        repo_url=$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true)
        local github_remote_re='^([[:alnum:]+.-]+://)?([^/@]+@)?(www\.)?github\.com[:/][^/]+/[^/]+$'
        if [[ -z "$repo_url" ]]; then
            _doctor_emit FAIL "GitHub origin" "no remote 'origin' configured"
            _doctor_hint "Run: git remote add origin https://github.com/<user>/<repo>.git"
            repo_name="$(basename "$PROJECT_ROOT")"
        elif [[ ! "$repo_url" =~ $github_remote_re ]]; then
            _doctor_emit FAIL "GitHub origin" "non-GitHub URL: $repo_url"
            _doctor_hint "Set origin to github.com (https://github.com/<user>/<repo>.git or git@github.com:<user>/<repo>.git)"
            repo_name="$(basename "${repo_url%.git}")"
        else
            _doctor_emit PASS "GitHub origin" "$repo_url"
            repo_name="$(basename "${repo_url%.git}")"
        fi
        REPO_NAME="$repo_name"

        git_name=$(git -C "$PROJECT_ROOT" config --get user.name 2>/dev/null || true)
        git_email=$(git -C "$PROJECT_ROOT" config --get user.email 2>/dev/null || true)
        if [[ -n "$git_name" && -n "$git_email" ]]; then
            _doctor_emit PASS "Git identity" "$git_name <$git_email>"
        else
            _doctor_emit WARN "Git identity" "missing user.name or user.email (PKGBUILD.HEADER falls back to Unknown User)"
            _doctor_hint "Run: git config user.name \"Your Name\" && git config user.email \"you@example.com\""
        fi

        printf '\n=== Configuration & Packaging ===\n'
        _doctor_source_helpers
        MAXDEPTH="${MAXDEPTH:-5}"

        local config_file="" config_ok=0 cfg_err=""
        config_file="$(aurgen_config_file)"
        if [[ -n "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" ]]; then
            load_aurgen_config "$config_file" >/dev/null 2>&1 || true
            _doctor_emit FAIL "Configuration" "file not found: $config_file"
            _doctor_hint "Create the config file or pass an existing file to -c/--config"
        elif [[ -z "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" && -f "$AUR_DIR/PKGBUILD" ]]; then
            load_aurgen_config "$config_file" >/dev/null 2>&1 || true
            _doctor_emit WARN "Configuration" "unimported aur/PKGBUILD found without aur/aurgen.install.yaml"
            _doctor_hint "Run 'aurgen config import' before 'aurgen config generate' or build modes"
        elif [[ ! -f "$config_file" ]]; then
            load_aurgen_config "$config_file" >/dev/null 2>&1 || true
            _doctor_emit WARN "Configuration" "missing ($config_file); built-in defaults apply"
            _doctor_hint "Run 'aurgen config generate' to create aur/aurgen.install.yaml"
        else
            if load_aurgen_config "$config_file" >/dev/null 2>&1 &&
               validate_config >/dev/null 2>&1 &&
               load_aur_integration_config >/dev/null 2>&1; then
                config_ok=1
                _doctor_emit PASS "Configuration" "valid ($config_file)"
            else
                cfg_err=$( { load_aurgen_config "$config_file" && validate_config && load_aur_integration_config; } 2>&1 || true )
                cfg_err="${cfg_err%%$'\n'*}"
                _doctor_emit FAIL "Configuration" "invalid ($config_file)"
                [[ -n "$cfg_err" ]] && _doctor_hint "$cfg_err"
                _doctor_hint "Run 'aurgen config validate' for details"
            fi
        fi

        local pkgname_val=""
        if [[ -n "${PKG_NAME:-}" ]]; then
            pkgname_val="$PKG_NAME"
        else
            pkgname_val="$(printf '%s' "$REPO_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
        fi
        # shellcheck disable=SC2034 # Used by sourced metadata/config helpers
        PKGNAME="$pkgname_val"
        if [[ "$pkgname_val" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
            _doctor_emit PASS "Package name" "$pkgname_val"
        else
            _doctor_emit FAIL "Package name" "invalid '$pkgname_val' (expected [a-z0-9@._+-], no leading dot or hyphen)"
            _doctor_hint "Set a valid package.name in $config_file"
        fi

        if [[ ! "$REPO_NAME" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
            _doctor_emit FAIL "Repository name" "invalid '$REPO_NAME'"
        fi

        if [[ -n "${PKG_INSTALL:-}" ]]; then
            if [[ "$PKG_INSTALL" == */* || "$PKG_INSTALL" == .* ]]; then
                _doctor_emit FAIL "Install scriptlet" "package.install must be a filename in aur/: $PKG_INSTALL"
            elif [[ ! -f "$AUR_DIR/$PKG_INSTALL" ]]; then
                _doctor_emit FAIL "Install scriptlet" "file not found: $AUR_DIR/$PKG_INSTALL"
            else
                _doctor_emit PASS "Install scriptlet" "$AUR_DIR/$PKG_INSTALL"
            fi
        fi

        if [[ -n "${AURGEN_CONFIG_FILE:-}" && ! -f "$config_file" ]]; then
            _doctor_emit INFO "Copy directories" "skipped (configuration file not found)"
        elif [[ -f "$config_file" ]] && (( ! config_ok )); then
            _doctor_emit INFO "Copy directories" "skipped (invalid configuration)"
        else
            local -a active_dirs=() absent_dirs=()
            local copy_out="" rule src_dir="" copy_rc=0
            copy_out="$(get_copy_directories 2>/dev/null)" || copy_rc=$?
            if (( copy_rc != 0 )); then
                _doctor_emit INFO "Copy directories" "skipped (invalid configuration)"
            elif [[ -z "$copy_out" ]]; then
                _doctor_emit INFO "Copy directories" "none configured"
            else
                while IFS= read -r rule; do
                    IFS=':' read -r src_dir _ <<< "$rule"
                    [[ -n "$src_dir" ]] || continue
                    if [[ -d "$PROJECT_ROOT/$src_dir" ]]; then
                        active_dirs+=("$src_dir")
                    else
                        absent_dirs+=("$src_dir")
                    fi
                done <<< "$copy_out"
                _doctor_emit INFO "Copy directories" "present: ${active_dirs[*]:-none}; absent: ${absent_dirs[*]:-none}"
            fi
        fi

        local ver_src="" pkgver=""
        IFS=$'\t' read -r ver_src pkgver < <(detect_project_version "$PROJECT_ROOT")
        case "$ver_src" in
            tag|version-file)
                _doctor_emit PASS "Version" "$pkgver ($ver_src)"
                ;;
            empty-version-file)
                _doctor_emit WARN "Version" "VERSION file is empty (fallback: $pkgver)"
                _doctor_hint "Write a version into VERSION or create a git tag (git tag -a v0.1.0 -m 'v0.1.0')"
                ;;
            *)
                _doctor_emit WARN "Version" "no git tag or VERSION file (fallback: $pkgver)"
                _doctor_hint "Create a VERSION file or annotated tag: git tag -a v0.1.0 -m 'v0.1.0'"
                ;;
        esac

        if [[ -n "${PKG_DESCRIPTION:-}" ]]; then
            _doctor_emit PASS "Description" "configured (package.description)"
        else
            local desc_src=""
            {
                IFS= read -r desc_src || true
                IFS= read -r _ || true
            } < <(detect_project_description "$PROJECT_ROOT" "$pkgname_val" 0)
            if [[ "$desc_src" == "fallback" || -z "$desc_src" ]]; then
                _doctor_emit WARN "Description" "no manifest or README summary found (fallback: $pkgname_val)"
                _doctor_hint "Add a README.md summary or set package.description"
            else
                _doctor_emit PASS "Description" "detected from $desc_src"
            fi
        fi

        # shellcheck disable=SC2154 # PKG_LICENSE may be populated by load_aurgen_config
        if (( ${#PKG_LICENSE[@]} )); then
            _doctor_emit PASS "License" "${PKG_LICENSE[*]} (configured)"
        else
            local lic_found=0 lic_id="" lic_file=""
            IFS=$'\t' read -r lic_found lic_id lic_file < <(detect_project_license "$PROJECT_ROOT")
            if (( lic_found )); then
                _doctor_emit PASS "License" "$lic_id ($lic_file)"
            else
                _doctor_emit WARN "License" "no LICENSE file found (fallback: custom)"
                _doctor_hint "Add a LICENSE file in repository root"
            fi
        fi

        local buildsys=""
        buildsys="$(detect_buildsys "$PROJECT_ROOT")"
        if [[ -n "$buildsys" ]]; then
            _doctor_emit PASS "Build system" "$buildsys"
        else
            local has_payload=0
            if find "$PROJECT_ROOT" -maxdepth "$MAXDEPTH" \
                \( -path "$PROJECT_ROOT/.git" -o -path "$AUR_DIR" \) -prune -o \
                -type f \( \( -executable -name "*.sh" \) -o -name "*.py" -o -name "*.pl" -o -name "*.rb" -o -name "*.js" \
                    -o -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" \
                    -o -name "*.md" -o -name "*.txt" -o -name "*.rst" -o -name "*.html" \
                    -o -name "*.dat" -o -name "*.csv" -o -name "*.xml" -o -name "*.sql" \) \
                -print -quit 2>/dev/null | grep -q .; then
                has_payload=1
            fi
            if (( has_payload )); then
                _doctor_emit PASS "Build system" "none (no-build project)"
            else
                _doctor_emit WARN "Build system" "unknown (no manifest or payload files found)"
                _doctor_hint "Add source/script files or build manifest; otherwise placeholder build() steps apply"
            fi
        fi

        printf '\n=== Signing & AUR Integration ===\n'
        if (( ! config_ok )); then
            load_aur_integration_config >/dev/null 2>&1 || true
        fi
        local source_kind="${PKG_SOURCE:-release}"
        if [[ "$source_kind" != "release" ]]; then
            _doctor_emit PASS "GPG signing" "not required (package.source=$source_kind)"
        elif (( ! have_gpg )); then
            if [[ -n "${PKG_GPG_KEY:-}" ]] || { [[ -n "${GPG_KEY_ID:-}" && "${GPG_KEY_ID:-}" != "TEST_KEY_FOR_DRY_RUN" ]]; }; then
                _doctor_emit FAIL "GPG signing" "signing key requested, but 'gpg' is missing"
                _doctor_hint "Install: sudo pacman -S $(_doctor_pkg_hint gpg)"
            else
                _doctor_emit INFO "GPG signing" "skipped (gpg unavailable; required for 'aur' release mode)"
            fi
        else
            local -a gpg_keys=()
            mapfile -t gpg_keys < <(gpg --list-secret-keys --with-colons 2>/dev/null | LC_ALL=C awk -F: '
                $1 == "sec" { want = ($2 !~ /^[erdi]$/ && $12 ~ /S/); next }
                want && $1 == "fpr" && $10 ~ /^[0-9A-Fa-f]{40}$/ { print $10; want = 0; next }
                $1 == "ssb" || $1 == "uid" || $1 == "uat" { want = 0 }
            ')
            local k=""
            if [[ "${GPG_KEY_ID:-}" == "TEST_KEY_FOR_DRY_RUN" ]]; then
                _doctor_emit INFO "GPG signing" "TEST_KEY_FOR_DRY_RUN configured"
            elif [[ -n "${GPG_KEY_ID:-}" ]]; then
                local want_env="${GPG_KEY_ID^^}" matched_env=0
                for k in "${gpg_keys[@]}"; do
                    if [[ "${k^^}" == "$want_env" || "${k^^}" == *"$want_env" ]]; then
                        matched_env=1
                        break
                    fi
                done
                if (( matched_env )); then
                    _doctor_emit PASS "GPG signing" "GPG_KEY_ID matched usable secret key"
                else
                    _doctor_emit FAIL "GPG signing" "GPG_KEY_ID '${GPG_KEY_ID}' not found in usable GPG secret keys"
                fi
            elif [[ -n "${PKG_GPG_KEY:-}" ]]; then
                local want_cfg="${PKG_GPG_KEY^^}" match_cfg="" cfg_matches=0
                if [[ "$want_cfg" =~ ^[[:xdigit:]]{16,40}$ ]]; then
                    for k in "${gpg_keys[@]}"; do
                        if [[ "${k^^}" == *"$want_cfg" ]]; then
                            match_cfg="$k"
                            cfg_matches=$((cfg_matches + 1))
                        fi
                    done
                fi
                if (( cfg_matches == 1 )); then
                    _doctor_emit PASS "GPG signing" "package.gpg_key matched ($match_cfg)"
                else
                    _doctor_emit FAIL "GPG signing" "package.gpg_key '${PKG_GPG_KEY}' does not match exactly one usable GPG signing key"
                fi
            elif (( ${#gpg_keys[@]} == 0 )); then
                _doctor_emit WARN "GPG signing" "no usable GPG signing key found (required for 'aur' mode release signing)"
                _doctor_hint "Run 'gpg --full-generate-key' or set package.source: archive"
            elif (( ${#gpg_keys[@]} == 1 )); then
                _doctor_emit PASS "GPG signing" "1 usable key (${gpg_keys[0]})"
            else
                _doctor_emit PASS "GPG signing" "${#gpg_keys[@]} usable keys available"
                _doctor_hint "Set package.gpg_key or GPG_KEY_ID for non-interactive 'aur' signing"
            fi
        fi

        if [[ -n "${AUR_SSH_KEY:-}" ]]; then
            local resolved_ssh="${AUR_SSH_KEY/#\~/$HOME}"
            if [[ -f "$resolved_ssh" ]]; then
                _doctor_emit PASS "AUR SSH key" "$resolved_ssh"
            else
                _doctor_emit WARN "AUR SSH key" "configured file not found: $resolved_ssh (will fall back to ~/.ssh/config)"
            fi
        fi

        local aur_repo_path="${AUR_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aurgen/aur}/$pkgname_val"
        if [[ ! -e "$aur_repo_path" && ! -L "$aur_repo_path" ]]; then
            _doctor_emit INFO "AUR clone" "not initialized ($aur_repo_path); run 'aurgen aur-init' before 'aurgen aur-deploy'"
        elif [[ ! -d "$aur_repo_path" || ! -d "$aur_repo_path/.git" ]]; then
            _doctor_emit FAIL "AUR clone" "non-git path blocks clone location: $aur_repo_path"
            _doctor_hint "Move or remove $aur_repo_path, then run 'aurgen aur-init'"
        elif ! git -C "$aur_repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            _doctor_emit FAIL "AUR clone" "broken git repository at $aur_repo_path"
            _doctor_hint "Reinitialize or inspect $aur_repo_path with 'aurgen aur-init'"
        else
            local aur_dirty="" aur_ahead=""
            aur_dirty="$(git -C "$aur_repo_path" status --porcelain 2>/dev/null || true)"
            aur_ahead="$(aur_ahead_count "$aur_repo_path" 2>/dev/null || true)"
            if [[ -n "$aur_dirty" ]]; then
                local dirty_msg="working tree has uncommitted changes at $aur_repo_path"
                if [[ "$aur_ahead" =~ ^[0-9]+$ ]] && (( aur_ahead > 0 )); then
                    dirty_msg="$dirty_msg ($aur_ahead unpushed commit(s))"
                fi
                _doctor_emit WARN "AUR clone" "$dirty_msg"
                _doctor_hint "Inspect or reset unpushed clone state with 'aurgen aur-deploy --rollback'"
            elif [[ "$aur_ahead" =~ ^[0-9]+$ ]] && (( aur_ahead > 0 )); then
                _doctor_emit INFO "AUR clone" "present at $aur_repo_path ($aur_ahead unpushed commit(s))"
                _doctor_hint "Run 'aurgen aur-push' to publish or 'aurgen aur-deploy --rollback' to revert"
            else
                _doctor_emit PASS "AUR clone" "present at $aur_repo_path"
            fi
        fi

        if (( config_ok )) && [[ -f "$AUR_DIR/PKGBUILD" && ! -f "$AUR_DIR/.SRCINFO" ]]; then
            _doctor_emit WARN "AUR artifacts" "aur/PKGBUILD exists without aur/.SRCINFO"
            _doctor_hint "Run 'aurgen local', 'aurgen aur', or 'aurgen git' to regenerate complete packaging artifacts"
        fi
    fi

    printf '\nSummary: %d passed, %d warning(s), %d failure(s)\n' "$pass_count" "$warn_count" "$fail_count"
    local rc=0
    if (( fail_count > 0 )); then
        printf 'Result: not ready — resolve [FAIL] check(s) above.\n'
        rc=1
    elif (( warn_count > 0 )); then
        printf 'Result: ready with warnings.\n'
    else
        printf 'Result: ready.\n'
    fi

    (( _had_e )) && set -e
    (( _had_u )) && set -u
    (( _had_pipefail )) && set -o pipefail
    return "$rc"
}
