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
- [Dependency Detection System](#dependency-detection-system)
  - [README Analysis](#readme-analysis)
  - [Project File Analysis](#project-file-analysis)
  - [Tool Mapping System](#tool-mapping-system)
- [Versioning](#versioning)
  - [Version Bumping](#version-bumping)
- [GitHub CLI Integration](#github-cli-integration)
- [Environment Variables for Automation/CI](#environment-variables-for-automationci)
- [Release vs Development Mode](#release-vs-development-mode)
- [Project Structure](#project-structure)
- [Community Guidelines](#community-guidelines)

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

AURGen automatically generates and manages PKGBUILD files through a template-based system with flexible configuration options. This includes:

- **Template-based Generation**: Uses `PKGBUILD.0` as the canonical template for build instructions
- **Configuration System**: Customizable directory copying with exclusion support via `aurgen.install.yaml`
- **Automatic Detection**: Build system detection, dependency analysis, and metadata extraction
- **Header Management**: Separate `PKGBUILD.HEADER` for consistent legal and maintainer information

For detailed documentation on PKGBUILD generation, configuration management, and advanced features, see [doc/PKGBUILD-GENERATION.md](doc/PKGBUILD-GENERATION.md).

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

## Project Structure

For a detailed overview of the project's directory structure, file organization, and design principles, see [doc/PROJECT-STRUCTURE.md](doc/PROJECT-STRUCTURE.md).

[↑ Back to top](#aurgen)

---

## Community Guidelines

### License

This project is licensed under the GNU General Public License v3.0 or later. See the [LICENSE](LICENSE) file for details.

### Contributing

We welcome contributions from everyone! Here's how you can help:

- **Bug Reports & Feature Requests**: Use the GitHub issue tracker with detailed descriptions
- **Pull Requests**: Fork the repository, create a feature branch, and submit a PR with clear descriptions
- **Code Style**: Follow existing conventions and include documentation updates

For detailed guidelines, see [CONTRIBUTING.md](.github/CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md).

### Security

If you discover a security vulnerability, please report it privately by emailing **lxldev.contact@gmail.com**. Do not create public issues for security problems.

We release security updates for the latest stable version - please keep AURGen updated to ensure you have the newest security fixes.

[↑ Back to top](#aurgen)