# AURGen: AUR Packaging Automation Script

`AURGen` is a utility script for automating the creation and maintenance of Arch Linux AUR packaging files for Github projects. It streamlines the process of generating tarballs, updating PKGBUILD and .SRCINFO files, and preparing the package for local testing or AUR submission.

> **Important:** This script is **only for GNU/Linux systems**. It will not work on BSD, macOS, or other non-GNU platforms. It requires GNU getopt (from util-linux) and other GNU-specific tools. Attempting to run it on non-GNU systems will result in a clear error message and immediate exit.

## Overview
- **Purpose:** Automates tarball creation, PKGBUILD and .SRCINFO updates, and AUR packaging tasks for GitHub projects. `origin` must be a GitHub URL (HTTPS or SSH). A different host, or no origin, is refused before `local`, `aur`, and `git` delete generated files. A repository name may contain dots. A repository whose owner and name are the same is accepted when that owner matches the `PKGBUILD.0` `url`.
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
    - [README.md Analysis](#1-readmemd-analysis)
    - [Project File Analysis](#2-project-file-analysis)
    - [Tool-to-Package Mapping](#3-tool-to-package-mapping)
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
- **Built-in Testing Framework**: Test mode dry-runs the local, aur and git modes for validation
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

- `--usage` prints the short usage: `aurgen <mode> [options]`, every mode (`local`, `aur`, `git`, `aur-init`, `aur-deploy`, `aur-status`, `clean`, `test`, `lint`, `golden`, `config`), and the option list. Options are accepted only when they appear before the mode, even though that line prints the mode first.
- `-h` and `--help` print that usage, then a note that a missing tool gets an install hint and that lint runs `shellcheck` and `bash -n`.

> **Note:** All flags/options must appear before the mode. For example: `/usr/bin/aurgen -n --dry-run aur`. Flags after the mode are not supported.
> 
> **Options are now parsed using getopt for unified short and long option support, improving robustness and maintainability.**

### Modes

- **`local`**: Build and install the package from a local tarball of the tracked files as they are in the working tree (uncommitted edits included, untracked files left out; non-ASCII names included; a directory prefix does not rewrite symlink targets). Updates PKGBUILD and .SRCINFO. Installs with `makepkg -si`, or `makepkg -s`, then namcap, then `makepkg -i` when namcap is installed (namcap `E:` findings stop the install).
- **`aur`**: Prepare a release tarball from the release tag, sign it with GPG, and update PKGBUILD for AUR upload. The tag is `v<pkgver>` when that git tag or GitHub release exists, otherwise `<pkgver>`. Same `pkgver` as the published PKGBUILD bumps `pkgrel` by one, including a minor release (`1.1` becomes `2`); a comment on that line is ignored. A new `pkgver` starts at `1`. Stops once PKGBUILD and .SRCINFO are ready (it does not install). If the release asset does not exist, AURGen uploads it automatically (if `gh` is installed). If the asset already exists, AURGen asks before overwriting; the default is no. A failed tarball upload or a failed signature upload stops the run. For `archive` and `signed-tag`, the run stops with `git push origin v<pkgver>` when that tag is not on `origin` yet (`--dry-run` skips the check).
- **`git`**: Generate a PKGBUILD for the `-git` package (`pkgname` and `.SRCINFO` `pkgbase` are `<name>-git`). Sets the source to the git repository, writes `b2sums=("SKIP")`, drops `validpgpkeys` and `sha256sums`, and stops once PKGBUILD and .SRCINFO are ready (it does not install). No tarball is created or signed. `build()`, `check()`, and `package()` are kept. See [PKGBUILD Generation](PKGBUILD-GENERATION.md#hand-file-equivalence).
- **`aur-init`**, **`aur-deploy`**, **`aur-status`**: AUR repository setup, deploy, and status. See [AUR Integration](AUR-INTEGRATION.md).
- **`clean`**: Remove generated `aur/PKGBUILD`, `aur/PKGBUILD.git`, `aur/.SRCINFO`, the `.prev` copies, tarballs, signatures, built packages, and `aur/golden/PKGBUILD.*.golden`. Leaves `PKGBUILD.0`, `PKGBUILD.HEADER`, and `aurgen.install.yaml`.
- **`test`**: Dry-run the local, aur and git modes to check for errors and report results, without installing, uploading or deploying. Generated files are removed before each of those runs. The first `aur/PKGBUILD.prev` is kept across them. Each PKGBUILD is compared with `aur/golden/PKGBUILD.<mode>.golden` when that file exists.
- **`lint`**: Run `shellcheck` and `bash -n` on every `*.sh` file and every file whose first line is a bash shebang, skipping `.git/`, `aur/`, and `Backups/`, to a maximum depth (default: 5, controlled by `--maxdepth` or `MAXDEPTH`). Exits with nonzero status if any check fails. If `shellcheck` is not installed, it is skipped with a warning. Example:
  ```sh
  /usr/bin/aurgen lint
  ```
- **`golden`**: Regenerate the golden PKGBUILD files in `aur/golden/` for test comparison. This mode runs `clean` first (and continues if that clean fails), then dry-runs local, aur, and git. A mode that fails does not update its golden file, and golden mode then exits nonzero.
- **`config`**: Manage install configuration files that control which directories are copied during package installation. This mode provides sub-commands for generating, editing, viewing, validating, and resetting configuration files.

> **Intelligent Mode Suggestions:** If you mistype a mode name, AURGen will suggest the closest valid mode using Levenshtein distance calculation. For example, if you type `aurgen loacl`, it will suggest "Did you mean 'local'?"

### Options

- **`--no-color`, `-n`**: Disable colored output on a terminal. Piped or redirected output is already plain. `NO_COLOR` set to any value does the same on a terminal. `CI` also turns color off.
- **`--ascii-armor`, `-a`**: Use ASCII-armored signatures (.asc) instead of binary signatures (.sig) for GPG signing. Some AUR helpers (like aurutils) prefer ASCII-armored signatures.
- **`--dry-run`, `-d`**: Regenerate the files under `aur/dry-run/` (the `local`, `aur` and `git` modes leave `aur/` unchanged), write `b2sums=('SKIP')` instead of running `updpkgsums`, and skip the install, the GitHub upload, and any AUR copy, commit, or push. `aur-init` does not clone or delete. `DRY_RUN=1` is the same switch; the flag overrides `DRY_RUN=0`.
- **`--no-wait`**: Skip the post-upload wait for asset availability after uploading assets to GitHub releases (for CI/advanced users). Can also be enabled by setting the `NO_WAIT=1` environment variable. This disables the wait/retry/prompt after uploading assets in `aur` mode, allowing for faster CI or scripting workflows. If the asset is not immediately available, you may need to retry `makepkg` after a short delay.
- **`--deploy`**: After a successful `aur` or `git` run, deploy the generated files to the AUR (the same steps as `aur-deploy`). With `--dry-run` it previews the deploy and changes nothing. Any other mode refuses it.
- **`--maxdepth N`**: Maximum search depth for lint and for clean's removal of `${PKGNAME}-*` directories (default: 5). The value must be a positive integer. Anything else, including `0`, exits with `Invalid --maxdepth` before a mode runs. `MAXDEPTH` is the same switch.
- **`--help`, `-h`**: Print the short usage, a missing-tool hint, and a one-line lint note, then exit.
- **`--usage`**: Print the short usage and exit.

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

The `package:` keys, and how `pkgname`, `arch`, `depends`, `check()`, `package()`, and `aur/.gitignore` are chosen, are documented in [Package section](PKGBUILD-GENERATION.md#package-section).

#### Configuration Files

When PKGBUILD.0 is created for the first time, AURGen automatically generates two configuration files in the `aur/` directory:

- **`aurgen.install.yaml`** - Your project's active configuration (includes AUR integration settings)
- **`aurgen.install.yaml.example`** - Reference example with documentation (includes AUR integration examples)

#### Configuration Format

The configuration uses a structured YAML format for better readability and maintainability:

```yaml
section_name:
  source: source_directory
  destination: destination_path
  permissions: executable|read-only
  exclude: [item1, item2, ...]
```

**Field Descriptions:**
- `section_name` - Unique identifier for this configuration section
- `source` - Directory in the project root: one of `bin`, `lib`, `etc`, `share`, `include`, `local`, `var`, or `opt`. Any other source is ignored
- `destination` - Destination path in the package (supports `$pkgname` variable)
- `permissions` - Permission type: `executable` (755) or `read-only` (644)
- `exclude` - **Optional**: Array of subdirectory names to exclude (a file name does not exclude that file)

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

# Print the package metadata and copy rules as parsed
aurgen config show effective

# Import a hand-written PKGBUILD
aurgen config import

# Show detailed help
aurgen config help
```

`config generate` fails when `aurgen.install.yaml` already exists. `config edit`, `config reset`, and `config validate` still run when that file is invalid. Every other mode stops.

#### Default Configuration

The default configuration includes these sections:

```yaml
# Executable files
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []

# Library files
libraries:
  source: lib
  destination: usr/lib/$pkgname
  permissions: read-only
  exclude: []

# Configuration files
config:
  source: etc
  destination: etc/$pkgname
  permissions: read-only
  exclude: []

# Shared data files
shared_data:
  source: share
  destination: usr/share/$pkgname
  permissions: read-only
  exclude: []

# Header files
headers:
  source: include
  destination: usr/include/$pkgname
  permissions: read-only
  exclude: []

# Local data files
local_data:
  source: local
  destination: usr/local/$pkgname
  permissions: read-only
  exclude: []

# Variable data files
variable_data:
  source: var
  destination: var/$pkgname
  permissions: read-only
  exclude: []

# Optional data files
optional_data:
  source: opt
  destination: opt/$pkgname
  permissions: read-only
  exclude: []

# AUR Integration Configuration
aur_integration:
  aur_repo_dir: ~/.local/share/aurgen/aur
  auto_push: true
  commit_message: "Update to version {version}"
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # SSH key for AUR authentication. When unset, ~/.ssh/config is used.
  # ssh_key: ~/.ssh/aur
  validate_before_push: true
```

#### AUR Integration Configuration

The configuration file also includes AUR integration settings that control how your package is deployed to the Arch User Repository (AUR). These settings are automatically included in generated configuration files.

**Key AUR Integration Settings:**
- **`aur_repo_dir`**: Directory where local AUR repositories are stored
- **`auto_push`**: Whether to automatically push changes to AUR after deployment
- **`commit_message`**: Template for commit messages (supports `{version}` placeholder)
- **`git_user_name`** and **`git_user_email`**: Git configuration for AUR commits
- **`ssh_key`**: SSH key for AUR authentication
- **`validate_before_push`**: Whether to validate repository before pushing

For complete AUR integration documentation, see [doc/AUR-INTEGRATION.md](AUR-INTEGRATION.md).

#### Examples

```yaml
# Basic examples
executables:
  source: bin
  destination: usr/bin
  permissions: executable
  exclude: []

libraries:
  source: lib
  destination: usr/lib/$pkgname
  permissions: read-only
  exclude: []

config:
  source: etc
  destination: etc/$pkgname
  permissions: read-only
  exclude: []

# Exclude specific subdirectories
config_with_exclusions:
  source: etc
  destination: etc/$pkgname
  permissions: read-only
  exclude: [test, temp]

shared_data_with_exclusions:
  source: share
  destination: usr/share/$pkgname
  permissions: read-only
  exclude: [docs, examples]

# Exclude single directory
local_data:
  source: local
  destination: usr/local/$pkgname
  permissions: read-only
  exclude: [cache]

# Disable a section (comment out)
# headers:
#   source: include
#   destination: usr/include/$pkgname
#   permissions: read-only
#   exclude: []

```

#### Exclusions

The exclusion feature copies a directory while skipping named subdirectories. A file name does not exclude that file. This is particularly useful for:

- **Development files**: Exclude `test/`, `temp/`, `backup/` directories
- **Documentation**: Exclude `docs/`, `examples/` when not needed in the package
- **Build artifacts**: Exclude `cache/` and `logs/` directories
- **Development tools**: Exclude IDE-specific directories like `.vscode/`, `.idea/`

**Exclusion Patterns:**
- Each exclusion names a subdirectory of the source directory
- Multiple exclusions are specified as YAML arrays: `[item1, item2]` (a space after the comma, and quotes around a name, are accepted)
- Exclusions are case-sensitive and must match exact directory names
- The exclude field is optional - use an empty array `[]` to copy everything

**Examples:**
```yaml
# Exclude development and temporary files
config:
  source: etc
  destination: etc/$pkgname
  permissions: read-only
  exclude: [test, temp, backup]

# Exclude documentation and examples
shared_data:
  source: share
  destination: usr/share/$pkgname
  permissions: read-only
  exclude: [docs, examples]

# Exclude cache and log directories
variable_data:
  source: var
  destination: var/$pkgname
  permissions: read-only
  exclude: [cache, logs]
```

#### Important Notes

- **Project-Specific**: Configuration files are stored in the `aur/` directory and are specific to each project
- **Auto-Generation**: Files are automatically created when PKGBUILD.0 is generated for the first time
- **No Overwriting**: Existing configuration files are never overwritten automatically
- **Backup Protection**: The `reset` command creates a `.bak` file before regenerating
- **Validation**: Use `aurgen config validate` to check your configuration syntax
- **YAML Format**: The new YAML format provides better structure and readability compared to the previous colon-separated format
- **Section-Based**: Each configuration section can be independently enabled, disabled, or customized
- **Permission Types**: Use `executable` for executable files (755) or `read-only` for data files (644)

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### Log Files and Directory

By default, all logs are written to `${XDG_STATE_HOME:-~/.local/state}/aurgen/aurgen.log` and errors to `${XDG_STATE_HOME:-~/.local/state}/aurgen/aurgen-error.log`. You can customize these locations using the `AURGEN_LOG` and `AURGEN_ERROR_LOG` environment variables. The script creates that directory (mode 0700) if it does not exist.

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
  On a terminal, `NO_COLOR` is what turns color off when `--no-color` is not passed. Piped or redirected stdout is plain without it. `CI` also turns color off.

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

- The `test` mode dry-runs the local, aur and git modes to verify they work; it does not run aur-init, aur-deploy or aur-status, and the bash suite (`bash tests/run.sh`) is separate.
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
- If the asset already exists, AURGen asks before uploading again. The default is no. Without a terminal the default is used, so the existing asset stays.
- If GitHub CLI is not installed, the script will provide clear instructions for manual upload.
- A failed upload of the tarball or of the signature stops aur mode.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### CI/Automation Support

- **If `CI` is set, color is off.** `CI` does not change the mode: a source checkout (`bin/` next to `lib/`) runs in development mode (`RELEASE=0`), an installed aurgen uses `/usr/lib/aurgen`, and an explicit `RELEASE` wins. `CI` does not answer prompts. A prompt takes its default when stdin is not a terminal. The overwrite prompt's default is no, so an existing GitHub asset is kept.
- Set `GPG_KEY_ID` to avoid GPG key selection prompts.
- Use `--dry-run` to test without installing packages (must be before the mode).
- Use `--no-wait` or set `NO_WAIT=1` to skip the post-upload wait for asset availability (for CI/advanced users). This disables the wait/retry/prompt after uploading assets in `aur` mode.

> **Prompt Handling and CI Safety:**
> All interactive prompts supply a default. When stdin is not a terminal, that default is used. `CI` does not answer the prompt.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

### Environment Variables

The script supports several environment variables for automation and customization:

- **`NO_COLOR`**: Set to any value to disable colored output on a terminal (alternative to `--no-color`). Piped or redirected output is already plain
- **`GPG_KEY_ID`**: Set to a GPG key ID to skip the interactive key selection menu (auto-selects the first key after a 10-second timeout if not set)
- **`CI`**: Turn color off. It does not change the mode. Prompts are unchanged
- **`DRY_RUN`**: Set to `1` to enable dry-run mode (alternative to `--dry-run`/`-d` flag)
- **`NO_WAIT`**: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- **`MAXDEPTH`**: Positive integer search depth for lint and clean (alternative to `--maxdepth`; default 5). `0` and any non-integer are refused
- **`AURGEN_LOG`**: Set to customize the main log file location (default: `${XDG_STATE_HOME:-~/.local/state}/aurgen/aurgen.log`)
- **`AURGEN_ERROR_LOG`**: Set to customize the error log file location (default: `${XDG_STATE_HOME:-~/.local/state}/aurgen/aurgen-error.log`)
- **`RELEASE`**: Override automatic mode detection (1=release mode, 0=development mode)
- **`AURGEN_LIB_DIR`**: Set custom library directory path
- **`DEBUG_LEVEL`**: Set to 1 or higher to enable debug logging (set to 1 in development mode when unset; release mode sets it to 0)

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Variable Naming Conventions

- Local, mutable variables use lowercase (e.g., `dry_run`, `ascii_armor`, `color_enabled`).
- ALL-CAPS is reserved for readonly constants and exported variables (e.g., `PKGNAME`, `PROJECT_ROOT`).
- This helps quickly distinguish between constants/globals and local, mutable state.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## How It Works

### Tarball Creation
- `aur` mode builds the release tarball with `git archive` from the release tag, not the working tree, limited to the filtered list of tracked files. Non-ASCII names are included (`core.quotePath` is off for that listing).
- `local` mode tars the same filtered list of tracked files, read from the working tree. When `package()` changes into a source directory, the archive prefix is applied to member names only, so symlink targets stay as stored. `git` mode creates no tarball.
- **Reproducibility:** The tarball modification time comes from `SOURCE_DATE_EPOCH` when it is set, otherwise from the commit time of the ref, so repeated builds of the same commit produce identical tarballs. (See [reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/))
- **SOURCE_DATE_EPOCH Support:** You can set the `SOURCE_DATE_EPOCH` environment variable to control the tarball modification time for reproducible builds. If not set, AURgen uses the commit date of the current tag or HEAD.
- **.gitattributes Updates:** When the project already has a `.gitattributes`, AURGen adds `export-ignore` lines for the files the package does not ship. It never creates the file: export-ignore would also drop tests from the GitHub archive that an `archive` PKGBUILD builds and checks.
- **Note:** `git archive` does _not_ include the contents of git submodules. If you ever add submodules to this project, the generated tarball will _not_ contain their files—only the main repository's files. You will need to update the packaging process to include submodule contents if submodules are introduced. See the [git-archive documentation](https://git-scm.com/docs/git-archive#_limitations) for details.

### PKGBUILD Generation
- Copies and updates PKGBUILD from the template file (`PKGBUILD.0`).
- Extracts `pkgver` from `PKGBUILD.0` using `awk` without sourcing the file.
- For `aur` mode: Updates the `source` line to the GitHub release asset for one tag, `v<pkgver>` when that git tag or GitHub release exists, otherwise `<pkgver>`.
- For `git` mode: Updates the `source` line to the git repository, writes `b2sums=("SKIP")`, and drops `validpgpkeys` and `sha256sums`.
- **File Locking:** Uses `flock` to prevent concurrent PKGBUILD updates, ensuring data integrity when multiple processes might be running simultaneously.
- **NEW:** The PKGBUILD generation now automatically scans the filtered project source tree for installable files and directories. The generated `package()` function includes a robust `copy_tree()` helper function that handles file installation with proper error handling and path resolution. It automatically installs files from common directories (`bin/`, `lib/`, `etc/`, `share/`, `include/`, `local/`, `var/`, `opt/`) with appropriate permissions, reducing the need for manual editing for common project layouts.
- **NEW:** Automatic makedepends detection: AURGen automatically detects and populates the `makedepends` array based on project files. It detects build systems (CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, Autotools), programming languages (C/C++, TypeScript, Vala, SCSS/SASS), and common build tools (pkg-config, gettext, asciidoc). This eliminates the need to manually specify build dependencies for most projects.
- `pkgname`, `arch`, `depends`, `check()`, `package()`, and `aur/.gitignore` follow the [Package section](PKGBUILD-GENERATION.md#package-section).

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
- **Make**: see the [Package section](PKGBUILD-GENERATION.md#package-section)
- **Python**: `python setup.py install --root="$pkgdir" --optimize=1 --skip-build`
- **Node.js**: `build()` runs `npm install` and `npm run build --if-present` (a failing `build` script stops the build; a missing script does not). `package()` runs `npm install -g --prefix "$pkgdir/usr" .`
- **Make**: `build()` runs `make` only when the Makefile's default goal builds something (not empty, `install`, `uninstall`, `test`, `check`, `clean`, `help`, or `lint`)
- **Rust**: `install -Dm755 target/release/$pkgname "$pkgdir/usr/bin/$pkgname"`
- **Go**: `install -Dm755 $pkgname "$pkgdir/usr/bin/$pkgname"`
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

README detection reads `pacman -S` names and dependency sections. A token that starts with `-` is ignored. apt, yum, and brew names are not read as Arch packages.

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
- For a `release` or `archive` source, `aur` and `local` run `updpkgsums` and then generate `.SRCINFO`. `--dry-run` writes `b2sums=('SKIP')` instead. A `signed-tag` source keeps `b2sums=('SKIP')` and sets `validpgpkeys` from the key that signed `v<pkgver>`.
- For `git` mode: does not run `updpkgsums`. The generated PKGBUILD has `b2sums=("SKIP")` and no `sha256sums`.
- `.SRCINFO` comes from `makepkg --printsrcinfo`. If that fails, the mode stops and the partial `.SRCINFO` is removed. There is no `mksrcinfo` fallback.

> **Note for maintainers:**
> If you ever split sources by architecture (e.g., x86_64, aarch64), you must update the corresponding `b2sums_x86_64=()`, `b2sums_aarch64=()`, etc., arrays in addition to the generic `b2sums=()`. This script uses `b2sums` (BLAKE2) for checksums, not `sha256sums`. Adjust accordingly if you change the checksum type.

### GPG Signing (aur mode only)
- Checks for available GPG secret keys.
- Prompts for key selection or uses `GPG_KEY_ID` environment variable.
- Creates a detached signature for the tarball (binary `.sig` by default, ASCII-armored `.asc` with `--ascii-armor`). `--dry-run` writes an empty signature file and does not call `gpg`.
- In test mode, creates dummy signature files.

### GitHub Asset Upload
- Checks if release assets exist on GitHub.
- If not found and GitHub CLI is available, uploads the tarball and the signature. Either upload failing stops aur mode. A release aurgen creates uses GitHub-generated notes.
- Uploads both tarball and signature files.
- Verifies upload success before proceeding.

### Installation
- Only `local` mode installs: it runs `makepkg -si`, or `makepkg -s`, then namcap on the built package, then `makepkg -i` when namcap is installed (namcap errors stop the install).
- `aur` and `git` modes stop once PKGBUILD and .SRCINFO are ready.
- `--dry-run` skips the install.

## Requirements

### Required Tools
- `bash` **version 4 or newer** (the script will exit with an error if run on Bash 3 or earlier)
- `makepkg` (from `pacman`)
- `updpkgsums` (from `pacman-contrib`)
- `curl` (for checking GitHub assets)
- `git` (the project has to be a Git repository with a GitHub `origin`)
- `jq` (required for `aur` and `golden`)
- `getopt` (**GNU version from util-linux; BSD/macOS getopt is NOT supported. This script is only for GNU/Linux.**)
- **Tool Hints:** If a required tool is missing, the script will print a hint with an installation suggestion (e.g., pacman -S pacman-contrib for updpkgsums).

> **Warning:** `pacman-contrib` is not included in the `base-devel` group on Arch Linux. You must install it separately, or you will get a `updpkgsums: command not found` error when building or packaging.

### Optional Tools
- `gpg` (required for `aur` mode signing)
- `gh` (GitHub CLI, for automatic asset upload)
- `shellcheck` (for lint mode)
- `namcap` (local install check, and PKGBUILD checks in test mode)
- `bwrap` (bubblewrap; used when runtime dependencies are taken from a sandboxed `make install`)

### Files
- `PKGBUILD.0` template file in `aur/` directory

#### The Role of PKGBUILD.0

- `PKGBUILD.0` is the canonical template for your package's build instructions.
- All automated PKGBUILD generation and updates are based on this file.
- AURGen checks `aur/.PKGBUILD.0.stamp` before reusing an existing `PKGBUILD.0`.
- A stamped (generated) `PKGBUILD.0` is regenerated, and the previous file is saved as `PKGBUILD.0.bak`, when `aurgen.install.yaml` or `PKGBUILD.HEADER` changes, when the latest git tag (the `pkgver` source) moves, or when aurgen itself is upgraded.
- A hand-written `PKGBUILD.0` without a stamp is left alone.
- If the file is missing or invalid, AURGen regenerates it and backs up the previous version as `PKGBUILD.0.bak`.
- Always check `PKGBUILD.0.bak` if you need to recover changes after a regeneration.

#### Automatic PKGBUILD.0 Generation

If `PKGBUILD.0` doesn't exist, AURGen can automatically generate a basic template with the following features:

- **Metadata Extraction**: Automatically extracts package name, version, description, and license from the project
- **Version Detection**: Automatically detects version from git tags, VERSION file, or falls back to default
- **Build System Detection**: Detects CMake, Make, Python setuptools, npm, Rust, Go, or Meson; scripts, configs, docs or data with no build files are detected as `none` (no build step)
- **Dependency Detection**: Automatically populates `makedepends` based on detected build systems and project files
- **Install Function Generation**: Creates basic install commands for common project layouts
- **GitHub Integration**: Sets up proper source URLs and GPG key validation
- **License Detection**: Reads an SPDX identifier from `SPDX-License-Identifier` when that line is present. Otherwise maps a recognized license text to an SPDX id (`AGPL-3.0-or-later`, `LGPL-3.0-or-later`, `LGPL-2.1-or-later`, `GPL-3.0-or-later`, `GPL-2.0-or-later`, `Apache-2.0`, `MIT`, `BSD-3-Clause`, `BSD-2-Clause`) or `custom`
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

A source checkout uses its own `lib/` in development mode unless `RELEASE` is set. An installed copy runs in release mode (system libraries and minimal logging). The `CI` environment variable does not change the mode. Set `RELEASE=1` or `RELEASE=0` to override.

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Notes for AUR Maintainers

- The package version comes from the latest git tag: run `scripts/bump-version.sh`, commit, tag and push before `aurgen aur`. `PKGBUILD.0` needs no hand edit.
- `PKGBUILD.0` is generated when it is missing or invalid, and a generated one is regenerated when `aurgen.install.yaml`, `PKGBUILD.HEADER`, the latest tag or the aurgen version changes.
- The script fails when a required tool is missing.
- For CI or automation, set `GPG_KEY_ID` to avoid interactive prompts.
- For a headless run, stdin is not a terminal, so prompts take their default (the overwrite default is no).
- `CI` turns color off and does not change the mode. It does not answer prompts.
- Use `/usr/bin/aurgen test` to dry-run the local, aur and git modes before making changes or releases.
- The release asset tag is `v<pkgver>` when that git tag or GitHub release exists, otherwise `<pkgver>`.
- VCS packages (`git` mode) write `b2sums=("SKIP")` and drop `validpgpkeys` and `sha256sums`.
- Environment variables are listed in [Environment Variables](#environment-variables). Running `aurgen` with no arguments prints modes and options, not those variables.
- Use `--ascii-armor` or `-a` to create ASCII-armored signatures (.asc) instead of binary signatures (.sig) for better compatibility with some AUR helpers (must be before the mode).

[↑ Back to top](#aurgen-aur-packaging-automation-script)

## Error Handling

- Comprehensive error checking for missing tools, files, and GPG keys.
- One release tag for the asset check, the upload, and the source URL. Template generation in aur mode asks `gh` for `v<pkgver>` and then the unprefixed tag when looking up a release tarball URL. It does not probe `origin` for the tag; that check is the later archive and signed-tag step.
- Clear error messages with actionable instructions.
- Test mode reports errors for each of the local, aur and git dry-runs.

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