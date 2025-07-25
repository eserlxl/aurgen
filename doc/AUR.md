# aurgen: AUR Packaging Automation Script

`aurgen` is a utility script for automating the creation and maintenance of Arch Linux AUR packaging files for Github projects. It streamlines the process of generating tarballs, updating PKGBUILD and .SRCINFO files, and preparing the package for local testing or AUR submission.

> **Important:** This script is **only for GNU/Linux systems**. It will not work on BSD, macOS, or other non-GNU platforms. It requires GNU getopt (from util-linux) and other GNU-specific tools. Attempting to run it on non-GNU systems will result in a clear error message and immediate exit.

## Overview
- **Purpose:** Automates tarball creation, PKGBUILD and .SRCINFO updates, and AUR packaging tasks for GitHub projects.
- **License:** GPLv3 or later (see LICENSE)
- **Platform:** The script is designed for **GNU/Linux environments only** and does not aim to support macOS, BSD, or any non-GNU system. It requires GNU getopt (util-linux) and will not work with BSD/macOS getopt implementations.
- **Bash Version:** The script requires **Bash version 4 or newer**. It will exit with an error if run on an older version.
- **Tool Hints:** If a required tool is missing, the script will print a hint with an installation suggestion (e.g., pacman -S pacman-contrib for updpkgsums).

## Usage

```sh
/usr/bin/aurgen [OPTIONS] MODE
```

- To print a minimal usage line (for scripts/AUR helpers):
  ```sh
  /usr/bin/aurgen --usage
  # or
  /usr/bin/aurgen -h
  ```
  This prints:
  ```
  Usage: aurgen [OPTIONS] MODE
  Modes: local | aur | aur-git | clean | test | lint | golden
  ```

- To print detailed help (options, documentation pointers, etc.):
  ```sh
  /usr/bin/aurgen --help
  ```
  This prints a detailed help message including options and documentation pointers.

> **Note:** All flags/options must appear before the mode. For example: `/usr/bin/aurgen -n --dry-run aur`. Flags after the mode are not supported.
> 
> **Options are now parsed using getopt for unified short and long option support, improving robustness and maintainability.**

### Modes

- **`local`**: Build and install the package from a local tarball (for testing). Creates a tarball from the current git repository, updates PKGBUILD and .SRCINFO, and runs `makepkg -si`.
- **`aur`**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload. Sets the source URL to the latest GitHub release tarball, updates checksums, and optionally runs `makepkg -si`. If the release asset does not exist, aurgen uploads it automatically (if `gh` is installed). If the asset already exists, you will be prompted to confirm overwriting before upload.
- **`aur-git`**: Generate a PKGBUILD for the -git (VCS) AUR package. Sets the source to the git repository, sets `sha256sums=('SKIP')`, adds `validpgpkeys`, and optionally runs `makepkg -si`. No tarball is created or signed.
- **`clean`**: Remove all generated files and directories in the `aur/` folder, including tarballs, signatures, PKGBUILD, .SRCINFO, and build artifacts.
- **`test`**: Run all modes (local, aur, aur-git) in dry-run mode to check for errors and report results. Useful for verifying all modes work correctly without performing actual operations.
- **`lint`**: Run `shellcheck` and `bash -n` on all `.sh` files in the project, skipping the `aur/` directory and using a maximum search depth of 5. This is a quick self-test/linting mode for CI or local development. Exits with nonzero status if any check fails. Example:
  ```sh
  /usr/bin/aurgen lint
  ```
  This will run both tools and print a summary. If `shellcheck` is not installed, it will be skipped with a warning.
- **`golden`**: Regenerate the golden PKGBUILD files in `test/fixtures/` for test comparison. This mode always runs `clean` before regenerating golden files. It is used to update the reference PKGBUILD files that are compared in test mode.

### Options

