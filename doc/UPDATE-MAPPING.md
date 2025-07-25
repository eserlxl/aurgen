# Update Mapping Workflow

This document describes the comprehensive `update-mapping` workflow script that orchestrates the complete tool mapping update process.

## Overview

The `bin/update-mapping` script provides a single command to run the complete tool mapping update workflow, combining expansion, version updates, and cleaning into one convenient operation.

## Features

### Complete Workflow Automation
- **Single command** to run all mapping updates
- **Step-by-step execution** with progress reporting
- **Comprehensive logging** of all operations
- **Automatic backups** at each step
- **Final statistics** and summary

### Flexible Commands
- **`workflow`** - Run complete workflow (default)
- **`expand`** - Expand mappings only
- **`update`** - Update versions only
- **`clean`** - Clean mappings only
- **`check`** - Check available updates
- **`status`** - Show current statistics

### Safety Options
- **`--dry-run`** - Show what would be done without making changes
- **`--force`** - Force update even if no changes detected
- **`--verbose`** - Enable detailed output

## Usage

### Basic Usage

```bash
# Run complete workflow
./bin/update-mapping

# Same as above
./bin/update-mapping workflow
```

### Individual Steps

```bash
# Expand mappings only
./bin/update-mapping expand

# Update versions only
./bin/update-mapping update

# Clean mappings only
./bin/update-mapping clean
```

### Safety and Debugging

```bash
# Show what would be done (no changes)
./bin/update-mapping --dry-run

# Enable verbose output
./bin/update-mapping --verbose

# Force update
./bin/update-mapping --force
```

### Information Commands

```bash
# Check current status
./bin/update-mapping status

# Check for available updates
./bin/update-mapping check

# Show help
./bin/update-mapping --help
```

## Complete Workflow

The `workflow` command performs these steps in sequence:

### Step 1: Expand Mappings
- Analyzes Arch Linux packages
- Checks popular AUR packages
- Scans system packages
- Generates expanded mapping

### Step 2: Update Versions
- Checks available package versions
- Applies migration rules (GTK3→GTK4, Qt5→Qt6, etc.)
- Updates tool mapping accordingly

### Step 3: Clean Mappings
- Removes self-mappings
- Filters out Android packages
- Removes other unnecessary packages

### Step 4: Generate Summary
- Shows final statistics
- Lists created files and backups
- Provides next steps

## Example Output

```
Starting complete tool mapping update workflow...
==================================================

Step 1: Expanding mappings...
----------------------------
[2025-07-26 01:15:30] Starting mapping expansion...
Starting tool mapping expansion...
[2025-07-26 01:15:30] Generating expanded mapping...
[2025-07-26 01:15:30] Analyzing Arch Linux packages...
[2025-07-26 01:15:30] Added 189 common tool mappings
[2025-07-26 01:15:31] Analyzing AUR packages for common dependencies...
[2025-07-26 01:15:31] Found 50 popular AUR packages
[2025-07-26 01:15:45] Analyzing system packages for provides...
[2025-07-26 01:15:45] Added 40 system provides mappings
[2025-07-26 01:15:45] Generated 312 unique tool mappings
[2025-07-26 01:15:45] Mapping expansion completed.

Step 2: Updating package versions...
-----------------------------------
[2025-07-26 01:15:45] Starting version updates...
Updating package versions in tool mapping...
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
[2025-07-26 01:15:50] Version updates completed.

Step 3: Cleaning mappings...
---------------------------
[2025-07-26 01:15:50] Starting mapping cleaning...
Cleaning tool mapping...
Cleaning statistics:
  Original mappings: 307
  Clean mappings: 93
  Removed mappings: 214
[2025-07-26 01:15:51] Mapping cleaning completed.

Step 4: Final statistics...
--------------------------
Current mapping statistics:
==========================
  Total mappings: 93

Mappings by category:
  Build tools: 8
  Compilers/Languages: 12
  Package managers: 6
  System tools: 15
  Qt tools: 8
  GTK tools: 5
  Database tools: 4
  Media tools: 6
  Security tools: 4

Last updated: 2025-07-26 01:15:51

Workflow completed successfully!
===============================

Files created:
  - Workflow log: /tmp/aurgen-mapping/workflow.log
  - Expansion files: /tmp/aurgen-mapping/expanded-mapping.txt
  - Version updates: /tmp/aurgen-mapping/version-updates.txt
  - Clean mappings: /tmp/aurgen-mapping/clean-mapping.txt

Backups created:
  - Expansion backup: /tmp/aurgen-mapping/tool-mapping.sh.backup
  - Version backup: /tmp/aurgen-mapping/tool-mapping.sh.backup.version
  - Clean backup: /tmp/aurgen-mapping/tool-mapping.sh.backup.clean

Next steps:
  1. Review the changes in lib/tool-mapping.sh
  2. Test aurgen with the updated mappings
  3. Commit the changes: git add lib/tool-mapping.sh && git commit -m 'Update tool mapping'

To restore from backup:
  cp /tmp/aurgen-mapping/tool-mapping.sh.backup.clean lib/tool-mapping.sh
```

