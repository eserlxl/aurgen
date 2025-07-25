# Tool Mapping System

This document provides a comprehensive overview of aurgen's tool mapping system, which automatically manages tool-to-package mappings for Arch Linux.

## Overview

The tool mapping system consists of three main components that work together to maintain accurate and up-to-date tool-to-package mappings:

1. **Mapping Expansion** - Adds new tool mappings from various sources
2. **Version Updates** - Migrates to newer package versions
3. **Mapping Cleaning** - Removes unnecessary and redundant mappings

## System Components

### 1. Mapping Expansion (`lib/expand-mapping.sh`)

**Purpose**: Automatically discovers new tool-to-package mappings from multiple sources.

**Sources**:
- Arch Linux package database
- Popular AUR packages
- System package analysis
- Common development tools

**Usage**:
```bash
./bin/expand-mapping generate    # Generate mapping only
./bin/expand-mapping apply       # Apply existing mapping
./bin/expand-mapping update      # Generate and apply (default)
```

### 2. Version Updates (`lib/version-updater.sh`)

**Purpose**: Detects and applies package version migrations (e.g., GTK3→GTK4, Qt5→Qt6).

**Features**:
- Automatic version detection
- Predefined migration rules
- Safety backups
- Validation checks

**Usage**:
```bash
./bin/update-versions check      # Check versions only
./bin/update-versions update     # Update versions (default)
```

### 3. Mapping Cleaning (`lib/clean-mapping.sh`)

**Purpose**: Removes unnecessary mappings and filters out unwanted packages.

**Filters**:
- Self-mappings (tool name = package name)
- Android-specific packages
- Unnecessary system packages

**Usage**:
```bash
source lib/clean-mapping.sh && clean_mapping
```

## Complete Workflow

### Step 1: Expand Mappings

Add new tool mappings from various sources:

```bash
./bin/expand-mapping update
```

This will:
- Analyze Arch Linux packages
- Check popular AUR packages
- Scan system packages
- Generate expanded mapping

### Step 2: Update Versions

Migrate to newer package versions:

```bash
./bin/update-versions update
```

This will:
- Check available package versions
- Apply migration rules (GTK3→GTK4, Qt5→Qt6, etc.)
- Update tool mapping accordingly

### Step 3: Clean Mappings

Remove unnecessary mappings:

```bash
source lib/clean-mapping.sh && clean_mapping
```

This will:
- Remove self-mappings
- Filter out Android packages
- Remove other unnecessary packages

### Step 4: Commit Changes

```bash
git add lib/tool-mapping.sh
git commit -m "Update tool mapping with expanded mappings and version migrations"
```

## Migration Rules

The version updater includes predefined migration rules for common package families:

### Framework Migrations

| Old Package | New Package | Description |
|-------------|-------------|-------------|
| `gtk3` | `gtk4` | GTK framework upgrade |
| `qt5-base` | `qt6-base` | Qt framework upgrade |
| `qt5-tools` | `qt6-tools` | Qt tools upgrade |

### Language Migrations

| Old Package | New Package | Description |
|-------------|-------------|-------------|
| `python2` | `python` | Python 2 to 3 |
| `jdk8-openjdk` | `jdk-openjdk` | Java JDK upgrade |
| `jdk11-openjdk` | `jdk-openjdk` | Java JDK upgrade |
| `jdk17-openjdk` | `jdk-openjdk` | Java JDK upgrade |

### Runtime Migrations

| Old Package | New Package | Description |
|-------------|-------------|-------------|
| `nodejs-lts-erbium` | `nodejs` | Node.js LTS to stable |
| `nodejs-lts-fermium` | `nodejs` | Node.js LTS to stable |
| `nodejs-lts-gallium` | `nodejs` | Node.js LTS to stable |
| `rust-nightly` | `rust` | Rust nightly to stable |
| `rust-beta` | `rust` | Rust beta to stable |

