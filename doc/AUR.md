# AURGen: AUR Packaging Automation Script

`AURGen` is a utility script for automating the creation and maintenance of Arch Linux AUR packaging files for Github projects. It streamlines the process of generating tarballs, updating PKGBUILD and .SRCINFO files, and preparing the package for local testing or AUR submission.

> **Important:** This script is **only for GNU/Linux systems**. It will not work on BSD, macOS, or other non-GNU platforms. It requires GNU getopt (from util-linux) and other GNU-specific tools. Attempting to run it on non-GNU systems will result in a clear error message and immediate exit.

## Overview
- **Purpose:** Automates tarball creation, PKGBUILD and .SRCINFO updates, and AUR packaging tasks for GitHub projects.
- **License:** GPLv3 or later (see LICENSE)
- **Platform:** The script is designed for **GNU/Linux environments only** and does not aim to support macOS, BSD, or any non-GNU system. It requires GNU getopt (util-linux) and will not work with BSD/macOS getopt implementations.
- **Bash Version:** The script requires **Bash version 4 or newer**. It will exit with an error if run on an older version.
- **Tool Hints:** If a required tool is missing, the script will print a hint with an installation suggestion (e.g., pacman -S pacman-contrib for updpkgsums).

## Table of Contents

- [Features](#features)
- [Usage](#usage)
  - [Modes](#modes)
  - [Options](#options)
- [Configuration System](#configuration-system)
  - [Configuration Files](#configuration-files)
  - [Configuration Format](#configuration-format)
  - [Configuration Commands](#configuration-commands)
  - [Default Configuration](#default-configuration)
  - [Examples](#examples)
  - [Exclusions](#exclusions)
  - [Important Notes](#important-notes)
- [Log Files and Directory](#log-files-and-directory)
- [Disabling Colored Output](#disabling-colored-output)
- [ASCII-Armored Signatures](#ascii-armored-signatures)
- [GPG Key Automation](#gpg-key-automation)
- [Test Mode](#test-mode)
- [GitHub CLI Integration](#github-cli-integration)
- [CI/Automation Support](#ciautomation-support)
- [Environment Variables](#environment-variables)
- [Variable Naming Conventions](#variable-naming-conventions)
- [How It Works](#how-it-works)
  - [Tarball Creation](#tarball-creation)
  - [PKGBUILD Generation](#pkgbuild-generation)
  - [Package Installation Mechanism](#package-installation-mechanism)
    - [Standard Directory Installation (FHS)](#standard-directory-installation-fhs)
    - [Build System Integration](#build-system-integration)
    - [License File Installation](#license-file-installation)
  - [Makedepends Detection](#makedepends-detection)
    - [README.md Analysis](#readmemd-analysis)
    - [Project File Analysis](#project-file-analysis)
    - [Tool-to-Package Mapping](#tool-to-package-mapping)
  - [Checksums and .SRCINFO](#checksums-and-srcinfo)
  - [GPG Signing (aur mode only)](#gpg-signing-aur-mode-only)
  - [GitHub Asset Upload](#github-asset-upload)
  - [Installation](#installation)
- [Requirements](#requirements)
  - [Required Tools](#required-tools)
  - [Optional Tools](#optional-tools)
  - [Files](#files)
    - [The Role of PKGBUILD.0](#the-role-of-pkgbuild0)
    - [Automatic PKGBUILD.0 Generation](#automatic-pkgbuild0-generation)
    - [Version Detection](#version-detection)
- [Release vs Development Mode](#release-vs-development-mode)
- [Notes for AUR Maintainers](#notes-for-aur-maintainers)
- [Error Handling](#error-handling)
- [Argument Parsing: Why We Use 'eval set --'](#argument-parsing-why-we-use-eval-set---)

## Features

- **Automated PKGBUILD Generation**: Creates complete PKGBUILD files with proper metadata, dependencies, and install functions
- **Smart Dependency Detection**: Automatically detects build dependencies through multiple methods: README.md analysis (package manager commands, explicit dependency sections), project file analysis (build systems, programming languages), and comprehensive tool-to-package mapping
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

[↑ Back to top](#aurgen-aur-packaging-automation-script)

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
  Modes: local | aur | git | clean | test | lint | golden
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
- **`aur`**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload. Sets the source URL to the latest GitHub release tarball, updates checksums, and optionally runs `makepkg -si`. If the release asset does not exist, AURGen uploads it automatically (if `gh` is installed). If the asset already exists, you will be prompted to confirm overwriting before upload.
- **`git`**: Generate a PKGBUILD for the -git (VCS) AUR package. Sets the source to the git repository, sets `b2sums=('SKIP')`, adds `validpgpkeys`, and optionally runs `makepkg -si`. No tarball is created or signed.
- **`clean`**: Remove all generated files and directories in the `aur/` folder, including tarballs, signatures, PKGBUILD, .SRCINFO, and build artifacts.
- **`test`**: Run all modes (local, aur, git) in dry-run mode to check for errors and report results. Useful for verifying all modes work correctly without performing actual operations.
- **`lint`**: Run `shellcheck` and `bash -n` on all `.sh` files in the project, skipping the `aur/` directory and using a configurable maximum search depth (default: 5, controlled by `--maxdepth` or `MAXDEPTH` environment variable). This is a quick self-test/linting mode for CI or local development. Exits with nonzero status if any check fails. Example:
  ```sh
  /usr/bin/aurgen lint
  ```
  This will run both tools and print a summary. If `shellcheck` is not installed, it will be skipped with a warning.
- **`golden`**: Regenerate the golden PKGBUILD files in `aur/golden/` for test comparison. This mode always runs `clean` before regenerating golden files. It is used to update the reference PKGBUILD files that are compared in test mode.
- **`config`**: Manage install configuration files that control which directories are copied during package installation. This mode provides sub-commands for generating, editing, viewing, validating, and resetting configuration files.

> **Intelligent Mode Suggestions:** If you mistype a mode name, AURGen will suggest the closest valid mode using Levenshtein distance calculation. For example, if you type `aurgen loacl`, it will suggest "Did you mean 'local'?"

### Options

- **`--no-color`, `-n`**: Disable colored output (for accessibility or when redirecting output). You can also set the `NO_COLOR` environment variable to any value to disable color.
- **`--ascii-armor`, `-a`**: Use ASCII-armored signatures (.asc) instead of binary signatures (.sig) for GPG signing. Some AUR helpers (like aurutils) prefer ASCII-armored signatures.
- **`--dry-run`, `-d`**: Run all steps except the final `makepkg -si` (useful for CI/testing).
- **`--no-wait`**: Skip the post-upload wait for asset availability after uploading assets to GitHub releases (for CI/advanced users). Can also be enabled by setting the `NO_WAIT=1` environment variable. This disables the wait/retry/prompt after uploading assets in `aur` mode, allowing for faster CI or scripting workflows. If the asset is not immediately available, you may need to retry `makepkg` after a short delay.

[↑ Back to top](#aurgen-aur-packaging-automation-script)
- **`--maxdepth N`**: Set maximum search depth for lint mode only (default: 5). This controls how deep the script searches for files when running lint checks. Dependency detection now uses git-tracked files filtered by the same logic used for AUR package creation, ensuring only relevant source files are considered.
- **`--help`, `-h`**: Print detailed help and exit (includes options, documentation pointers, etc.).
- **`--usage`**: Print a minimal usage line and exit (no color, no extra text; suitable for scripts/AUR helpers).

[↑ Back to top](#aurgen-aur-packaging-automation-script)

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

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### Configuration System

AURGen includes a flexible configuration system that allows you to customize which directories are copied during package installation. This is particularly useful for projects that don't need all the default directories or have custom directory structures.

#### Configuration Files

When PKGBUILD.0 is created for the first time, AURGen automatically generates two configuration files in the `aur/` directory:

- **`aurgen.install.yaml`** - Your project's active configuration
- **`aurgen.install.yaml.example`** - Reference example with documentation

#### Configuration Format

```
source_dir:dest_dir:permissions[:exclude1,exclude2,...]
```

**Field Descriptions:**
- `source_dir` - Directory in your project root to copy from
- `dest_dir` - Destination path in the package (supports `$pkgname` variable)
- `permissions` - Octal permissions (e.g., 755 for executable, 644 for read-only)
- `exclude1,exclude2,...` - **Optional**: Comma-separated list of subdirectories or files to exclude

#### Configuration Commands

```bash
# Generate default configuration file
aurgen config generate

# Edit configuration file with default editor
aurgen config edit

# Show current configuration
aurgen config show

# Validate configuration syntax and show active rules
aurgen config validate

# Reset to defaults (creates backup)
aurgen config reset

# Show detailed help
aurgen config help
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

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### Log Files and Directory

By default, all logs are written to `/tmp/aurgen/aurgen.log` and errors to `/tmp/aurgen/aurgen-error.log`. You can customize these locations using the `AURGEN_LOG` and `AURGEN_ERROR_LOG` environment variables. The script will create `/tmp/aurgen` if it does not exist.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

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

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### GPG Key Automation

- For `aur` mode, a GPG secret key is required to sign the release tarball.
- By default, the script will prompt you to select a GPG key from your available secret keys.
- **Smart key selection behavior:**
  - **Single key**: Auto-selects immediately (no choice needed)
  - **Multiple keys**: Shows all keys and auto-selects the first key after 10 seconds if no input is provided
  - Users can press Enter immediately to select the first key, or enter a specific key number within the timeout
- **To skip the interactive menu and use a specific key, set the `GPG_KEY_ID` environment variable:**

  ```sh
  GPG_KEY_ID=ABCDEF /usr/bin/aurgen aur
  ```
  Replace `ABCDEF` with your GPG key's ID or fingerprint. This is useful for automation or CI workflows.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### Test Mode

- The `test` mode runs all other modes (local, aur, git) in dry-run mode to verify they work correctly.
- Each test runs in isolation with a clean environment (automatically runs clean before each test).
- Test mode handles GPG prompts by creating dummy signature files for testing purposes.
- Provides comprehensive error reporting and shows which tests passed or failed.
- Useful for CI/CD pipelines or verifying script functionality before actual use.

  ```sh
  /usr/bin/aurgen test
  ```

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### GitHub CLI Integration

- If GitHub CLI (`gh`) is installed, the script can automatically upload missing release assets to GitHub releases.
- When a release asset is not found, the script will upload the tarball and signature automatically (no prompt).
- If the asset already exists, you will be prompted to confirm overwriting before upload.
- To skip the upload prompt (always overwrite), set the `AUTO` environment variable.
- If GitHub CLI is not installed, the script will provide clear instructions for manual upload.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### CI/Automation Support

- Set `CI=1` to skip interactive prompts in `aur` mode (automatically skips `makepkg -si` prompt). **If `CI` is set, AURGen automatically runs in development mode (RELEASE=0) unless `RELEASE` is explicitly set.**
- Set `AUTO=y` to skip the GitHub asset upload prompt.
- Set `GPG_KEY_ID` to avoid GPG key selection prompts.
- Use `--dry-run` to test without installing packages (must be before the mode).
- Use `--no-wait` or set `NO_WAIT=1` to skip the post-upload wait for asset availability (for CI/advanced users). This disables the wait/retry/prompt after uploading assets in `aur` mode.

> **Prompt Handling and CI Safety:**
> All interactive prompts in this script always supply a default value. This ensures that, even in CI or headless environments (when `CI=1`), the default is automatically selected and the corresponding variable is always set. This design prevents failures due to unset variables and is intentional for robust automation. If you add new prompts, always supply a default value to maintain this guarantee.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### Environment Variables

The script supports several environment variables for automation and customization:

- **`NO_COLOR`**: Set to any value to disable colored output (alternative to `--no-color` option)
- **`GPG_KEY_ID`**: Set to your GPG key ID to skip the interactive key selection menu (auto-selects first key after 15-second timeout if not set)
- **`AUTO`**: Skip the GitHub asset upload prompt in `aur` mode
- **`CI`**: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines)
- **`DRY_RUN`**: Set to `1` to enable dry-run mode (alternative to `--dry-run`/`-d` flag)
- **`NO_WAIT`**: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- **`MAXDEPTH`**: Set to control maximum search depth for lint and clean modes (alternative to `--maxdepth` flag) (defaults to 5)
- **`AURGEN_LOG`**: Set to customize the main log file location (default: `/tmp/aurgen/aurgen.log`)
- **`AURGEN_ERROR_LOG`**: Set to customize the error log file location (default: `/tmp/aurgen/aurgen-error.log`)
- **`RELEASE`**: Override automatic mode detection (1=release mode, 0=development mode)
- **`AURGEN_LIB_DIR`**: Set custom library directory path
- **`DEBUG_LEVEL`**: Set to 1 or higher to enable debug logging (automatically enabled in development mode)
- **`MAXDEPTH`**: (clean mode) Set to control the maximum directory depth for deletion of ${PKGNAME}-* directories in clean mode. Defaults to 1 if unset.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Variable Naming Conventions

- Local, mutable variables use lowercase (e.g., `dry_run`, `ascii_armor`, `color_enabled`).
- ALL-CAPS is reserved for readonly constants and exported variables (e.g., `PKGNAME`, `PROJECT_ROOT`).
- This helps quickly distinguish between constants/globals and local, mutable state.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## How It Works

### Tarball Creation
- Creates a new source tarball from the project root using `git archive`, excluding build and VCS files (except in `git` mode).
- Uses `git archive` to respect `.gitignore` and only include tracked files.
- **Reproducibility:** Sets the tarball modification time (mtime) to a fixed date (2020-01-01) for reproducible builds. This ensures that repeated builds produce identical tarballs, regardless of when the script is run. (See [reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/))
- **SOURCE_DATE_EPOCH Support:** You can set the `SOURCE_DATE_EPOCH` environment variable to control the tarball modification time for reproducible builds. If not set, AURgen uses the commit date of the current tag or HEAD.
- **Automatic .gitattributes Generation:** AURGen automatically generates or updates `.gitattributes` files to mark excluded files as `export-ignore`. This ensures that only relevant source files are included in source tarballs and VCS-based AUR packages, excluding build artifacts, temporary files, and other non-essential content.
- **Note:** `git archive` does _not_ include the contents of git submodules. If you ever add submodules to this project, the generated tarball will _not_ contain their files—only the main repository's files. You will need to update the packaging process to include submodule contents if submodules are introduced. See the [git-archive documentation](https://git-scm.com/docs/git-archive#_limitations) for details.

### PKGBUILD Generation
- Copies and updates PKGBUILD from the template file (`PKGBUILD.0`).
- Extracts `pkgver` from `PKGBUILD.0` using `awk` without sourcing the file.
- For `aur` mode: Updates the `source` line to point to the GitHub release tarball, tries both with and without 'v' prefix.
- For `git` mode: Updates the `source` line to use the git repository, sets `b2sums=('SKIP')`, and adds `validpgpkeys`.
- **File Locking:** Uses `flock` to prevent concurrent PKGBUILD updates, ensuring data integrity when multiple processes might be running simultaneously.
- **NEW:** The PKGBUILD generation now automatically scans the filtered project source tree for installable files and directories. The generated `package()` function includes a robust `copy_tree()` helper function that handles file installation with proper error handling and path resolution. It automatically installs files from common directories (`bin/`, `lib/`, `etc/`, `share/`, `include/`, `local/`, `var/`, `opt/`) with appropriate permissions, reducing the need for manual editing for common project layouts.
- **NEW:** Automatic makedepends detection: AURGen automatically detects and populates the `makedepends` array based on project files. It detects build systems (CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, Autotools), programming languages (C/C++, TypeScript, Vala, SCSS/SASS), and common build tools (pkg-config, gettext, asciidoc). This eliminates the need to manually specify build dependencies for most projects.

### Package Installation Mechanism

AURGen uses a standard directory installation procedure that follows the Linux Filesystem Hierarchy Standard (FHS). The generated `package()` function automatically installs files from common project directories to their appropriate system locations, ensuring proper organization and permissions according to Linux conventions.

#### Standard Directory Installation (FHS)
The generated `package()` function automatically installs files from common project directories:

- `bin/` → `usr/bin/` (mode 755 - executable)
- `lib/` → `usr/lib/$pkgname/` (mode 644 - library files)
- `etc/` → `etc/$pkgname/` (mode 644 - configuration files)
- `share/` → `usr/share/$pkgname/` (mode 644 - shared data)
- `include/` → `usr/include/$pkgname/` (mode 644 - header files)
- `local/` → `usr/local/$pkgname/` (mode 644 - local data)
- `var/` → `var/$pkgname/` (mode 644 - variable data)
- `opt/` → `opt/$pkgname/` (mode 644 - optional data)

#### Build System Integration
For projects with build systems, additional installation steps are automatically added:

- **CMake**: `DESTDIR="$pkgdir" cmake --install build`
- **Make**: `make DESTDIR="$pkgdir" install`
- **Python**: `python setup.py install --root="$pkgdir" --optimize=1 --skip-build`
- **Node.js**: `npm install -g --prefix "$pkgdir/usr" .`
- **Rust**: `install -Dm755 target/release/$PKGNAME "$pkgdir/usr/bin/$PKGNAME"`
- **Go**: `install -Dm755 $PKGNAME "$pkgdir/usr/bin/$PKGNAME"`
- **Meson**: `DESTDIR="$pkgdir" meson install -C build`

#### License File Installation
Automatically installs license files from common locations:
- `LICENSE` → `usr/share/licenses/$pkgname/LICENSE`
- `LICENSE.txt` → `usr/share/licenses/$pkgname/LICENSE`
- `COPYING` → `usr/share/licenses/$pkgname/LICENSE`

### Makedepends Detection

AURGen automatically detects build dependencies through multiple methods, ensuring comprehensive coverage:

#### 1. README.md Analysis
AURGen scans README files (case-insensitive: `README.md`, `README.txt`, `README.rst`, `README`) for explicit dependency information:

**Package Manager Commands:**
- `pacman -S package1 package2` → detects `package1`, `package2`
- `apt install package1 package2` → detects `package1`, `package2`
- `yum install package1 package2` → detects `package1`, `package2`
- `brew install package1 package2` → detects `package1`, `package2`

**Explicit Dependency Sections:**
- Sections titled "Installation", "Requirements", "Dependencies", "Prerequisites", "Build Dependencies", or "Make Dependencies"
- Package lists in markdown format with backticks: `` `package-name` ``
- Explicit "Required:" and "Optional:" sections with backticked package names

#### 2. Project File Analysis
AURGen analyzes git-tracked project files (filtered using the same logic as AUR package creation):

**Build Systems:**
- `CMakeLists.txt` → `cmake`, `make`
- `Makefile` → `make`
- `setup.py` → `python-setuptools`
- `package.json` → `npm`
- `Cargo.toml` → `rust`, `cargo`
- `go.mod` → `go`
- `pom.xml` → `maven`, `jdk-openjdk`
- `build.gradle` → `gradle`, `jdk-openjdk`
- `meson.build` → `meson`, `ninja`
- `configure.ac`/`configure.in` → `autoconf`, `automake`, `libtool`, `make`

**Programming Languages:**
- `*.cpp`, `*.cc`, `*.cxx`, `*.c++` → `gcc`
- `*.c` → `gcc`
- `*.ts`, `*.tsx` → `typescript`
- `*.vala` → `vala`
- `*.scss`, `*.sass` → `sassc`

**Frameworks and Tools:**
- Qt projects (`*.pro` or CMake with Qt) → `qt6-base`
- `*.pc.in` → `pkgconf`
- `*.po`, `*.pot` → `gettext`
- `*.adoc` → `asciidoc`
- YAML/JSON processing → `jq`

#### 3. Tool-to-Package Mapping
AURGen includes a comprehensive mapping system that converts common tool names to their containing packages:

**Core System Tools:**
- `getopt` → `util-linux`
- `updpkgsums` → `pacman-contrib`
- `makepkg` → `pacman`

**Development Tools:**
- `python` → `python`
- `node` → `nodejs`
- `rust` → `rust`
- `go` → `go`
- `java` → `jdk-openjdk`
- `npm` → `npm`
- `cargo` → `rust`
- `maven` → `maven`
- `gradle` → `gradle`

**Build Tools:**
- `cmake` → `cmake`
- `make` → `make`
- `gcc` → `gcc`
- `clang` → `clang`
- `meson` → `meson`
- `ninja` → `ninja`
- `autoconf` → `autoconf`
- `automake` → `automake`
- `libtool` → `libtool`

**Utilities:**
- `curl` → `curl`
- `jq` → `jq`
- `gpg` → `gnupg`
- `gh` → `github-cli`
- `shellcheck` → `shellcheck`
- `bash` → `bash`

The detection automatically removes duplicates, maps tool names to packages, and logs the detected dependencies for transparency. This multi-layered approach ensures comprehensive dependency detection while maintaining accuracy and performance.

### Checksums and .SRCINFO
- For `aur` and `local` modes: Runs `updpkgsums` to update checksums and generates `.SRCINFO`.
- For `git` mode: Skips `updpkgsums` and sets `b2sums=('SKIP')` (required for VCS packages).
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
- `shellcheck` (for lint mode)

### Files
- `PKGBUILD.0` template file in `aur/` directory

#### The Role of PKGBUILD.0

- `PKGBUILD.0` is the canonical template for your package's build instructions.
- All automated PKGBUILD generation and updates are based on this file.
- You should edit `PKGBUILD.0` directly for any customizations.
- If the file is missing or invalid, AURGen will regenerate it and back up the previous version as `PKGBUILD.0.bak`.
- Always check `PKGBUILD.0.bak` if you need to recover manual changes after a regeneration.

#### Automatic PKGBUILD.0 Generation

If `PKGBUILD.0` doesn't exist, AURGen can automatically generate a basic template with the following features:

- **Metadata Extraction**: Automatically extracts package name, version, description, and license from the project
- **Version Detection**: Automatically detects version from git tags, VERSION file, or falls back to default
- **Build System Detection**: Detects CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, or Autotools
- **Dependency Detection**: Automatically populates `makedepends` based on detected build systems and project files
- **Install Function Generation**: Creates basic install commands for common project layouts
- **GitHub Integration**: Sets up proper source URLs and GPG key validation
- **License Detection**: Automatically detects MIT, GPL, Apache, or custom licenses
- **Header Generation**: Creates proper copyright headers in `PKGBUILD.HEADER` with maintainer information and license details

The generated `PKGBUILD.0` will be customized for your specific project and can be further edited as needed.

#### Version Detection

AURGen automatically detects the package version using the following priority order:

1. **Git Tags** (highest priority): Extracts version from the most recent git tag
   - Uses `git describe --tags --abbrev=0` to find the latest tag
   - Automatically removes 'v' prefix if present (e.g., `v1.0.0` → `1.0.0`)
   - Provides the most reliable version for release packages

2. **VERSION File** (first fallback): Reads version from `VERSION` file in project root
   - Looks for a `VERSION` file containing the version number
   - Automatically trims whitespace from the version
   - Useful for projects that don't use git tags or prefer file-based versioning
   - Shows warning if VERSION file exists but is empty

3. **Default Fallback** (last resort): Uses hardcoded version `1.0.0`
   - Applied when neither git tags nor VERSION file are available
   - Includes clear warning messages about the fallback

**Examples:**
```bash
# Git tag detection
git tag v2.1.0
# AURGen will use: 2.1.0

# VERSION file detection
echo "1.5.2" > VERSION
# AURGen will use: 1.5.2

# Fallback (no tags, no VERSION file)
# AURGen will use: 1.0.0 (with warning)
```

**GitHub Release Integration:**
- When using git tags, AURGen attempts to fetch corresponding GitHub release tarballs
- For VERSION file or fallback versions, no GitHub release tarball is set (manual update required)
- Clear warnings indicate which version source is being used

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Release vs Development Mode

By default, AURGen runs in release mode (using system libraries and minimal logging). If the `CI` environment variable is set (as in most CI/CD systems), AURGen automatically switches to development mode (using local libraries and debug logging), unless the `RELEASE` variable is explicitly set. You can override this behavior by setting `RELEASE=1` or `RELEASE=0` in your environment as needed.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Notes for AUR Maintainers

- Always update `PKGVER` in `PKGBUILD.0` for new releases.
- The script expects `PKGBUILD.0` to exist and be up to date.
- The script will fail if required tools or the template are missing.
- For CI or automation, set `GPG_KEY_ID` to avoid interactive prompts.
- For CI or automation with automatic asset upload, set `AUTO=y` to skip upload prompts.
- For CI environments, set `CI=1` to skip all interactive prompts.
- Use `/usr/bin/aurgen test` to verify all modes work correctly before making changes or releases.
- The script automatically handles both 'v' and non-'v' prefixed GitHub release URLs.
- VCS packages (`git` mode) automatically set `b2sums=('SKIP')` and add `validpgpkeys`.
- All environment variables are documented in the script's usage function (`/usr/bin/aurgen` without arguments).
- Use `--ascii-armor` or `-a` to create ASCII-armored signatures (.asc) instead of binary signatures (.sig) for better compatibility with some AUR helpers (must be before the mode).

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Error Handling

- Comprehensive error checking for missing tools, files, and GPG keys.
- Graceful fallback for GitHub asset URLs (tries both with and without 'v' prefix).
- Clear error messages with actionable instructions.
- Test mode provides detailed error reporting for all modes.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Argument Parsing: Why We Use 'eval set --'

The script uses GNU getopt for robust option parsing. To correctly handle quoted arguments and avoid subtle bugs (such as modes being passed with extra quotes), we use:

```bash
eval set -- "$getopt_output"
```

This is the recommended approach (see: https://mywiki.wooledge.org/BashFAQ/035) because it ensures that all arguments are split and quoted as the user intended, even if they contain spaces or special characters. Avoid using array-based splitting (e.g., `read -ra`) on getopt output, as it can introduce quoting bugs and break mode detection. This fix was introduced after a bug where the mode was parsed as `'lint'` (with quotes) instead of `lint`, causing the script to reject valid modes.

---
For more details, see the comments in `/usr/lib/aurgen/` and `/usr/bin/aurgen`.

[↑ Back to top](#aurgen-aur-packaging-automation-script)