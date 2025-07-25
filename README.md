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
- **Automatic GitHub asset upload:** If the release asset does not exist, aurgen uploads it automatically (if `gh` is installed). If the asset already exists, you will be prompted to confirm overwriting before upload.
- **Comprehensive CI/automation support** (via environment variables; automatically runs in development mode if CI is detected)
- **Reproducible tarball creation** (mtime handling)
- **Robust error handling and tool hints**
- **Interactive and non-interactive (CI) modes**
- **Can be used to package software from any GitHub project**
- **Automatic PKGBUILD install step generation:** aurgen now scans the filtered project source tree for installable files and directories (`bin/`, `lib/`, `share/`, `LICENSE`, and for CMake: `build/` executables). The generated `package()` function in PKGBUILD will include the appropriate `install` commands for these files, reducing the need for manual editing for common project layouts.
- **Automatic makedepends detection:** aurgen automatically detects and populates the `makedepends` array based on project files. It detects build systems (CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, Autotools), programming languages (C/C++, TypeScript, Vala, SCSS/SASS), and common build tools (pkg-config, gettext, asciidoc). The detection uses git-tracked files filtered by the same logic used for AUR package creation, ensuring only relevant source files are considered.

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
- `--maxdepth N`          Set maximum search depth for lint mode only (default: 5)
- `-h`, `--help`          Show detailed help and exit
- `--usage`               Show minimal usage and exit

> **All options must appear before the mode.**  
> Example: `aurgen -n --dry-run aur`

### Modes

- **local**: Build and install the package from a local tarball (for testing). Creates a tarball from the current git repository, updates PKGBUILD and .SRCINFO, and runs `makepkg -si`.
- **aur**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload. Sets the source URL to the latest GitHub release tarball, updates checksums, and optionally runs `makepkg -si`. If the release asset does not exist, aurgen uploads it automatically (if `gh` is installed). If the asset already exists, you will be prompted to confirm overwriting before upload.
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
- `CI`: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines). **If set, aurgen automatically runs in development mode (RELEASE=0) unless RELEASE is explicitly set.**
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)

## Release vs Development Mode

By default, aurgen runs in release mode (using system libraries and minimal logging). If the `CI` environment variable is set (as in most CI/CD systems), aurgen automatically switches to development mode (using local libraries and debug logging), unless the `RELEASE` variable is explicitly set. You can override this behavior by setting `RELEASE=1` or `RELEASE=0` in your environment as needed.

## Directory Structure

- `bin/aurgen` — Main CLI entrypoint
- `lib/` — Helper libraries and mode scripts
  - `helpers.sh`, `init.sh`, `valid-modes.sh`, `colors.sh`, `