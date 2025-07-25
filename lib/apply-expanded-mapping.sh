#!/bin/bash
# Apply expanded mapping to tool-mapping.sh
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

# Source the expansion script
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/expand-mapping.sh"

# Configuration
TEMP_DIR="/tmp/aurgen-mapping"
MAPPING_OUTPUT="$TEMP_DIR/expanded-mapping.txt"
BACKUP_FILE="$TEMP_DIR/tool-mapping.sh.backup"
NEW_MAPPING_FILE="$TEMP_DIR/new-tool-mapping.sh"

# Apply expanded mapping to tool-mapping.sh
apply_expanded_mapping() {
    local tool_mapping_file="$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"
    
    echo "Applying expanded mapping to tool-mapping.sh..."
    
    # Create backup
    cp "$tool_mapping_file" "$BACKUP_FILE"
    echo "Backup created: $BACKUP_FILE"
    
    # Generate expanded mapping if it doesn't exist
    if [[ ! -f "$MAPPING_OUTPUT" ]]; then
        echo "Expanded mapping not found. Generating..."
        generate_expanded_mapping
    fi
    
    # Read existing mappings
    local existing_mappings=()
    while IFS= read -r line; do
        # Extract tool and package using grep and sed
        if echo "$line" | grep -q '^[[:space:]]*[a-zA-Z0-9_-]\+)[[:space:]]*echo[[:space:]]*"[^"]*"[[:space:]]*;;'; then
            local tool
            tool=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]\+\))[[:space:]]*echo[[:space:]]*"\([^"]*\)"[[:space:]]*;;/\1/p')
            local package
            package=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]\+\))[[:space:]]*echo[[:space:]]*"\([^"]*\)"[[:space:]]*;;/\2/p')
            if [[ -n "$tool" && -n "$package" ]]; then
                existing_mappings+=("$tool:$package")
            fi
        fi
    done < "$tool_mapping_file"
    
    # Read new mappings
    local new_mappings=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)$ ]]; then
            local tool="${BASH_REMATCH[1]}"
            local package="${BASH_REMATCH[2]}"
            new_mappings+=("$tool:$package")
        fi
    done < "$MAPPING_OUTPUT"
    
    # Merge mappings (new mappings override existing ones)
    local merged_mappings=()
    local seen_tools=()
    
    # Add existing mappings first
    for mapping in "${existing_mappings[@]}"; do
        local tool="${mapping%:*}"
        merged_mappings+=("$mapping")
        seen_tools+=("$tool")
    done
    
    # Add new mappings (skip if tool already exists)
    for mapping in "${new_mappings[@]}"; do
        local tool="${mapping%:*}"
        local found=0
        for existing_tool in "${seen_tools[@]}"; do
            if [[ "$tool" == "$existing_tool" ]]; then
                found=1
                break
            fi
        done
        
        if [[ $found -eq 0 ]]; then
            merged_mappings+=("$mapping")
            seen_tools+=("$tool")
        fi
    done
    
    # Sort mappings by tool name
    IFS=$'\n' merged_mappings=($(sort <<<"${merged_mappings[*]}"))
    unset IFS
    
    # Generate new tool-mapping.sh
    cat > "$NEW_MAPPING_FILE" << 'EOF'
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
    
    # Add mappings
    for mapping in "${merged_mappings[@]}"; do
        local tool="${mapping%:*}"
        local package="${mapping#*:}"
        echo "        $tool) echo \"$package\" ;;" >> "$NEW_MAPPING_FILE"
    done
    
    # Add default case
    cat >> "$NEW_MAPPING_FILE" << 'EOF'
        
        # Default: return the tool name as-is if no mapping exists
        *) echo "$tool" ;;
    esac
}
EOF
    
    # Show statistics
    local existing_count=${#existing_mappings[@]}
    local new_count=${#new_mappings[@]}
    local merged_count=${#merged_mappings[@]}
    local added_count=$((merged_count - existing_count))
    
    echo "Mapping statistics:"
    echo "  Existing mappings: $existing_count"
    echo "  New mappings: $new_count"
    echo "  Merged mappings: $merged_count"
    echo "  Added mappings: $added_count"
    
    # Ask for confirmation
    echo
    echo "New tool-mapping.sh generated: $NEW_MAPPING_FILE"
    echo "Backup of original: $BACKUP_FILE"
    echo
    echo "To apply the changes:"
    echo "  cp $NEW_MAPPING_FILE $(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"
    echo
    echo "To restore the original:"
    echo "  cp $BACKUP_FILE $(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"
}

# Main function
update_tool_mapping() {
    echo "Updating tool mapping..."
    apply_expanded_mapping
    echo "Done! Review the generated file and apply if satisfied."
} 