- **`--no-color`, `-n`**: Disable colored output (for accessibility or when redirecting output). You can also set the `NO_COLOR` environment variable to any value to disable color.
- **`--ascii-armor`, `-a`**: Use ASCII-armored signatures (.asc) instead of binary signatures (.sig) for GPG signing. Some AUR helpers (like aurutils) prefer ASCII-armored signatures.
- **`--dry-run`, `-d`**: Run all steps except the final `makepkg -si` (useful for CI/testing).
- **`--no-wait`**: Skip the post-upload wait for asset availability after uploading assets to GitHub releases (for CI/advanced users). Can also be enabled by setting the `NO_WAIT=1` environment variable. This disables the wait/retry/prompt after uploading assets in `aur` mode, allowing for faster CI or scripting workflows. If the asset is not immediately available, you may need to retry `makepkg` after a short delay.
- **`--help`, `-h`**: Print detailed help and exit (includes options, documentation pointers, etc.).
- **`--usage`**: Print a minimal usage line and exit (no color, no extra text; suitable for scripts/AUR helpers).

> **Important:** All options/flags must be specified before the mode. For example:
> ```sh
> /usr/bin/aurgen --no-color --ascii-armor --dry-run aur
> /usr/bin/aurgen -n -a -d aur
> ```
> The following is **not** supported:
> ```sh
> /usr/bin/aurgen aur --dry-run   # Not supported
> ```
> 
> **Options are parsed using getopt for unified short and long option support.**

### Log Files and Directory

By default, all logs are written to `/tmp/aurgen/aurgen.log` and errors to `/tmp/aurgen/aurgen-error.log`. You can customize these locations using the `AURGEN_LOG` and `AURGEN_ERROR_LOG` environment variables. The script will create `/tmp/aurgen` if it does not exist.

### Disabling Colored Output

You can disable colored output in two ways:

- By passing the `--no-color` or `-n` option **before the mode**:
  ```sh
  /usr/bin/aurgen --no-color aur
  ```
- By setting the `NO_COLOR` environment variable to any value (including empty):
  ```sh
  NO_COLOR= /usr/bin/aurgen aur
  ```
  This is useful for CI, automation, or when redirecting output to files.

### ASCII-Armored Signatures

By default, the script creates binary GPG signatures (.sig files). Some AUR helpers and maintainers prefer ASCII-armored signatures (.asc files) for better compatibility and readability.

To use ASCII-armored signatures, add the `--ascii-armor` or `-a` option **before the mode**:

```sh
/usr/bin/aurgen --ascii-armor aur
```

This will:
- Use `gpg --armor --detach-sign` instead of `gpg --detach-sign`
- Create `.asc` files instead of `.sig` files
- Update all references to signature files in logs and messages
- Clean up both `.sig` and `.asc` files when using the `clean` mode

### GPG Key Automation

- For `aur` mode, a GPG secret key is required to sign the release tarball.
- By default, the script will prompt you to select a GPG key from your available secret keys.
- **To skip the interactive menu and use a specific key, set the `GPG_KEY_ID` environment variable:**

  ```sh
  GPG_KEY_ID=ABCDEF /usr/bin/aurgen aur
  ```
  Replace `ABCDEF` with your GPG key's ID or fingerprint. This is useful for automation or CI workflows.

### Test Mode

- The `test` mode runs all other modes (local, aur, aur-git) in dry-run mode to verify they work correctly.
- Each test runs in isolation with a clean environment (automatically runs clean before each test).
- Test mode handles GPG prompts by creating dummy signature files for testing purposes.
- Provides comprehensive error reporting and shows which tests passed or failed.
- Useful for CI/CD pipelines or verifying script functionality before actual use.

  ```sh
  /usr/bin/aurgen test
  ```

### GitHub CLI Integration

- If GitHub CLI (`gh`) is installed, the script can automatically upload missing release assets to GitHub releases.
- When a release asset is not found, the script will upload the tarball and signature automatically (no prompt).
- If the asset already exists, you will be prompted to confirm overwriting before upload.
- To skip the upload prompt (always overwrite), set the `AUTO` environment variable.
- If GitHub CLI is not installed, the script will provide clear instructions for manual upload.

### CI/Automation Support

