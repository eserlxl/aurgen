# Tool Mapping System

This document describes the tool mapping system used by aurgen to map tool names to their containing packages in Arch Linux.

## Overview

The tool mapping system consists of a comprehensive mapping of tool names to their corresponding Arch Linux packages. This mapping is used by aurgen to automatically detect dependencies when analyzing projects.

aurgen includes an intelligent tool mapping system that automatically maps tool names to their corresponding Arch Linux packages. This system helps aurgen accurately detect dependencies when analyzing projects.

### Features

- **Automatic Discovery**: Analyzes Arch Linux packages, AUR packages, and system packages
- **Version Updates**: Automatically discovers current package versions (GTK4, Qt6, etc.)
- **Comprehensive Coverage**: Maps build tools, compilers, package managers, and utilities
- **Safe Updates**: Automatic backups and git integration for easy rollback

### Usage

```bash
# Update tool mappings
./dev-bin/update-mapping workflow

# Check current status
./dev-bin/update-mapping status

# Expand mappings only
./dev-bin/update-mapping expand

# Check what's available
./dev-bin/update-mapping check

# Dry run (see what would be done)
./dev-bin/update-mapping --dry-run workflow
```

### Current Statistics

The system currently maps **307 tools** across multiple categories:
- **Build tools**: 10 (cmake, make, ninja, etc.)
- **Compilers/Languages**: 36 (gcc, clang, python, rust, go, etc.)
- **Package managers**: 8 (npm, cargo, maven, gradle, etc.)
- **System tools**: 21 (ssh, rsync, tar, gzip, etc.)
- **Qt tools**: 29 (qmake, moc, uic, rcc, etc.)
- **GTK tools**: 16 (gtk-builder-tool, gtk-launch, etc.)
- **Database tools**: 5 (sqlite3, psql, mysql, etc.)
- **Media tools**: 6 (ffmpeg, convert, identify, etc.)
- **Security tools**: 5 (gpg, openssl, etc.)

## Components

### 1. Core Mapping File

**`lib/tool-mapping.sh`** - The main mapping file containing tool-to-package mappings.

### 2. Update System

**`bin/update-mapping`** - CLI tool for updating and managing the tool mapping.

## Usage

### Basic Commands

```bash
./dev-bin/update-mapping workflow    # Run complete workflow (expand + apply)
./dev-bin/update-mapping expand      # Expand mappings only
./dev-bin/update-mapping status      # Show current statistics
./dev-bin/update-mapping check       # Check what's available
```

### Workflow

The mapping system uses a simplified workflow:

1. **Expand** - Discover new tools from Arch Linux, AUR, and system packages
2. **Apply** - Automatically apply changes to `lib/tool-mapping.sh`
3. **Version Updates** - Handled automatically during expansion (GTK4, Qt6, etc.)

## Mapping Format

The mapping uses a Bash case statement format:

```bash
map_tool_to_package() {
    local tool="$1"
    
    case "$tool" in
        cmake) echo "cmake" ;;
        make) echo "make" ;;
        gcc) echo "gcc" ;;
        python) echo "python" ;;
        node) echo "nodejs" ;;
        # ... more mappings
        *) echo "$tool" ;;  # Default: return tool name as-is
    esac
}
```

## Automatic Version Updates

**Version updates are now handled automatically during expansion:**

- The system naturally discovers current package versions (GTK4, Qt6, etc.)
- No separate version migration step is needed
- Always gets the latest available versions from repositories

### Examples of Automatic Updates

- **GTK3 → GTK4**: Discovered automatically from current repositories
- **Qt5 → Qt6**: Found during expansion of current packages
- **Python2 → Python3**: Naturally mapped to current Python package
- **JDK versions**: Mapped to current `jdk-openjdk` package

## Safety Features

- **Automatic backups** before any changes
- **Git version control** for easy rollback
- **Clean output** showing exactly what changed
- **No complex version conflicts** - just simple expansion

## Examples

### Update Mapping

```bash
# Run complete workflow
./dev-bin/update-mapping workflow

# Or expand only
./dev-bin/update-mapping expand
```

### Check Status

```bash
./dev-bin/update-mapping status
```

### Dry Run

```bash
./dev-bin/update-mapping --dry-run workflow
```

### Verbose Output

```bash
./dev-bin/update-mapping --verbose expand
```

## Integration with aurgen

The tool mapping is used by aurgen's dependency detection system:

1. **README Analysis** - Maps tool names found in README files
2. **Project File Analysis** - Maps build system and language tools
3. **Tool Detection** - Maps tools detected in project files

## Troubleshooting

### Restore from Backup

```bash
cp /tmp/aurgen-mapping/tool-mapping.sh.backup lib/tool-mapping.sh
```

### Git Rollback

```bash
git checkout lib/tool-mapping.sh
```

### Check What's Available

```bash
./dev-bin/update-mapping check
```

## Best Practices

1. **Run Regularly** - Update mappings periodically to stay current
2. **Review Changes** - Check the output to see what was added
3. **Test Thoroughly** - Test aurgen with new mappings before committing
4. **Use Git** - Commit changes to track mapping evolution

## Contributing

When contributing to the mapping system:

1. Run `./dev-bin/update-mapping expand` to discover new tools
2. Review the generated mappings
3. Test with various project types
4. Commit the updated mapping file

## License

This system is part of aurgen and is licensed under the GNU General Public License v3.0 or later. 