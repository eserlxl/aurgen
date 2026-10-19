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
    if [[ -n "$old_pkgver" && -n "$old_pkgrel" && "$old_pkgver" == "$new_pkgver" ]]; then
        printf '%s\n' "$((old_pkgrel + 1))"
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
        mapfile -t paths < <(git -C "$PROJECT_ROOT" ls-tree -r --name-only "$ref" | filter_pkgbuild_sources)
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

mode_aur() {
    log "${SILVER}[aur] Prepare for AUR upload: creates tarball, GPG signature, and PKGBUILD for release.${RESET}"
    # Release URLs and gh --repo use the repository, not the Arch package name.
    local repo_name="${REPO_NAME:-$PKGNAME}"
    extract_pkgbuild_data || exit 1

    # release publishes a signed asset. archive and signed-tag point at the tag.
    local source_kind="${PKG_SOURCE:-}"
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
        exec 200>"$LOCKFILE"
        flock -n 200 || { err "[aur] Another process is already updating PKGBUILD. Aborting."; exit 1; }
        OLD_PKGVER=""
        OLD_PKGREL=""
        # Read the published PKGBUILD before PKGBUILD.0 replaces it. The template pkgrel is always 1.
        if [[ -s "$PKGBUILD" ]]; then
            OLD_PKGVER=$(awk -F= '/^[[:space:]]*pkgver[[:space:]]*=/ {print $2}' "$PKGBUILD" | tr -d "\"'[:space:]")
            OLD_PKGREL=$(awk -F= '/^[[:space:]]*pkgrel[[:space:]]*=/ {print $2}' "$PKGBUILD" | tr -d "\"'[:space:]")
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
            if (( asset_exists == 1 )); then
                warn "[aur] Asset already exists at $TARBALL_URL."
                # shellcheck disable=SC2154 # upload_choice is set by prompt helper; default to 'n' if unset
                : "${upload_choice:=n}"
                prompt "Asset already exists. Do you want to overwrite it by uploading again? [y/N] " upload_choice n
                if [[ "$upload_choice" =~ ^[Yy]$ ]]; then
                    set_signature_ext
                    log "[aur] Overwriting ${TARBALL} and ${TARBALL}${SIGNATURE_EXT} on GitHub release ${RELEASE_TAG}..."
                    gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${repo_name}" --clobber || err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$RELEASE_TAG\""
                    gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""
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
                    gh release create "$RELEASE_TAG" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${repo_name}" --title "$RELEASE_TAG" --notes "Release $RELEASE_TAG" || err "[aur] Failed to create GitHub release $RELEASE_TAG"
                    gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""
                else
                    gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${repo_name}" --clobber || err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$RELEASE_TAG\""
                    gh release upload "$RELEASE_TAG" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${repo_name}" --clobber || err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$RELEASE_TAG\""
                fi
                log "[aur] Asset(s) uploaded."
            fi
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
        if [[ "$source_kind" == "archive" ]]; then
            update_checksums || exit 1
        elif [[ -n "${GPG_KEY_ID:-}" ]]; then
            write_validpgpkeys "$PKGBUILD" "$GPG_KEY_ID"
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
    printf 'Then, copy the generated PKGBUILD and .SRCINFO to your local AUR git repository, commit, and push to update the AUR package.\n'
    
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
}
