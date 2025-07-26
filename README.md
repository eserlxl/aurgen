# aurgen

**AUR Packaging Automation Script for Arch Linux**

`aurgen` is a general-purpose Bash utility for automating the creation, maintenance, and testing of Arch Linux AUR packaging files. It streamlines the process of generating tarballs, updating `PKGBUILD` and `.SRCINFO` files, and preparing packages for local testing or AUR submission. It can be used to package software from any GitHub project, not just a specific repository.

> **Note:** This tool is designed for **GNU/Linux** systems only. It requires GNU Bash (v4+), GNU getopt (from `util-linux`), and other GNU-specific tools. It will not work on BSD, macOS, or other non-GNU platforms.

## Features

- **Automated PKGBUILD Generation**: Creates complete PKGBUILD files with proper metadata, dependencies, and install functions
- **Smart Dependency Detection**: Automatically detects build systems (CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, Autotools) and programming languages (C/C++, TypeScript, Vala, SCSS/SASS)
- **Automatic Install Function Generation**: Scans project source tree for installable files and directories (`bin/`, `lib/`, `share/`, `LICENSE`, and CMake `build/` executables)
- **Multiple Package Modes**: Supports local builds, AUR release, and -git (VCS) package generation
- **Automatic GitHub Asset Management**: Uploads release assets if missing, prompts for overwrite confirmation if they exist
- **Comprehensive CI/automation Support**: Environment variable-driven automation with development/release mode detection
- **Reproducible Tarball Creation**: Proper mtime handling for consistent builds
- **Robust Error Handling**: Detailed error/warning messages with tool installation hints
- **Interactive and Non-interactive Modes**: Supports both manual and CI/CD workflows
- **Built-in Testing Framework**: Test mode runs all modes in dry-run for validation
- **Linting Support**: ShellCheck and bash syntax validation for all scripts
- **Golden File Testing**: Regenerates and compares against reference PKGBUILD files
- **Cleanup Utilities**: Removes generated files and artifacts
- **Colored Output**: Enhanced user experience with color-coded messages
- **GPG Integration**: Automatic signing with smart key selection (auto-selects immediately for single key, 10-second timeout for multiple keys) and ASCII armor support
- **Automatic PKGBUILD.0 Generation**: Can automatically generate a basic PKGBUILD.0 template if one doesn't exist, with proper metadata extraction from the project

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

## Tool Mapping System

aurgen includes an intelligent tool mapping system that automatically maps tool names to their corresponding Arch Linux packages. This system helps aurgen accurately detect dependencies when analyzing projects.

### Features

- **Automatic Discovery**: Analyzes Arch Linux packages, AUR packages, and system packages
- **Version Updates**: Automatically discovers current package versions (GTK4, Qt6, etc.)
- **Comprehensive Coverage**: Maps build tools, compilers, package managers, and utilities
- **Safe Updates**: Automatic backups and git integration for easy rollback

### Usage

```bash
# Update tool mappings
./dev-bin/update-mapping workflow

# Check current status
./dev-bin/update-mapping status

# Expand mappings only
./dev-bin/update-mapping expand

# Check what's available
./dev-bin/update-mapping check

# Dry run (see what would be done)
./dev-bin/update-mapping --dry-run workflow
```

### Current Statistics

The system currently maps **307 tools** across multiple categories:
- **Build tools**: 10 (cmake, make, ninja, etc.)
- **Compilers/Languages**: 36 (gcc, clang, python, rust, go, etc.)
- **Package managers**: 8 (npm, cargo, maven, gradle, etc.)
- **System tools**: 21 (ssh, rsync, tar, gzip, etc.)
- **Qt tools**: 29 (qmake, moc, uic, rcc, etc.)
- **GTK tools**: 16 (gtk-builder-tool, gtk-launch, etc.)
- **Database tools**: 5 (sqlite3, psql, mysql, etc.)
- **Media tools**: 6 (ffmpeg, convert, identify, etc.)
- **Security tools**: 5 (gpg, openssl, etc.)

