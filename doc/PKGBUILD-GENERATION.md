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
- `source` - Directory in your project root to copy from
- `destination` - Destination path in the package (supports `$pkgname` variable)
- `permissions` - Permission type: `executable` (755) or `read-only` (644)
- `exclude` - **Optional**: Array of subdirectories or files to exclude

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

# Custom sections with exclusions
custom_data:
  source: custom
  destination: usr/share/$pkgname/custom
  permissions: read-only
  exclude: [backup, old]
```

### Managing Configuration

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
  git_user_name: "Your Name"
  git_user_email: "your.email@example.com"
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

For complete AUR integration documentation, see [doc/AUR-INTEGRATION.md](doc/AUR-INTEGRATION.md).

### Exclusions

The exclusion feature allows you to copy most of a directory while excluding specific subdirectories or files. This is particularly useful for:

- **Development files**: Exclude `test/`, `temp/`, `backup/` directories
- **Documentation**: Exclude `docs/`, `examples/` when not needed in the package
- **Build artifacts**: Exclude `cache/`, `logs/`, `*.tmp` files
- **Development tools**: Exclude IDE-specific directories like `.vscode/`, `.idea/`

**Exclusion Patterns:**
- Exclusions are matched against subdirectories and files within the source directory
- Multiple exclusions are specified as YAML arrays: `[item1, item2, item3]`
- Exclusions are case-sensitive and must match exact directory/file names
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
  exclude: [docs, examples, README.md]

# Exclude cache and log files
variable_data:
  source: var
  destination: var/$pkgname
  permissions: read-only
  exclude: [cache, logs, *.tmp]
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

## PKGBUILD.0 Template

- `PKGBUILD.0` is the canonical template for your package's build instructions
- All automated PKGBUILD generation and updates are based on this file
- You should edit `PKGBUILD.0` directly for any customizations
- If the file is missing or invalid, AURGen will regenerate it and back up the previous version as `PKGBUILD.0.bak`

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
- Customizations are preserved unless AURGen detects outdated fields (backed up as `PKGBUILD.HEADER.bak`)
- Delete the file to force regeneration based on current project metadata

**Usage:**
- Edit `PKGBUILD.0` for build logic
- Edit `PKGBUILD.HEADER` for legal/metadata changes

This separation keeps PKGBUILD files organized and AUR-compliant. 