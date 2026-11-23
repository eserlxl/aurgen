#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# aurgen aur mode-specific logic

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

init_error_trap

# Same pkgver keeps the published pkgrel and adds one. A new pkgver starts at 1.
aur_next_pkgrel() {
    local old_pkgver="$1"
    local old_pkgrel="$2"
    local new_pkgver="$3"
    # pkgrel may be N or N.M (makepkg minor release). Only the matched integer reaches
    # arithmetic, so no PKGBUILD text is ever evaluated.
    if [[ -n "$old_pkgver" && "$old_pkgver" == "$new_pkgver" && "$old_pkgrel" =~ ^([0-9]+)(\.[0-9]+)?$ ]]; then
        printf '%s\n' "$((10#${BASH_REMATCH[1]} + 1))"
    else
        printf '%s\n' 1
    fi
}

# 0 when the published PKGBUILD exists and the candidate, with its first pkgrel=
# line set to pkgrel=<old_pkgrel>, is byte-identical to it (dropping
# checksum-array and validpgpkeys lines on a dry run), and any install=
# file matches the copy published beside that PKGBUILD. Otherwise 1.
aur_pkgbuild_unchanged() {
    local candidate="$1"
    local published="$2"
    local old_pkgrel="$3"
    local install_file="" install_src="" published_install=""
    [[ -f "$candidate" && -f "$published" ]] || return 1
    # shellcheck disable=SC2154 # dry_run is set by the caller; default to 0 if unset
    : "${dry_run:=0}"
    if (( dry_run == 1 )); then
        cmp -s \
            <(LC_ALL=C awk -v sq="'" "$_AWK_PKGBUILD_UNQUOTED"'
                BEGIN { in_skip = 0 }
                in_skip { if (unquoted($0) ~ /\)[[:space:]]*$/) in_skip = 0; next }
                /^[[:space:]]*(validpgpkeys|[a-zA-Z0-9_]+sums(_[a-zA-Z0-9_]+)?)[[:space:]]*=/ {
                    u = unquoted($0)
                    if (u ~ /=[[:space:]]*\(/ && u !~ /\)[[:space:]]*$/) in_skip = 1
                    next
                }
                { print }
            ' "$published") \
            <(LC_ALL=C awk -v new_pkgrel="$old_pkgrel" -v sq="'" "$_AWK_PKGBUILD_UNQUOTED"'
                BEGIN { done = 0; in_skip = 0 }
                in_skip { if (unquoted($0) ~ /\)[[:space:]]*$/) in_skip = 0; next }
                /^[[:space:]]*(validpgpkeys|[a-zA-Z0-9_]+sums(_[a-zA-Z0-9_]+)?)[[:space:]]*=/ {
                    u = unquoted($0)
                    if (u ~ /=[[:space:]]*\(/ && u !~ /\)[[:space:]]*$/) in_skip = 1
                    next
                }
                /^[[:space:]]*pkgrel[[:space:]]*=/ && !done {
                    print "pkgrel=" new_pkgrel
                    done = 1
                    next
                }
                { print }
            ' "$candidate") || return 1
    else
        cmp -s "$published" <(LC_ALL=C awk -v new_pkgrel="$old_pkgrel" 'BEGIN{done=0} /^[[:space:]]*pkgrel[[:space:]]*=/ && !done {print "pkgrel=" new_pkgrel; done=1; next} {print}' "$candidate") || return 1
    fi
    install_file=$(pkgbuild_install_file "$candidate")
    [[ -n "$install_file" ]] || return 0
    # Same lookup as deploy_to_aur: beside the candidate PKGBUILD, else $AUR_DIR.
    install_src="$(dirname "$candidate")/$install_file"
    if [[ ! -f "$install_src" ]]; then
        # shellcheck disable=SC2154 # AUR_DIR is set by the caller
        install_src="$AUR_DIR/$install_file"
    fi
    published_install="$(dirname "$published")/$install_file"
    [[ -f "$install_src" && -f "$published_install" ]] || return 1
    cmp -s "$published_install" "$install_src" || return 1
}