For detailed documentation, see [doc/MAPPING-SYSTEM.md](doc/MAPPING-SYSTEM.md) and [doc/MAPPING-EXPANSION.md](doc/MAPPING-EXPANSION.md).

## Environment Variables for Automation/CI

- `NO_COLOR`: Set to any value to disable colored output (alternative to `--no-color`)
- `GPG_KEY_ID`: Set to your GPG key ID to skip the interactive key selection menu (auto-selects first key after 10-second timeout if not set)
- `AUTO`: Skip the GitHub asset upload prompt in `aur` mode
- `CI`: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines). **If set, aurgen automatically runs in development mode (RELEASE=0) unless RELEASE is explicitly set.**
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- `RELEASE`: Override automatic mode detection (1=release mode, 0=development mode)
- `AURGEN_LIB_DIR`: Set custom library directory path
- `AURGEN_LOG`: Set custom log file path (default: `/tmp/aurgen/aurgen.log`)
- `AURGEN_ERROR_LOG`: Set custom error log file path (default: `/tmp/aurgen/aurgen-error.log`)

## Release vs Development Mode

By default, aurgen runs in release mode (using system libraries and minimal logging). If the `CI` environment variable is set (as in most CI/CD systems), aurgen automatically switches to development mode (using local libraries and debug logging), unless the `RELEASE` variable is explicitly set. You can override this behavior by setting `RELEASE=1` or `RELEASE=0` in your environment as needed.

## Directory Structure

- `bin/aurgen` — Main CLI entrypoint
- `dev-bin/update-mapping` — Tool mapping update CLI (development tool)
- `lib/` — Helper libraries and mode scripts
  - `helpers.sh` — Core utility functions, error handling, and prompts
  - `init.sh` — Initialization and setup functions
  - `valid-modes.sh` — Mode validation and usage information
  - `colors.sh` — Color output and formatting
  - `detect-deps.sh` — Automatic dependency detection for build systems
  - `tool-mapping.sh` — Tool to package mapping for Arch Linux
  - `expand-mapping.sh` — Tool mapping expansion and update system
  - `gen-pkgbuild0.sh` — PKGBUILD generation with install function creation
  - `check-pkgbuild0.sh` — PKGBUILD validation and checking
  - `clean-mapping.sh` — Tool mapping cleanup utilities
  - `modes/` — Individual mode implementations
    - `aur.sh` — AUR release package mode
    - `aur-git.sh` — AUR VCS package mode
    - `local.sh` — Local build and test mode
    - `clean.sh` — Cleanup mode
    - `test.sh` — Testing framework mode
    - `lint.sh` — Code linting mode
    - `golden.sh` — Golden file generation mode
- `doc/` — Documentation
  - `AUR.md` — Comprehensive AUR documentation
  - `MAPPING-SYSTEM.md` — Tool mapping system documentation
  - `MAPPING-EXPANSION.md` — Tool mapping expansion documentation
- `aur/` — Generated AUR package files and artifacts
  - `PKGBUILD` — Generated package build file
  - `PKGBUILD.git` — Git version package build file
  - `.SRCINFO` — Package source information
  - `test/` — Test output files
  - `lint/` — Lint mode output
  - `aurgen/` — Git repository for package
- `.github/` — GitHub-specific files
  - `workflows/shellcheck.yml` — CI/CD pipeline for code quality
  - `ISSUE_TEMPLATE/` — Issue and feature request templates
  - `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` — Project governance
- `LICENSE` — GNU General Public License v3.0 or later

## License

This project is licensed under the GNU General Public License v3.0 or later. See the [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](.github/CONTRIBUTING.md) for guidelines and [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md) for our community standards.

## Security

For security issues, please see [SECURITY.md](.github/SECURITY.md) for reporting procedures.