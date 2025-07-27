# PKGBUILD Generation

AURGen automatically generates and manages PKGBUILD files through a template-based system:

## Configuration System

AURGen includes a flexible configuration system that allows you to customize which directories are copied during package installation. This is particularly useful for projects that don't need all the default directories or have custom directory structures.

### Overview

The configuration system automatically generates two files in the `aur/` directory when PKGBUILD.0 is created for the first time:
- **`aurgen.install.yaml`** - Your project's active configuration
- **`aurgen.install.yaml.example`** - Reference example with documentation

### Configuration File Locations
- `aur/aurgen.install.yaml` - Project-specific configuration file
- `aur/aurgen.install.yaml.example` - Example configuration file with documentation

### Configuration Format
```
source_dir:dest_dir:permissions[:exclude1,exclude2,...]
```

**Field Descriptions:**
- `source_dir` - Directory in your project root to copy from
- `dest_dir` - Destination path in the package (supports `$pkgname` variable)
- `permissions` - Octal permissions (e.g., 755 for executable, 644 for read-only)
- `exclude1,exclude2,...` - **Optional**: Comma-separated list of subdirectories or files to exclude

### Examples
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

The default configuration includes these directories:
- `bin` → `usr/bin` (755 - executable files)
- `lib` → `usr/lib/$pkgname` (644 - library files)
- `etc` → `etc/$pkgname` (644 - configuration files)
- `share` → `usr/share/$pkgname` (644 - shared data)
- `include` → `usr/include/$pkgname` (644 - header files)
- `local` → `usr/local/$pkgname` (644 - local data)
- `var` → `var/$pkgname` (644 - variable data)
- `opt` → `opt/$pkgname` (644 - optional data)

### Exclusions

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

### Important Notes

- **Project-Specific**: Configuration files are stored in the `aur/` directory and are specific to each project
- **Auto-Generation**: Files are automatically created when PKGBUILD.0 is generated for the first time
- **No Overwriting**: Existing configuration files are never overwritten automatically
- **Backup Protection**: The `reset` command creates a `.bak` file before regenerating
- **Validation**: Use `aurgen config validate` to check your configuration syntax
- **Backward Compatibility**: Existing configurations without exclusions continue to work unchanged

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