## Output Files

All tools create files in `/tmp/aurgen-mapping/`:

### Expansion Files
- `expanded-mapping.txt` - Raw tool:package mappings
- `analysis.log` - Detailed analysis log
- `tool-mapping.sh.backup` - Backup of original file

### Version Update Files
- `version-updates.txt` - Applied migrations
- `tool-mapping.sh.backup.version` - Backup before version updates

### Cleaning Files
- `clean-mapping.txt` - Cleaned mappings
- `tool-mapping.sh.backup.clean` - Backup before cleaning

## Safety Features

### Automatic Backups
- Each tool creates backups before making changes
- Clear instructions for restoration
- Multiple backup types for different operations

### Validation
- Checks package availability before applying migrations
- Validates tool and package names
- Provides detailed statistics and reports

### Selective Updates
- Only updates when newer versions are available
- Preserves existing custom mappings
- Respects user preferences

## Customization

### Adding Migration Rules

Edit the `VERSION_MIGRATIONS` array in `lib/version-updater.sh`:

```bash
declare -A VERSION_MIGRATIONS=(
    # Existing rules...
    ["old-package"]="new-package"
    ["deprecated-tool"]="modern-tool"
)
```

### Adding Custom Tools

Edit the `common_tools` array in `lib/expand-mapping.sh`:

```bash
local common_tools=(
    # Existing tools...
    "your-tool:your-package"
    "another-tool:another-package"
)
```

### Custom Filtering

Edit the filtering logic in `lib/clean-mapping.sh`:

```bash
# Skip some other unnecessary packages
if [[ ! "$tool" =~ ^(your-pattern|another-pattern)$ ]]; then
    clean_mappings+=("$tool:$package")
fi
```

## Best Practices

### Regular Maintenance
1. **Weekly**: Run expansion to add new tools
2. **Monthly**: Run version updates to migrate to newer versions
3. **Quarterly**: Run cleaning to remove unnecessary mappings

### Before Committing
1. **Review changes** - Check what mappings were added/modified
2. **Test thoroughly** - Test aurgen with updated mappings
3. **Backup first** - Keep backups of working configurations

### Error Recovery
1. **Use backups** - Restore from appropriate backup file
2. **Regenerate** - Run the complete workflow again
3. **Debug** - Enable debug output for troubleshooting

## Troubleshooting

### Common Issues

1. **Network Errors**
   - AUR analysis requires internet connection
   - Check network connectivity

2. **Permission Errors**
   - Ensure write access to `/tmp/aurgen-mapping/`
   - Check file permissions

3. **Package Not Found**
   - Some packages may not be available
   - Check package availability with `pacman -Ss`

### Debug Mode

Enable debug output:

```bash
DEBUG_LEVEL=1 ./bin/expand-mapping update
DEBUG_LEVEL=1 ./bin/update-versions update
```

### Manual Recovery

If something goes wrong:

```bash
# Restore from specific backup
cp /tmp/aurgen-mapping/tool-mapping.sh.backup.* lib/tool-mapping.sh

# Or regenerate from scratch
rm -rf /tmp/aurgen-mapping/
./bin/expand-mapping update
./bin/update-versions update
source lib/clean-mapping.sh && clean_mapping
```

## Integration with aurgen

The tool mapping system is automatically used by aurgen's dependency detection:

1. **README Analysis** - Maps tools found in README files
2. **Project File Analysis** - Maps build system and language tools
3. **Tool Detection** - Maps tools detected in project files

The expanded mapping significantly improves aurgen's ability to detect and suggest the correct packages for build dependencies.

## Contributing

When contributing to the mapping system:

1. **Add new tools** to the expansion arrays
2. **Add migration rules** for new package families
3. **Test thoroughly** with various project types
4. **Update documentation** for new features
5. **Ensure accuracy** of all mappings

## License

This system is part of aurgen and is licensed under the GNU General Public License v3.0 or later. 