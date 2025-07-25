# Tool Mapping Expansion

This document describes the tool mapping expansion feature for aurgen, which automatically analyzes various sources to expand the tool-to-package mapping used for dependency detection.

## Overview

The tool mapping expansion system consists of three main components:

1. **`lib/expand-mapping.sh`** - Core expansion logic
2. **`lib/apply-expanded-mapping.sh`** - Application logic
3. **`bin/expand-mapping`** - CLI interface

## Features

### Automatic Analysis Sources

The expansion system analyzes multiple sources to find tool-to-package mappings:

#### 1. Arch Linux Package Analysis
- Analyzes common development tools and their packages
- Covers build systems, compilers, package managers, and utilities
- Includes system tools, documentation tools, and framework-specific tools

#### 2. AUR Package Analysis
- Analyzes popular AUR packages for dependencies
- Extracts both `Depends` and `MakeDepends` arrays
- Provides real-world usage patterns

#### 3. System Package Analysis
- Uses `pacman -Qo` to find which package provides a specific tool
- Analyzes installed packages for tool-to-package relationships
- Provides accurate mappings for the current system

### Comprehensive Tool Coverage

The expansion covers:

#### Build Systems
- CMake, Make, Ninja, Autotools, Meson
- Language-specific build tools (Cargo, npm, Maven, Gradle)

#### Compilers and Languages
- GCC, Clang, Python, Node.js, Rust, Go, Java
- Ruby, PHP, Perl, Lua, Haskell, OCaml, Nim, Zig
- Crystal, Dart, Kotlin, Scala, Groovy, Clojure

#### Utilities
- Network tools (curl, wget, git, ssh, rsync)
- Archive tools (tar, gzip, bzip2, xz, zstd, unzip, zip, 7z)
- System tools (fakeroot, sudo, systemd tools)

#### Documentation
- AsciiDoc, SassC, Pandoc, Doxygen
- Language-specific documentation tools

#### Frameworks and Libraries
- Qt tools (qmake, moc, uic, rcc)
- GTK tools (gtk-builder-tool, gtk-launch)
- ImageMagick tools (convert, identify, mogrify)
- Audio/Video tools (ffmpeg, sox, lame)

#### Development Tools
- Database tools (sqlite3, psql, mysql, mongosh)
- Web servers (nginx, apache, lighttpd, caddy)
- Container tools (docker, podman, kubectl, helm)
- Security tools (openssl, gpg tools)

## Usage

### Command Line Interface

```bash
# Generate expanded mapping only
./bin/expand-mapping generate

# Apply existing expanded mapping
./bin/expand-mapping apply

# Generate and apply expanded mapping (default)
./bin/expand-mapping update

# Show help
./bin/expand-mapping --help
```

### Programmatic Usage

```bash
# Source the libraries
source lib/expand-mapping.sh
source lib/apply-expanded-mapping.sh

# Generate expanded mapping
expand_tool_mapping

# Apply to tool-mapping.sh
update_tool_mapping
```

## Output Files

The expansion process creates several files in `/tmp/aurgen-mapping/`:

- **`expanded-mapping.txt`** - Raw tool:package mappings
- **`analysis.log`** - Detailed analysis log
- **`tool-mapping.sh.backup`** - Backup of original tool-mapping.sh
- **`new-tool-mapping.sh`** - Generated new tool-mapping.sh

## Safety Features

### Backup and Restore
- Automatically creates backup of original `tool-mapping.sh`
- Provides clear instructions for applying changes
- Allows easy restoration if needed

### Validation
- Validates tool and package names
- Skips invalid mappings
- Provides detailed statistics

### Conflict Resolution
- New mappings don't override existing ones
- Preserves existing custom mappings
- Merges mappings intelligently

## Integration with aurgen

The expanded mapping is automatically used by aurgen's dependency detection system:

1. **README Analysis** - Maps tool names found in README files
2. **Project File Analysis** - Maps build system and language tools
3. **Tool Detection** - Maps tools detected in project files

## Complete Workflow

The mapping expansion system works together with the version updater:

1. **Expand** - Use `./bin/expand-mapping update` to add new mappings
2. **Update** - Use `./bin/update-versions update` to migrate to newer versions
3. **Clean** - Use `lib/clean-mapping.sh` to remove unnecessary mappings

### Example Workflow

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

## Customization

### Adding Custom Mappings

To add custom mappings, edit the `common_tools` array in `lib/expand-mapping.sh`:

```bash
local common_tools=(
    "your-tool:your-package"
    "another-tool:another-package"
)
```

### Filtering Mappings

The system automatically filters out:
- Invalid package names
- Common false positives
- Self-mapping tools (tool name = package name)

### Extending Analysis Sources

To add new analysis sources, extend the functions in `lib/expand-mapping.sh`:

```bash
analyze_custom_source() {
    # Your custom analysis logic
    # Add mappings to $MAPPING_OUTPUT
}
```

## Best Practices

1. **Run Regularly** - Update mappings periodically to stay current
2. **Review Changes** - Always review generated mappings before applying
3. **Test Thoroughly** - Test aurgen with new mappings before committing
4. **Backup First** - Keep backups of working configurations

## Troubleshooting

### Common Issues

1. **Network Errors** - AUR analysis requires internet connection
2. **Permission Errors** - Ensure write access to `/tmp/aurgen-mapping/`
3. **Package Not Found** - Some tools may not be available on your system

### Debug Mode

Enable debug output by setting environment variables:

```bash
DEBUG_LEVEL=1 ./bin/expand-mapping update
```

### Manual Recovery

If something goes wrong:

```bash
# Restore from backup
cp /tmp/aurgen-mapping/tool-mapping.sh.backup lib/tool-mapping.sh

# Or regenerate from scratch
rm -rf /tmp/aurgen-mapping/
./bin/expand-mapping update
```

## Contributing

When contributing to the mapping expansion:

1. Add new tools to the `common_tools` array
2. Test with various project types
3. Update documentation
4. Ensure mappings are accurate and up-to-date

## License

This feature is part of aurgen and is licensed under the GNU General Public License v3.0 or later. 