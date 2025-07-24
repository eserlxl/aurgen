# aurgen

**AUR Packaging Automation Script for Arch Linux**

`aurgen` is a general-purpose Bash utility for automating the creation, maintenance, and testing of Arch Linux AUR packaging files. It streamlines the process of generating tarballs, updating `PKGBUILD` and `.SRCINFO` files, and preparing packages for local testing or AUR submission. It can be used to package software from any GitHub project, not just a specific repository.

> **Note:** This tool is designed for **GNU/Linux** systems only. It requires GNU Bash (v4+), GNU getopt (from util-linux), and other GNU-specific tools. It will not work on BSD, macOS, or other non-GNU platforms.

## Features

- Automates tarball creation, PKGBUILD and .SRCINFO updates
- Supports local builds, AUR release, and -git (VCS) package generation
- Cleans up generated files and artifacts
- Lints Bash scripts with `shellcheck` and `bash -n`
- Regenerates and tests against golden PKGBUILD files for CI
- Provides colored output and detailed error/warning messages
- Prints tool installation hints for missing dependencies
- **Automatic GitHub asset upload** (if `gh` is installed)
- **Comprehensive CI/automation support** (via environment variables)
- **Reproducible tarball creation** (mtime handling)
- **Robust error handling and tool hints**
- **Interactive and non-interactive (CI) modes**
- **Can be used to package software from any GitHub project**

## Installation

1. Copy or symlink the `bin/aurgen` script to a directory in your `$PATH`.
2. Ensure the `lib/` directory is available at `/usr/lib/aurgen` (or set the `LIB_INSTALL_DIR` variable accordingly).
3. Install dependencies:
   - **Required:** `bash` (v4+), `getopt` (GNU, from `util-linux`), `makepkg`, `updpkgsums`, `curl`, `jq`
   - **Optional:** `gpg` (for signing), `gh` (for GitHub asset upload), `shellcheck` (for linting)

> The script prints tool installation hints if a required tool is missing.

## Usage

```sh
aurgen [OPTIONS] MODE
```

### Options

- `-n`, `--no-color`      Disable colored output
- `-a`, `--ascii-armor`   Use ASCII-armored GPG signatures (.asc)
- `-d`, `--dry-run`       Dry run (no changes, for testing)
- `--no-wait`             Skip post-upload wait for asset availability (for CI)
- `-h`, `--help`          Show detailed help and exit
- `--usage`               Show minimal usage and exit

> **All options must appear before the mode.**  
> Example: `aurgen -n --dry-run aur`

### Modes

- **local**: Build and install the package from a local tarball (for testing). Creates a tarball from the current git repository, updates PKGBUILD and .SRCINFO, and runs `makepkg -si`.
- **aur**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload. Sets the source URL to the latest GitHub release tarball, updates checksums, and optionally runs `makepkg -si`. Can automatically upload missing assets to GitHub releases if GitHub CLI is installed.
- **aur-git**: Generate a PKGBUILD for the -git (VCS) AUR package. Sets the source to the git repository, sets `sha256sums=('SKIP')`, adds `validpgpkeys`, and optionally runs `makepkg -si`. No tarball is created or signed.
- **clean**: Remove all generated files and directories in the output folder, including tarballs, signatures, PKGBUILD, .SRCINFO, and build artifacts.
- **test**: Run all modes (local, aur, aur-git) in dry-run mode to check for errors and report results. Cleans before each test, provides detailed error reporting, and is useful for CI/CD pipelines.
- **lint**: Run `shellcheck` and `bash -n` on all Bash scripts for linting. Exits with nonzero status if any check fails.
- **golden**: Regenerate the golden PKGBUILD files for test comparison.

### Example

```sh
aurgen local
aurgen aur-git
aurgen clean
aurgen test
aurgen lint
aurgen golden
aurgen --no-color --dry-run aur
```

---
For more detailed documentation, advanced usage, and troubleshooting, see [doc/AUR.md](doc/AUR.md).

## Environment Variables for Automation/CI

- `NO_COLOR`: Set to any value to disable colored output (alternative to `--no-color`)
- `GPG_KEY_ID`: Set to your GPG key ID to skip the interactive key selection menu
- `AUTO`: Skip the GitHub asset upload prompt in `aur` mode
- `CI`: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines)
- `DRY_RUN`: Set to `1` to enable dry-run mode (alternative to `--dry-run`/`-d` flag)
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)

## Directory Structure

- `bin/aurgen` — Main CLI entrypoint
- `lib/` — Helper libraries and mode scripts
  - `helpers.sh`, `init.sh`, `valid-modes.sh`, `colors.sh`, `check-pkgbuild0.sh`, `gen-pkgbuild0.sh`, etc.
  - `modes/` — Mode-specific logic (`aur.sh`, `local.sh`, `aur-git.sh`, `clean.sh`, `lint.sh`, `golden.sh`, `test.sh`)
- `doc/AUR.md` — Detailed documentation and usage notes

## About PKGBUILD.0

- `PKGBUILD.0` is the template file for generating the actual `PKGBUILD` used for building and releasing your package.
- You can manually edit `PKGBUILD.0` to customize package metadata, dependencies, or build steps.
- If `PKGBUILD.0` is missing or invalid, `aurgen` will automatically regenerate it and back up your previous version as `PKGBUILD.0.bak`.
- **Warning:** If you make manual changes, ensure the file remains valid to avoid automatic regeneration and possible loss of unsaved edits. Your last version will always be saved as `PKGBUILD.0.bak` if regeneration occurs.

## Requirements

- GNU Bash 4+
- GNU getopt (from util-linux)
- Standard Arch packaging tools: `makepkg`, `updpkgsums`, `curl`, `jq`
- Optional: `gpg` for signing, `gh` for GitHub asset upload, `shellcheck` for linting

## License

This project is licensed under the **GNU General Public License v3.0 or later**. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions, bug reports, and suggestions are welcome! Please open an issue or submit a pull request.
