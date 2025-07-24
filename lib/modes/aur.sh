#!/bin/bash
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
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

mode_aur() {
    log ${SILVER}"[aur] Prepare for AUR upload: creates tarball, GPG signature, and PKGBUILD for release."${RESET}
    extract_pkgbuild_data

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
    GIT_VERSION=$(git --version | awk '{print $3}')
    GIT_VERSION_MAJOR=$(echo "$GIT_VERSION" | cut -d. -f1)
    GIT_VERSION_MINOR=$(echo "$GIT_VERSION" | cut -d. -f2)
    GIT_MTIME_SUPPORTED=0
    if (( GIT_VERSION_MAJOR > 2 )) || { (( GIT_VERSION_MAJOR == 2 )) && (( GIT_VERSION_MINOR > 31 )); }; then
        GIT_MTIME_SUPPORTED=1
    fi
    if git archive --help | grep -q -- '--mtime'; then
        GIT_MTIME_SUPPORTED=1
    fi
    if (( ! GIT_MTIME_SUPPORTED )); then
        warn "[aurgen] Your git version ($GIT_VERSION) does not support 'git archive --mtime'. For fully reproducible tarballs, upgrade to git ≥ 2.32.0. Falling back to tar --mtime for reproducibility."
    fi
    if (( GIT_MTIME_SUPPORTED )); then
        (
            set -euo pipefail
            unset CI
            trap '' ERR
            git -C "$PROJECT_ROOT" archive --format=tar --prefix="${PKGNAME}-${PKGVER}/" "$ARCHIVE_MTIME" "$GIT_REF" | \
                gzip -n >| "$AUR_DIR/$TARBALL"
        )
        log "Created $AUR_DIR/$TARBALL using $GIT_REF with reproducible mtime."
    else
        (
            set -euo pipefail
            unset CI
            trap '' ERR
            git -C "$PROJECT_ROOT" archive --format=tar --prefix="${PKGNAME}-${PKGVER}/" "$GIT_REF" >| "$AUR_DIR/$TARBALL.tmp.tar"
            TAR_MTIME=""
            if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
                TAR_MTIME="--mtime=@${SOURCE_DATE_EPOCH}"
            else
                TAR_MTIME="--mtime=@${COMMIT_EPOCH}"
            fi
            tar "$TAR_MTIME" -cf - -C "$AUR_DIR" "${PKGNAME}-${PKGVER}" | gzip -n >| "$AUR_DIR/$TARBALL"
            rm -rf "$AUR_DIR/${PKGNAME}-${PKGVER}" "$AUR_DIR/$TARBALL.tmp.tar"
        )
        log "Created $AUR_DIR/$TARBALL using $GIT_REF (tar --mtime fallback for reproducibility)."
    fi
    cd "$PROJECT_ROOT" || exit 1

    # 3. GPG signing (aur mode only)
    if ! gpg --list-secret-keys --with-colons | grep -q '^sec:'; then
        err "Error: No GPG secret key found. Please generate or import a GPG key before signing."
    fi
    set_signature_ext
    log "[aur] Using $( [[ $ascii_armor -eq 1 ]] && printf '%s' 'ASCII-armored signatures (.asc)' || printf '%s' 'binary signatures (.sig)' )"
    GPG_KEY=""
    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        if [[ "${GPG_KEY_ID:-}" == "TEST_KEY_FOR_DRY_RUN" ]]; then
            log "[aur] Test mode: Skipping GPG signing"
            GPG_KEY=""
        else
            GPG_KEY="$GPG_KEY_ID"
        fi
    else
        mapfile -t KEYS < <(gpg --list-secret-keys --with-colons | awk -F: '/^sec/ {print $5}')
        if [[ ${#KEYS[@]} -eq 0 ]]; then
            err "No GPG secret keys found."
        fi
        warn "Available GPG secret keys:" >&2
        for i in "${!KEYS[@]}"; do
            USER=$(gpg --list-secret-keys "${KEYS[$i]}" | grep uid | head -n1 | sed 's/.*] //')
            warn "$((i+1)). ${KEYS[$i]} ($USER)" >&2
        done
        if ! have_tty; then
            err "No interactive terminal: please set GPG_KEY_ID in headless mode."
        fi
        prompt "Select a key [1-${#KEYS[@]}]: " choice 1
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#KEYS[@]} )); then
            err "Invalid selection."
        fi
        GPG_KEY="${KEYS[$((choice-1))]}"
    fi
    if [[ -n "$GPG_KEY" ]]; then
        gpg --detach-sign $GPG_ARMOR_OPT -u "$GPG_KEY" --output "$AUR_DIR/$TARBALL$SIGNATURE_EXT" "$AUR_DIR/$TARBALL"
        log "[aur] Created GPG signature: $AUR_DIR/$TARBALL$SIGNATURE_EXT"
    elif [[ "${GPG_KEY_ID:-}" == "TEST_KEY_FOR_DRY_RUN" ]]; then
        touch "$AUR_DIR/$TARBALL$SIGNATURE_EXT"
        log "[aur] Test mode: Created dummy signature file: $AUR_DIR/$TARBALL$SIGNATURE_EXT"
        GPG_KEY=""
    else
        gpg --detach-sign $GPG_ARMOR_OPT --output "$AUR_DIR/$TARBALL$SIGNATURE_EXT" "$AUR_DIR/$TARBALL"
        log "[aur] Created GPG signature: $AUR_DIR/$TARBALL$SIGNATURE_EXT"
    fi

    # 4. PKGBUILD update and asset upload
    set_signature_ext
    TARBALL_URL="https://github.com/${GH_USER}/${PKGNAME}/releases/download/${PKGVER}/${TARBALL}"
    TARBALL_URL="${TARBALL_URL//\"/}"

    # --- Begin flock-protected critical section for pkgrel bump ---
    LOCKFILE="$AUR_DIR/.aurgen.lock"
    (
        set -euo pipefail
        exec 200>"$LOCKFILE"
        flock -n 200 || err "[aur] Another process is already updating PKGBUILD. Aborting."
        OLD_PKGVER=""
        OLD_PKGREL=""
        cp -f "$PKGBUILD0" "$PKGBUILD"
        log "[aur] PKGBUILD.0 copied to PKGBUILD. (locked)"
        if [[ -s "$PKGBUILD" ]]; then
            cp "$PKGBUILD" "$PKGBUILD.bak"
            trap 'rm -f "$PKGBUILD.bak"' RETURN INT TERM
            OLD_PKGVER=$(awk -F= '/^[[:space:]]*pkgver[[:space:]]*=/ {print $2}' "$PKGBUILD.bak" | tr -d "\"'[:space:]")
            OLD_PKGREL=$(awk -F= '/^[[:space:]]*pkgrel[[:space:]]*=/ {print $2}' "$PKGBUILD.bak" | tr -d "\"'[:space:]")
        fi
        NEW_PKGREL=1
        if [[ -n "$OLD_PKGVER" && -n "$OLD_PKGREL" ]]; then
            if [[ "$OLD_PKGVER" == "$PKGVER" ]]; then
                NEW_PKGREL=$((OLD_PKGREL + 1))
                log "[aur] pkgver unchanged ($PKGVER), bumping pkgrel to $NEW_PKGREL. (locked)"
            else
                NEW_PKGREL=1
                log "[aur] pkgver changed ($OLD_PKGVER -> $PKGVER), setting pkgrel to 1. (locked)"
            fi
        else
            log "[aur] No previous PKGBUILD found, setting pkgrel to 1. (locked)"
        fi
        awk -v new_pkgrel="$NEW_PKGREL" 'BEGIN{done=0} /^[[:space:]]*pkgrel[[:space:]]*=/ && !done {print "pkgrel=" new_pkgrel; done=1; next} {print}' "$PKGBUILD" >| "$PKGBUILD.tmp" && mv "$PKGBUILD.tmp" "$PKGBUILD"
        trap - RETURN INT TERM
    )
    # --- End flock-protected critical section ---

    if asset_exists "$TARBALL_URL" "$PKGVER" "$TARBALL"; then
        asset_exists=1
    else
        asset_exists=0
    fi
    if (( asset_exists == 0 )); then
        warn "[aur] WARNING: Release asset not found at $TARBALL_URL. Trying fallback with 'v' prefix."
        TARBALL_URL="https://github.com/${GH_USER}/${PKGNAME}/releases/download/v${PKGVER}/${TARBALL}"
        if asset_exists "$TARBALL_URL" "$PKGVER" "$TARBALL"; then
            asset_exists=1
        else
            asset_exists=0
        fi
        if (( asset_exists == 0 )); then
            if command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
                warn "[aur] Release asset not found. GitHub CLI (gh) detected."
                if [[ "${AUTO:-}" == "y" ]]; then
                    upload_choice="y"
                else
                    prompt "Do you want to upload the tarball and signature to GitHub releases automatically? [y/N] " upload_choice n
                fi
                if [[ "$upload_choice" =~ ^[Yy]$ ]]; then
                    set_signature_ext
                    log "[aur] Uploading ${TARBALL} and ${TARBALL}${SIGNATURE_EXT} to GitHub release ${PKGVER}..."
                    gh release upload "$PKGVER" "$AUR_DIR/$TARBALL" --repo "${GH_USER}/${PKGNAME}" --clobber || err "[aur] Failed to upload \"$TARBALL\" to GitHub release \"$PKGVER\""
                    gh release upload "$PKGVER" "$AUR_DIR/$TARBALL$SIGNATURE_EXT" --repo "${GH_USER}/${PKGNAME}" --clobber || err "[aur] Failed to upload \"$TARBALL$SIGNATURE_EXT\" to GitHub release \"$PKGVER\""
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
                else
                    err "[aur] Release asset not found and automatic upload declined. Aborting."
                    printf 'After uploading the tarball manually, run: makepkg -g >> PKGBUILD to update checksums.\n'
                    exit 1
                fi
            else
                err "[aur] ERROR: Release asset not found at either location. GitHub CLI (gh) not available for automatic upload."
                printf 'Please install GitHub CLI (gh) or manually upload %q and %q to the GitHub release page.\n' "$AUR_DIR/$TARBALL" "$AUR_DIR/$TARBALL$SIGNATURE_EXT"
                printf 'After uploading the tarball, run: makepkg -g >> PKGBUILD to update checksums.\n'
                exit 1
            fi
        fi
    fi
    # Only update the source array once, after the final TARBALL_URL is determined
    update_source_array_in_pkgbuild "$PKGBUILD" "$TARBALL_URL"
    log "[aur] Set tarball URL in source array in PKGBUILD (single authoritative update)."
    if ! grep -q '^b2sums=' "$PKGBUILD"; then
        printf "b2sums=('SKIP')\n" >> "$PKGBUILD"
        log "[aur] Added missing b2sums=('SKIP') to PKGBUILD."
    fi
    update_checksums
    generate_srcinfo
    log "[aur] Preparation complete."
    if (( asset_exists == 0 )); then
        if command -v gh > /dev/null 2>>"$AURGEN_ERROR_LOG"; then
            printf 'Assets have been automatically uploaded to GitHub release %s.\n' "$PKGVER"
        else
            set_signature_ext
            printf 'Now push the git tag and upload %q and %q to the GitHub release page.\n' "$AUR_DIR/$TARBALL" "$AUR_DIR/$TARBALL$SIGNATURE_EXT"
        fi
    else
        printf 'Assets already exist on GitHub release %s. No upload was performed.\n' "$PKGVER" >&2
    fi
    printf 'Then, copy the generated PKGBUILD and .SRCINFO to your local AUR git repository, commit, and push to update the AUR package.\n'
    install_pkg "aur"
}
