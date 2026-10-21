# PKGBUILD Generation

AURGen automatically generates and manages PKGBUILD files through a template-based system:

## Configuration System

AURGen includes a flexible configuration system that allows you to customize which directories are copied during package installation. This is particularly useful for projects that don't need all the default directories or have custom directory structures.

### Overview

The configuration system automatically generates two files in the `aur/` directory when PKGBUILD.0 is created for the first time:
- **`aurgen.install.yaml`** - Your project's active configuration (includes AUR integration settings)
- **`aurgen.install.yaml.example`** - Reference example with documentation (includes AUR integration examples)

### Configuration File Locations
- `aur/aurgen.install.yaml` - Project-specific configuration file
- `aur/aurgen.install.yaml.example` - Example configuration file with documentation

### Configuration Format

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
- `source` - Directory in your project root to copy from: one of `bin`, `lib`, `etc`, `share`, `include`, `local`, `var` or `opt` (a section with any other source is ignored)
- `destination` - Destination path in the package (supports `$pkgname` variable)
- `permissions` - Permission type: `executable` (755) or `read-only` (644)
- `exclude` - **Optional**: Array of subdirectory names to exclude (a file name does not exclude that file)

### Examples
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

### Managing Configuration

**Generate Configuration:**
```bash
aurgen config generate    # Create default configuration file (fails if it already exists)
```

**Edit Configuration:**
```bash
aurgen config edit        # Open in default editor
```

**View Configuration:**
```bash
aurgen config show        # Display current configuration
aurgen config show effective  # Print parsed package metadata and copy rules
aurgen config validate    # Validate syntax and show active rules
```

**Reset Configuration:**
```bash
aurgen config reset       # Reset to defaults (creates backup)

`config edit`, `config reset`, and `config validate` still run when `aurgen.install.yaml` is invalid. Every other mode stops on that file so it can be repaired from config mode. `config generate` refuses to replace a file that already exists.
```

**Import from a PKGBUILD:**
```bash
aurgen config import [path]
```

The command reads a PKGBUILD's fields, source kind, `install_vars`, `post_package`, and `check` (default path `aur/PKGBUILD`) and appends a `package:` section to the configuration. It refuses to run when a `package:` section already exists. On the first run, when `aur/aurgen.install.yaml` is missing and `aur/PKGBUILD` exists, aurgen does the same import by itself.

**Get Help:**
```bash
aurgen config help        # Show detailed usage information
```

### Default Configuration

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
  aur_repo_dir: /opt/AUR
  auto_push: true
  commit_message: "Update to version {version}"
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  ssh_key: ~/.ssh/aur_key
  backup_existing: true
  validate_before_push: true
