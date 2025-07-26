# aurgen

**AUR Packaging Automation Script for Arch Linux**

`aurgen` is a general-purpose Bash utility for automating the creation, maintenance, and testing of Arch Linux AUR packaging files. It streamlines the process of generating tarballs, updating `PKGBUILD` and `.SRCINFO` files, and preparing packages for local testing or AUR submission. It can be used to package software from any GitHub project, not just a specific repository.

> **Note:** aurgen is designed for **GNU/Linux** systems only. It requires GNU Bash (v4+), GNU getopt (from `util-linux`), and other GNU-specific tools. aurgen will not work on BSD, macOS, or other non-GNU platforms.

## Features

- **Automated PKGBUILD Generation**: Creates complete PKGBUILD files with proper metadata, dependencies, and install functions
- **Smart Dependency Detection**: Automatically detects build systems and programming languages through README analysis, project file scanning, and comprehensive tool-to-package mapping
- **Multiple Package Modes**: Supports local builds, AUR release, and -git (VCS) package generation
- **CI/Automation Support**: Environment variable-driven automation with development/release mode detection
- **Built-in Testing Framework**: Test mode runs all modes in dry-run for validation
- **GPG Integration**: Automatic signing with smart key selection and ASCII armor support

## Installation

1. Copy or symlink the `bin/aurgen` script to a directory in your `$PATH`.
2. Ensure the `lib/` directory is available at `/usr/lib/aurgen` (or set the `AURGEN_LIB_DIR` environment variable accordingly).
3. Install dependencies:
   - **Required:** `bash` (v4+), `getopt` (GNU, from `util-linux`), `makepkg`, `updpkgsums`, `curl`, `jq`
   - **Optional:** `gpg` (for signing), `gh` (for GitHub asset upload), `shellcheck` (for linting)

> aurgen prints tool installation hints if a required tool is missing.

## Usage

```sh
aurgen [OPTIONS] MODE
```

### Modes

- **local**: Build and install the package from a local tarball (for testing). Creates a tarball from the current git repository, updates PKGBUILD and .SRCINFO, and runs `makepkg -si`.
- **aur**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload. Sets the source URL to the latest GitHub release tarball, updates checksums, and optionally runs `makepkg -si`. If the release asset does not exist, aurgen uploads it automatically (if `gh` is installed). If the asset already exists, you will be prompted to confirm overwriting before upload.
- **aur-git**: Generate a PKGBUILD for the -git (VCS) AUR package. Sets the source to the git repository, sets `b2sums=('SKIP')`, adds `validpgpkeys`, and optionally runs `makepkg -si`. No tarball is created or signed.
- **clean**: Remove all generated files and directories in the output folder, including tarballs, signatures, PKGBUILD, .SRCINFO, and build artifacts.
- **test**: Run all modes (local, aur, aur-git) in dry-run mode to check for errors and report results. Cleans before each test, provides detailed error reporting, and is useful for CI/CD pipelines.
- **lint**: Run `shellcheck` and `bash -n` on all Bash scripts for linting. Exits with nonzero status if any check fails.
- **golden**: Regenerate the golden PKGBUILD files for test comparison.

### Options

For detailed option descriptions and examples, see [doc/AUR.md](doc/AUR.md).

**Quick reference:**
- `-n`, `--no-color`      Disable colored output
- `-d`, `--dry-run`       Dry run (no changes, for testing)
- `-h`, `--help`          Show detailed help and exit

> **All options must appear before the mode.**  
> Example: `aurgen -n --dry-run aur`

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

For more detailed documentation, advanced usage, and troubleshooting, see [doc/AUR.md](doc/AUR.md).

## PKGBUILD Generation

aurgen automatically generates and manages PKGBUILD files through a template-based system:

### PKGBUILD.0 Template

- `PKGBUILD.0` is the canonical template for your package's build instructions
- All automated PKGBUILD generation and updates are based on this file
- You should edit `PKGBUILD.0` directly for any customizations
- If the file is missing or invalid, aurgen will regenerate it and back up the previous version as `PKGBUILD.0.bak`

### Automatic Generation

If `PKGBUILD.0` doesn't exist, aurgen can automatically generate a basic template with:
- **Metadata Extraction**: Automatically extracts package name, version, description, and license from the project
- **Build System Detection**: Detects CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, or Autotools
- **Dependency Detection**: Automatically populates `makedepends` based on detected build systems and project files
- **Install Function Generation**: Creates basic install commands for common project layouts
- **GitHub Integration**: Sets up proper source URLs and GPG key validation

### PKGBUILD.HEADER

aurgen generates a `PKGBUILD.HEADER` file containing metadata and legal information that is prepended to every generated `PKGBUILD` file. This ensures consistent copyright, maintainer, and license information across all packages.

**Contents:**
- Copyright and license statements (GPLv3 or as detected from your project)
- Maintainer information (auto-detected or prompted)
- Project metadata (name, version, description)
- Build system and packaging comments
- AUR compliance requirements

**Workflow:**
- Created automatically during PKGBUILD.0 generation
- Combined with `PKGBUILD.0` to produce the final `PKGBUILD`
- Customizations are preserved unless aurgen detects outdated fields (backed up as `PKGBUILD.HEADER.bak`)
- Delete the file to force regeneration based on current project metadata

**Usage:**
- Edit `PKGBUILD.0` for build logic
- Edit `PKGBUILD.HEADER` for legal/metadata changes

This separation keeps PKGBUILD files organized and AUR-compliant.

## Dependency Detection System

aurgen automatically detects build dependencies through multiple methods:

### README Analysis
Scans README files for package manager commands (`pacman -S`, `apt install`, etc.) and explicit dependency sections.

### Project File Analysis
Analyzes git-tracked project files to detect:
- **Build Systems**: CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, Autotools
- **Programming Languages**: C/C++, TypeScript, Vala, SCSS/SASS
- **Frameworks**: Qt, GTK, and other common libraries

### Tool Mapping System
Uses a comprehensive mapping system that converts common tool names to their containing packages. The system currently maps **307 tools** across build tools, compilers, package managers, and utilities.

For detailed documentation on the tool mapping system, see [doc/MAPPING-SYSTEM.md](doc/MAPPING-SYSTEM.md).

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
- `MAXDEPTH`          Set maximum search depth for lint and clean modes (default: 5)

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
  - `PKGBUILD.0` — Template file for PKGBUILD generation
  - `PKGBUILD.HEADER` — Header template with maintainer information
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

---

## License

This project is licensed under the GNU General Public License v3.0 or later. See the [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](.github/CONTRIBUTING.md) for guidelines and [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md) for our community standards.

## Security

For security issues, please see [SECURITY.md](.github/SECURITY.md) for reporting procedures.