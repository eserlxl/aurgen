# Version Check and Updater

This document describes the version check and updater feature for aurgen, which automatically detects and applies package version migrations in the tool mapping.

## Overview

The version updater system consists of two main components:

1. **`lib/version-updater.sh`** - Core version checking and migration logic
2. **`bin/update-versions`** - CLI interface

## Features

### Automatic Version Detection

The version updater automatically detects:

- **Available package versions** in the Arch Linux repositories
- **Version migration rules** for common package families
- **Newer versions** of existing packages

### Version Migration Rules

The system includes predefined migration rules for common package families:

#### GTK Framework
- `gtk3` → `gtk4`
- `gtk-update-icon-cache` → `gtk-update-icon-cache`

#### Qt Framework
- `qt5-base` → `qt6-base`
- `qt5-tools` → `qt6-tools`

#### Python
- `python2` → `python`
- `python2-pip` → `python-pip`

#### Java
- `jdk8-openjdk` → `jdk-openjdk`
- `jdk11-openjdk` → `jdk-openjdk`
- `jdk17-openjdk` → `jdk-openjdk`

#### Node.js
- `nodejs-lts-erbium` → `nodejs`
- `nodejs-lts-fermium` → `nodejs`
- `nodejs-lts-gallium` → `nodejs`

#### Rust
- `rust-nightly` → `rust`
- `rust-beta` → `rust`

#### Go
- `go1.18` → `go`
- `go1.19` → `go`
- `go1.20` → `go`
- `go1.21` → `go`

#### System Libraries
- `systemd-sysvcompat` → `systemd`
- `openssl-1.1` → `openssl`
- `openssl-1.0` → `openssl`
- `libpng16` → `libpng`
- `libjpeg-turbo` → `libjpeg`

## Usage

### Command Line Interface

```bash
# Check available versions and migration rules
./bin/update-versions check

# Update package versions in tool mapping
./bin/update-versions update

# Show help
./bin/update-versions --help
```

### Programmatic Usage

```bash
# Source the library
source lib/version-updater.sh

# Check versions only
check_versions

# Update versions
update_versions
```

## How It Works

### 1. Version Detection

The system uses `pacman -Ss` to check for available package versions:

```bash
# Check if a specific version is available
pacman -Ss "^package-name$"

# Find newer versions
pacman -Ss "^package" | grep -o "package[0-9.-]*" | sort -V | tail -1
```

### 2. Migration Rules

Predefined migration rules are stored in an associative array:

```bash
declare -A VERSION_MIGRATIONS=(
    ["gtk3"]="gtk4"
    ["qt5-base"]="qt6-base"
    ["python2"]="python"
    # ... more rules
)
```

### 3. Update Process

1. **Backup** - Creates backup of current tool-mapping.sh
2. **Scan** - Reads all current mappings
3. **Check** - Applies migration rules and version detection
4. **Update** - Generates new tool-mapping.sh with updated versions
5. **Report** - Shows statistics and applied migrations

## Output Files

The version updater creates several files in `/tmp/aurgen-mapping/`:

- **`version-updates.txt`** - List of applied migrations
- **`tool-mapping.sh.backup.version`** - Backup of original tool-mapping.sh

## Safety Features

### Backup and Restore
- Automatically creates backup before making changes
- Provides clear instructions for restoration
- Preserves original mappings

### Validation
- Checks if target packages are actually available
- Validates package names before applying migrations
- Provides detailed migration statistics

### Selective Updates
- Only updates packages that have newer versions available
- Respects existing mappings if no migration is needed
- Preserves custom mappings

## Integration with aurgen

The version updater works alongside the mapping expansion system:

1. **Expand** - Use `./bin/expand-mapping update` to add new mappings
2. **Update** - Use `./bin/update-versions update` to migrate to newer versions
3. **Clean** - Use `lib/clean-mapping.sh` to remove unnecessary mappings

## Customization

### Adding Migration Rules

To add new migration rules, edit the `VERSION_MIGRATIONS` array in `lib/version-updater.sh`:

```bash
declare -A VERSION_MIGRATIONS=(
    # Existing rules...
    ["old-package"]="new-package"
    ["deprecated-tool"]="modern-tool"
)
```

### Custom Version Detection

To add custom version detection logic, extend the `check_package_version` function:

```bash
check_package_version() {
    local package="$1"
    local version="$2"
    
    # Your custom detection logic
    # Return newer version if found
}
```

## Best Practices

1. **Run Regularly** - Update versions periodically to stay current
2. **Review Changes** - Always review applied migrations before committing
3. **Test Thoroughly** - Test aurgen with updated mappings
4. **Backup First** - Keep backups of working configurations

## Troubleshooting

### Common Issues

1. **Package Not Found** - Some packages may not be available in repositories
2. **Migration Conflicts** - Multiple migration paths may exist
3. **Version Mismatches** - Package versions may not match expectations

### Debug Mode

Enable debug output by setting environment variables:

```bash
DEBUG_LEVEL=1 ./bin/update-versions update
```

### Manual Recovery

If something goes wrong:

```bash
# Restore from backup
cp /tmp/aurgen-mapping/tool-mapping.sh.backup.version lib/tool-mapping.sh

# Or regenerate from scratch
rm -rf /tmp/aurgen-mapping/
./bin/expand-mapping update
./bin/update-versions update
```

## Examples

### Example Migration Output

```
Checking package versions...
Available package versions:
  gtk3: 3.24.38-1
  gtk4: 4.12.4-1
  qt5-base: 5.15.11+kde+r167-1
  qt6-base: 6.6.2-1

Checking for version migrations...
Version migration statistics:
  Migrations found: 3

Migrations applied:
  gtk:gtk3 → gtk4
  qmake:qt5-base → qt6-base
  moc:qt5-base → qt6-base
```

### Example Usage Workflow

```bash
# 1. Expand mappings (add new tools)
./bin/expand-mapping update

# 2. Update versions (migrate to newer versions)
./bin/update-versions update

# 3. Clean mappings (remove unnecessary ones)
source lib/clean-mapping.sh && clean_mapping

# 4. Commit changes
git add lib/tool-mapping.sh
git commit -m "Update tool mapping with expanded mappings and version migrations"
```

## Contributing

When contributing to the version updater:

1. Add new migration rules to the `VERSION_MIGRATIONS` array
2. Test with various package combinations
3. Update documentation
4. Ensure migrations are accurate and safe

## License

This feature is part of aurgen and is licensed under the GNU General Public License v3.0 or later. 