- Set `CI=1` to skip interactive prompts in `aur` mode (automatically skips `makepkg -si` prompt). **If `CI` is set, aurgen automatically runs in development mode (RELEASE=0) unless `RELEASE` is explicitly set.**
- Set `AUTO=y` to skip the GitHub asset upload prompt.
- Set `GPG_KEY_ID` to avoid GPG key selection prompts.
- Use `--dry-run` to test without installing packages (must be before the mode).
- Use `--no-wait` or set `NO_WAIT=1` to skip the post-upload wait for asset availability (for CI/advanced users). This disables the wait/retry/prompt after uploading assets in `aur` mode.

> **Prompt Handling and CI Safety:**
> All interactive prompts in this script always supply a default value. This ensures that, even in CI or headless environments (when `CI=1`), the default is automatically selected and the corresponding variable is always set. This design prevents failures due to unset variables and is intentional for robust automation. If you add new prompts, always supply a default value to maintain this guarantee.

### Environment Variables

The script supports several environment variables for automation and customization:

- **`NO_COLOR`**: Set to any value to disable colored output (alternative to `--no-color` option)
- **`GPG_KEY_ID`**: Set to your GPG key ID to skip the interactive key selection menu
- **`AUTO`**: Skip the GitHub asset upload prompt in `aur` mode
- **`CI`**: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines)
- **`DRY_RUN`**: Set to `1` to enable dry-run mode (alternative to `--dry-run`/`-d` flag)
- **`NO_WAIT`**: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- **`AURGEN_LOG`**: Set to customize the main log file location (default: `/tmp/aurgen/aurgen.log`)
- **`AURGEN_ERROR_LOG`**: Set to customize the error log file location (default: `/tmp/aurgen/aurgen-error.log`)

## Variable Naming Conventions

- Local, mutable variables use lowercase (e.g., `dry_run`, `ascii_armor`, `color_enabled`).
- ALL-CAPS is reserved for readonly constants and exported variables (e.g., `PKGNAME`, `PROJECT_ROOT`).
- This helps quickly distinguish between constants/globals and local, mutable state.

## How It Works

### Tarball Creation
- Creates a new source tarball from the project root using `git archive`, excluding build and VCS files (except in `aur-git` mode).
- Uses `git archive` to respect `.gitignore` and only include tracked files.
- **Reproducibility:** Sets the tarball modification time (mtime) to a fixed date (2020-01-01) for reproducible builds. This ensures that repeated builds produce identical tarballs, regardless of when the script is run. (See [reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/))
- **Note:** `git archive` does _not_ include the contents of git submodules. If you ever add submodules to this project, the generated tarball will _not_ contain their files—only the main repository's files. You will need to update the packaging process to include submodule contents if submodules are introduced. See the [git-archive documentation](https://git-scm.com/docs/git-archive#_limitations) for details.

### PKGBUILD Generation
- Copies and updates PKGBUILD from the template file (`PKGBUILD.0`).
- Extracts `pkgver` from `PKGBUILD.0` using `awk` without sourcing the file.
- For `aur` mode: Updates the `source` line to point to the GitHub release tarball, tries both with and without 'v' prefix.
- For `aur-git` mode: Updates the `source` line to use the git repository, sets `sha256sums=('SKIP')`, and adds `validpgpkeys`.

### Checksums and .SRCINFO
- For `aur` and `local` modes: Runs `updpkgsums` to update checksums and generates `.SRCINFO`.
- For `aur-git` mode: Skips `updpkgsums` and sets `sha256sums=('SKIP')` (required for VCS packages).
- Uses `makepkg --printsrcinfo` (or `mksrcinfo` as fallback) to generate `.SRCINFO`.

> **Note for maintainers:**
> If you ever split sources by architecture (e.g., x86_64, aarch64), you must update the corresponding `b2sums_x86_64=()`, `b2sums_aarch64=()`, etc., arrays in addition to the generic `b2sums=()`. This script uses `b2sums` (BLAKE2) for checksums, not `sha256sums`. Adjust accordingly if you change the checksum type.