## Status Command

The `status` command provides detailed statistics about the current mapping:

```
Current mapping statistics:
==========================
  Total mappings: 93

Mappings by category:
  Build tools: 8
  Compilers/Languages: 12
  Package managers: 6
  System tools: 15
  Qt tools: 8
  GTK tools: 5
  Database tools: 4
  Media tools: 6
  Security tools: 4

Last updated: 2025-07-26 01:15:51
```

## Check Command

The `check` command shows what updates are available:

```
Checking for available updates...
=================================

1. Mapping Expansion:
   - Arch Linux packages: Available
   - AUR packages: Available
   - System packages: Available

2. Version Updates:
   - GTK3 → GTK4: Available
   - Qt5 → Qt6: Available
   - Python2 → Python3: Available

3. Mapping Cleaning:
   - Self-mappings: Will be removed
   - Android packages: Will be filtered
   - Unnecessary packages: Will be filtered

Run './bin/update-mapping workflow' to apply all updates.
```

## Files and Logs

### Workflow Log
- **Location**: `/tmp/aurgen-mapping/workflow.log`
- **Content**: Timestamped log of all operations
- **Format**: `[YYYY-MM-DD HH:MM:SS] message`

### Output Files
- **Expansion**: `/tmp/aurgen-mapping/expanded-mapping.txt`
- **Version updates**: `/tmp/aurgen-mapping/version-updates.txt`
- **Clean mappings**: `/tmp/aurgen-mapping/clean-mapping.txt`

### Backup Files
- **Expansion**: `/tmp/aurgen-mapping/tool-mapping.sh.backup`
- **Version**: `/tmp/aurgen-mapping/tool-mapping.sh.backup.version`
- **Clean**: `/tmp/aurgen-mapping/tool-mapping.sh.backup.clean`

## Best Practices

### Regular Maintenance
```bash
# Weekly: Check for updates
./bin/update-mapping check

# Monthly: Run complete workflow
./bin/update-mapping workflow

# Before committing: Review changes
./bin/update-mapping status
```

### Safety First
```bash
# Always test with dry-run first
./bin/update-mapping --dry-run

# Use verbose mode for debugging
./bin/update-mapping --verbose

# Keep backups before major updates
cp lib/tool-mapping.sh lib/tool-mapping.sh.backup.$(date +%Y%m%d)
```

### Integration with Git
```bash
# Run workflow
./bin/update-mapping workflow

# Review changes
git diff lib/tool-mapping.sh

# Test aurgen
./bin/aurgen test

# Commit if everything looks good
git add lib/tool-mapping.sh
git commit -m "Update tool mapping with expanded mappings and version migrations"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Ensure script is executable
   chmod +x bin/update-mapping
   
   # Check temp directory permissions
   ls -la /tmp/aurgen-mapping/
   ```

2. **Network Errors**
   ```bash
   # Check internet connection
   ping -c 1 aur.archlinux.org
   
   # Try individual steps
   ./bin/update-mapping expand
   ```

3. **Package Not Found**
   ```bash
   # Update package database
   sudo pacman -Sy
   
   # Check specific package
   pacman -Ss package-name
   ```

### Recovery

```bash
# Restore from backup
cp /tmp/aurgen-mapping/tool-mapping.sh.backup.clean lib/tool-mapping.sh

# Or restore from specific step
cp /tmp/aurgen-mapping/tool-mapping.sh.backup lib/tool-mapping.sh

# Regenerate from scratch
rm -rf /tmp/aurgen-mapping/
./bin/update-mapping workflow
```

## Integration

The workflow script integrates seamlessly with the existing mapping system:

- **Uses all existing libraries** (expand-mapping.sh, version-updater.sh, clean-mapping.sh)
- **Maintains compatibility** with individual scripts
- **Provides unified interface** for all mapping operations
- **Generates comprehensive logs** for debugging and auditing

## License

This script is part of aurgen and is licensed under the GNU General Public License v3.0 or later. 