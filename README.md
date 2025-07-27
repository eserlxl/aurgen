# AURGen

**AUR Packaging Automation Script for Arch Linux**

`AURGen` is a general-purpose Bash utility for automating the creation, maintenance, and testing of Arch Linux AUR packaging files. It streamlines the process of generating tarballs, updating `PKGBUILD` and `.SRCINFO` files, and preparing packages for local testing or AUR submission. It can be used to package software from any GitHub project, not just a specific repository.

> **Note:** AURGen is designed for **GNU/Linux** systems only. It requires GNU Bash (v4+), GNU getopt (from `util-linux`), and other GNU-specific tools. AURGen will not work on BSD, macOS, or other non-GNU platforms.

## Table of Contents

- [Features](#features)
- [Automation & CI/CD](#automation--cicd)
- [Installation](#installation)
- [Usage](#usage)
  - [Modes](#modes)
  - [Options](#options)
- [PKGBUILD Generation](#pkgbuild-generation)
  - [Configuration System](#configuration-system)
    - [Overview](#overview)
    - [Configuration File Locations](#configuration-file-locations)
    - [Configuration Format](#configuration-format)
    - [Examples](#examples)
    - [Managing Configuration](#managing-configuration)
    - [Default Configuration](#default-configuration)
    - [Exclusions](#exclusions)
    - [Important Notes](#important-notes)
  - [PKGBUILD.0 Template](#pkgbuild0-template)
  - [Automatic Generation](#automatic-generation)
  - [PKGBUILD.HEADER](#pkgbuildheader)
- [Dependency Detection System](#dependency-detection-system)
  - [README Analysis](#readme-analysis)
  - [Project File Analysis](#project-file-analysis)
  - [Tool Mapping System](#tool-mapping-system)
- [Versioning](#versioning)
  - [Version Bumping](#version-bumping)
- [GitHub CLI Integration](#github-cli-integration)
- [Environment Variables for Automation/CI](#environment-variables-for-automationci)
- [Release vs Development Mode](#release-vs-development-mode)
- [Directory Structure](#directory-structure)
- [License](#license)
- [Contributing](#contributing)
- [Security](#security)

## Features

- **Automated PKGBUILD Generation**: Creates complete PKGBUILD files with proper metadata, dependencies, and install functions
- **Smart Dependency Detection**: Automatically detects build systems and programming languages through README analysis, project file scanning, and comprehensive tool-to-package mapping
- **Multiple Package Modes**: Supports local builds, AUR release, and -git (VCS) package generation
- **CI/Automation Support**: Environment variable-driven automation with development/release mode detection
- **Built-in Testing Framework**: Comprehensive test mode that validates all packaging modes in dry-run mode
- **Robust GPG Integration**: Automatic signing with smart key selection, ASCII armor support, and graceful fallback for test environments
- **Semantic Versioning**: Full semantic versioning support with automated version bumping and git integration
- **Error Handling**: Comprehensive error checking with helpful installation hints and graceful degradation for missing tools

[↑ Back to top](#aurgen)

## Automation & CI/CD

AURGen includes comprehensive GitHub Actions automation for security, quality, and maintenance:

- **🔄 Auto Version Bump**: Automatically bumps semantic versions and creates releases based on conventional commit messages
- **🔒 Security Scanning**: CodeQL vulnerability detection for supported languages (JavaScript, Python) and ShellCheck for shell scripts
- **📦 Dependency Updates**: Dependabot automatically updates GitHub Actions and other dependencies
- **✅ Quality Checks**: ShellCheck linting and functional testing on every change
- **🚀 Release Automation**: Automated release creation with changelog generation

All automation runs on pushes to main and pull requests, ensuring code quality and security.

[↑ Back to top](#aurgen)

## Installation

1. Copy or symlink the `bin/aurgen` script to a directory in your `$PATH`.
2. Ensure the `lib/` directory is available at `/usr/lib/aurgen` (or set the `AURGEN_LIB_DIR` environment variable accordingly).
3. Install dependencies:
   - **Required:** `bash` (v4+), `getopt` (GNU, from `util-linux`), `makepkg`, `updpkgsums`, `curl`, `jq`
   - **Optional:** `gpg` (for signing), `gh` (for GitHub asset upload), `shellcheck` (for linting)

> AURGen prints tool installation hints if a required tool is missing.

[↑ Back to top](#aurgen)

## Usage

```sh
aurgen [OPTIONS] MODE
```

### Modes

- **local**: Build and install the package from a local tarball for testing.
- **aur**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload.
- **aur-git**: Generate a PKGBUILD for the -git (VCS) AUR package.
- **clean**: Remove all generated files and directories in the output folder.
- **test**: Run all modes in dry-run mode to check for errors and report results.
- **lint**: Run `shellcheck` and `bash -n` on all Bash scripts for linting.
- **golden**: Regenerate the golden PKGBUILD files for test comparison.
- **config**: Manage AURGen configuration for directory copying behavior.

### Options

**Quick reference:**
- `-n`, `--no-color`      Disable colored output
- `-d`, `--dry-run`       Dry run (no changes, for testing)
- `-h`, `--help`          Show detailed help and exit

> **All options must appear before the mode.**  
> Example: `aurgen -n --dry-run aur`

For more detailed documentation, advanced usage, and troubleshooting, see [doc/AUR.md](doc/AUR.md).

[↑ Back to top](#aurgen)

## PKGBUILD Generation

AURGen automatically generates and manages PKGBUILD files through a template-based system:

### Configuration System

AURGen includes a flexible configuration system that allows you to customize which directories are copied during package installation. This is particularly useful for projects that don't need all the default directories or have custom directory structures.

#### Overview

The configuration system automatically generates two files in the `aur/` directory when PKGBUILD.0 is created for the first time:
- **`aurgen.install.yaml`** - Your project's active configuration
- **`aurgen.install.yaml.example`** - Reference example with documentation

#### Configuration File Locations
- `aur/aurgen.install.yaml` - Project-specific configuration file
- `aur/aurgen.install.yaml.example` - Example configuration file with documentation

#### Configuration Format
```
source_dir:dest_dir:permissions[:exclude1,exclude2,...]
```

**Field Descriptions:**
- `source_dir` - Directory in your project root to copy from
- `dest_dir` - Destination path in the package (supports `$pkgname` variable)
- `permissions` - Octal permissions (e.g., 755 for executable, 644 for read-only)
- `exclude1,exclude2,...` - **Optional**: Comma-separated list of subdirectories or files to exclude

#### Examples
```bash
# Basic examples
bin:usr/bin:755          # Copy bin/ to usr/bin/ with executable permissions
lib:usr/lib/$pkgname:644 # Copy lib/ to usr/lib/$pkgname/ with read permissions
etc:etc/$pkgname:644     # Copy etc/ to etc/$pkgname/ with read permissions

# Exclude specific subdirectories
etc:etc/$pkgname:644:test,temp     # Copy etc/ but exclude test/ and temp/ subdirectories
share:usr/share/$pkgname:644:docs,examples  # Copy share/ but exclude docs/ and examples/

# Exclude single directory
local:usr/local/$pkgname:644:cache  # Copy local/ but exclude cache/ subdirectory

# Disable a directory (comment out)
# include:usr/include/$pkgname:644  # Won't copy include/ directory

# Custom directories with exclusions
custom:usr/share/$pkgname/custom:644:backup,old
```

#### Managing Configuration

**Generate Configuration:**
```bash
aurgen config generate    # Create default configuration file
```

**Edit Configuration:**
```bash
aurgen config edit        # Open in default editor
```

**View Configuration:**
```bash
aurgen config show        # Display current configuration
aurgen config validate    # Validate syntax and show active rules
```

**Reset Configuration:**
```bash
aurgen config reset       # Reset to defaults (creates backup)
```

**Get Help:**
```bash
aurgen config help        # Show detailed usage information
```

#### Default Configuration

The default configuration includes these directories:
- `bin` → `usr/bin` (755 - executable files)
- `lib` → `usr/lib/$pkgname` (644 - library files)
- `etc` → `etc/$pkgname` (644 - configuration files)
- `share` → `usr/share/$pkgname` (644 - shared data)
- `include` → `usr/include/$pkgname` (644 - header files)
- `local` → `usr/local/$pkgname` (644 - local data)
- `var` → `var/$pkgname` (644 - variable data)
- `opt` → `opt/$pkgname` (644 - optional data)

#### Exclusions

The exclusion feature allows you to copy most of a directory while excluding specific subdirectories or files. This is particularly useful for:

- **Development files**: Exclude `test/`, `temp/`, `backup/` directories
- **Documentation**: Exclude `docs/`, `examples/` when not needed in the package
- **Build artifacts**: Exclude `cache/`, `logs/`, `*.tmp` files
- **Development tools**: Exclude IDE-specific directories like `.vscode/`, `.idea/`

**Exclusion Patterns:**
- Exclusions are matched against subdirectories and files within the source directory
- Multiple exclusions are separated by commas (no spaces)
- Exclusions are case-sensitive and must match exact directory/file names
- The exclusion field is optional - omit it to copy everything

**Examples:**
```bash
# Exclude development and temporary files
etc:etc/$pkgname:644:test,temp,backup

# Exclude documentation and examples
share:usr/share/$pkgname:644:docs,examples,README.md

# Exclude cache and log files
var:var/$pkgname:644:cache,logs,*.tmp
```

#### Important Notes

- **Project-Specific**: Configuration files are stored in the `aur/` directory and are specific to each project
- **Auto-Generation**: Files are automatically created when PKGBUILD.0 is generated for the first time
- **No Overwriting**: Existing configuration files are never overwritten automatically
- **Backup Protection**: The `reset` command creates a `.bak` file before regenerating
- **Validation**: Use `aurgen config validate` to check your configuration syntax
- **Backward Compatibility**: Existing configurations without exclusions continue to work unchanged

### PKGBUILD.0 Template

- `PKGBUILD.0` is the canonical template for your package's build instructions
- All automated PKGBUILD generation and updates are based on this file
- You should edit `PKGBUILD.0` directly for any customizations
- If the file is missing or invalid, AURGen will regenerate it and back up the previous version as `PKGBUILD.0.bak`

### Automatic Generation

If `PKGBUILD.0` doesn't exist, AURGen can automatically generate a basic template with:
- **Metadata Extraction**: Automatically extracts package name, version, description, and license from the project
- **Build System Detection**: Detects CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, or Autotools
- **Dependency Detection**: Automatically populates `makedepends` based on detected build systems and project files
- **Install Function Generation**: Creates basic install commands for common project layouts
- **GitHub Integration**: Sets up proper source URLs and GPG key validation

### PKGBUILD.HEADER

AURGen generates a `PKGBUILD.HEADER` file containing metadata and legal information that is prepended to every generated `PKGBUILD` file. This ensures consistent copyright, maintainer, and license information across all packages.

**Contents:**
- Copyright and license statements (GPLv3 or as detected from your project)
- Maintainer information (auto-detected or prompted)
- Project metadata (name, version, description)
- Build system and packaging comments
- AUR compliance requirements

**Workflow:**
- Created automatically during PKGBUILD.0 generation
- Combined with `PKGBUILD.0` to produce the final `PKGBUILD`
- Customizations are preserved unless AURGen detects outdated fields (backed up as `PKGBUILD.HEADER.bak`)
- Delete the file to force regeneration based on current project metadata

**Usage:**
- Edit `PKGBUILD.0` for build logic
- Edit `PKGBUILD.HEADER` for legal/metadata changes

This separation keeps PKGBUILD files organized and AUR-compliant.

[↑ Back to top](#aurgen)

## Dependency Detection System

AURGen automatically detects build dependencies through multiple methods:

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

[↑ Back to top](#aurgen)

## Versioning

AURGen follows [Semantic Versioning (SemVer)](https://semver.org/) principles. The current version is stored in the `VERSION` file and can be displayed using:

```bash
aurgen --version
# Output: aurgen version 1.0.0
```

### Version Bumping

Use the included version bumping script for consistent version management:

```bash
# Bump patch version (bug fixes)
./dev-bin/bump-version patch

# Bump minor version (new features) and create commit
./dev-bin/bump-version minor --commit

# Bump major version (breaking changes), commit, and tag
./dev-bin/bump-version major --commit --tag
```

For detailed versioning documentation, see [doc/VERSIONING.md](doc/VERSIONING.md).

[↑ Back to top](#aurgen)

## GitHub CLI Integration

AURGen integrates with GitHub CLI (`gh`) to automatically upload release assets:

- **Automatic Asset Upload**: If GitHub CLI is installed, AURGen can automatically upload missing release assets to GitHub releases
- **Smart Asset Management**: When a release asset doesn't exist, AURGen uploads the tarball and signature automatically (no prompt)
- **Overwrite Protection**: If the asset already exists, you'll be prompted to confirm overwriting before upload
- **CI/Automation**: Set the `AUTO` environment variable to skip the upload prompt (always overwrite)
- **Graceful Fallback**: If GitHub CLI is not installed, AURGen provides clear instructions for manual upload

[↑ Back to top](#aurgen)

## Environment Variables for Automation/CI

- `NO_COLOR`: Set to any value to disable colored output (alternative to `--no-color`)
- `GPG_KEY_ID`: Set to your GPG key ID to skip the interactive key selection menu (auto-selects first key after 10-second timeout if not set)
- `AUTO`: Skip the GitHub asset upload prompt in `aur` mode (requires GitHub CLI `gh` to be installed)
- `CI`: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines). **If set, AURGen automatically runs in development mode (RELEASE=0) unless RELEASE is explicitly set.**
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- `RELEASE`: Override automatic mode detection (1=release mode, 0=development mode)
- `AURGEN_LIB_DIR`: Set custom library directory path
- `AURGEN_LOG`: Set custom log file path (default: `/tmp/aurgen/aurgen.log`)
- `AURGEN_ERROR_LOG`: Set custom error log file path (default: `/tmp/aurgen/aurgen-error.log`)
- `MAXDEPTH`          Set maximum search depth for lint and clean modes (default: 5)

[↑ Back to top](#aurgen)

## Release vs Development Mode

By default, AURGen runs in release mode (using system libraries and minimal logging). If the `CI` environment variable is set (as in most CI/CD systems), AURGen automatically switches to development mode (using local libraries and debug logging), unless the `RELEASE` variable is explicitly set. You can override this behavior by setting `RELEASE=1` or `RELEASE=0` in your environment as needed.

[↑ Back to top](#aurgen)

## Directory Structure

- `bin/aurgen` — Main CLI entrypoint
- `dev-bin/update-mapping` — Tool mapping update CLI (development tool)
- `dev-bin/bump-version` — Version bumping script (development tool)
- `VERSION` — Current semantic version number
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
  - `VERSIONING.md` — Semantic versioning system documentation
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
  - `workflows/` — GitHub Actions automation
    - `version-bump.yml` — Automatic semantic versioning and release creation
    - `codeql.yml` — Security vulnerability scanning with CodeQL for supported languages (future expansion)
    - `shellcheck.yml` — Shell script linting and code quality checks
    - `test.yml` — Functional testing pipeline that validates all packaging modes
  - `dependabot.yml` — Automated dependency updates for GitHub Actions
  - `ISSUE_TEMPLATE/` — Issue and feature request templates
  - `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` — Project governance
- `LICENSE` — GNU General Public License v3.0 or later

[↑ Back to top](#aurgen)

---

## License

This project is licensed under the GNU General Public License v3.0 or later. See the [LICENSE](LICENSE) file for details.

[↑ Back to top](#aurgen)

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](.github/CONTRIBUTING.md) for guidelines and [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md) for our community standards.

[↑ Back to top](#aurgen)

## Security

For security issues, please see [SECURITY.md](.github/SECURITY.md) for reporting procedures.

[↑ Back to top](#aurgen)