### GPG Signing (aur mode only)
- Checks for available GPG secret keys.
- Prompts for key selection or uses `GPG_KEY_ID` environment variable.
- Creates detached signature for the tarball (binary .sig by default, ASCII-armored .asc with `--ascii-armor`).
- In test mode, creates dummy signature files.

### GitHub Asset Upload
- Checks if release assets exist on GitHub.
- If not found and GitHub CLI is available, offers automatic upload.
- Uploads both tarball and signature files.
- Verifies upload success before proceeding.

### Installation
- For `aur` mode: Prompts before running `makepkg -si` (unless `CI=1` or `AUTO=y`).
- For other modes: Automatically runs `makepkg -si`.
- Respects `--dry-run` flag to skip installation (must be before the mode).

## Requirements

### Required Tools
- `bash` **version 4 or newer** (the script will exit with an error if run on Bash 3 or earlier)
- `makepkg` (from `pacman`)
- `updpkgsums` (from `pacman-contrib`)
- `curl` (for checking GitHub assets)
- `getopt` (**GNU version from util-linux; BSD/macOS getopt is NOT supported. This script is only for GNU/Linux.**)
- **Tool Hints:** If a required tool is missing, the script will print a hint with an installation suggestion (e.g., pacman -S pacman-contrib for updpkgsums).

> **Warning:** `pacman-contrib` is not included in the `base-devel` group on Arch Linux. You must install it separately, or you will get a `updpkgsums: command not found` error when building or packaging.

### Optional Tools
- `gpg` (required for `aur` mode signing)
- `gh` (GitHub CLI, for automatic asset upload)

### Files
- `PKGBUILD.0` template file in `aur/` directory

#### The Role of PKGBUILD.0

- `PKGBUILD.0` is the canonical template for your package’s build instructions.
- All automated PKGBUILD generation and updates are based on this file.
- You should edit `PKGBUILD.0` directly for any customizations.
- If the file is missing or invalid, `aurgen` will regenerate it and back up the previous version as `PKGBUILD.0.bak`.
- Always check `PKGBUILD.0.bak` if you need to recover manual changes after a regeneration.

## Notes for AUR Maintainers

- Always update `PKGVER` in `PKGBUILD.0` for new releases.
- The script expects `PKGBUILD.0` to exist and be up to date.
- The script will fail if required tools or the template are missing.
- For CI or automation, set `GPG_KEY_ID` to avoid interactive prompts.
- For CI or automation with automatic asset upload, set `AUTO=y` to skip upload prompts.
- For CI environments, set `CI=1` to skip all interactive prompts.
- Use `/usr/bin/aurgen test` to verify all modes work correctly before making changes or releases.
- The script automatically handles both 'v' and non-'v' prefixed GitHub release URLs.
- VCS packages (`aur-git` mode) automatically set `sha256sums=('SKIP')` and add `validpgpkeys`.
- All environment variables are documented in the script's usage function (`/usr/bin/aurgen` without arguments).
- Use `--ascii-armor` or `-a` to create ASCII-armored signatures (.asc) instead of binary signatures (.sig) for better compatibility with some AUR helpers (must be before the mode).

## Error Handling

- Comprehensive error checking for missing tools, files, and GPG keys.
- Graceful fallback for GitHub asset URLs (tries both with and without 'v' prefix).
- Clear error messages with actionable instructions.
- Test mode provides detailed error reporting for all modes.

## Argument Parsing: Why We Use 'eval set --'

The script uses GNU getopt for robust option parsing. To correctly handle quoted arguments and avoid subtle bugs (such as modes being passed with extra quotes), we use:

```bash
eval set -- "$getopt_output"
```

This is the recommended approach (see: https://mywiki.wooledge.org/BashFAQ/035) because it ensures that all arguments are split and quoted as the user intended, even if they contain spaces or special characters. Avoid using array-based splitting (e.g., `read -ra`) on getopt output, as it can introduce quoting bugs and break mode detection. This fix was introduced after a bug where the mode was parsed as `'lint'` (with quotes) instead of `lint`, causing the script to reject valid modes.

---
For more details, see the comments in `/usr/lib/aurgen/` and `/usr/bin/aurgen`.