# Flat archive of one git ref. A release build() does not cd into a prefix directory,
# and the published asset must be that ref, not the working tree.
aur_create_tarball() {
    local ref="$1"
    local out="$2"
    (
        set -euo pipefail
        unset CI
        trap '' ERR
        local -a paths=()
        local mtime listing
        # Default core.quotePath C-quotes non-ASCII names, so archive pathspecs miss the path.
        # Not a process substitution: its status is lost, and a failed listing would
        # archive nothing and still return 0.
        # A newline in a tracked name would split it into two paths; refuse such a tree.
        if [[ "$(git -C "$PROJECT_ROOT" ls-tree -r -z --name-only "$ref" | tr -cd '\n' | wc -c)" != 0 ]]; then
            err "[aur] A tracked file name in $ref contains a newline; refusing to build the archive."
            exit 1
        fi
        listing=$(set -o pipefail; git -C "$PROJECT_ROOT" ls-tree -r -z --name-only "$ref" | tr '\0' '\n' | filter_pkgbuild_sources) || exit 1
        if [[ -n "$listing" ]]; then
            mapfile -t paths <<< "$listing"
        fi
        # shellcheck disable=SC2154 # mode_aur sets this from SOURCE_DATE_EPOCH or the ref commit time
        mtime="$ARCHIVE_MTIME"
        # No pathspecs makes git archive emit the whole tree, including files the filter dropped.
        if ((${#paths[@]} == 0)); then
            tar "$mtime" -cf - --files-from=/dev/null | gzip -n >| "$out"
        else
            # Literal pathspecs: a name starting with ":" or holding "*?[" is a path, not magic or a glob.
            git --literal-pathspecs -C "$PROJECT_ROOT" archive --format=tar "$mtime" "$ref" -- "${paths[@]}" | gzip -n >| "$out"
        fi
    )
}

# A failed gh release view is treated as a missing release. Check login before
# any create or upload so that failure names gh auth login. err returns 0, so exit.
aur_require_gh_auth() {
    if ! gh auth status --hostname github.com &>/dev/null; then
        err "[aur] gh is not logged in to github.com; run: gh auth login --hostname github.com"
        exit 1
    fi
}

# err returns 0, so a failed gh release create/upload must exit or aur mode
# continues into the success log and the CDN wait.
# shellcheck disable=SC2154 # asset_exists, TARBALL, RELEASE_TAG, AUR_DIR, GH_USER, TARBALL_URL, and RELEASE_COMMIT are set by mode_aur
aur_upload_assets() {
    local repo_name="$1"
    local asset_dir="${OUT_DIR:-$AUR_DIR}"
    if (( asset_exists == 1 )); then
        # The tarball check above does not see the signature. A missing .sig or
        # .asc 404s for makepkg, so upload only that file before asking to replace the tarball.
        set_signature_ext
        # 2 means the probe failed. Uploading would pass --clobber against a
        # signature that may already be published. err returns 0, so exit.
        local sig_status=0
        asset_exists "${TARBALL_URL}${SIGNATURE_EXT}" "$RELEASE_TAG" "${TARBALL}${SIGNATURE_EXT}" || sig_status=$?
        if (( sig_status == 2 )); then
            # shellcheck disable=SC2154 # dry_run is set by the caller; default to 0 if unset
            : "${dry_run:=0}"
            if (( dry_run )); then
                warn "[aur] (dry run) GitHub could not be reached for ${TARBALL_URL}${SIGNATURE_EXT}."
                return 0
            fi
            err "[aur] GitHub could not be reached for ${TARBALL_URL}${SIGNATURE_EXT}."
            exit 1
        fi
        if (( sig_status != 0 )); then
            aur_require_gh_auth
            log "[aur] Uploading missing ${TARBALL}${SIGNATURE_EXT} to GitHub release ${RELEASE_TAG}..."
            gh release upload "$RELEASE_TAG" "$asset_dir/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            assets_uploaded=1
            sig_only_uploaded=1
        fi
        warn "[aur] Asset already exists at $TARBALL_URL."
        # shellcheck disable=SC2154 # upload_choice is set by prompt helper; default to 'n' if unset
        : "${upload_choice:=n}"
        if [[ "${AURGEN_OVERWRITE_ASSETS:-0}" == "1" ]]; then
            log "[aur] Overwrite requested (--overwrite-assets / AURGEN_OVERWRITE_ASSETS=1); replacing existing asset without prompting."
            upload_choice="y"
        else
            prompt "Asset already exists. Do you want to overwrite it by uploading again? [y/N] " upload_choice n
        fi
        if [[ "$upload_choice" =~ ^[Yy]$ ]]; then
            aur_require_gh_auth
            set_signature_ext
            log "[aur] Overwriting ${TARBALL} and ${TARBALL}${SIGNATURE_EXT} on GitHub release ${RELEASE_TAG}..."
            gh release upload "$RELEASE_TAG" "$asset_dir/$TARBALL" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            gh release upload "$RELEASE_TAG" "$asset_dir/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            log "[aur] Asset(s) overwritten."
            assets_uploaded=1
            sig_only_uploaded=0
        else
            log "[aur] Skipped uploading; using existing asset."
        fi
    else
        aur_require_gh_auth
        warn "[aur] Asset is missing and must be uploaded to GitHub releases for the process to continue."
        set_signature_ext
        log "[aur] Uploading ${TARBALL} and ${TARBALL}${SIGNATURE_EXT} to GitHub release ${RELEASE_TAG}..."
        # Check if the release exists, create if missing
        if ! gh release view "$RELEASE_TAG" --repo "${GH_USER}/${repo_name}" &>/dev/null; then
            log "[aur] Release $RELEASE_TAG does not exist. Creating it before uploading assets."
            local -a target_opt=()
            local target_commit="${RELEASE_COMMIT:-}"
            if [[ -z "$target_commit" && -n "${PROJECT_ROOT:-}" ]] && git -C "$PROJECT_ROOT" rev-parse -q --verify "${RELEASE_TAG}^{commit}" >/dev/null 2>&1; then
                target_commit="$(git -C "$PROJECT_ROOT" rev-parse "${RELEASE_TAG}^{commit}" 2>>"$AURGEN_ERROR_LOG")"
            fi
            if [[ -n "$target_commit" ]]; then
                target_opt=(--target "$target_commit")
            fi
            local -a notes_opt=(--generate-notes)
            if [[ -n "${AURGEN_RELEASE_NOTES_FILE:-}" ]]; then
                notes_opt=(--notes-file "$AURGEN_RELEASE_NOTES_FILE")
            fi
            gh release create "$RELEASE_TAG" "$asset_dir/$TARBALL" --repo "${GH_USER}/${repo_name}" "${target_opt[@]}" --title "$RELEASE_TAG" "${notes_opt[@]}" || { err "[aur] Failed to create GitHub release $RELEASE_TAG"; exit 1; }
            gh release upload "$RELEASE_TAG" "$asset_dir/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
        else
            gh release upload "$RELEASE_TAG" "$asset_dir/$TARBALL" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            gh release upload "$RELEASE_TAG" "$asset_dir/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
        fi
        log "[aur] Asset(s) uploaded."
    fi
}

# archive and signed-tag fetch the selected version tag from origin. --exit-code is 2 when that
# tag is absent; any other status is a transport failure with a different cause.
# AURGEN_PUSH_TAG=1 pushes an existing local tag and continues. Never --force:
# a rejected update must stop the run rather than overwrite origin.
aur_require_remote_tag() {
    local status=0 tag
    tag="$(version_tag_name)"
    git -C "$PROJECT_ROOT" ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>>"$AURGEN_ERROR_LOG" || status=$?
    if (( status == 2 )); then
        if [[ "${AURGEN_PUSH_TAG:-0}" == 1 ]] && git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>>"$AURGEN_ERROR_LOG"; then
            log "[aur] AURGEN_PUSH_TAG=1: pushing tag ${tag} to origin"
            status=0
            git -C "$PROJECT_ROOT" push origin "refs/tags/${tag}:refs/tags/${tag}" || status=$?
            if (( status != 0 )); then
                err "[aur] Failed to push tag ${tag} to origin"
                exit 1
            fi
        else
            err "[aur] Tag ${tag} is not on origin; push it first: git push origin ${tag}"
            exit 1
        fi
    elif (( status != 0 )); then
        err "[aur] Could not check origin for tag ${tag}; see ${AURGEN_ERROR_LOG}"
        exit 1
    fi
}

# install= is a filename in $AUR_DIR, same rule as deploy_to_aur.
# shellcheck disable=SC2154 # PKGBUILD is set by the caller
aur_print_copy_steps() {
    local install_file=""
    if [[ -f "${PKGBUILD:-}" ]]; then
        install_file=$(pkgbuild_install_file "$PKGBUILD")
    fi
    if [[ -n "$install_file" ]]; then
        printf 'Then, copy the generated PKGBUILD, .SRCINFO, and %s to your local AUR git repository, commit, and push to update the AUR package.\n' "$install_file"
    else
        printf 'Then, copy the generated PKGBUILD and .SRCINFO to your local AUR git repository, commit, and push to update the AUR package.\n'
    fi
}

# The unpacked source is the release tag, which can lag a check target added at HEAD.
_aur_extract_check_body() {
    local pkgbuild0="$1"
    [[ -f "$pkgbuild0" ]] || return 0
    LC_ALL=C awk -v sq="'" '
        function scan_check_line(s,    i, n, c, out, prev) {
            out = ""; prev = ""; n = length(s)
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (escaped) {
                    out = out c; escaped = 0; prev = c; continue
                }
                if (in_sq) {
                    out = out c
                    if (c == sq) in_sq = 0
                    prev = c; continue
                }
                if (in_dq) {
                    if (c == "\\") escaped = 1
                    else if (c == "\"") in_dq = 0
                    out = out c; prev = c; continue
                }
                if (c == "#" && (prev == "" || prev ~ /[[:space:]]/)) {
                    if (out != "") print out
                    return
                }
                if (c == "\\") {
                    escaped = 1; out = out c; prev = c; continue
                }
                if (c == sq) {
                    in_sq = 1; out = out c; prev = c; continue
                }
                if (c == "\"") {
                    in_dq = 1; out = out c; prev = c; continue
                }
                if (c == "{") {
                    depth++
                } else if (c == "}") {
                    depth--
                    if (depth == 0) {
                        if (out != "") print out
                        done = 1
                        exit
                    }
                }
                out = out c
                prev = c
            }
            if (out != "") print out
        }
        !capture && !await_brace && /^[[:space:]]*check[[:space:]]*\([[:space:]]*\)[[:space:]]*(\{.*)?$/ {
            pos = index($0, "{")
            if (pos > 0) {
                capture = 1; depth = 1
                scan_check_line(substr($0, pos + 1))
                if (done) exit
            } else {
                await_brace = 1
            }
            next
        }
        await_brace && /^[[:space:]]*\{/ {
            await_brace = 0; capture = 1; depth = 1
            pos = index($0, "{")
            scan_check_line(substr($0, pos + 1))
            if (done) exit
            next
        }
        capture {
            scan_check_line($0)
            if (done) exit
        }
    ' "$pkgbuild0"
}

_aur_collect_make_cmd_targets() {
    local -n _cmct_targets="$1"
    shift
    local -a args=("$@")
    local cmd_idx=0 skip=0 end_opts=0 expect_arg="" idx arg
    while (( cmd_idx < ${#args[@]} )) && [[ "${args[cmd_idx]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
        cmd_idx=$((cmd_idx + 1))
    done
    (( cmd_idx < ${#args[@]} )) && [[ "${args[cmd_idx]}" == "make" ]] || return 0
    for (( idx = cmd_idx + 1; idx < ${#args[@]}; idx++ )); do
        arg="${args[idx]}"
        [[ "$arg" == "--" ]] && break
        # -C/-f/--file name some other Makefile, so the tag's file is the wrong one.
        case "$arg" in
            -C*|-f*|--directory*|--file*|--makefile*) skip=1; break ;;
        esac
    done
    ((skip)) && return 0
    for (( idx = cmd_idx + 1; idx < ${#args[@]}; idx++ )); do
        arg="${args[idx]}"
        if [[ -n "$expect_arg" ]]; then
            case "$expect_arg" in
                req)
                    expect_arg=""
                    continue
                    ;;
                int)
                    expect_arg=""
                    if [[ "$arg" =~ ^[0-9]+$ ]]; then
                        continue
                    fi
                    ;;
                float)
                    expect_arg=""
                    if [[ "$arg" =~ ^([0-9]+(\.[0-9]+)?|\.[0-9]+)$ ]]; then
                        continue
                    fi
                    ;;
            esac
        fi
        if (( ! end_opts )); then
            if [[ "$arg" == "--" ]]; then
                end_opts=1
                continue
            fi
            case "$arg" in
                -I|--include-dir|-W|--what-if|--new-file|--assume-new|-o|--old-file|--assume-old|-E|--eval)
                    expect_arg="req"
                    continue
                    ;;
                -j|--jobs)
                    expect_arg="int"
                    continue
                    ;;
                -l|--load-average|--max-load)
                    expect_arg="float"
                    continue
                    ;;
                -*)
                    continue
                    ;;
            esac
        fi
        case "$arg" in
            *=*) ;;
            *) _cmct_targets+=("$arg") ;;
        esac
    done
}

_aur_collect_check_make_targets() {
    local LC_ALL=C
    local -n _ccmt_targets="$1"
    local body="$2"
    local -a cmd_args=()
    local tok="" ch="" next=""
    local in_tok=0 in_sq=0 in_dq=0 escaped=0 flush=0 i=0 n=${#body}
    for (( i = 0; i < n; i++ )); do
        ch="${body:i:1}"
        next="${body:i+1:1}"
        if (( escaped )); then
            escaped=0
            if [[ "$ch" == $'\n' ]]; then
                continue
            fi
            tok+="$ch"
            in_tok=1
            continue
        fi
        if (( in_sq )); then
            if [[ "$ch" == "'" ]]; then
                in_sq=0
            else
                tok+="$ch"
            fi
            in_tok=1
            continue
        fi
        if (( in_dq )); then
            if [[ "$ch" == "\\" && ( "$next" == '"' || "$next" == "\\" || "$next" == '$' || "$next" == '`' || "$next" == $'\n' ) ]]; then
                escaped=1
            elif [[ "$ch" == '"' ]]; then
                in_dq=0
            else
                tok+="$ch"
            fi
            in_tok=1
            continue
        fi
        if [[ "$ch" == "\\" ]]; then
            escaped=1
            in_tok=1
            continue
        fi
        if [[ "$ch" == "'" ]]; then
            in_sq=1
            in_tok=1
            continue
        fi
        if [[ "$ch" == '"' ]]; then
            in_dq=1
            in_tok=1
            continue
        fi
        if [[ "$ch" == '#' && $in_tok -eq 0 ]]; then
            while (( i + 1 < n )) && [[ "${body:i+1:1}" != $'\n' ]]; do
                i=$((i + 1))
            done
            continue
        fi
        flush=0
        if [[ "$ch" == $'\n' || "$ch" == ';' || "$ch" == '|' ]]; then
            flush=1
        elif [[ ( "$ch" == '&' && "$next" == '&' ) || ( "$ch" == '|' && "$next" == '|' ) ]]; then
            flush=1
            i=$((i + 1))
        fi
        if (( flush )); then
            if (( in_tok )); then
                cmd_args+=("$tok")
                tok=""
                in_tok=0
            fi
            if (( ${#cmd_args[@]} )); then
                _aur_collect_make_cmd_targets "${!_ccmt_targets}" "${cmd_args[@]}"
                cmd_args=()
            fi
            continue
        fi
        if [[ "$ch" == [[:space:]] ]]; then
            if (( in_tok )); then
                cmd_args+=("$tok")
                tok=""
                in_tok=0
            fi
            continue
        fi
        tok+="$ch"
        in_tok=1
    done
    if (( in_tok )); then
        cmd_args+=("$tok")
    fi
    if (( ${#cmd_args[@]} )); then
        _aur_collect_make_cmd_targets "${!_ccmt_targets}" "${cmd_args[@]}"
    fi
}

_aur_parse_makefile_targets() {
    local makefile="$1"
    local -n _pmt_defined="$2"
    local -n _pmt_has_include="$3"
    local line="" lhs="" rest="" word=""
    local -a words=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # A recipe line is not a rule, and a tabbed "include" is a shell command.
        if [[ "$line" == $'\t'* ]]; then
            continue
        fi
        line="${line%%#*}"
        read -ra words <<< "$line"
        case "${words[0]:-}" in
            include|-include|sinclude) _pmt_has_include=1 ;;
        esac
        if [[ "$line" != *:* ]]; then
            continue
        fi
        lhs="${line%%:*}"
        rest="${line#*:}"
        if [[ "$rest" == :* ]]; then
            rest="${rest#:}"
        fi
        # := and ::= assign. The character after the colon(s) is "=".
        if [[ "$rest" == =* ]]; then
            continue
        fi
        # Words before the colon are the targets. ".PHONY: a" does not define a.
        read -ra words <<< "$lhs"
        for word in "${words[@]}"; do
            _pmt_defined["$word"]=1
        done
    done <<< "$makefile"
}

aur_check_make_targets() {
    local ref="" git_ref="" found="" name="" makefile="" body="" target="" msg=""
    local has_include=0
    local -a targets=()
    local -A defined=()
    # [a-z] in a Turkish locale does not match ASCII i.
    local LC_ALL=C

    if git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/v${PKGVER}" >/dev/null 2>>"$AURGEN_ERROR_LOG"; then
        ref="v${PKGVER}"
        git_ref="refs/tags/v${PKGVER}"
    elif git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/${PKGVER}" >/dev/null 2>>"$AURGEN_ERROR_LOG"; then
        ref="${PKGVER}"
        git_ref="refs/tags/${PKGVER}"
    else
        ref="HEAD"
        git_ref="HEAD"
    fi

    body="$(_aur_extract_check_body "${PKGBUILD0:-}")"
    [[ -n "$body" ]] || return 0

    _aur_collect_check_make_targets targets "$body"
    if ((${#targets[@]} == 0)); then
        return 0
    fi

    found=""
    for name in GNUmakefile makefile Makefile; do
        if git -C "$PROJECT_ROOT" cat-file -e "${git_ref}:${name}" >/dev/null 2>>"$AURGEN_ERROR_LOG"; then
            found="$name"
            break
        fi
    done
    if [[ -z "$found" ]]; then
        err "[aur] check() runs 'make ${targets[*]}', but ${ref} has no Makefile. Tag a release that contains it, or change package.check."
        exit 1
    fi
    if ! makefile="$(git -C "$PROJECT_ROOT" show "${git_ref}:${found}" 2>>"$AURGEN_ERROR_LOG")"; then
        err "[aur] check() runs 'make ${targets[*]}', but the Makefile at ${ref} could not be read."
        exit 1
    fi

    _aur_parse_makefile_targets "$makefile" defined has_include

    for target in "${targets[@]}"; do
        if [[ -v defined["$target"] ]]; then
            continue
        fi
        msg="[aur] check() runs 'make ${target}', but the Makefile at ${ref} has no '${target}' target. Tag a release that contains it, or change package.check."
        # An included file is not in this blob; the target may be defined there.
        if ((has_include)); then
            warn "${msg} (it may come from an included file)"
            continue
        fi
        err "$msg"
        exit 1
    done
}

_aur_verify_signed_tag() {
    local -n _vst_signer="$1"
    local signed_tag verify_out=""
    signed_tag="$(version_tag_name)"
    if ! git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/${signed_tag}" >/dev/null 2>>"$AURGEN_ERROR_LOG"; then
        err "[aur] signed-tag requires local tag ${signed_tag}"
        exit 1
    fi
    # A lightweight tag on a signed commit is not a signed tag. The signature is on the tag object.
    if [[ "$(git -C "$PROJECT_ROOT" cat-file -t "refs/tags/${signed_tag}" 2>>"$AURGEN_ERROR_LOG")" != "tag" ]] \
        || ! git -C "$PROJECT_ROOT" cat-file -p "refs/tags/${signed_tag}" 2>>"$AURGEN_ERROR_LOG" | grep -q 'BEGIN PGP SIGNATURE'; then
        err "[aur] Tag ${signed_tag} is not a signed tag"
        exit 1
    fi
    # makepkg accepts the key that signed the tag. Another local secret key must not be published instead.
    verify_out="$(mktemp)"
    if ! git -C "$PROJECT_ROOT" verify-tag --raw "refs/tags/${signed_tag}" >| "$verify_out" 2>&1; then
        cat "$verify_out" >>"$AURGEN_ERROR_LOG"
        rm -f "$verify_out"
        err "[aur] Tag ${signed_tag} signature verification failed"
        exit 1
    fi
    _vst_signer="$(awk '/\[GNUPG:\] VALIDSIG / { f = $NF } END { print f }' "$verify_out")"
    rm -f "$verify_out"
    if [[ -z "$_vst_signer" ]]; then
        err "[aur] Tag ${signed_tag} signature verification failed"
        exit 1
    fi
}

# Dynamic scope contract with mode_aur: reads out, repo_name, TARBALL;
# sets RELEASE_COMMIT, RELEASE_TAG and TARBALL_URL in mode_aur.
_aur_prepare_release_archive() {
    cd "$PROJECT_ROOT" || exit 1
    local GIT_REF="HEAD" git_ref_label="HEAD" COMMIT_EPOCH="" GPG_KEY=""
    # shellcheck disable=SC2034 # read by aur_create_tarball via dynamic scope
    local ARCHIVE_MTIME=""
    if git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/v${PKGVER}" > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        GIT_REF="refs/tags/v${PKGVER}"
        git_ref_label="v${PKGVER}"
        log "[aur] Using tag v${PKGVER} for archiving"
    elif git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/${PKGVER}" > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        GIT_REF="refs/tags/${PKGVER}"
        git_ref_label="${PKGVER}"
        log "[aur] Using tag ${PKGVER} for archiving"
    else
        warn "[aur] Warning: No tag found for version ${PKGVER}, using HEAD (this may cause checksum mismatches)"
    fi
    RELEASE_COMMIT="$(git -C "$PROJECT_ROOT" rev-parse "${GIT_REF}^{commit}" 2>>"$AURGEN_ERROR_LOG")"
    if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
        ARCHIVE_MTIME="--mtime=@$SOURCE_DATE_EPOCH"
        log "[aur] Using SOURCE_DATE_EPOCH=\"$SOURCE_DATE_EPOCH\" for tarball mtime."
    else
        # ^{commit}: on an annotated tag, git show also prints the tag header and message.
        COMMIT_EPOCH=$(git show -s --format=%ct "${GIT_REF}^{commit}")
        ARCHIVE_MTIME="--mtime=@$COMMIT_EPOCH"
        log "[aur] Using commit date (epoch \"$COMMIT_EPOCH\") of \"$git_ref_label\" for tarball mtime."
    fi
    # Called from a condition, errexit is off; never sign or upload a tarball that was not made.
    # Record only a path that was not already there. A failed run removes those paths
    # and must not delete a tarball or signature this run did not create.
    local tarball_path="$out/$TARBALL" tarball_existed=0
    [[ -e "$tarball_path" ]] && tarball_existed=1
    aur_create_tarball "$GIT_REF" "$tarball_path" || { err "[aur] Failed to create $tarball_path from $git_ref_label"; exit 1; }
    log "Created $tarball_path using $git_ref_label with reproducible mtime."
    if (( ! tarball_existed )); then
        # shellcheck disable=SC2034 # Read by _aurgen_on_mode_exit in bin/aurgen
        declare -ga _AURGEN_RUN_ARTIFACTS
        _AURGEN_RUN_ARTIFACTS+=("$tarball_path")
    fi
    cd "$PROJECT_ROOT" || exit 1

    set_signature_ext
    : "${ascii_armor:=0}"
    log "[aur] Using $( [[ $ascii_armor -eq 1 ]] && printf '%s' 'ASCII-armored signatures (.asc)' || printf '%s' 'binary signatures (.sig)' )"
    local sig_path="$out/$TARBALL$SIGNATURE_EXT" sig_existed=0
    [[ -e "$sig_path" ]] && sig_existed=1

    if [[ -z "${GPG_KEY_ID:-}" ]]; then
        select_gpg_key || exit 1
    fi
    GPG_KEY="$GPG_KEY_ID"

    # A dry run never signs. A preset GPG_KEY_ID skips select_gpg_key and its
    # dry-run test key, so the dry run is checked here; validpgpkeys keeps the key.
    : "${dry_run:=0}"
    if [[ "${GPG_KEY_ID:-}" == "TEST_KEY_FOR_DRY_RUN" ]] || (( dry_run )); then
        touch "$sig_path"
        log "[aur] Test mode: Created dummy signature file: $sig_path"
        GPG_KEY=""
    else
        local -a gpg_args=(--detach-sign)
        [[ -n "$GPG_ARMOR_OPT" ]] && gpg_args+=("$GPG_ARMOR_OPT")
        [[ -n "$GPG_KEY" ]] && gpg_args+=(-u "$GPG_KEY")
        gpg_args+=(--output "$sig_path" "$tarball_path")
        gpg "${gpg_args[@]}" || { err "[aur] Failed to create GPG signature: $sig_path"; exit 1; }
        log "[aur] Created GPG signature: $sig_path"
    fi
    if (( ! sig_existed )); then
        # shellcheck disable=SC2034 # Read by _aurgen_on_mode_exit in bin/aurgen
        declare -ga _AURGEN_RUN_ARTIFACTS
        _AURGEN_RUN_ARTIFACTS+=("$sig_path")
    fi

    set_signature_ext
    # One tag for the asset check, the upload, and the source URL. Prefer v$PKGVER when that
    # git tag or release exists, so creating a release never adds a second, unprefixed tag.
    RELEASE_TAG="$PKGVER"
    if git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/v${PKGVER}" > /dev/null 2>&1; then
        RELEASE_TAG="v${PKGVER}"
    elif command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG" && gh release view "v${PKGVER}" --repo "${GH_USER}/${repo_name}" &>/dev/null; then
        RELEASE_TAG="v${PKGVER}"
    fi
    TARBALL_URL="https://github.com/${GH_USER}/${repo_name}/releases/download/${RELEASE_TAG}/${TARBALL}"
    TARBALL_URL="${TARBALL_URL//\"/}"
}

# Dynamic scope contract with mode_aur: reads lock_fd, out; sets OLD_PKGVER, OLD_PKGREL, aur_clone.
_aur_resolve_published_version() {
    local pkgrel_source="local fallback" published="" published_version="" aur_name=""
    if [[ -f "$LIB_INSTALL_DIR/aur-integration.sh" ]]; then
        # shellcheck disable=SC1091
        . "$LIB_INSTALL_DIR/aur-integration.sh"
        load_aur_integration_config || { exec {lock_fd}>&-; return 1; }
        # Startup cleanup removed .SRCINFO, so this is normally PKGNAME, the release package.
        aur_name=$(aur_package_name) || aur_name="$PKGNAME"
        aur_clone="$AUR_REPO_DIR/$aur_name"
        if [[ -f "$aur_clone/.SRCINFO" ]]; then
            OLD_PKGVER=$(aur_srcinfo_field pkgver "$aur_clone/.SRCINFO") || OLD_PKGVER=""
            OLD_PKGREL=$(aur_srcinfo_field pkgrel "$aur_clone/.SRCINFO") || OLD_PKGREL=""
            pkgrel_source="AUR clone $aur_clone/.SRCINFO"
        elif [[ -d "$aur_clone" ]]; then
            pkgrel_source="AUR clone $aur_clone (unpublished)"
        elif [[ "${dry_run:-0}" == 0 ]] && published_version=$(aur_rpc_version "$aur_name"); then
            pkgrel_source="AUR RPC ($aur_name)"
            if [[ -n "$published_version" ]]; then
                published_version="${published_version#*:}"
                OLD_PKGVER="${published_version%-*}"
                OLD_PKGREL="${published_version##*-}"
            else
                pkgrel_source="AUR RPC ($aur_name, unpublished)"
            fi
        fi
    fi
    if [[ "$pkgrel_source" == "local fallback" ]]; then
        # Cleanup moves the last local PKGBUILD to .prev; dry runs leave it in AUR_DIR.
        published="$PKGBUILD"
        if [[ -s "$AUR_DIR/PKGBUILD" && "$AUR_DIR/PKGBUILD" != "$PKGBUILD" ]]; then
            published="$AUR_DIR/PKGBUILD"
        elif [[ ! -s "$published" && "$out" == "${AUR_DIR:-}" ]]; then
            # Only a real run's cleanup moved a published PKGBUILD to .prev; a dry run's
            # .prev is its own earlier preview and must not bump pkgrel again.
            published="$out/PKGBUILD.prev"
        fi
        if [[ -s "$published" ]]; then
            local old_pkgver_line old_pkgrel_line
            old_pkgver_line=$(awk '/^[[:space:]]*pkgver[[:space:]]*=/ { line=$0; sub(/^[^=]*=/, "", line); print line; exit }' "$published")
            OLD_PKGVER=$(_pkgbuild_trim_ws "$(_pkgbuild_unquote_pair "$(_pkgbuild_strip_comment "$old_pkgver_line")")")
            old_pkgrel_line=$(awk '/^[[:space:]]*pkgrel[[:space:]]*=/ { line=$0; sub(/^[^=]*=/, "", line); print line; exit }' "$published")
            OLD_PKGREL=$(_pkgbuild_trim_ws "$(_pkgbuild_unquote_pair "$(_pkgbuild_strip_comment "$old_pkgrel_line")")")
        fi
        pkgrel_source="local fallback $published (AUR unavailable or dry run)"
    fi
    log "[aur] pkgrel source: $pkgrel_source"
}

# Dynamic scope contract with mode_aur: reads out, repo_name, TARBALL, RELEASE_TAG, TARBALL_URL;
# sets asset_exists and assets_uploaded in mode_aur.
_aur_publish_release_assets() {
    # 0 present, 1 missing, 2 the probe failed. An if would collapse 2 into missing
    # and aur_upload_assets would then create or --clobber. err returns 0, so exit.
    local asset_status=0 sig_only_uploaded=0
    assets_uploaded=0
    asset_exists "$TARBALL_URL" "$RELEASE_TAG" "$TARBALL" || asset_status=$?
    # shellcheck disable=SC2154 # dry_run is set by environment or calling context; default to 0 if unset
    : "${dry_run:=0}"
    if (( asset_status == 2 )); then
        if (( dry_run )); then
            warn "[aur] (dry run) GitHub could not be reached for $TARBALL_URL."
        else
            err "[aur] GitHub could not be reached for $TARBALL_URL."
            exit 1
        fi
    fi
    if (( asset_status == 0 )); then
        asset_exists=1
    else
        asset_exists=0
    fi
    if command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        : "${dry_run:=0}"
        if (( dry_run )); then
            if (( asset_status != 2 && asset_exists == 1 )); then
                if [[ "${AURGEN_OVERWRITE_ASSETS:-0}" == "1" ]]; then
                    warn "[aur] (dry run) Asset already exists at $TARBALL_URL. Would overwrite and upload $TARBALL and $TARBALL$SIGNATURE_EXT to GitHub release $RELEASE_TAG without prompting."
                else
                    warn "[aur] (dry run) Asset already exists at $TARBALL_URL. Would prompt to overwrite and upload $TARBALL and $TARBALL$SIGNATURE_EXT to GitHub release $RELEASE_TAG."
                fi
            elif (( asset_status != 2 )); then
                warn "[aur] (dry run) Asset is missing. Would upload $TARBALL and $TARBALL$SIGNATURE_EXT to GitHub release $RELEASE_TAG."
            fi
        else
            aur_upload_assets "$repo_name"
            if (( asset_exists == 0 || ${assets_uploaded:-0} )); then
                local wait_url="$TARBALL_URL"
                if (( ${sig_only_uploaded:-0} )); then
                    set_signature_ext
                    wait_url="${TARBALL_URL}${SIGNATURE_EXT}"
                fi
                # Wait for CDN propagation only when an asset was actually uploaded.
                : "${no_wait:=0}"
                if (( no_wait )); then
                    printf '[aur] --no-wait flag set: Skipping post-upload wait for asset availability. (CI/advanced mode)\n' >&2
                else
                    printf '[aur] Waiting for GitHub to propagate the uploaded asset (this may take some time due to CDN delay)...\n' >&2
                    local RETRIES=6 i total_wait=0 DELAY
                    local -a DELAYS=(10 20 30 40 50 60)
                    for ((i=1; i<=RETRIES; i++)); do
                        DELAY=${DELAYS[$((i-1))]}
                        if curl -I -L -f --silent "$wait_url" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"; then
                            log "[aur] Asset is now available on GitHub (after $i attempt(s))."
                            if (( total_wait > 0 )); then
                                printf '[aur] Total wait time: %s seconds.\n' "$total_wait" >&2
                            fi
                            break
                        else
                            if (( i < RETRIES )); then
                                printf '[aur] Asset not available yet (attempt %s/%s). Waiting %s seconds...\n' "$i" "$RETRIES" "$DELAY" >&2
                                sleep "$DELAY"
                                total_wait=$((total_wait + DELAY))
                            else
                                warn "[aur] Asset still not available after $RETRIES attempts. This is normal if GitHub CDN is slow."
                                if ! have_tty; then
                                    err "[aur] Asset $wait_url is still unavailable in non-interactive mode; verify the release URL or rerun with --no-wait / NO_WAIT=1."
                                    exit 1
                                fi
                                printf '[aur] Please check the asset URL in your browser: %s\n' "$wait_url" >&2
                                printf 'If the asset is available, you can continue. If not, wait a bit longer and refresh the page.\n' >&2
                                prompt "Press Enter to continue when the asset is available (or Ctrl+C to abort)..." _
                            fi
                        fi
                    done
                fi
                printf '[aur] Note: After upload, makepkg will attempt to download the asset to generate checksums. If you see a download error, wait a few seconds and retry. This is normal due to GitHub CDN propagation.\n' >&2
            fi
        fi
    else
        # gh is optional: it only uploads. An asset uploaded by hand is enough.
        : "${dry_run:=0}"
        if (( asset_status == 2 )); then
            : # The warning above is the dry-run report. A real run already exited.
        elif (( asset_exists == 1 )); then
            log "[aur] Release asset found at $TARBALL_URL."
        elif (( dry_run )); then
            warn "[aur] (dry run) Release asset not found at $TARBALL_URL and GitHub CLI (gh) is not installed. A real run stops here until $TARBALL and $TARBALL$SIGNATURE_EXT are uploaded."
        else
            err "[aur] ERROR: Release asset not found at $TARBALL_URL. GitHub CLI (gh) not available for automatic upload."
            printf 'Please install GitHub CLI (gh) or manually upload %q and %q to the GitHub release page.\n' "$out/$TARBALL" "$out/$TARBALL$SIGNATURE_EXT"
            printf 'After uploading both files, re-run aurgen aur\n'
            exit 1
        fi
    fi
    # Only update the source array once, after the final TARBALL_URL is determined.
    # makepkg verifies the signature against validpgpkeys.
    update_source_array_in_pkgbuild "$PKGBUILD" "$TARBALL_URL" "${TARBALL_URL}${SIGNATURE_EXT}"
    log "[aur] Set tarball URL in source array in PKGBUILD (single authoritative update)."
    if ! grep -q '^b2sums=' "$PKGBUILD"; then
        printf "b2sums=('SKIP' 'SKIP')\n" >> "$PKGBUILD"
        log "[aur] Added missing b2sums=('SKIP' 'SKIP') to PKGBUILD."
    fi
    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        write_validpgpkeys "$PKGBUILD" "$GPG_KEY_ID"
    fi
    update_checksums || exit 1
}

# Dynamic scope contract with mode_aur: reads asset_exists, assets_uploaded, RELEASE_TAG, out, TARBALL.
_aur_report_release_result() {
    if (( asset_exists == 0 )); then
        if (( dry_run )); then
            printf '(dry run) No upload was performed.\n'
        elif command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
            printf 'Assets have been automatically uploaded to GitHub release %s.\n' "$RELEASE_TAG"
        else
            set_signature_ext
            printf 'Now push the git tag and upload %q and %q to the GitHub release page.\n' "$out/$TARBALL" "$out/$TARBALL$SIGNATURE_EXT"
        fi
    else
        if (( ${assets_uploaded:-0} )); then
            printf 'Uploaded to existing GitHub release %s.\n' "$RELEASE_TAG" >&2
        else
            printf 'Assets already exist on GitHub release %s. No upload was performed.\n' "$RELEASE_TAG" >&2
        fi
    fi
}

mode_aur() {
    log "${SILVER}[aur] Prepare for AUR upload: creates tarball, GPG signature, and PKGBUILD for release.${RESET}"
    local out="${OUT_DIR:-$AUR_DIR}"
    # Release URLs and gh --repo use the repository, not the Arch package name.
    local repo_name="${REPO_NAME:-$PKGNAME}"
    # A changelog tool's notes replace --generate-notes; check the file before any side effect.
    if [[ -n "${AURGEN_RELEASE_NOTES_FILE:-}" && ( ! -f "$AURGEN_RELEASE_NOTES_FILE" || ! -r "$AURGEN_RELEASE_NOTES_FILE" ) ]]; then
        err "[aur] AURGEN_RELEASE_NOTES_FILE is not a readable file: $AURGEN_RELEASE_NOTES_FILE"
        return 1
    fi
    if [[ -f "${LIB_INSTALL_DIR:-}/aur-integration.sh" ]]; then
        # shellcheck disable=SC1091
        . "$LIB_INSTALL_DIR/aur-integration.sh"
        load_aur_integration_config || return 1
    fi
    extract_pkgbuild_data || exit 1

    # release publishes a signed asset. archive and signed-tag point at the tag.
    local source_kind="${PKG_SOURCE:-}" tag_signer=""
    : "${source_kind:=release}"
    case "$source_kind" in
        release|archive|signed-tag) ;;
        *)
            err "[aur] Unknown package.source: $source_kind"
            exit 1
            ;;
    esac
    aur_check_make_targets
    if [[ "$source_kind" == "signed-tag" ]]; then
        _aur_verify_signed_tag tag_signer
    fi

    # Keep the lock inode. Unlinking it lets a second run create a new file and pass flock.
    local lock_fd=""
    [[ -d "$out" ]] || mkdir -p "$out" || exit 1
    exec {lock_fd}>>"$out/.aurgen.lock"
    if ! flock -n "$lock_fd"; then
        exec {lock_fd}>&-
        err "[aur] Another process is already updating PKGBUILD. Aborting."
        exit 1
    fi

    # Dynamic scope contract across _aur_* helpers and aur_upload_assets.
    # shellcheck disable=SC2034
    local RELEASE_COMMIT="" RELEASE_TAG="" TARBALL_URL="" OLD_PKGVER="" OLD_PKGREL="" aur_clone="" asset_exists=0 assets_uploaded=0

    if [[ "$source_kind" == "release" ]]; then
        # shellcheck disable=SC2034 # read by _aur_* helpers and aur_upload_assets via dynamic scope
        local -r TARBALL="${PKGNAME}-${PKGVER}.tar.gz"
        _aur_prepare_release_archive
    fi

    _aur_resolve_published_version || return 1

    # pkgrel bump and PKGBUILD rewrite run under the active .aurgen.lock.
    local NEW_PKGREL
    cp -f "$PKGBUILD0" "$PKGBUILD" || { exec {lock_fd}>&-; exit 1; }
    log "[aur] PKGBUILD.0 copied to PKGBUILD. (locked)"
    NEW_PKGREL=$(aur_next_pkgrel "$OLD_PKGVER" "$OLD_PKGREL" "$PKGVER") || { exec {lock_fd}>&-; exit 1; }
    if [[ -n "$OLD_PKGVER" && -n "$OLD_PKGREL" ]]; then
        if [[ "$OLD_PKGVER" == "$PKGVER" ]]; then
            log "[aur] pkgver unchanged ($PKGVER), bumping pkgrel to $NEW_PKGREL. (locked)"
        else
            log "[aur] pkgver changed ($OLD_PKGVER -> $PKGVER), setting pkgrel to 1. (locked)"
        fi
    else
        log "[aur] No published version found, setting pkgrel to 1. (locked)"
    fi
    if ! awk -v new_pkgrel="$NEW_PKGREL" 'BEGIN{done=0} /^[[:space:]]*pkgrel[[:space:]]*=/ && !done {print "pkgrel=" new_pkgrel; done=1; next} {print}' "$PKGBUILD" >| "$PKGBUILD.tmp" || ! mv "$PKGBUILD.tmp" "$PKGBUILD"; then
        exec {lock_fd}>&-
        exit 1
    fi

    if [[ "$source_kind" == "release" ]]; then
        _aur_publish_release_assets
    else
        # The source line from PKGBUILD.0 stays. archive sums are real; a signed tag stays SKIP.
        : "${dry_run:=0}"
        if (( dry_run == 0 )); then
            aur_require_remote_tag
        fi
        if [[ "$source_kind" == "archive" ]]; then
            write_validpgpkeys "$PKGBUILD" "" || exit 1
            update_checksums || exit 1
        elif [[ "$source_kind" == "signed-tag" ]]; then
            write_validpgpkeys "$PKGBUILD" "$tag_signer"
        fi
    fi
    # Checksums are final. A clone whose PKGBUILD matches, aside from the bumped
    # pkgrel, keeps the published pkgrel so a re-run does not force a rebuild.
    # AURGEN_BUMP_PKGREL=1 forces the bump, as a dependency soname change needs.
    if [[ -n "${aur_clone:-}" && -f "$aur_clone/PKGBUILD" && "$OLD_PKGVER" == "$PKGVER" && -n "$OLD_PKGREL" ]]; then
        if [[ "${AURGEN_BUMP_PKGREL:-0}" == 1 ]]; then
            log "[aur] AURGEN_BUMP_PKGREL=1: bumping pkgrel although the PKGBUILD may be unchanged"
        elif aur_pkgbuild_unchanged "$PKGBUILD" "$aur_clone/PKGBUILD" "$OLD_PKGREL"; then
            awk -v new_pkgrel="$OLD_PKGREL" 'BEGIN{done=0} /^[[:space:]]*pkgrel[[:space:]]*=/ && !done {print "pkgrel=" new_pkgrel; done=1; next} {print}' "$PKGBUILD" >| "$PKGBUILD.tmp" && mv "$PKGBUILD.tmp" "$PKGBUILD"
            log "[aur] PKGBUILD unchanged since the published release, keeping pkgrel=$OLD_PKGREL"
        fi
    fi
    generate_srcinfo || { exec {lock_fd}>&-; exit 1; }
    # shellcheck disable=SC2034 # Read by bin/aurgen failure recovery handler
    _AURGEN_ARTIFACTS_COMMITTED=1
    exec {lock_fd}>&-
    log "[aur] Preparation complete."
    if [[ "$source_kind" == "release" ]]; then
        _aur_report_release_result
    else
        log "[aur] package.source=${source_kind}: skipped release tarball and asset upload."
    fi
    aur_print_copy_steps
    if [[ -f "$out/PKGBUILD.prev" && -f "$out/PKGBUILD" ]] && ! cmp -s "$out/PKGBUILD.prev" "$out/PKGBUILD"; then
        log "[aur] Changes since the previous PKGBUILD: diff -u ${out#"$PROJECT_ROOT"/}/PKGBUILD.prev ${out#"$PROJECT_ROOT"/}/PKGBUILD"
    fi
    # install_pkg prints the Next: command, which stays the last line.
    install_pkg "aur" || exit $?
}
