#!/bin/bash
# Version check and updater for tool mapping
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Configuration
TEMP_DIR="/tmp/aurgen-mapping"
VERSION_UPDATE_FILE="$TEMP_DIR/version-updates.txt"
BACKUP_FILE="$TEMP_DIR/tool-mapping.sh.backup.version"

# Version migration rules
declare -A VERSION_MIGRATIONS=(
    # GTK migrations
    ["gtk3"]="gtk4"
    ["gtk-update-icon-cache"]="gtk-update-icon-cache"
    
    # Qt migrations
    ["qt5-base"]="qt6-base"
    ["qt5-tools"]="qt6-tools"
    
    # Python migrations
    ["python2"]="python"
    ["python2-pip"]="python-pip"
    
    # Java migrations
    ["jdk8-openjdk"]="jdk-openjdk"
    ["jdk11-openjdk"]="jdk-openjdk"
    ["jdk17-openjdk"]="jdk-openjdk"
    
    # Node.js migrations
    ["nodejs-lts-erbium"]="nodejs"
    ["nodejs-lts-fermium"]="nodejs"
    ["nodejs-lts-gallium"]="nodejs"
    
    # Rust migrations
    ["rust-nightly"]="rust"
    ["rust-beta"]="rust"
    
    # Go migrations
    ["go1.18"]="go"
    ["go1.19"]="go"
    ["go1.20"]="go"
    ["go1.21"]="go"
    
    # Systemd migrations
    ["systemd-sysvcompat"]="systemd"
    
    # Other migrations
    ["openssl-1.1"]="openssl"
    ["openssl-1.0"]="openssl"
    ["libpng16"]="libpng"
    ["libjpeg-turbo"]="libjpeg"
)

# Check if a package version is available
check_package_version() {
    local package="$1"
    local version="$2"
    
    # Check if the specific version is available
    if pacman -Ss "^$version$" | grep -q "$version"; then
        return 0
    fi
    
    # Check if a newer version is available
    local available_versions
    available_versions=$(pacman -Ss "^$package" | grep -o "$package[0-9.-]*" | sort -V | tail -1)
    
    if [[ -n "$available_versions" && "$available_versions" != "$package" ]]; then
        echo "$available_versions"
        return 0
    fi
    
    return 1
}

# Check for version migrations
check_version_migrations() {
    local tool_mapping_file="$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"
    
    echo "Checking for version migrations..."
    
    # Create backup
    cp "$tool_mapping_file" "$BACKUP_FILE"
    echo "Backup created: $BACKUP_FILE"
    
    local migrations=()
    local updated_mappings=()
    
    # Read current mappings
    while IFS= read -r line; do
        # Extract tool and package using grep and sed
        if echo "$line" | grep -q '^[[:space:]]*[a-zA-Z0-9_-]\+)[[:space:]]*echo[[:space:]]*"[^"]*"[[:space:]]*;;'; then
            local tool
            tool=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]\+\))[[:space:]]*echo[[:space:]]*"\([^"]*\)"[[:space:]]*;;/\1/p')
            local package
            package=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]\+\))[[:space:]]*echo[[:space:]]*"\([^"]*\)"[[:space:]]*;;/\2/p')
            
            if [[ -n "$tool" && -n "$package" ]]; then
                # Check for migration rules
                if [[ -n "${VERSION_MIGRATIONS[$package]:-}" ]]; then
                    local new_package="${VERSION_MIGRATIONS[$package]}"
                    
                    # Check if the new package is available
                    if pacman -Ss "^$new_package$" | grep -q "$new_package"; then
                        migrations+=("$tool:$package → $new_package")
                        updated_mappings+=("$tool:$new_package")
                    else
                        updated_mappings+=("$tool:$package")
                    fi
                else
                    # Check for version updates
                    local newer_version
                    newer_version=$(check_package_version "$package" "$package")
                    if [[ -n "$newer_version" ]]; then
                        migrations+=("$tool:$package → $newer_version")
                        updated_mappings+=("$tool:$newer_version")
                    else
                        updated_mappings+=("$tool:$package")
                    fi
                fi
            fi
        fi
    done < "$tool_mapping_file"
    
    # Write migrations to file
    printf '%s\n' "${migrations[@]}" > "$VERSION_UPDATE_FILE"
    
    # Generate updated tool-mapping.sh
    cat > "$tool_mapping_file" << 'EOF'
#!/bin/bash
# Tool to package mapping for Arch Linux
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Map tool names to their containing packages
# Usage: map_tool_to_package <tool_name>
# Returns: package name that contains the tool
map_tool_to_package() {
    local tool="$1"
    
    # Tool to package mapping for Arch Linux
    case "$tool" in
EOF
    
    # Add updated mappings
    for mapping in "${updated_mappings[@]}"; do
        local tool="${mapping%:*}"
        local package="${mapping#*:}"
        echo "        $tool) echo \"$package\" ;;" >> "$tool_mapping_file"
    done
    
    # Add default case
    cat >> "$tool_mapping_file" << 'EOF'
        
        # Default: return the tool name as-is if no mapping exists
        *) echo "$tool" ;;
    esac
}
EOF
    
    # Show statistics
    local migration_count=${#migrations[@]}
    
    echo "Version migration statistics:"
    echo "  Migrations found: $migration_count"
    echo
    echo "Migrations applied:"
    if [[ $migration_count -gt 0 ]]; then
        printf '  %s\n' "${migrations[@]}"
    else
        echo "  No migrations needed"
    fi
    echo
    echo "Version updates saved to: $VERSION_UPDATE_FILE"
    echo "Backup of original: $BACKUP_FILE"
    echo
    echo "Tool mapping has been updated with version migrations."
}

# Check for available package versions
check_available_versions() {
    echo "Checking available package versions..."
    
    local packages=(
        "gtk3" "gtk4"
        "qt5-base" "qt6-base"
        "qt5-tools" "qt6-tools"
        "python2" "python"
        "jdk8-openjdk" "jdk11-openjdk" "jdk17-openjdk" "jdk-openjdk"
        "nodejs-lts-erbium" "nodejs-lts-fermium" "nodejs-lts-gallium" "nodejs"
        "rust-nightly" "rust-beta" "rust"
        "go1.18" "go1.19" "go1.20" "go1.21" "go"
        "openssl-1.1" "openssl-1.0" "openssl"
    )
    
    echo "Available package versions:"
    for package in "${packages[@]}"; do
        if pacman -Ss "^$package$" | grep -q "$package"; then
            local version
            version=$(pacman -Ss "^$package$" | head -1 | awk '{print $1}' | sed 's/^[^/]*\///')
            echo "  $package: $version"
        fi
    done
}

# Main function
update_versions() {
    echo "Updating package versions in tool mapping..."
    check_available_versions
    echo
    check_version_migrations
    echo "Done! Package versions have been updated."
}

# Check only function
check_versions() {
    echo "Checking package versions..."
    check_available_versions
    echo
    echo "Version migration rules:"
    for old_pkg in "${!VERSION_MIGRATIONS[@]}"; do
        local new_pkg="${VERSION_MIGRATIONS[$old_pkg]}"
        echo "  $old_pkg → $new_pkg"
    done
} 