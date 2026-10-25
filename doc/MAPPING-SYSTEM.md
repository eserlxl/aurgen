# Tool Mapping System

This document describes the tool mapping system used by AURGen to map tool names to their containing packages in Arch Linux.

## Overview

The tool mapping system consists of a comprehensive mapping of tool names to their corresponding Arch Linux packages. This mapping is used by AURGen to automatically detect dependencies when analyzing projects.

AURGen includes an intelligent tool mapping system that automatically maps tool names to their corresponding Arch Linux packages. This system helps AURGen accurately detect dependencies when analyzing projects.

### Features

- **Automatic Discovery**: Analyzes Arch Linux packages and system packages
- **Comprehensive Coverage**: Maps build tools, compilers, package managers, and utilities
- **Safe Updates**: Automatic backups and git integration for easy rollback

### Usage

```bash
# Update tool mappings
./scripts/update-mapping workflow

# Check current status
./scripts/update-mapping status

# Expand mappings only
./scripts/update-mapping expand

# Check what's available
./scripts/update-mapping check

# Dry run (see what would be done)
./scripts/update-mapping --dry-run workflow
./scripts/update-mapping --dry-run expand
```

### Current Statistics

The mapping table holds **372 tools** (count the case entries in `lib/tool-mapping.sh` with `grep -cE '^[[:space:]]+[a-z0-9._+|-]+\)' lib/tool-mapping.sh`). They span build tools, compilers and languages, package managers, system tools, Qt and GTK tools, and database, media and security tools.

## Components

### 1. Core Mapping File

**`lib/tool-mapping.sh`** - The main mapping file containing tool-to-package mappings.

### 2. Update System

**`scripts/update-mapping`** - CLI tool for updating and managing the tool mapping.

## Usage

### Basic Commands

```bash
./scripts/update-mapping workflow    # Run complete workflow (expand + apply)
./scripts/update-mapping expand      # Expand mappings only
./scripts/update-mapping status      # Show current statistics
./scripts/update-mapping check       # Check what's available
```

### Workflow

The mapping system uses a simplified workflow:

1. **Expand** - Discover new tools from Arch Linux, AUR, and system packages
2. **Apply** - Automatically apply changes to `lib/tool-mapping.sh`
3. **Existing mappings are kept** - Expansion only adds tools that are not mapped yet; an outdated mapping is edited by hand

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

## Existing Mappings Are Kept

Expansion only adds tools that have no mapping yet. A tool that is already in `lib/tool-mapping.sh` keeps its package, so an older mapping (for example a GTK3 or Qt5 package) is not upgraded automatically; edit that line by hand.

## Safety Features

- **Automatic backups** before any changes
- **Git version control** for easy rollback
- **Clean output** showing exactly what changed
- **No complex version conflicts** - just simple expansion

## Examples

### Update Mapping

```bash
# Run complete workflow
./scripts/update-mapping workflow

# Or expand only
./scripts/update-mapping expand
```

### Check Status

```bash
./scripts/update-mapping status
```

### Dry Run

```bash
./scripts/update-mapping --dry-run workflow
./scripts/update-mapping --dry-run expand
```

### Verbose Output

```bash
./scripts/update-mapping --verbose expand
```

## Integration with AURGen

The tool mapping is used by AURGen's dependency detection system:

1. **README Analysis** - Maps tool names found in README files
2. **Project File Analysis** - Maps build system and language tools
3. **Tool Detection** - Maps tools detected in project files

## Troubleshooting

### Restore from Backup

```bash
cp "${TMPDIR:-/tmp}/aurgen-mapping/tool-mapping.sh.backup" lib/tool-mapping.sh
```

### Git Rollback

```bash
git checkout lib/tool-mapping.sh
```

### Check What's Available

```bash
./scripts/update-mapping check
```

## Best Practices

1. **Run Regularly** - Update mappings periodically to stay current
2. **Review Changes** - Check the output to see what was added
3. **Test Thoroughly** - Test AURGen with new mappings before committing
4. **Use Git** - Commit changes to track mapping evolution

## Contributing

When contributing to the mapping system:

1. Run `./scripts/update-mapping expand` to discover new tools
2. Review the generated mappings
3. Test with various project types
4. Commit the updated mapping file

## License

This system is part of AURGen and is licensed under the GNU General Public License v3.0 or later. 