```

### AUR Integration Configuration

The configuration file also includes AUR integration settings that control how your package is deployed to the Arch User Repository (AUR). These settings are automatically included in generated configuration files.

**Key AUR Integration Settings:**
- **`aur_repo_dir`**: Directory where local AUR repositories are stored
- **`auto_push`**: Whether to automatically push changes to AUR after deployment
- **`commit_message`**: Template for commit messages (supports `{version}` placeholder)
- **`git_user_name`** and **`git_user_email`**: Git configuration for AUR commits
- **`ssh_key`**: SSH key for AUR authentication
- **`backup_existing`**: Whether to create backups before overwriting files
- **`validate_before_push`**: Whether to validate repository before pushing

For complete AUR integration documentation, see [doc/AUR-INTEGRATION.md](AUR-INTEGRATION.md).

### Exclusions

The exclusion feature allows you to copy most of a directory while excluding specific subdirectories. This is particularly useful for:

- **Development files**: Exclude `test/`, `temp/`, `backup/` directories
- **Documentation**: Exclude `docs/`, `examples/` when not needed in the package
- **Build artifacts**: Exclude `cache/`, `logs/` directories
- **Development tools**: Exclude IDE-specific directories like `.vscode/`, `.idea/`

**Exclusion Patterns:**
- Each exclusion names a subdirectory of the source directory and skips everything under it; a single file cannot be excluded
- Multiple exclusions are specified as YAML arrays: `[item1, item2]` or `[item1, item2]` with a space after the comma. A name written in quotes is stored without the quotes
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

### Important Notes

- **Project-Specific**: Configuration files are stored in the `aur/` directory and are specific to each project
- **Auto-Generation**: Files are automatically created when PKGBUILD.0 is generated for the first time
- **No Overwriting**: Existing configuration files are never overwritten automatically
- **Backup Protection**: The `reset` command creates a `.bak` file before regenerating
- **Validation**: Use `aurgen config validate` to check your configuration syntax
- **YAML Format**: The new YAML format provides better structure and readability compared to the previous colon-separated format
- **Section-Based**: Each configuration section can be independently enabled, disabled, or customized
- **Permission Types**: Use `executable` for executable files (755) or `read-only` for data files (644)

## Package section

`aur/aurgen.install.yaml` may contain a top-level `package:` mapping. That mapping is package metadata, not a copy rule. Detected values stay in place. Entries in the mapping are added, or they replace the detected value when the key says so. An absent `package:` section leaves every key empty and the generator uses detection alone.

Lists may be inline (`[a, b]`) when no item contains a comma, or a block of `-` items. A block item is kept intact, so an `optdepends` entry may contain `: `. An empty list is omitted from the PKGBUILD. `makedepends` is the exception: it is always written, as `makedepends=()` when nothing remains.

### Keys

- `name` — `pkgname`. Default is the repository name, lowercased: the `origin` remote's basename with a trailing `.git` removed, otherwise the git root directory. A dot inside the name is kept (`my.tool`). A repository whose owner and name are the same is accepted when that owner matches the owner in the `PKGBUILD.0` `url`. Allowed characters are lowercase letters, digits, and `@._+-`, with no leading `.` or `-`. The `origin` URL has to be a GitHub URL (`https://github.com/...` or `git@github.com:...`). Any other origin, or none, is refused before `local`, `aur`, and `git` delete generated files.
- `description` — replaces the detected `pkgdesc`.
- `license` — list that replaces the detected license. The first item is also the license id written into `PKGBUILD.HEADER`.
- `install` — file name of a `.install` script in `aur/`, next to this config. An existing file takes precedence. A missing file falls back to generation when units or messages are available; otherwise it is rejected. A path or a leading `.` is always rejected.
- `install_messages` — optional mapping of `post_install`, `post_upgrade`, and `pre_remove` to block lists of literal message lines. A hand-written `install` file takes precedence.
- `check` — `true`, `false`, or a shell command. See [check()](#check).
- `source` — `release` (default), `archive`, or `signed-tag`. Any other value is an error.
  - `release` keeps the existing release-tarball or VCS source selection.
  - `archive` sets `source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")` and `cd`s into `"$srcdir/<repo>-$pkgver"`. No `validpgpkeys` line is written.
  - `signed-tag` sets `source=("$pkgname::git+$url.git#tag=v$pkgver?signed")`, `cd`s into `"$srcdir/$pkgname"`, adds `git` to `makedepends` when it is not already there, and writes `validpgpkeys` as the fingerprint that signed v<pkgver>.
- `arch` — architecture list. See [arch](#arch).
- `depends` — extra runtime dependencies, added to detection. See [depends](#depends).
- `optdepends` — written as given. A guarded command (`command -v`, `type -P`, `hash`, or `which`) is only printed as an `optdepends suggestion` on stderr; it is not added to this array.
- `makedepends` — names added after the detected build dependencies, once each. A name whose base is already in `depends` is not repeated. A detected name whose base is listed in `optdepends` is dropped: an optional tool a script mentions is not a build dependency. Detected names that are members of `base-devel` are dropped; a name written in this list is kept. `signed-tag` adds `git` when it is missing.
- `conflicts`, `provides`, `backup` — written as given.
- `install_vars` — extra `NAME=value` arguments for `make install`. `NAME` is an identifier; `value` is letters, digits, and `._/+-`. See [package()](#package).
- `post_package` — shell lines appended at the end of `package()`.

`post_package` lines and a custom `check` command are written into the PKGBUILD as shell code, and makepkg runs them. Put only commands you would put in a hand-written PKGBUILD.

### Example

```yaml
package:
  name: linux-mytool
  install: mytool.install
  check: true
  source: release
  arch: [any]
  depends:
    - systemd>=249
  optdepends:
    - "libnotify: desktop notifications"
  makedepends: []
  conflicts: [mytool]
  provides: []
  backup:
    - etc/mytool/mytool.conf
  install_vars:
    - UNITDIR=/usr/lib/systemd/system
  description: "what the package does"
  license: [GPL-3.0-or-later]
  post_package: []
```

### Install messages

Without an existing `package.install` file, AURGen writes `aur/<pkgname>.install`, next to `PKGBUILD.0` and regenerated with it, when the install scan detects units or `install_messages` is present. The same sandboxed `make install` scan used for dependencies supplies the unit list; it is not run twice. Only direct children of `usr/lib/systemd/system/` and `usr/lib/systemd/user/` count. Timers are preferred; services are used when no timer is shipped. If the install scan is unavailable or fails, configure messages explicitly.

```yaml
package:
  install_messages:
    post_install:
      - 'Preview cleanup first: mytool --dry-run'
      - 'sudo systemctl enable --now mytool.timer'
    post_upgrade:
      - 'Review the updated configuration before the next run.'
    pre_remove:
      - 'sudo systemctl disable --now mytool.timer'
```

Configured lines are printed verbatim and replace the automatic text for that hook. Without configured lines, `post_install` prints `==> <pkgname>: nothing was enabled.` and one `enable --now` hint per detected timer (or service), and `pre_remove` prints `==> <pkgname>: disable the units you enabled before removing:` followed by matching `disable --now` hints. System units use `sudo systemctl`; user units use `systemctl --user`. `post_upgrade` is emitted only when configured.

Lines are literal text, printed through quoted here-documents: `$HOME`, backticks, and `$(...)` are never expanded or executed. Quoted items preserve leading/trailing spaces and empty lines. The generated scriptlet never enables, starts, stops, or reloads units itself. An explicit existing `package.install` file remains unchanged and takes precedence over generated messages.

### pkgname

`package.name` is `pkgname` when it is set. Otherwise `pkgname` is the repository name folded to lowercase.

### arch

`package.arch` is written as given when the list is non-empty. Otherwise the field is `arch=('any')`, or `arch=('x86_64' 'aarch64')` when the project compiles. A project compiles when the detected build system is CMake, Rust, Go, or Meson, or when a tracked source file ends in `.c`, `.cc`, `.cpp`, `.cxx`, `.c++`, `.rs`, `.go`, or `.vala`. A Makefile alone does not count as compiled.

### depends

Runtime `depends` come from the files the package ships:

1. When the Makefile has an `install:` target and `bwrap` is available, the generator runs `make install DESTDIR=… PREFIX=/usr` plus `install_vars` inside a bubblewrap sandbox and scans the installed files.
2. Otherwise it scans the copy-rule source directories.
3. Otherwise it scans tracked files, skipping `tests/`, `test/`, `doc/`, and `docs/`.

From those files it records the shebang interpreter, mapped shell commands, and `python-<module>` only when that name is in the mapping table. A command inside double quotes still counts when it is `$(...)` or a backtick substitution. The command after that substitution is a separate command (`x"$(date)" jq` records `date` and `jq`). Single-quoted text, here-document bodies, `case` patterns (`gcc|sudo)`), and the elements of a multi-line array literal are not scanned. A `#` starts a comment only at the start of a word, so `$((10#x))` is not a comment. README detection reads `pacman -S` names only: a token that starts with `-` is a flag and is ignored, and apt, yum, and brew names are not Arch packages. Configured `depends` are listed first. A detected package is dropped when its base name matches a configured entry. The base name is the text before `>=`, `<=`, `=`, `>`, or `<`, so `systemd>=249` replaces a detected `systemd`.

### check

`check: false` omits `check()`. Any other non-empty value other than `true` is written as the check command. `true` and an empty `check` follow the build system, and `check()` is omitted when that system has no test command:

- Make: `make check` when the Makefile has a `check:` target (the GNU Coding Standards self-test target, which Arch packages run in `check()`). Make is not executed to discover the target. `test` is not a standard target, so a `test:` target alone gives no `check()`.
- CMake: `ctest --test-dir build`
- Rust: `cargo test --release`
- Go: `go test ./...`
- Meson: `meson test -C build`

`check()` runs on every install through makepkg, yay, and paru. The command it runs must pass from an unpacked source tree without git, network, root, the user's home, or installed system state. yay and paru build inside a git clone of the AUR repository, so a test that asks git about the work tree sees the AUR clone, not the project. When the project's self-test suite needs any of that (lint, drift checks, slow or host-dependent tests), give the package a separate hermetic target and name it explicitly, for example `check: make check-package`.

`aurgen aur` refuses a `check()` `make` target that the release tag's Makefile does not define. The refusal runs on a dry run and on a real run, before any tarball or upload.

### package

`package()` always installs the first of `LICENSE`, `LICENSE.txt`, or `COPYING` that exists.

When the build system is Make and the Makefile has an `install:` target, copy rules are skipped. The function runs `make install DESTDIR="$pkgdir" PREFIX=/usr` with each `install_vars` entry appended. Without that target, copy rules are the install step and `make` is not run. `build()` runs `make` only when the Makefile's default goal is something other than empty, `install`, `uninstall`, `test`, `check`, `clean`, `help`, or `lint`.

A Node `build()` runs `npm install` and then `npm run build --if-present`. A `build` script that fails stops the function. A package with no `build` script does not.

Every other build system keeps the copy rules and then adds its own install command (CMake `--install`, Python `setup.py install`, npm, the Rust or Go binary, or Meson `install`). `post_package` lines are appended after that command.

### aur/.gitignore

On startup, when `aur/.gitignore` does not exist, AURGen creates it. Everything in `aur/` is generated except the package config, so the file ignores everything and re-includes only that config:

```
*
!.gitignore
!aurgen.install.yaml
```

`PKGBUILD`, `.SRCINFO`, and the install scriptlet are regenerated on every run and are not committed. A file written by an older AURGen, which also re-included `PKGBUILD`, `.SRCINFO`, and `*.install`, is replaced with these rules. Any other existing `aur/.gitignore` is left unchanged.

## PKGBUILD.0 Template

- `PKGBUILD.0` is the canonical template for your package's build instructions
- All automated PKGBUILD generation and updates are based on this file
- You should edit `PKGBUILD.0` directly for any customizations
- If the file is missing or invalid, AURGen will regenerate it and back up the previous version as `PKGBUILD.0.bak`

### Hand-file equivalence

Identity, dependencies, source shape, and the `build`, `check`, and `package` bodies on `PKGBUILD.0` are the semantic layer `tests/test-parity.sh` already checks. That test sources `aur/PKGBUILD.0` and does not open `hand/PKGBUILD`. Matching a hand file byte for byte is the wrong check. A hand file pins `sha256sums` and says to run `updpkgsums`; those pins are separate from the generator contract.

Source shape for `release`, `archive`, and `signed-tag` stays in the [`package.source`](#package-section) bullets above.

`gen_pkgbuild0` writes `b2sums=('SKIP')` on the template. A non-VCS pinned checksum is the later `updpkgsums` result that `update_checksums` writes on the mode-output `PKGBUILD`. Dry-run and VCS-only sources keep `SKIP`.

Signed-tag aur mode keeps `b2sums=('SKIP')` on the mode-output `PKGBUILD` and writes `validpgpkeys` as the key that signed `v$pkgver`, through `write_validpgpkeys`. Local mode copies the template and then updates checksums (`lib/modes/local.sh`).

Git mode drops `validpgpkeys` and `sha256sums`, writes `b2sums=("SKIP")` beside the git source, and ensures `makedepends` contains a `git` entry. A name that only contains those letters, such as `libgit2`, does not count. Configured `provides` and `conflicts` are kept, and the short package name is appended when it is missing. `build()`, `check()`, and `package()` stay, including when `source=` is a single line. A branch, owner, or repository name that cannot be written safely into that URL stops git mode. Signed-tag `git` in `makedepends` comes from `gen_pkgbuild0` when `source_kind` is `signed-tag`. That is why `tests/fixtures/ramcleaner/aur/aurgen.install.yaml` omits `makedepends`, and why `lib/config-import.sh` strips `git` on signed-tag import.

A later `makepkg --printsrcinfo` check uses the command and the `aur/` working directory in `generate_srcinfo`. The parsed file is the mode-output `PKGBUILD` in `aur/` after the copy in local mode or aur mode. `PKGBUILD.0` stays the template.

## Automatic Generation

If `PKGBUILD.0` doesn't exist, AURGen can automatically generate a basic template with:
- **Metadata Extraction**: Automatically extracts package name, version, description, and license from the project
- **Build System Detection**: Detects CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, or Autotools
- **Dependency Detection**: Automatically populates `makedepends` based on detected build systems and project files
- **Install Function Generation**: Creates basic install commands for common project layouts
- **GitHub Integration**: Sets up proper source URLs and GPG key validation

## PKGBUILD.HEADER

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
- An existing `PKGBUILD.HEADER` is never changed, so customizations are kept
- Delete the file to force regeneration based on current project metadata

**Usage:**
- Edit `PKGBUILD.0` for build logic
- Edit `PKGBUILD.HEADER` for legal/metadata changes

This separation keeps PKGBUILD files organized and AUR-compliant.

## PKGBUILD Generation

AURGen automatically generates and manages PKGBUILD files through a template-based system with flexible configuration options. This includes:

- **Template-based Generation**: Uses `PKGBUILD.0` as the canonical template for build instructions
- **Configuration System**: Customizable directory copying with exclusion support via `aurgen.install.yaml`
- **Automatic Detection**: Build system detection, dependency analysis, and metadata extraction
- **Header Management**: Separate `PKGBUILD.HEADER` for consistent legal and maintainer information

### Configuration File System

AURGen uses a YAML-based configuration system to control package installation behavior. Configuration files are automatically generated when you first run `aurgen aur` or `aurgen config generate`. Each project gets its own `aur/aurgen.install.yaml` file that allows you to customize which directories are copied during package installation, where they're placed in the final package, and what files are excluded. The system supports both executable and read-only permissions, making it easy to create properly structured packages for different types of software.

**Configuration File Usage:**
- **Auto-Generated**: Configuration files are created automatically when you first run `aurgen aur` or `aurgen config generate`
- **Project-Specific**: Each project gets its own `aur/aurgen.install.yaml` file for customizing installation behavior
- **Directory Control**: Configure which project directories are copied during package installation and where they're placed
- **Exclusion Support**: Exclude development files, documentation, or temporary files from the final package
- **Permission Management**: Set executable or read-only permissions for different file types

For detailed documentation on PKGBUILD generation, configuration management, and advanced features, see [doc/PKGBUILD-GENERATION.md](PKGBUILD-GENERATION.md).

## Dependency Detection System

AURGen automatically detects build dependencies through multiple methods:

### README Analysis
Scans README files for `pacman -S` commands and dependency sections.

### Project File Analysis
Analyzes git-tracked project files to detect:
- **Build Systems**: CMake, Make, Python setuptools, npm, Rust, Go, Java, Meson, Autotools
- **Programming Languages**: C/C++, TypeScript, Vala, SCSS/SASS
- **Frameworks**: Qt, GTK, and other common libraries
