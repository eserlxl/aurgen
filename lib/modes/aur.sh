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
        local mtime
        # Default core.quotePath C-quotes non-ASCII names, so archive pathspecs miss the path.
        mapfile -t paths < <(git -c core.quotePath=false -C "$PROJECT_ROOT" ls-tree -r --name-only "$ref" | filter_pkgbuild_sources)
        # shellcheck disable=SC2154 # mode_aur sets this from SOURCE_DATE_EPOCH or the ref commit time
        mtime="$ARCHIVE_MTIME"
        # No pathspecs makes git archive emit the whole tree, including files the filter dropped.
        if ((${#paths[@]} == 0)); then
            tar "$mtime" -cf - --files-from=/dev/null | gzip -n >| "$out"
        else
            git -C "$PROJECT_ROOT" archive --format=tar "$mtime" "$ref" -- "${paths[@]}" | gzip -n >| "$out"
        fi
    )
}

# err returns 0, so a failed gh release create/upload must exit or aur mode
# continues into the success log and the CDN wait.
# shellcheck disable=SC2154 # asset_exists, TARBALL, RELEASE_TAG, AUR_DIR, GH_USER, and TARBALL_URL are set by mode_aur
aur_upload_assets() {
    local repo_name="$1"
    if (( asset_exists == 1 )); then
        warn "[aur] Asset already exists at $TARBALL_URL."
        # shellcheck disable=SC2154 # upload_choice is set by prompt helper; default to 'n' if unset
        : "${upload_choice:=n}"
        prompt "Asset already exists. Do you want to overwrite it by uploading again? [y/N] " upload_choice n
        if [[ "$upload_choice" =~ ^[Yy]$ ]]; then
            set_signature_ext
            log "[aur] Overwriting ${TARBALL} and ${TARBALL}${SIGNATURE_EXT} on GitHub release ${RELEASE_TAG}..."
            gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            log "[aur] Asset(s) overwritten."
        else
            log "[aur] Skipped uploading; using existing asset."
        fi
    else
        warn "[aur] Asset is missing and must be uploaded to GitHub releases for the process to continue."
        set_signature_ext
        log "[aur] Uploading ${TARBALL} and ${TARBALL}${SIGNATURE_EXT} to GitHub release ${RELEASE_TAG}..."
        # Check if the release exists, create if missing
        if ! gh release view "$RELEASE_TAG" --repo "${GH_USER}/${repo_name}" &>/dev/null; then
            log "[aur] Release $RELEASE_TAG does not exist. Creating it before uploading assets."
            gh release create "$RELEASE_TAG" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${repo_name}" --title "$RELEASE_TAG" --generate-notes || { err "[aur] Failed to create GitHub release $RELEASE_TAG"; exit 1; }
            gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
        else
            gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
            gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || { err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""; exit 1; }
        fi
        log "[aur] Asset(s) uploaded."
    fi
}

# archive and signed-tag fetch v$PKGVER from origin. --exit-code is 2 when that
# tag is absent; any other status is a transport failure with a different cause.
aur_require_remote_tag() {
    local status=0
    git -C "$PROJECT_ROOT" ls-remote --exit-code --tags origin "refs/tags/v${PKGVER}" >/dev/null 2>>"$AURGEN_ERROR_LOG" || status=$?
    if (( status == 2 )); then
        err "[aur] Tag v${PKGVER} is not on origin; push it first: git push origin v${PKGVER}"
        exit 1
    fi
}

# install= is a filename in $AUR_DIR, same rule as deploy_to_aur.
# shellcheck disable=SC2154 # PKGBUILD is set by the caller
aur_print_copy_steps() {
    local install_file="" line=""
    if [[ -f "${PKGBUILD:-}" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*install=(.*)$ ]] || continue
            install_file="${BASH_REMATCH[1]}"
            install_file="${install_file#"${install_file%%[![:space:]]*}"}"
            install_file="${install_file%"${install_file##*[![:space:]]}"}"
            if [[ ${#install_file} -ge 2 ]]; then
                case "$install_file" in
                    \'*\') install_file="${install_file:1:${#install_file}-2}" ;;
                    \"*\") install_file="${install_file:1:${#install_file}-2}" ;;
                esac
            fi
            break
        done < "$PKGBUILD"
    fi
    if [[ -n "$install_file" ]]; then
        printf 'Then, copy the generated PKGBUILD, .SRCINFO, and %s to your local AUR git repository, commit, and push to update the AUR package.\n' "$install_file"
    else
        printf 'Then, copy the generated PKGBUILD and .SRCINFO to your local AUR git repository, commit, and push to update the AUR package.\n'
    fi
}

mode_aur() {
    log "${SILVER}[aur] Prepare for AUR upload: creates tarball, GPG signature, and PKGBUILD for release.${RESET}"
    # Release URLs and gh --repo use the repository, not the Arch package name.
    local repo_name="${REPO_NAME:-$PKGNAME}"
    extract_pkgbuild_data || exit 1

    # release publishes a signed asset. archive and signed-tag point at the tag.
    local source_kind="${PKG_SOURCE:-}"
    local tag_signer=""
    if [[ -z "$source_kind" ]]; then
        source_kind=release
    fi
    case "$source_kind" in
        release|archive|signed-tag) ;;
        *)
            err "[aur] Unknown package.source: $source_kind"
            exit 1
            ;;
    esac
    if [[ "$source_kind" == "signed-tag" ]]; then
        local signed_tag="v${PKGVER}"
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
        local verify_out=""
        verify_out="$(mktemp)"
        if ! git -C "$PROJECT_ROOT" verify-tag --raw "refs/tags/v${PKGVER}" >| "$verify_out" 2>&1; then
            cat "$verify_out" >>"$AURGEN_ERROR_LOG"
            rm -f "$verify_out"
            err "[aur] Tag ${signed_tag} signature verification failed"
            exit 1
        fi
        tag_signer="$(awk '/\[GNUPG:\] VALIDSIG / { f = $NF } END { print f }' "$verify_out")"
        rm -f "$verify_out"
        if [[ -z "$tag_signer" ]]; then
            err "[aur] Tag ${signed_tag} signature verification failed"
            exit 1
        fi
    fi

    if [[ "$source_kind" == "release" ]]; then
    declare -r TARBALL="${PKGNAME}-${PKGVER}.tar.gz"

    # 2. Create tarball from git
    cd "$PROJECT_ROOT" || exit 1
    GIT_REF="HEAD"
    if git -C "$PROJECT_ROOT" rev-parse "v${PKGVER}" > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        GIT_REF="v${PKGVER}"
        log "[aur] Using tag v${PKGVER} for archiving"
    elif git -C "$PROJECT_ROOT" rev-parse "${PKGVER}" > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        GIT_REF="${PKGVER}"
        log "[aur] Using tag ${PKGVER} for archiving"
    else
        warn "[aur] Warning: No tag found for version ${PKGVER}, using HEAD (this may cause checksum mismatches)"
    fi
    if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
        ARCHIVE_MTIME="--mtime=@$SOURCE_DATE_EPOCH"
        log "[aur] Using SOURCE_DATE_EPOCH=\"$SOURCE_DATE_EPOCH\" for tarball mtime."
    else
        COMMIT_EPOCH=$(git show -s --format=%ct "$GIT_REF")
        ARCHIVE_MTIME="--mtime=@$COMMIT_EPOCH"
        log "[aur] Using commit date (epoch \"$COMMIT_EPOCH\") of \"$GIT_REF\" for tarball mtime."
    fi
    aur_create_tarball "$GIT_REF" "$AUR_DIR/$TARBALL"
    log "Created $AUR_DIR/$TARBALL using $GIT_REF with reproducible mtime."
    cd "$PROJECT_ROOT" || exit 1

    # 3. GPG signing (aur mode only)
    set_signature_ext
    : "${ascii_armor:=0}"
    log "[aur] Using $( [[ $ascii_armor -eq 1 ]] && printf '%s' 'ASCII-armored signatures (.asc)' || printf '%s' 'binary signatures (.sig)' )"

    # Use GPG key if already selected, otherwise prompt
    if [[ -z "${GPG_KEY_ID:-}" ]]; then
        select_gpg_key
    fi
    GPG_KEY="$GPG_KEY_ID"
    
    # Check for GPG keys only if not using test key
    if [[ "${GPG_KEY_ID:-}" != "TEST_KEY_FOR_DRY_RUN" ]]; then
        if ! gpg --list-secret-keys --with-colons | grep -q '^sec:'; then
            err "Error: No GPG secret key found. Please generate or import a GPG key before signing."
        fi
    fi

    if [[ "${GPG_KEY_ID:-}" == "TEST_KEY_FOR_DRY_RUN" ]]; then
        touch "$AUR_DIR/$TARBALL$SIGNATURE_EXT"
        log "[aur] Test mode: Created dummy signature file: $AUR_DIR/$TARBALL$SIGNATURE_EXT"
        GPG_KEY=""
    elif [[ -n "$GPG_KEY" ]]; then
        gpg_args=(--detach-sign -u "$GPG_KEY" --output "$AUR_DIR/$TARBALL$SIGNATURE_EXT" "$AUR_DIR/$TARBALL")
        if [[ -n "$GPG_ARMOR_OPT" ]]; then
            gpg_args=(--detach-sign "$GPG_ARMOR_OPT" -u "$GPG_KEY" --output "$AUR_DIR/$TARBALL$SIGNATURE_EXT" "$AUR_DIR/$TARBALL")
        fi
        gpg "${gpg_args[@]}"
        log "[aur] Created GPG signature: $AUR_DIR/$TARBALL$SIGNATURE_EXT"
    else
        gpg_args=(--detach-sign --output "$AUR_DIR/$TARBALL$SIGNATURE_EXT" "$AUR_DIR/$TARBALL")
        if [[ -n "$GPG_ARMOR_OPT" ]]; then
            gpg_args=(--detach-sign "$GPG_ARMOR_OPT" --output "$AUR_DIR/$TARBALL$SIGNATURE_EXT" "$AUR_DIR/$TARBALL")
        fi
        gpg "${gpg_args[@]}"
        log "[aur] Created GPG signature: $AUR_DIR/$TARBALL$SIGNATURE_EXT"
    fi

    # 4. PKGBUILD update and asset upload
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
    fi

    # --- Begin flock-protected critical section for pkgrel bump ---
    LOCKFILE="$AUR_DIR/.aurgen.lock"
    (
        set -euo pipefail
        # Keep the lock inode. Unlinking it lets a second run create a new file and pass flock.
        exec 200>>"$LOCKFILE"
        flock -n 200 || { err "[aur] Another process is already updating PKGBUILD. Aborting."; exit 1; }
        OLD_PKGVER=""
        OLD_PKGREL=""
        # Startup cleanup already moved the published PKGBUILD to PKGBUILD.prev.
        # The template pkgrel is always 1, so an empty read must not win.
        published="$PKGBUILD"
        if [[ ! -s "$published" ]]; then
            published="$AUR_DIR/PKGBUILD.prev"
        fi
        if [[ -s "$published" ]]; then
            OLD_PKGVER=$(awk -F= '/^[[:space:]]*pkgver[[:space:]]*=/ {print $2}' "$published" | tr -d "\"'[:space:]")
            OLD_PKGREL=$(awk -F= '/^[[:space:]]*pkgrel[[:space:]]*=/ {sub(/[[:space:]]*#.*/, "", $2); print $2}' "$published" | tr -d "\"'[:space:]")
        fi
        cp -f "$PKGBUILD0" "$PKGBUILD"
        log "[aur] PKGBUILD.0 copied to PKGBUILD. (locked)"
        NEW_PKGREL=$(aur_next_pkgrel "$OLD_PKGVER" "$OLD_PKGREL" "$PKGVER")
        if [[ -n "$OLD_PKGVER" && -n "$OLD_PKGREL" ]]; then
            if [[ "$OLD_PKGVER" == "$PKGVER" ]]; then
                log "[aur] pkgver unchanged ($PKGVER), bumping pkgrel to $NEW_PKGREL. (locked)"
            else
                log "[aur] pkgver changed ($OLD_PKGVER -> $PKGVER), setting pkgrel to 1. (locked)"
            fi
        else
            log "[aur] No previous PKGBUILD found, setting pkgrel to 1. (locked)"
        fi
        awk -v new_pkgrel="$NEW_PKGREL" 'BEGIN{done=0} /^[[:space:]]*pkgrel[[:space:]]*=/ && !done {print "pkgrel=" new_pkgrel; done=1; next} {print}' "$PKGBUILD" >| "$PKGBUILD.tmp" && mv "$PKGBUILD.tmp" "$PKGBUILD"
    ) || exit 1
    # --- End flock-protected critical section ---

    if [[ "$source_kind" == "release" ]]; then
    if asset_exists "$TARBALL_URL" "$RELEASE_TAG" "$TARBALL"; then
        asset_exists=1
    else
        asset_exists=0
    fi
    if command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
        # shellcheck disable=SC2154 # dry_run is set by environment or calling context; default to 0 if unset
        : "${dry_run:=0}"
        if (( dry_run )); then
            if (( asset_exists == 1 )); then
                warn "[aur] (dry run) Asset already exists at $TARBALL_URL. Would prompt to overwrite and upload $TARBALL and $TARBALL$SIGNATURE_EXT to GitHub release $RELEASE_TAG."
            else
                warn "[aur] (dry run) Asset is missing. Would upload $TARBALL and $TARBALL$SIGNATURE_EXT to GitHub release $RELEASE_TAG."
            fi
        else
            aur_upload_assets "$repo_name"
            # Wait for CDN propagation as before
            : "${no_wait:=0}"
            if (( no_wait )); then
                printf '[aur] --no-wait flag set: Skipping post-upload wait for asset availability. (CI/advanced mode)\n' >&2
            else
                printf '[aur] Waiting for GitHub to propagate the uploaded asset (this may take some time due to CDN delay)...\n' >&2
                RETRIES=6
                DELAYS=(10 20 30 40 50 60)
                total_wait=0
                for ((i=1; i<=RETRIES; i++)); do
                    DELAY=${DELAYS[$((i-1))]}
                    if curl -I -L -f --silent "$TARBALL_URL" 1>>"$AURGEN_LOG" 2>>"$AURGEN_ERROR_LOG"; then
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
                            printf '[aur] Please check the asset URL in your browser: %s\n' "$TARBALL_URL" >&2
                            printf 'If the asset is available, you can continue. If not, wait a bit longer and refresh the page.\n' >&2
                            prompt "Press Enter to continue when the asset is available (or Ctrl+C to abort)..." _
                        fi
                    fi
                done
            fi
            printf '[aur] Note: After upload, makepkg will attempt to download the asset to generate checksums. If you see a download error, wait a few seconds and retry. This is normal due to GitHub CDN propagation.\n' >&2
        fi
    else
        err "[aur] ERROR: Release asset not found at $TARBALL_URL. GitHub CLI (gh) not available for automatic upload."
        printf 'Please install GitHub CLI (gh) or manually upload %q and %q to the GitHub release page.\n' "$AUR_DIR/$TARBALL" "$AUR_DIR/$TARBALL$SIGNATURE_EXT"
        printf 'After uploading the tarball, run: makepkg -g >> PKGBUILD to update checksums.\n'
        exit 1
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
    else
        # The source line from PKGBUILD.0 stays. archive sums are real; a signed tag stays SKIP.
        : "${dry_run:=0}"
        if (( dry_run == 0 )); then
            aur_require_remote_tag
        fi
        if [[ "$source_kind" == "archive" ]]; then
            update_checksums || exit 1
        elif [[ "$source_kind" == "signed-tag" ]]; then
            write_validpgpkeys "$PKGBUILD" "$tag_signer"
        fi
    fi
    generate_srcinfo || exit 1
    log "[aur] Preparation complete."
    if [[ "$source_kind" == "release" ]]; then
    if (( asset_exists == 0 )); then
        if command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
            printf 'Assets have been automatically uploaded to GitHub release %s.\n' "$RELEASE_TAG"
        else
            set_signature_ext
            printf 'Now push the git tag and upload %q and %q to the GitHub release page.\n' "$AUR_DIR/$TARBALL" "$AUR_DIR/$TARBALL$SIGNATURE_EXT"
        fi
    else
        printf 'Assets already exist on GitHub release %s. No upload was performed.\n' "$RELEASE_TAG" >&2
    fi
    else
        log "[aur] package.source=${source_kind}: skipped release tarball and asset upload."
    fi
    aur_print_copy_steps
    
    # Check if AUR integration is available and offer deployment
    if [[ -f "$LIB_INSTALL_DIR/aur-integration.sh" ]]; then
        echo ""
        echo "=== AUR Integration Available ==="
        echo "AURGen can automatically deploy your package to AUR."
        echo "Use 'aurgen aur-deploy' to deploy the generated PKGBUILD and .SRCINFO to AUR."
        echo "Use 'aurgen aur-status' to check your AUR repository status."
        echo "Use 'aurgen aur-init' to initialize a new AUR repository."
    fi
    
    install_pkg "aur"
    if [[ -f "$AUR_DIR/PKGBUILD.prev" && -f "$AUR_DIR/PKGBUILD" ]] && ! cmp -s "$AUR_DIR/PKGBUILD.prev" "$AUR_DIR/PKGBUILD"; then
        log "[aur] Changes since the previous PKGBUILD: diff -u aur/PKGBUILD.prev aur/PKGBUILD"
    fi
}
