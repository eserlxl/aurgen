# Tool Mapping Expansion

This document describes the tool mapping expansion system for aurgen.

## Overview

The tool mapping expansion system automatically discovers and maps tool names to their containing packages in Arch Linux. It analyzes multiple sources to build a comprehensive mapping of development tools.

## Workflow

The expansion workflow consists of two main steps:

1. **Expand** - Use `./bin/update-mapping expand` to discover new tools from repositories
2. **Apply** - The expansion automatically applies changes to `lib/tool-mapping.sh`

### Complete Workflow

```bash
# Run the complete workflow (expand + apply)
./dev-bin/update-mapping workflow

# Or run steps individually
./dev-bin/update-mapping expand      # Expand and apply
./dev-bin/update-mapping status      # Show current statistics
./dev-bin/update-mapping check       # Check what's available
```

## How It Works

### 1. Arch Linux Package Analysis

The system analyzes common development tools and their packages:

- **Build systems**: cmake, make, ninja, autoconf, automake, libtool, meson
- **Compilers**: gcc, clang, g++, clang++
- **Package managers**: npm, cargo, maven, gradle, pip, poetry, yarn
- **Languages**: python, node, rust, go, java, ruby, php, perl, lua, haskell, ocaml, nim, zig, crystal, dart, kotlin, scala, groovy, clojure, erlang, elixir
- **Utilities**: curl, wget, jq, gpg, gh, shellcheck, bash, git

### 2. AUR Package Analysis

Analyzes popular AUR packages to discover additional dependencies and tools.

### 3. System Package Analysis

Checks system packages for tools that provide common development utilities.

### 4. Automatic Version Updates

**Version updates are now handled automatically during expansion:**
- The system naturally discovers current package versions (GTK4, Qt6, etc.)
- No separate version migration step is needed
- Always gets the latest available versions from repositories

## Output Files

- **`/tmp/aurgen-mapping/expanded-mapping.txt`** - Raw expanded mappings
- **`/tmp/aurgen-mapping/analysis.log`** - Detailed analysis log
- **`/tmp/aurgen-mapping/tool-mapping.sh.backup`** - Backup of original mapping
- **`lib/tool-mapping.sh`** - Updated tool mapping (automatically applied)

## Safety Features

- **Automatic backups** before any changes
- **Git version control** for easy rollback
- **Clean output** showing exactly what changed
- **No complex version conflicts** - just simple expansion

## Examples

### Basic Expansion

```bash
./dev-bin/update-mapping expand
```

### Check Current Status

```bash
./dev-bin/update-mapping status
```

### Dry Run (see what would be done)

```bash
./dev-bin/update-mapping --dry-run workflow
```

### Verbose Output

```bash
./dev-bin/update-mapping --verbose expand
```

### Check Available Updates

```bash
./dev-bin/update-mapping check
```

## Troubleshooting

### Restore from Backup

If you need to restore the original mapping:

```bash
cp /tmp/aurgen-mapping/tool-mapping.sh.backup lib/tool-mapping.sh
```

### Git Rollback

Since the mapping is under git version control:

```bash
git checkout lib/tool-mapping.sh
```

### Check What's Available

```bash
./dev-bin/update-mapping check
```

## Integration

The expanded mapping is automatically integrated into aurgen's dependency detection system. When aurgen runs, it will use the updated mappings to find the correct packages for detected tools. 