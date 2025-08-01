# AURGen

**AUR Packaging Automation Script for Arch Linux**

`AURGen` is a general-purpose Bash utility for automating the creation, maintenance, and testing of Arch Linux AUR packaging files. It streamlines the process of generating tarballs, updating `PKGBUILD` and `.SRCINFO` files, and preparing packages for local testing or AUR submission. It can be used to package software from any GitHub project, not just a specific repository.

> **Note:** AURGen is designed for **GNU/Linux** systems only. It requires GNU Bash (v4+), GNU getopt (from `util-linux`), and other GNU-specific tools. AURGen will not work on BSD, macOS, or other non-GNU platforms.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Modes](#modes)
  - [Options](#options)
  - [Workflows](#workflows)
- [PKGBUILD Generation](#pkgbuild-generation)
- [Dependency Detection System](#dependency-detection-system)
  - [README Analysis](#readme-analysis)
  - [Project File Analysis](#project-file-analysis)
- [AUR Integration](#aur-integration)
- [Release vs Development Mode](#release-vs-development-mode)
- [Project Structure](#project-structure)
- [Community Guidelines](#community-guidelines)

## Features

- **Automated PKGBUILD Generation**: Creates complete PKGBUILD files with proper metadata, dependencies, and install functions
- **Smart Dependency Detection**: Automatically detects build systems and programming languages through README analysis, project file scanning, and comprehensive tool-to-package mapping
- **Multiple Package Modes**: Supports local builds, AUR release, and -git (VCS) package generation
- **Built-in Testing Framework**: Comprehensive test mode that validates all packaging modes in dry-run mode
- **AUR Integration**: Complete AUR workflow automation with repository management, deployment, and validation
- **Robust GPG Integration**: Automatic signing with smart key selection, ASCII armor support, and graceful fallback for test environments
- **CI/Automation Support**: Environment variable-driven automation with development/release mode detection
- **Semantic Versioning**: Full semantic versioning support with automated version bumping and git integration
- **Error Handling**: Comprehensive error checking with helpful installation hints and graceful degradation for missing tools

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
- **git**: Generate a PKGBUILD for the -git (VCS) AUR package.
- **aur-init**: Initialize a new AUR repository for package deployment.
- **aur-deploy**: Deploy the generated PKGBUILD and .SRCINFO to AUR.
- **aur-status**: Check the status of your AUR repository.
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

For more detailed documentation, advanced usage, and troubleshooting, see [doc/USAGE.md](doc/USAGE.md) and [doc/AUR.md](doc/AUR.md).

## Workflows

### Complete AUR Release Workflow

1. **Test locally first:**
   ```bash
   aurgen local
   ```

2. **Prepare for AUR release:**
   ```bash
   aurgen aur
   ```

3. **Initialize AUR repository (first time only):**
   ```bash
   aurgen aur-init
   ```

4. **Deploy to AUR:**
   ```bash
   aurgen aur-deploy
   ```

### Git Package Workflow

1. **Generate git package:**
   ```bash
   aurgen git
   ```

2. **Deploy to AUR:**
   ```bash
   aurgen aur-deploy
   ```

### Testing and Validation Workflow

1. **Run comprehensive tests:**
   ```bash
   aurgen test
   ```

2. **Check code quality:**
   ```bash
   aurgen lint
   ```

3. **Clean up after testing:**
   ```bash
   aurgen clean
   ```

For complete workflow documentation and examples, see [doc/USAGE.md](doc/USAGE.md).

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

[↑ Back to top](#aurgen)

## AUR Integration

AURGen includes comprehensive AUR (Arch User Repository) integration that automates the entire workflow from PKGBUILD generation to AUR submission:

### AUR Workflow

1. **Generate Package Files**: `aurgen aur` creates PKGBUILD and .SRCINFO
2. **Initialize AUR Repository**: `aurgen aur-init` sets up your local AUR repository
3. **Deploy to AUR**: `aurgen aur-deploy` automatically deploys your package to AUR

### Key Features

- **Automatic Repository Management**: Initialize and manage local AUR repositories
- **Seamless Deployment**: Deploy PKGBUILD and .SRCINFO with a single command
- **Configurable Workflow**: Customize behavior through `aurgen.install.yaml`
- **Safety Features**: Automatic backups, validation, and error handling
- **SSH Integration**: Secure AUR authentication with SSH key management

### Configuration

Configure AUR integration in your `aurgen.install.yaml`:

```yaml
aur_integration:
  aur_repo_dir: /opt/AUR
  auto_push: true
  commit_message: "Update to version {version}"
  backup_existing: true
  validate_before_push: true
```

For complete AUR integration documentation, see [doc/AUR-INTEGRATION.md](doc/AUR-INTEGRATION.md) and [doc/AUR-QUICK-REFERENCE.md](doc/AUR-QUICK-REFERENCE.md).

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

### For Developers

Versioning information, development workflows, and contributing guidelines are available in [doc/DEVELOPER_GUIDE.md](doc/DEVELOPER_GUIDE.md).

### Security

If you discover a security vulnerability, please report it privately by emailing **lxldev.contact@gmail.com**. Do not create public issues for security problems.

We release security updates for the latest stable version - please keep AURGen updated to ensure you have the newest security fixes.

[↑ Back to top](#aurgen)